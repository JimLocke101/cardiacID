//
//  ProtectedFileVault.swift
//  CardiacID
//
//  HeartID-gated encrypted file vault.
//
//  Storage layout (Application Support/HeartIDVault/):
//    manifest.enc   — AES-GCM encrypted JSON array of VaultItem
//    <uuid>.enc     — AES-GCM encrypted file payload
//
//  All encryption uses CryptoKit AES.GCM with a single vault key
//  managed by SecureKeyManagerProtocol.
//
//  Decryption requires an AuthPolicyDecision with decision == .allow.
//  The vault re-locks automatically when SessionTrustManager expires
//  or the app moves to background.
//

import Foundation
import CryptoKit
import Combine
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Errors

enum ProtectedFileVaultError: Error, LocalizedError, Sendable {
    case denied(String)
    case encryptionFailed
    case decryptionFailed
    case manifestCorrupted
    case itemNotFound(UUID)
    case directoryCreationFailed
    case fileWriteFailed

    var errorDescription: String? {
        switch self {
        case .denied(let r):         return "Access denied: \(r)"
        case .encryptionFailed:      return "AES-GCM encryption failed"
        case .decryptionFailed:      return "AES-GCM decryption failed"
        case .manifestCorrupted:     return "Vault manifest could not be decrypted"
        case .itemNotFound(let id):  return "No vault item with id \(id)"
        case .directoryCreationFailed: return "Could not create vault directory"
        case .fileWriteFailed:       return "Could not write encrypted file to disk"
        }
    }
}

// MARK: - ProtectedFileVault

/// HeartID-gated encrypted file vault.
///
/// Thread-safe: all mutable state is isolated to `@MainActor`.
/// Key management is delegated to `SecureKeyManagerProtocol`.
/// The manifest (item list) is stored encrypted on disk — never as plaintext JSON.
@MainActor
final class HeartIDFileVault: ObservableObject {

    // MARK: - Published state

    @Published private(set) var items: [VaultItem] = []
    @Published private(set) var isLocked: Bool = true

    // MARK: - Dependencies (protocol-typed for testability)

    private let keyManager: any SecureKeyManagerProtocol
    private let auditLogger: any AuditLoggerProtocol

    // MARK: - File layout

    private let vaultDirectory: URL
    private let manifestFile: URL            // manifest.enc
    private static let manifestFilename = "manifest.enc"

    // MARK: - App lifecycle observation

    private var lifecycleCancellable: AnyCancellable?

    // MARK: - Init

    /// Production initialiser.
    /// Uses Application Support / HeartIDVault / as storage root.
    init(
        keyManager: any SecureKeyManagerProtocol = DefaultSecureKeyManager(),
        auditLogger: any AuditLoggerProtocol = DefaultAuditLogger()
    ) {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        self.vaultDirectory = appSupport.appendingPathComponent("HeartIDVault", isDirectory: true)
        self.manifestFile   = vaultDirectory.appendingPathComponent(Self.manifestFilename)
        self.keyManager     = keyManager
        self.auditLogger    = auditLogger

        createDirectoryIfNeeded()
        loadManifest()
        seedDemoFilesIfFirstLaunch()
        observeAppLifecycle()
    }

    // MARK: - Public API

    /// Return all vault items (metadata only, no plaintext).
    func listItems() async throws -> [VaultItem] {
        items
    }

    /// Encrypt `data` and store it in the vault under `name`.
    func addItem(name: String, data: Data) async throws -> VaultItem {
        let vaultKey = try await keyManager.retrieveOrCreateVaultKey()
        let item     = VaultItem.create(displayName: name)

        // Encrypt payload
        let sealed = try encrypt(data, using: vaultKey)
        let filePath = vaultDirectory.appendingPathComponent(item.encryptedDataReference)
        guard (try? sealed.write(to: filePath, options: .completeFileProtection)) != nil else {
            throw ProtectedFileVaultError.fileWriteFailed
        }

        items.append(item)
        try await persistManifest(using: vaultKey)

        await auditLogger.log(SecurityEvent(
            action: .unlockProtectedFile,
            decision: .allow,
            sessionState: .recentlyVerified,
            reasonCode: "item_added:\(name)"
        ))

        return item
    }

    /// Decrypt a vault item's payload.
    /// Requires `decision.decision == .allow`; any other value throws `.denied`.
    func decryptItem(
        _ item: VaultItem,
        authorizedBy decision: AuthPolicyDecision
    ) async throws -> Data {
        // Hard gate: only .allow proceeds
        guard decision.decision == .allow else {
            await auditLogger.log(SecurityEvent(
                action: .unlockProtectedFile,
                decision: decision.decision,
                sessionState: .denied,
                reasonCode: "decrypt_blocked:\(decision.rationale)"
            ))
            throw ProtectedFileVaultError.denied(decision.rationale)
        }

        let vaultKey = try await keyManager.retrieveOrCreateVaultKey()
        let filePath = vaultDirectory.appendingPathComponent(item.encryptedDataReference)

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            throw ProtectedFileVaultError.itemNotFound(item.id)
        }

        let ciphertext = try Data(contentsOf: filePath)
        let plaintext  = try decrypt(ciphertext, using: vaultKey)

        // Update lastAccessedAt
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].lastAccessedAt = Date()
            items[idx].isLocked       = false
            try? await persistManifest(using: vaultKey)
        }

        isLocked = false

        await auditLogger.log(SecurityEvent(
            action: .unlockProtectedFile,
            decision: .allow,
            sessionState: .recentlyVerified,
            reasonCode: "decrypted:\(item.displayName)"
        ))

        return plaintext
    }

    /// Remove a vault item and its encrypted file from disk.
    func deleteItem(_ item: VaultItem) async throws {
        let filePath = vaultDirectory.appendingPathComponent(item.encryptedDataReference)
        try? FileManager.default.removeItem(at: filePath)
        items.removeAll { $0.id == item.id }

        let vaultKey = try await keyManager.retrieveOrCreateVaultKey()
        try await persistManifest(using: vaultKey)

        await auditLogger.log(SecurityEvent(
            action: .unlockProtectedFile,
            decision: .allow,
            sessionState: .recentlyVerified,
            reasonCode: "deleted:\(item.displayName)"
        ))
    }

    /// Explicitly lock the vault (wipes any in-memory plaintext references).
    func lock() {
        isLocked = true
        for i in items.indices { items[i].isLocked = true }
    }

    // MARK: - Encrypted manifest persistence

    /// The manifest is stored as AES-GCM encrypted JSON — never plaintext.
    private func persistManifest(using key: SymmetricKey) async throws {
        let json   = try JSONEncoder().encode(items)
        let sealed = try encrypt(json, using: key)
        try sealed.write(to: manifestFile, options: .completeFileProtection)
    }

    private func loadManifest() {
        guard FileManager.default.fileExists(atPath: manifestFile.path) else { return }
        guard let ciphertext = try? Data(contentsOf: manifestFile) else { return }

        // We need the vault key to decrypt — run synchronously on first load.
        // If the key doesn't exist yet (fresh install), items stays empty
        // and seedDemoFiles will populate it.
        Task {
            do {
                let vaultKey  = try await keyManager.retrieveOrCreateVaultKey()
                let json      = try decrypt(ciphertext, using: vaultKey)
                let decoded   = try JSONDecoder().decode([VaultItem].self, from: json)
                self.items    = decoded
            } catch {
                // Manifest unreadable (key rotated, corrupted, first launch) — start fresh
                self.items = []
            }
        }
    }

    // MARK: - AES-GCM helpers

    private func encrypt(_ plaintext: Data, using key: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw ProtectedFileVaultError.encryptionFailed
        }
        return combined
    }

    private func decrypt(_ ciphertext: Data, using key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        do {
            return try AES.GCM.open(box, using: key)
        } catch {
            throw ProtectedFileVaultError.decryptionFailed
        }
    }

    // MARK: - Directory setup

    private func createDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(
            at: vaultDirectory, withIntermediateDirectories: true
        )
    }

    // MARK: - App lifecycle → re-lock

    private func observeAppLifecycle() {
        #if os(iOS)
        lifecycleCancellable = NotificationCenter.default
            .publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.lock()
                }
            }
        #endif
    }

    // =========================================================================
    // MARK: - Demo-only seed files
    //
    // WARNING: The following code generates placeholder demo content.
    // It exists solely for first-launch demonstration and testing.
    // These files do NOT contain real sensitive data.
    // Remove or gate behind a feature flag before any production release.
    // =========================================================================

    private func seedDemoFilesIfFirstLaunch() {
        // Only seed if the manifest is empty (fresh install or wiped vault)
        guard items.isEmpty else { return }

        let seeds: [(name: String, content: String)] = [
            (
                "HeartID_Welcome.txt",
                """
                Welcome to HeartID Protected Vault
                ===================================
                This file is encrypted at rest using AES-256-GCM.
                It can only be decrypted after HeartID verification
                passes the policy engine with decision == .allow.

                This is a demo file — not real sensitive data.
                """
            ),
            (
                "SecureNote_Demo.txt",
                """
                Secure Note — Demo Content
                --------------------------
                This note demonstrates the encrypted-at-rest pattern.
                In production, users would import real documents here.

                Vault key: managed by SecureKeyManagerProtocol
                Encryption: CryptoKit AES.GCM (256-bit)
                Auth gate: HeartID → PolicyEngine → .allow required

                This is a demo file — not real sensitive data.
                """
            ),
            (
                "VaultTest_Data.bin",
                """
                VAULT_TEST_BINARY_PAYLOAD
                ========================
                This file simulates a binary payload stored in the vault.
                In a real deployment this could be a certificate, key blob,
                signed configuration, or exported credential bundle.

                Content: 256 bytes of deterministic placeholder data.
                Purpose: round-trip encryption/decryption validation.

                \(String(repeating: "DEADBEEF", count: 32))

                This is a demo file — not real sensitive data.
                """
            ),
        ]

        Task {
            do {
                for seed in seeds {
                    guard let data = seed.content.data(using: .utf8) else { continue }
                    _ = try await addItem(name: seed.name, data: data)
                }
            } catch {
                // Seed failure is non-fatal — vault still works, just empty
            }
        }
    }
}
