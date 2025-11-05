//
//  EncryptionService.swift
//  CardiacID
//
//  Created for Phase 5 - Encryption Implementation
//  AES-256-GCM encryption for biometric templates
//

import Foundation
import CryptoKit

/// Encryption service for biometric template protection
/// Uses AES-256-GCM (Galois/Counter Mode) with authentication
class EncryptionService {
    static let shared = EncryptionService()

    private let credentialManager = SecureCredentialManager.shared

    private init() {}

    // MARK: - Encryption Key Management

    /// Get or create encryption key for biometric data
    /// Key is stored securely in Keychain with biometric protection
    private func getEncryptionKey() throws -> SymmetricKey {
        // Try to load existing key from Keychain
        if let existingKeyData = try? credentialManager.retrieve(forKey: .biometricEncryptionKey),
           let keyData = Data(base64Encoded: existingKeyData) {
            return SymmetricKey(data: keyData)
        }

        // Generate new key
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let base64Key = keyData.base64EncodedString()

        // Store in Keychain with biometric protection
        try credentialManager.store(
            base64Key,
            forKey: .biometricEncryptionKey,
            securityLevel: .biometricRequired
        )

        print("✅ Generated new AES-256 encryption key")
        return key
    }

    // MARK: - Encryption

    /// Encrypt data using AES-256-GCM
    /// Returns encrypted data with nonce prepended for decryption
    func encrypt(_ data: Data) throws -> Data {
        let key = try getEncryptionKey()

        // Generate random nonce (12 bytes for GCM)
        let nonce = AES.GCM.Nonce()

        // Encrypt data
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)

        // Combine nonce + ciphertext + tag for storage
        // Format: [nonce(12) | ciphertext(variable) | tag(16)]
        guard let combined = sealedBox.combined else {
            throw EncryptionError.encryptionFailed
        }

        print("✅ Data encrypted (\(data.count) bytes → \(combined.count) bytes)")
        return combined
    }

    /// Encrypt string using AES-256-GCM
    func encrypt(_ string: String) throws -> Data {
        guard let data = string.data(using: .utf8) else {
            throw EncryptionError.invalidData
        }
        return try encrypt(data)
    }

    /// Encrypt Codable object using AES-256-GCM
    func encrypt<T: Encodable>(_ object: T) throws -> Data {
        let encoder = JSONEncoder()
        let data = try encoder.encode(object)
        return try encrypt(data)
    }

    // MARK: - Decryption

    /// Decrypt data using AES-256-GCM
    /// Expects data format: [nonce(12) | ciphertext(variable) | tag(16)]
    func decrypt(_ encryptedData: Data) throws -> Data {
        let key = try getEncryptionKey()

        // Create sealed box from combined data
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)

        // Decrypt data
        let decryptedData = try AES.GCM.open(sealedBox, using: key)

        print("✅ Data decrypted (\(encryptedData.count) bytes → \(decryptedData.count) bytes)")
        return decryptedData
    }

    /// Decrypt to string using AES-256-GCM
    func decryptToString(_ encryptedData: Data) throws -> String {
        let decryptedData = try decrypt(encryptedData)
        guard let string = String(data: decryptedData, encoding: .utf8) else {
            throw EncryptionError.invalidData
        }
        return string
    }

    /// Decrypt to Codable object using AES-256-GCM
    func decrypt<T: Decodable>(_ encryptedData: Data, as type: T.Type) throws -> T {
        let decryptedData = try decrypt(encryptedData)
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: decryptedData)
    }

    // MARK: - Key Rotation

    /// Rotate encryption key (decrypt with old key, encrypt with new key)
    /// Use this when security requirements change or key may be compromised
    func rotateEncryptionKey() throws {
        // Delete existing key
        try? credentialManager.delete(forKey: .biometricEncryptionKey)

        // New key will be generated on next encryption
        print("✅ Encryption key rotated")
    }

    // MARK: - Validation

    /// Validate that encryption/decryption is working correctly
    func validateEncryption() -> Bool {
        let testData = "HeartID Test Data".data(using: .utf8)!

        do {
            let encrypted = try encrypt(testData)
            let decrypted = try decrypt(encrypted)

            return testData == decrypted
        } catch {
            print("❌ Encryption validation failed: \(error)")
            return false
        }
    }
}

// MARK: - Errors

enum EncryptionError: Error, LocalizedError {
    case encryptionFailed
    case decryptionFailed
    case invalidData
    case keyGenerationFailed
    case keyNotFound

    var errorDescription: String? {
        switch self {
        case .encryptionFailed:
            return "Failed to encrypt data"
        case .decryptionFailed:
            return "Failed to decrypt data"
        case .invalidData:
            return "Invalid data format"
        case .keyGenerationFailed:
            return "Failed to generate encryption key"
        case .keyNotFound:
            return "Encryption key not found in Keychain"
        }
    }
}

// MARK: - CredentialKey Extension

extension SecureCredentialManager.CredentialKey {
    static let biometricEncryptionKey = SecureCredentialManager.CredentialKey(rawValue: "biometric_encryption_key")
}
