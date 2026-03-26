//
//  ProtectedFileVaultTests.swift
//  CardiacIDTests
//
//  Tests HeartIDFileVault encrypt/decrypt round-trip, manifest CRUD,
//  and policy-denied decryption.
//  Uses temp directory — never touches Application Support.
//  Uses MockHeartIdentityEngine — no biometric hardware.
//  No network calls.
//

import XCTest
import CryptoKit
@testable import CardiacID

@MainActor
final class ProtectedFileVaultTests: XCTestCase {

    private var vault: HeartIDFileVault!
    private var tempDir: URL!

    override func setUp() async throws {
        // Create isolated temp directory for each test
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HeartIDVaultTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Vault with test key manager and no-op audit logger
        vault = HeartIDFileVault(
            keyManager: TestKeyManager(),
            auditLogger: NullAuditLogger()
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        vault = nil
    }

    // MARK: - Encrypt → Decrypt round-trip produces identical Data

    func testEncryptDecrypt_roundTrip_identicalData() async throws {
        let original = "HeartID secure content — round-trip test".data(using: .utf8)!
        let item = try await vault.addItem(name: "RoundTrip.txt", data: original)

        let allow = AuthPolicyDecision.allow(action: .unlockProtectedFile, score: 0.90, threshold: 0.75)
        let decrypted = try await vault.decryptItem(item, authorizedBy: allow)

        XCTAssertEqual(original, decrypted, "Decrypted data must match original plaintext exactly")
    }

    func testEncryptDecrypt_binaryData() async throws {
        // Test with non-UTF8 binary payload
        var binary = Data(count: 1024)
        for i in 0..<1024 { binary[i] = UInt8(i % 256) }

        let item = try await vault.addItem(name: "Binary.bin", data: binary)
        let allow = AuthPolicyDecision.allow(action: .unlockProtectedFile, score: 0.90, threshold: 0.75)
        let decrypted = try await vault.decryptItem(item, authorizedBy: allow)

        XCTAssertEqual(binary, decrypted)
    }

    // MARK: - decryptItem with .deny throws

    func testDecryptItem_denyDecision_throws() async throws {
        let item = try await vault.addItem(name: "Denied.txt", data: Data("secret".utf8))
        let deny = AuthPolicyDecision.deny(action: .unlockProtectedFile, score: 0.40, threshold: 0.75)

        do {
            _ = try await vault.decryptItem(item, authorizedBy: deny)
            XCTFail("decryptItem with .deny should throw")
        } catch let error as ProtectedFileVaultError {
            if case .denied = error { /* expected */ } else {
                XCTFail("Expected .denied error, got \(error)")
            }
        }
    }

    func testDecryptItem_requireStepUp_throws() async throws {
        let item = try await vault.addItem(name: "StepUp.txt", data: Data("secret".utf8))
        let stepUp = AuthPolicyDecision.stepUp(action: .unlockProtectedFile, score: 0.65, threshold: 0.75)

        do {
            _ = try await vault.decryptItem(item, authorizedBy: stepUp)
            XCTFail("decryptItem with .requireStepUp should throw")
        } catch let error as ProtectedFileVaultError {
            if case .denied = error { /* expected */ } else {
                XCTFail("Expected .denied error, got \(error)")
            }
        }
    }

    // MARK: - Adding item creates manifest entry

    func testAddItem_createsManifestEntry() async throws {
        // Allow any async seed Task from init to settle
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2s

        let countBefore = vault.items.count
        _ = try await vault.addItem(name: "NewFile.txt", data: Data("content".utf8))
        XCTAssertEqual(vault.items.count, countBefore + 1,
                       "Adding an item must increase the manifest count by exactly 1")
    }

    func testAddItem_namePreserved() async throws {
        let item = try await vault.addItem(name: "SpecificName.txt", data: Data("data".utf8))
        XCTAssertEqual(item.displayName, "SpecificName.txt")
        XCTAssertTrue(vault.items.contains(where: { $0.id == item.id }))
    }

    func testAddItem_encryptedReferenceIsDotEnc() async throws {
        let item = try await vault.addItem(name: "Test.txt", data: Data("abc".utf8))
        XCTAssertTrue(item.encryptedDataReference.hasSuffix(".enc"),
                      "Encrypted file reference should end with .enc")
    }

    // MARK: - Deleting item removes from manifest

    func testDeleteItem_removesFromManifest() async throws {
        let item = try await vault.addItem(name: "ToDelete.txt", data: Data("bye".utf8))
        XCTAssertTrue(vault.items.contains(where: { $0.id == item.id }))

        try await vault.deleteItem(item)
        XCTAssertFalse(vault.items.contains(where: { $0.id == item.id }),
                       "Item must be removed from manifest after deletion")
    }

    func testDeleteItem_subsequentDecryptFails() async throws {
        let item = try await vault.addItem(name: "Gone.txt", data: Data("gone".utf8))
        try await vault.deleteItem(item)

        let allow = AuthPolicyDecision.allow(action: .unlockProtectedFile, score: 0.90, threshold: 0.75)
        do {
            _ = try await vault.decryptItem(item, authorizedBy: allow)
            XCTFail("Decrypting deleted item should throw")
        } catch {
            // Expected — item not found
        }
    }

    // MARK: - Multiple items

    func testMultipleItems_independentEncryption() async throws {
        let data1 = Data("File One Content".utf8)
        let data2 = Data("File Two Content".utf8)

        let item1 = try await vault.addItem(name: "One.txt", data: data1)
        let item2 = try await vault.addItem(name: "Two.txt", data: data2)

        let allow = AuthPolicyDecision.allow(action: .unlockProtectedFile, score: 0.90, threshold: 0.75)
        let dec1 = try await vault.decryptItem(item1, authorizedBy: allow)
        let dec2 = try await vault.decryptItem(item2, authorizedBy: allow)

        XCTAssertEqual(dec1, data1)
        XCTAssertEqual(dec2, data2)
        XCTAssertNotEqual(dec1, dec2, "Different files should have different content")
    }

    // MARK: - Lock state

    func testLock_setsAllItemsLocked() async throws {
        _ = try await vault.addItem(name: "A.txt", data: Data("a".utf8))
        _ = try await vault.addItem(name: "B.txt", data: Data("b".utf8))

        vault.lock()

        XCTAssertTrue(vault.isLocked)
        for item in vault.items {
            XCTAssertTrue(item.isLocked, "All items should be locked after vault.lock()")
        }
    }
}

// MARK: - Test doubles

/// In-memory key manager that never touches the real Keychain.
private struct TestKeyManager: SecureKeyManagerProtocol, @unchecked Sendable {
    private static let sharedKey = SymmetricKey(size: .bits256)

    func retrieveOrCreateVaultKey() async throws -> SymmetricKey {
        Self.sharedKey
    }

    func wrapKey(_ key: SymmetricKey) async throws -> Data {
        let plain = key.withUnsafeBytes { Data($0) }
        let sealed = try AES.GCM.seal(plain, using: Self.sharedKey)
        return sealed.combined!
    }

    func unwrapKey(_ wrappedKey: Data) async throws -> SymmetricKey {
        let box = try AES.GCM.SealedBox(combined: wrappedKey)
        let plain = try AES.GCM.open(box, using: Self.sharedKey)
        return SymmetricKey(data: plain)
    }
}

/// Audit logger that discards all events (test isolation).
private actor NullAuditLogger: AuditLoggerProtocol {
    func log(_ event: SecurityEvent) {}
}
