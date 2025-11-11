import Foundation
import Security

/// Secure credential management using Keychain Services
class SecureCredentialManager {
    static let shared = SecureCredentialManager()
    
    private init() {}
    
    enum CredentialKey: String, CaseIterable {
        case entraIDTenantID = "entraid_tenant_id"
        case entraIDClientID = "entraid_client_id"
        case entraIDAccessToken = "entraid_access_token"
        case entraIDRefreshToken = "entraid_refresh_token"
        case supabaseAPIKey = "supabase_api_key"
        case supabaseURL = "supabase_url"
        case heartIDEncryptionKey = "heartid_encryption_key"
        case deviceAuthToken = "device_auth_token"
    }
    
    enum SecurityLevel {
        case standard
        case biometricRequired
        case passcodeRequired
    }
    
    func store(_ value: String, forKey key: CredentialKey, securityLevel: SecurityLevel = .standard) throws {
        let data = Data(value.utf8)
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Add biometric protection if required
        if securityLevel == .biometricRequired {
            let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .biometryAny,
                nil
            )
            query[kSecAttrAccessControl as String] = access
        }
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.storeFailed(status)
        }
    }
    
    func retrieve(forKey key: CredentialKey) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            throw KeychainError.retrieveFailed(status)
        }
        
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        
        return value
    }
    
    func delete(forKey key: CredentialKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
    
    func deleteAll() throws {
        for key in CredentialKey.allCases {
            try? delete(forKey: key)
        }
    }
    
    func hasCredential(forKey key: CredentialKey) -> Bool {
        return (try? retrieve(forKey: key)) != nil
    }
}

enum KeychainError: LocalizedError {
    case storeFailed(OSStatus)
    case retrieveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .storeFailed(let status):
            return "Failed to store credential: \(status)"
        case .retrieveFailed(let status):
            return "Failed to retrieve credential: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete credential: \(status)"
        case .invalidData:
            return "Invalid credential data"
        }
    }
}