// EncryptionService+Compat.swift
import Foundation
import CryptoKit

extension EncryptionService {
    // Heart pattern helpers used by older code
    func encryptHeartPattern(_ data: Data) throws -> Data {
        return try encrypt(data)
    }

    func decryptHeartPattern(_ data: Data) throws -> Data {
        return try decrypt(data)
    }

    func generateRandomData(length: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        if status == errSecSuccess { return Data(bytes) }
        throw NSError(domain: "EncryptionService", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Random generation failed"])
    }

    func generateRandomString(length: Int) throws -> String {
        let data = try generateRandomData(length: length)
        return data.base64EncodedString()
    }

    func hash(_ data: Data) -> Data {
        let digest = SHA256.hash(data: data)
        return Data(digest)
    }
}
