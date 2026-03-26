//
//  SecureKeyManagerTests.swift
//  CardiacIDTests
//
//  Tests SecureKeyManagerProtocol wrap/unwrap and key consistency.
//  Uses an in-memory MockSecureKeyManager — no real Keychain required.
//  No biometric hardware. No network calls.
//

import XCTest
import CryptoKit
@testable import CardiacID

final class SecureKeyManagerTests: XCTestCase {

    private var keyManager: MockSecureKeyManager!

    override func setUp() {
        super.setUp()
        keyManager = MockSecureKeyManager()
    }

    // MARK: - retrieveOrCreateVaultKey returns same key on repeated calls

    func testRetrieveOrCreate_returnsSameKeyTwice() async throws {
        let key1 = try await keyManager.retrieveOrCreateVaultKey()
        let key2 = try await keyManager.retrieveOrCreateVaultKey()

        XCTAssertEqual(
            key1.withUnsafeBytes { Data($0) },
            key2.withUnsafeBytes { Data($0) },
            "Two consecutive retrievals must return the same vault key"
        )
    }

    func testRetrieveOrCreate_keyIs256Bits() async throws {
        let key = try await keyManager.retrieveOrCreateVaultKey()
        let size = key.withUnsafeBytes { Data($0) }.count
        XCTAssertEqual(size, 32, "Vault key must be 256 bits (32 bytes)")
    }

    // MARK: - Wrap / unwrap round-trip produces equivalent SymmetricKey

    func testWrapUnwrap_roundTrip() async throws {
        let original = SymmetricKey(size: .bits256)
        let wrapped = try await keyManager.wrapKey(original)
        let unwrapped = try await keyManager.unwrapKey(wrapped)

        XCTAssertEqual(
            original.withUnsafeBytes { Data($0) },
            unwrapped.withUnsafeBytes { Data($0) },
            "Unwrapped key must match the original"
        )
    }

    func testWrapUnwrap_multipleDifferentKeys() async throws {
        let key1 = SymmetricKey(size: .bits256)
        let key2 = SymmetricKey(size: .bits256)

        let wrapped1 = try await keyManager.wrapKey(key1)
        let wrapped2 = try await keyManager.wrapKey(key2)

        // Wrapped blobs differ (different keys + random AES-GCM nonce)
        XCTAssertNotEqual(wrapped1, wrapped2)

        let unwrapped1 = try await keyManager.unwrapKey(wrapped1)
        let unwrapped2 = try await keyManager.unwrapKey(wrapped2)

        XCTAssertEqual(key1.withUnsafeBytes { Data($0) },
                       unwrapped1.withUnsafeBytes { Data($0) })
        XCTAssertEqual(key2.withUnsafeBytes { Data($0) },
                       unwrapped2.withUnsafeBytes { Data($0) })
    }

    // MARK: - Wrapped data is ciphertext (not plaintext)

    func testWrappedData_isNotPlaintextKey() async throws {
        let original = SymmetricKey(size: .bits256)
        let originalBytes = original.withUnsafeBytes { Data($0) }
        let wrapped = try await keyManager.wrapKey(original)

        XCTAssertNotEqual(wrapped, originalBytes,
                          "Wrapped output must not be raw key bytes")
        XCTAssertGreaterThan(wrapped.count, originalBytes.count,
                             "AES-GCM adds nonce + tag overhead")
    }

    // MARK: - Corrupted wrapped data fails unwrap

    func testUnwrap_corruptedData_throws() async throws {
        let key = SymmetricKey(size: .bits256)
        var wrapped = try await keyManager.wrapKey(key)

        if wrapped.count > 15 { wrapped[15] ^= 0xFF }

        do {
            _ = try await keyManager.unwrapKey(wrapped)
            XCTFail("Unwrapping corrupted data should throw")
        } catch let error as SecureKeyManagerError {
            if case .unwrapFailed = error { /* expected */ } else {
                XCTFail("Expected .unwrapFailed, got \(error)")
            }
        }
    }

    func testUnwrap_emptyData_throws() async {
        do {
            _ = try await keyManager.unwrapKey(Data())
            XCTFail("Unwrapping empty data should throw")
        } catch {
            // Expected
        }
    }

    // MARK: - Different instances share the same key (singleton behavior)

    func testDifferentInstances_shareKey() async throws {
        // Both instances backed by the same static shared key
        let mgr1 = MockSecureKeyManager()
        let mgr2 = MockSecureKeyManager()

        let key1 = try await mgr1.retrieveOrCreateVaultKey()
        let key2 = try await mgr2.retrieveOrCreateVaultKey()

        XCTAssertEqual(
            key1.withUnsafeBytes { Data($0) },
            key2.withUnsafeBytes { Data($0) },
            "Both instances should return the same vault key"
        )
    }

    // MARK: - Cross-instance wrap/unwrap

    func testCrossInstance_wrapUnwrap() async throws {
        let mgr1 = MockSecureKeyManager()
        let mgr2 = MockSecureKeyManager()

        let fileKey = SymmetricKey(size: .bits256)
        let wrapped = try await mgr1.wrapKey(fileKey)
        let unwrapped = try await mgr2.unwrapKey(wrapped)

        XCTAssertEqual(
            fileKey.withUnsafeBytes { Data($0) },
            unwrapped.withUnsafeBytes { Data($0) },
            "Key wrapped by instance 1 must unwrap by instance 2"
        )
    }
}

// MARK: - In-memory mock (no real Keychain)

/// Thread-safe mock key manager that stores the vault key in memory.
/// Mimics DefaultSecureKeyManager behavior without Keychain access.
private final class MockSecureKeyManager: SecureKeyManagerProtocol, @unchecked Sendable {
    /// Shared across all instances to simulate Keychain persistence
    private static let vaultKey = SymmetricKey(size: .bits256)

    func retrieveOrCreateVaultKey() async throws -> SymmetricKey {
        Self.vaultKey
    }

    func wrapKey(_ key: SymmetricKey) async throws -> Data {
        let plain = key.withUnsafeBytes { Data($0) }
        guard let sealed = try? AES.GCM.seal(plain, using: Self.vaultKey),
              let combined = sealed.combined else {
            throw SecureKeyManagerError.wrapFailed
        }
        return combined
    }

    func unwrapKey(_ wrappedKey: Data) async throws -> SymmetricKey {
        guard let box = try? AES.GCM.SealedBox(combined: wrappedKey),
              let plain = try? AES.GCM.open(box, using: Self.vaultKey) else {
            throw SecureKeyManagerError.unwrapFailed
        }
        return SymmetricKey(data: plain)
    }
}
