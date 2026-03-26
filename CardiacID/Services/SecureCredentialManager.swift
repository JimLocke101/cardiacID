//
//  SecureCredentialManager.swift
//  CardiacID
//
//  Cross-platform secure credential storage
//  Uses Keychain on iOS and UserDefaults with encryption on watchOS
//

import Foundation
import Security
import CryptoKit

enum CredentialKey: String, CaseIterable {
    case entraIDTenantID = "entra_id_tenant_id"
    case entraIDClientID = "entra_id_client_id"
    case entraIDAccessToken = "entra_id_access_token"
    case entraIDRefreshToken = "entra_id_refresh_token"
    case userProfile = "user_profile"
    case heartIDPattern = "heart_id_pattern"
    case biometricEncryptionKey = "biometric_encryption_key"
    case supabaseAPIKey = "supabase_api_key"
    case supabaseURL = "supabase_url"
    case radiusSharedSecret = "radius_shared_secret"
}

enum SecurityLevel {
    case standard
    case biometricRequired
    case devicePasscodeRequired
}

class SecureCredentialManager {
    static let shared = SecureCredentialManager()
    
    private let serviceName = "com.argos.cardiacid"
    private let accessGroup = "group.com.argos.cardiacid"
    
    #if os(watchOS)
    // On watchOS, use UserDefaults with app group and encryption
    private let userDefaults = UserDefaults(suiteName: "group.com.argos.cardiacid")
    private let encryptionKey: SymmetricKey
    #endif
    
    private init() {
        #if os(watchOS)
        // Generate or retrieve encryption key for watchOS
        if let keyData = UserDefaults.standard.data(forKey: "encryption_key") {
            encryptionKey = SymmetricKey(data: keyData)
        } else {
            encryptionKey = SymmetricKey(size: .bits256)
            UserDefaults.standard.set(encryptionKey.withUnsafeBytes { Data($0) }, forKey: "encryption_key")
        }
        #endif
    }
    
    // MARK: - Storage Methods
    
    func store(_ value: String, forKey key: CredentialKey, securityLevel: SecurityLevel = .standard) throws {
        #if os(iOS)
        try storeInKeychain(value, forKey: key, securityLevel: securityLevel)
        #else
        try storeInUserDefaults(value, forKey: key)
        #endif
    }
    
    func retrieve(forKey key: CredentialKey) throws -> String {
        #if os(iOS)
        return try retrieveFromKeychain(forKey: key)
        #else
        return try retrieveFromUserDefaults(forKey: key)
        #endif
    }
    
    func delete(forKey key: CredentialKey) throws {
        #if os(iOS)
        try deleteFromKeychain(forKey: key)
        #else
        try deleteFromUserDefaults(forKey: key)
        #endif
    }
    
    func exists(forKey key: CredentialKey) -> Bool {
        #if os(iOS)
        return existsInKeychain(forKey: key)
        #else
        return existsInUserDefaults(forKey: key)
        #endif
    }
    
    // MARK: - iOS Keychain Implementation
    
    #if os(iOS)
    private func storeInKeychain(_ value: String, forKey key: CredentialKey, securityLevel: SecurityLevel) throws {
        let data = value.data(using: .utf8)!
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessGroup as String: accessGroup
        ]
        
        // Add biometric protection if required
        switch securityLevel {
        case .biometricRequired:
            query[kSecAttrAccessControl as String] = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .biometryAny,
                nil
            )
        case .devicePasscodeRequired:
            query[kSecAttrAccessControl as String] = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                [],
                nil
            )
        case .standard:
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        
        // Delete any existing item first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialError.storageError("Failed to store credential: \(status)")
        }
    }
    
    private func retrieveFromKeychain(forKey key: CredentialKey) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrAccessGroup as String: accessGroup,
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
            throw CredentialError.corruptedData("Failed to decode credential data")
        }
        
        return string
    }
    
    private func deleteFromKeychain(forKey key: CredentialKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrAccessGroup as String: accessGroup
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialError.storageError("Failed to delete credential: \(status)")
        }
    }
    
    private func existsInKeychain(forKey key: CredentialKey) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrAccessGroup as String: accessGroup,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    #endif
    
    // MARK: - watchOS UserDefaults Implementation
    
    #if os(watchOS)
    private func storeInUserDefaults(_ value: String, forKey key: CredentialKey) throws {
        let data = value.data(using: .utf8)!
        
        do {
            let sealedBox = try AES.GCM.seal(data, using: encryptionKey)
            let encryptedData = sealedBox.combined
            userDefaults?.set(encryptedData, forKey: key.rawValue)
        } catch {
            throw CredentialError.encryptionError("Failed to encrypt credential: \(error)")
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
                throw CredentialError.corruptedData("Failed to decode credential data")
            }
            
            return string
        } catch {
            throw CredentialError.decryptionError("Failed to decrypt credential: \(error)")
        }
    }
    
    private func deleteFromUserDefaults(forKey key: CredentialKey) throws {
        userDefaults?.removeObject(forKey: key.rawValue)
    }
    
    private func existsInUserDefaults(forKey key: CredentialKey) -> Bool {
        return userDefaults?.data(forKey: key.rawValue) != nil
    }
    #endif
    
    // MARK: - Utility Methods
    
    func clearAllCredentials() throws {
        for key in CredentialKey.allCases {
            try? delete(forKey: key)
        }
    }
    
    func exportCredentials() throws -> [String: String] {
        var credentials: [String: String] = [:]
        
        for key in CredentialKey.allCases {
            if let value = try? retrieve(forKey: key) {
                credentials[key.rawValue] = value
            }
        }
        
        return credentials
    }
}

// MARK: - Errors

enum CredentialError: LocalizedError {
    case storageError(String)
    case notFound(String)
    case corruptedData(String)
    case encryptionError(String)
    case decryptionError(String)
    
    var errorDescription: String? {
        switch self {
        case .storageError(let message):
            return "Storage error: \(message)"
        case .notFound(let message):
            return "Not found: \(message)"
        case .corruptedData(let message):
            return "Corrupted data: \(message)"
        case .encryptionError(let message):
            return "Encryption error: \(message)"
        case .decryptionError(let message):
            return "Decryption error: \(message)"
        }
    }
}