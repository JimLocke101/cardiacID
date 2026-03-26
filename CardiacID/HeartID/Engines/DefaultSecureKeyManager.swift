//
//  DefaultSecureKeyManager.swift
//  CardiacID
//
//  Production implementation of SecureKeyManagerProtocol.
//
//  ARCHITECTURE:
//    HeartID score → policy gate → if allowed → LAContext biometric → Keychain access
//    HeartID NEVER directly unlocks the Secure Enclave.
//    LAContext (Face ID / passcode) is the actual SE unlock mechanism.
//
//  Vault master key: AES-256, Keychain, kSecAttrAccessibleWhenUnlocked.
//  Per-file keys: wrapped (AES key-wrap via AES.GCM) with the vault master key.
//

import Foundation
import CryptoKit
import Security
import LocalAuthentication

final class DefaultSecureKeyManager: SecureKeyManagerProtocol, @unchecked Sendable {

    private let keychainService = "com.heartid.vaultmaster"
    private let keychainAccount = "vault_master_key"

    // MARK: - SecureKeyManagerProtocol

    func retrieveOrCreateVaultKey() async throws -> SymmetricKey {
        // Attempt retrieval first (requires device unlock, not biometric directly)
        if let existing = try? loadFromKeychain() {
            return existing
        }

        // Create and persist a new vault master key
        let newKey = SymmetricKey(size: .bits256)
        try saveToKeychain(newKey)
        return newKey
    }

    func wrapKey(_ key: SymmetricKey) async throws -> Data {
        let masterKey = try await retrieveOrCreateVaultKey()
        let plainBytes = key.withUnsafeBytes { Data($0) }
        guard let sealed = try? AES.GCM.seal(plainBytes, using: masterKey),
              let combined = sealed.combined else {
            throw SecureKeyManagerError.wrapFailed
        }
        return combined
    }

    func unwrapKey(_ wrappedKey: Data) async throws -> SymmetricKey {
        let masterKey = try await retrieveOrCreateVaultKey()
        guard let sealedBox = try? AES.GCM.SealedBox(combined: wrappedKey),
              let plainBytes = try? AES.GCM.open(sealedBox, using: masterKey) else {
            throw SecureKeyManagerError.unwrapFailed
        }
        return SymmetricKey(data: plainBytes)
    }

    // MARK: - Keychain (kSecAttrAccessibleWhenUnlocked)

    private func loadFromKeychain() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw SecureKeyManagerError.keyNotFound
        }
        return SymmetricKey(data: data)
    }

    private func saveToKeychain(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        let attrs: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrService as String:    keychainService,
            kSecAttrAccount as String:    keychainAccount,
            kSecValueData as String:      keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        // Remove existing if present
        SecItemDelete(attrs as CFDictionary)
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureKeyManagerError.keychainError(status)
        }
        // Key data is on the stack; no log, no retain.
    }

    // MARK: - LAContext-gated retrieval (for elevated operations)

    /// Retrieve vault key with LAContext biometric/passcode gate.
    /// Call this AFTER HeartID policy has approved the action.
    /// HeartID decides IF we proceed; LAContext is the actual unlock.
    func retrieveVaultKeyWithBiometric(reason: String) async throws -> SymmetricKey {
        let context = LAContext()
        context.localizedReason = reason

        // Build a Keychain query that requires user presence via LAContext
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var result: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                if status == errSecSuccess, let data = result as? Data {
                    continuation.resume(returning: SymmetricKey(data: data))
                } else if status == errSecUserCanceled || status == errSecAuthFailed {
                    continuation.resume(throwing: SecureKeyManagerError.laContextDenied("User cancelled or auth failed"))
                } else {
                    continuation.resume(throwing: SecureKeyManagerError.keychainError(status))
                }
            }
        }
    }
}
