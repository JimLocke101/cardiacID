//
//  SecureCredentialManager.swift
//  CardiacID
//
//  SINGLE INSTANCE - Cross-platform secure credential storage
//

import Foundation
import Security

#if os(watchOS)
import CryptoKit
#endif

enum CredentialKey: String, CaseIterable {
    case entraIDTenantID = "entra_id_tenant_id"
    case entraIDClientID = "entra_id_client_id"
    case entraIDAccessToken = "entra_id_access_token"
    case entraIDRefreshToken = "entra_id_refresh_token"
    case userProfile = "user_profile"
}

enum SecurityLevel {
    case standard
    case biometricRequired
}

final class SecureCredentialManager {
    static let shared = SecureCredentialManager()
    
    private let serviceName = "com.argos.cardiacid"
    private let accessGroup = "group.com.argos.cardiacid"
    
    #if os(watchOS)
    private let userDefaults = UserDefaults(suiteName: "group.com.argos.cardiacid")
    private let encryptionKey: SymmetricKey
    #endif
    
    private init() {
        #if os(watchOS)
        // Initialize encryption key for watchOS
        if let keyData = UserDefaults.standard.data(forKey: "encryption_key_fixed") {
            encryptionKey = SymmetricKey(data: keyData)
        } else {
            encryptionKey = SymmetricKey(size: .bits256)
            UserDefaults.standard.set(encryptionKey.withUnsafeBytes { Data($0) }, forKey: "encryption_key_fixed")
        }
        #endif
    }
    
    // MARK: - Public Methods
    
    func store(_ value: String, forKey key: CredentialKey, securityLevel: SecurityLevel = .standard) throws {
        #if os(iOS) || os(macOS)
        try storeInKeychain(value, forKey: key, securityLevel: securityLevel)
        #elseif os(watchOS)
        try storeInUserDefaults(value, forKey: key)
        #endif
    }
    
    func retrieve(forKey key: CredentialKey) throws -> String {
        #if os(iOS) || os(macOS)
        return try retrieveFromKeychain(forKey: key)
        #elseif os(watchOS)
        return try retrieveFromUserDefaults(forKey: key)
        #else
        throw CredentialError.notSupported
        #endif
    }
    
    func delete(forKey key: CredentialKey) throws {
        #if os(iOS) || os(macOS)
        try deleteFromKeychain(forKey: key)
        #elseif os(watchOS)
        try deleteFromUserDefaults(forKey: key)
        #endif
    }
    
    func exists(forKey key: CredentialKey) -> Bool {
        do {
            _ = try retrieve(forKey: key)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - iOS/macOS Keychain Implementation

#if os(iOS) || os(macOS)
extension SecureCredentialManager {
    private func storeInKeychain(_ value: String, forKey key: CredentialKey, securityLevel: SecurityLevel) throws {
        let data = value.data(using: .utf8)!
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete existing item
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialError.storageError("Keychain store failed: \(status)")
        }
    }
    
    private func retrieveFromKeychain(forKey key: CredentialKey) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            throw CredentialError.notFound("Credential not found: \(key.rawValue)")
        }
        
        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw CredentialError.corruptedData("Failed to decode credential")
        }
        
        return string
    }
    
    private func deleteFromKeychain(forKey key: CredentialKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
#endif

// MARK: - watchOS Implementation

#if os(watchOS)
extension SecureCredentialManager {
    private func storeInUserDefaults(_ value: String, forKey key: CredentialKey) throws {
        let data = value.data(using: .utf8)!
        
        do {
            let sealedBox = try AES.GCM.seal(data, using: encryptionKey)
            userDefaults?.set(sealedBox.combined, forKey: key.rawValue)
        } catch {
            throw CredentialError.encryptionError("Encryption failed: \(error)")
        }
    }
    
    private func retrieveFromUserDefaults(forKey key: CredentialKey) throws -> String {
        guard let encryptedData = userDefaults?.data(forKey: key.rawValue) else {
            throw CredentialError.notFound("Credential not found: \(key.rawValue)")
        }
        
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: encryptionKey)
            
            guard let string = String(data: decryptedData, encoding: .utf8) else {
                throw CredentialError.corruptedData("Failed to decode credential")
            }
            
            return string
        } catch {
            throw CredentialError.decryptionError("Decryption failed: \(error)")
        }
    }
    
    private func deleteFromUserDefaults(forKey key: CredentialKey) throws {
        userDefaults?.removeObject(forKey: key.rawValue)
    }
}
#endif

// MARK: - Errors

enum CredentialError: LocalizedError {
    case storageError(String)
    case notFound(String)
    case corruptedData(String)
    case encryptionError(String)
    case decryptionError(String)
    case notSupported
    
    var errorDescription: String? {
        switch self {
        case .storageError(let message): return "Storage error: \(message)"
        case .notFound(let message): return "Not found: \(message)"
        case .corruptedData(let message): return "Corrupted data: \(message)"
        case .encryptionError(let message): return "Encryption error: \(message)"
        case .decryptionError(let message): return "Decryption error: \(message)"
        case .notSupported: return "Operation not supported"
        }
    }
}
