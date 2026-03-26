//
//  ProtectedFileVault.swift
//  CardiacID
//
//  View-facing facade that wraps HeartIDFileVault (the canonical engine)
//  and presents a singleton with the API that existing SwiftUI views expect.
//  Delegates all real crypto and manifest handling to HeartIDFileVault.
//

import Foundation
import CryptoKit

@MainActor
final class ProtectedFileVault: ObservableObject {
    static let shared = ProtectedFileVault()

    // The canonical vault engine
    private let engine: HeartIDFileVault

    // Forwarded published state
    @Published private(set) var items: [VaultItem] = []
    @Published private(set) var isLocked: Bool = true
    @Published private(set) var errorMessage: String?

    // Dependencies for HeartID-gated unlock flow
    private let policyEngine   = HeartAuthPolicyEngine.shared
    private let identityEngine = HeartIdentityEngine.shared
    private let sessionManager = SessionTrustManager.shared
    private let auditLogger    = AuditLogger.shared

    private var lockTimer: Timer?
    private let autoLockInterval: TimeInterval = 120

    private init() {
        self.engine = HeartIDFileVault()
        syncFromEngine()
    }

    // MARK: - Sync published state from engine

    private func syncFromEngine() {
        items    = engine.items
        isLocked = engine.isLocked
    }

    // MARK: - HeartID-gated unlock (used by views)

    func unlock(for action: ProtectedAction = .unlockProtectedFile) async -> Bool {
        errorMessage = nil

        if sessionManager.satisfiesTrust(for: action) {
            grantAccess()
            return true
        }

        let result   = await identityEngine.verify()
        let decision = policyEngine.evaluate(result, for: action)
        sessionManager.recordVerification(result)

        if decision.isAllowed {
            grantAccess()
            auditLogger.logOperational(action: "vault.unlock", outcome: "allowed", score: result.combinedScore)
            return true
        }

        errorMessage = "HeartID confidence too low. Score: \(pct(result.combinedScore)) (required \(pct(decision.requiredScore)))"
        auditLogger.logOperational(action: "vault.unlock", outcome: "denied", score: result.combinedScore)
        return false
    }

    func lock() {
        isLocked = true
        engine.lock()
        lockTimer?.invalidate()
        syncFromEngine()
        auditLogger.logOperational(action: "vault.lock", outcome: "locked")
    }

    // MARK: - Delegated CRUD

    @discardableResult
    func addItem(displayName: String, plaintext: Data) throws -> VaultItem {
        // Synchronous bridge: the engine's addItem is async, so we launch a task
        // and for backward compat return a placeholder. Prefer the async overload.
        let item = VaultItem.create(displayName: displayName)
        Task {
            _ = try? await engine.addItem(name: displayName, data: plaintext)
            syncFromEngine()
        }
        return item
    }

    func addItemAsync(displayName: String, plaintext: Data) async throws -> VaultItem {
        let item = try await engine.addItem(name: displayName, data: plaintext)
        syncFromEngine()
        return item
    }

    func open(_ item: VaultItem) throws -> Data {
        guard !isLocked else { throw VaultError.locked }

        // Build an .allow decision since the vault is already unlocked
        let decision = AuthPolicyDecision.allow(
            action: .unlockProtectedFile, score: 1.0, threshold: 0.75
        )

        // Bridge sync → async
        var result: Data?
        var decryptError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                result = try await engine.decryptItem(item, authorizedBy: decision)
            } catch {
                decryptError = error
            }
            semaphore.signal()
        }
        semaphore.wait()

        if let error = decryptError { throw error }
        guard let plaintext = result else { throw VaultError.decryptionFailed }
        syncFromEngine()
        return plaintext
    }

    func deleteItem(_ item: VaultItem) {
        Task {
            try? await engine.deleteItem(item)
            syncFromEngine()
        }
    }

    // MARK: - Private

    private func grantAccess() {
        isLocked = false
        scheduleAutoLock()
    }

    private func scheduleAutoLock() {
        lockTimer?.invalidate()
        lockTimer = Timer.scheduledTimer(withTimeInterval: autoLockInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.lock() }
        }
    }

    private func pct(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}

// MARK: - Errors (kept for existing view compatibility)

enum VaultError: Error, LocalizedError {
    case locked
    case encryptionFailed
    case decryptionFailed
    case itemNotFound

    var errorDescription: String? {
        switch self {
        case .locked:           return "Vault is locked — verify with HeartID first"
        case .encryptionFailed: return "Failed to encrypt file"
        case .decryptionFailed: return "Failed to decrypt file"
        case .itemNotFound:     return "File not found in vault"
        }
    }
}
