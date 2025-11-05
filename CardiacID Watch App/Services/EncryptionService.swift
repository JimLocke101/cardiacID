import Foundation
import CryptoKit

/// Service for encrypting and decrypting sensitive data
class EncryptionService {
    private let key: SymmetricKey
    
    init() {
        // In a real app, this should be derived from a secure keychain entry
        // For now, we'll use a static key (this should be changed in production)
        let keyData = "HeartID_Encryption_Key_2024".data(using: .utf8) ?? Data()
        self.key = SymmetricKey(data: keyData)
    }
    
    // MARK: - XenonX Result Encryption
    
    /// Encrypt a XenonX result
    func encryptXenonXResult(_ result: XenonXResult) -> Data? {
        do {
            let data = try JSONEncoder().encode(result)
            return try encrypt(data)
        } catch {
            print("Failed to encrypt XenonX result: \(error)")
            return nil
        }
    }
    
    /// Decrypt a XenonX result
    func decryptXenonXResult(_ data: Data) -> XenonXResult? {
        do {
            let decryptedData = try decrypt(data)
            return try JSONDecoder().decode(XenonXResult.self, from: decryptedData)
        } catch {
            print("Failed to decrypt XenonX result: \(error)")
            return nil
        }
    }
    
    // MARK: - Generic Encryption
    
    /// Encrypt data using AES-GCM
    func encrypt(_ data: Data) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        
        // Combine nonce, ciphertext, and tag
        var encryptedData = Data()
        encryptedData.append(sealedBox.nonce.withUnsafeBytes { Data($0) })
        encryptedData.append(sealedBox.ciphertext)
        encryptedData.append(sealedBox.tag)
        
        return encryptedData
    }
    
    /// Decrypt data using AES-GCM
    func decrypt(_ data: Data) throws -> Data {
        guard data.count > 12 else { // 12 bytes for nonce + at least 1 byte for ciphertext + 16 bytes for tag
            throw EncryptionError.invalidData
        }
        
        let nonceSize = 12
        let tagSize = 16
        
        let nonce = data.prefix(nonceSize)
        let ciphertext = data.dropFirst(nonceSize).dropLast(tagSize)
        let tag = data.suffix(tagSize)
        
        let sealedBox = try AES.GCM.SealedBox(
            nonce: try AES.GCM.Nonce(data: nonce),
            ciphertext: ciphertext,
            tag: tag
        )
        
        return try AES.GCM.open(sealedBox, using: key)
    }
    
    // MARK: - String Encryption
    
    /// Encrypt a string
    func encryptString(_ string: String) -> String? {
        guard let data = string.data(using: .utf8) else { return nil }
        
        do {
            let encryptedData = try encrypt(data)
            return encryptedData.base64EncodedString()
        } catch {
            print("Failed to encrypt string: \(error)")
            return nil
        }
    }
    
    /// Decrypt a string
    func decryptString(_ encryptedString: String) -> String? {
        guard let data = Data(base64Encoded: encryptedString) else { return nil }
        
        do {
            let decryptedData = try decrypt(data)
            return String(data: decryptedData, encoding: .utf8)
        } catch {
            print("Failed to decrypt string: \(error)")
            return nil
        }
    }
    
    // MARK: - Hash Functions
    
    /// Generate SHA-256 hash of data
    func hash(_ data: Data) -> String {
        let hashed = SHA256.hash(data: data)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Generate SHA-256 hash of string
    func hashString(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "" }
        return hash(data)
    }
    
    // MARK: - Key Management
    
    /// Generate a new encryption key
    static func generateKey() -> SymmetricKey {
        return SymmetricKey(size: .bits256)
    }
    
    /// Convert key to data
    static func keyToData(_ key: SymmetricKey) -> Data {
        return key.withUnsafeBytes { Data($0) }
    }
    
    /// Create key from data
    static func keyFromData(_ data: Data) -> SymmetricKey {
        return SymmetricKey(data: data)
    }
}

// MARK: - Encryption Errors

enum EncryptionError: Error, LocalizedError {
    case invalidData
    case encryptionFailed
    case decryptionFailed
    case keyGenerationFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Invalid data provided for encryption/decryption"
        case .encryptionFailed:
            return "Failed to encrypt data"
        case .decryptionFailed:
            return "Failed to decrypt data"
        case .keyGenerationFailed:
            return "Failed to generate encryption key"
        }
    }
}