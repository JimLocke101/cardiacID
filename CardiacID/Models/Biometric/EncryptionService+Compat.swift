import Foundation
import CryptoKit

// Compatibility extension providing missing APIs used across the project
extension Data {
    // Encrypts heart pattern data - simple wrapper using AES.GCM encryption for demonstration
    static func encryptHeartPattern(_ data: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        return sealedBox.combined ?? Data()
    }

    // Decrypts heart pattern data - simple wrapper using AES.GCM decryption for demonstration
    static func decryptHeartPattern(_ encryptedData: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        return try AES.GCM.open(sealedBox, using: key)
    }

    // Generates random data of specified length
    static func generateRandomData(length: Int) -> Data {
        var data = Data(count: length)
        let result = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, length, $0.baseAddress!)
        }
        assert(result == errSecSuccess, "Failed to generate random bytes")
        return data
    }
}

extension String {
    // Generates a random string of specified length from alphanumeric characters
    static func generateRandomString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).compactMap { _ in letters.randomElement() })
    }

    // Hashes the string using SHA256 and returns hex string
    func hash() -> String {
        let data = Data(self.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

extension Data {
    // Hashes the data using SHA256 and returns Data
    func hash() -> Data {
        let digest = SHA256.hash(data: self)
        return Data(digest)
    }
}
