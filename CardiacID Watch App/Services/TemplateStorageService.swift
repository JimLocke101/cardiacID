//
//  TemplateStorageService.swift
//  CardiacID Watch App
//
//  Ported from HeartID_0_7 - Enterprise-Ready Secure Storage
//  Created by HeartID Team on 10/27/25.
//  Enhanced with AES-256 encryption for DOD-level security
//

import Foundation
import Security
import CryptoKit

/// Secure storage for biometric templates with AES-256 encryption
/// Always stores locally on device (never in cloud)
/// Compliant with DOD security requirements
class TemplateStorageService {
    private let keychainService = "com.cardiacid.biometric.template"
    private let templateKey = "master_template"
    private let encryptionKeyTag = "com.cardiacid.encryption.key"

    // MARK: - Template Storage (AES-256 Encrypted)

    /// Save biometric template with AES-256 encryption to Keychain
    func saveTemplate(_ template: BiometricTemplate) throws {
        // 1. Encode template to JSON
        let encoder = JSONEncoder()
        let templateData = try encoder.encode(template)

        // 2. Get or create encryption key
        let encryptionKey = try getOrCreateEncryptionKey()

        // 3. Encrypt template data using AES-256-GCM
        let encryptedData = try encryptData(templateData, using: encryptionKey)

        // 4. Delete existing template first
        deleteTemplate()

        // 5. Store encrypted template in Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: templateKey,
            kSecValueData as String: encryptedData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable as String: false // Never sync to iCloud
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw StorageError.saveFailed(status)
        }

        print("✅ Template saved securely to Keychain (AES-256 encrypted)")
        print("🔐 Encryption: AES-256-GCM | Storage: Local Keychain | Sync: Disabled")
    }

    /// Load and decrypt biometric template from Keychain
    func loadTemplate() throws -> BiometricTemplate {
        // 1. Retrieve encrypted data from Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: templateKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let encryptedData = result as? Data else {
            throw StorageError.notFound
        }

        // 2. Get encryption key
        let encryptionKey = try getOrCreateEncryptionKey()

        // 3. Decrypt template data
        let decryptedData = try decryptData(encryptedData, using: encryptionKey)

        // 4. Decode template
        let decoder = JSONDecoder()
        let template = try decoder.decode(BiometricTemplate.self, from: decryptedData)

        print("✅ Template loaded from Keychain (AES-256 decrypted)")
        return template
    }

    /// Delete biometric template from Keychain
    func deleteTemplate() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: templateKey
        ]

        SecItemDelete(query as CFDictionary)
        print("🗑️ Template deleted from Keychain")
    }

    /// Check if template exists
    func hasTemplate() -> Bool {
        do {
            _ = try loadTemplate()
            return true
        } catch {
            return false
        }
    }

    // MARK: - AES-256 Encryption/Decryption

    /// Encrypt data using AES-256-GCM
    private func encryptData(_ data: Data, using key: SymmetricKey) throws -> Data {
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            guard let combined = sealedBox.combined else {
                throw StorageError.encryptionFailed
            }
            return combined
        } catch {
            throw StorageError.encryptionFailed
        }
    }

    /// Decrypt data using AES-256-GCM
    private func decryptData(_ encryptedData: Data, using key: SymmetricKey) throws -> Data {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            return decryptedData
        } catch {
            throw StorageError.decryptionFailed
        }
    }

    // MARK: - Encryption Key Management

    /// Get existing encryption key or create new one
    private func getOrCreateEncryptionKey() throws -> SymmetricKey {
        // Try to load existing key
        if let existingKey = try? loadEncryptionKey() {
            return existingKey
        }

        // Create new key if not exists
        return try createEncryptionKey()
    }

    /// Create new AES-256 encryption key and store in Keychain
    private func createEncryptionKey() throws -> SymmetricKey {
        // Generate 256-bit symmetric key
        let key = SymmetricKey(size: .bits256)

        // Convert to Data for storage
        let keyData = key.withUnsafeBytes { Data($0) }

        // Store in Keychain with highest security
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: encryptionKeyTag,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable as String: false // Never sync to iCloud
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw StorageError.keyGenerationFailed
        }

        print("🔑 Generated new AES-256 encryption key")
        return key
    }

    /// Load encryption key from Keychain
    private func loadEncryptionKey() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: encryptionKeyTag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let keyData = result as? Data else {
            throw StorageError.keyNotFound
        }

        return SymmetricKey(data: keyData)
    }

    /// Delete encryption key (use with caution - will make existing templates unrecoverable)
    func deleteEncryptionKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: encryptionKeyTag
        ]

        SecItemDelete(query as CFDictionary)
        print("🗑️ Encryption key deleted")
    }

    // MARK: - Secure Wipe

    /// Complete secure wipe of all biometric data
    func secureWipe() {
        deleteTemplate()
        deleteEncryptionKey()
        print("🧹 Secure wipe complete - All biometric data erased")
    }
}

// MARK: - Storage Errors

enum StorageError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case notFound
    case decodingFailed
    case encryptionFailed
    case decryptionFailed
    case keyGenerationFailed
    case keyNotFound

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save template (status: \(status))"
        case .notFound:
            return "No template found. Please enroll first."
        case .decodingFailed:
            return "Failed to decode template data."
        case .encryptionFailed:
            return "Failed to encrypt template data (AES-256)"
        case .decryptionFailed:
            return "Failed to decrypt template data (AES-256)"
        case .keyGenerationFailed:
            return "Failed to generate encryption key"
        case .keyNotFound:
            return "Encryption key not found"
        }
    }
}
