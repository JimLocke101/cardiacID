import Foundation
import Security

/// Service for secure keychain operations
class KeychainService {
    static let shared = KeychainService()
    
    private init() {}
    
    /// Store a string value in the keychain
    func store(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        store(data, forKey: key)
    }
    
    /// Store a Data value in the keychain
    func store(_ data: Data, forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            print("Failed to store item in keychain: \(status)")
            return
        }
    }
    
    /// Retrieve a string value from the keychain
    func retrieve(forKey key: String) -> String? {
        guard let data = retrieveData(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    /// Retrieve a Data value from the keychain
    func retrieveData(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                print("Failed to retrieve item from keychain: \(status)")
            }
            return nil
        }
        
        return result as? Data
    }
    
    /// Delete an item from the keychain
    func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
    
    /// Clear all items from the keychain
    func clearAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
