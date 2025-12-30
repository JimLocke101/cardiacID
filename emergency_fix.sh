#!/bin/bash

# Emergency Fix Script for Duplicate File Issues
# This will completely resolve the SecureCredentialManager duplicate issue

echo "🚨 Emergency Fix: Resolving Duplicate File References"

PROJECT_PATH="/Users/jimlocke/Desktop/Working_folder/CardiacID"
SERVICES_PATH="$PROJECT_PATH/CardiacID/Services"

# Step 1: Navigate to project
cd "$PROJECT_PATH" || exit 1

# Step 2: Remove ALL instances of SecureCredentialManager.swift
echo "🗑️ Removing all instances of SecureCredentialManager.swift..."
find . -name "SecureCredentialManager.swift" -delete

# Step 3: Create Services directory if it doesn't exist
mkdir -p "$SERVICES_PATH"

# Step 4: Create a single, clean SecureCredentialManager.swift
echo "📝 Creating clean SecureCredentialManager.swift..."

cat > "$SERVICES_PATH/SecureCredentialManager.swift" << 'EOF'
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
EOF

echo "✅ Created clean SecureCredentialManager.swift in Services folder"
echo "📍 Location: $SERVICES_PATH/SecureCredentialManager.swift"

# Step 5: Instructions
cat << 'EOF'

🎯 NEXT STEPS IN XCODE:

1. Open your CardiacID project in Xcode
2. If you see any RED SecureCredentialManager.swift files:
   - Right-click → Delete → "Remove Reference"
3. Add the new clean file:
   - Right-click on CardiacID/Services folder
   - "Add Files to CardiacID"
   - Select the new SecureCredentialManager.swift
   - ✅ Check both iOS and watchOS targets
   - Click "Add"
4. Clean Build Folder (⌘+Shift+K)
5. Build project (⌘+B)

🚫 CRITICAL: Make sure there's only ONE SecureCredentialManager.swift in your project!

EOF

echo "🏁 Emergency fix complete! Follow the Xcode steps above."
EOF

chmod +x emergency_fix.sh
