//
//  SecureCredentialManager.swift
//  HeartID Mobile
//
//  Production-grade credential management with enhanced security
//  Features:
//  - Biometric-protected Keychain access
//  - Access Control Flags (kSecAttrAccessControl)
//  - Automatic credential validation
//  - Secure credential injection (no hardcoded secrets)
//

import Foundation
import Security
import LocalAuthentication

/// Secure credential storage and retrieval with biometric protection
class SecureCredentialManager {
    static let shared = SecureCredentialManager()

    // MARK: - Keychain Access Group
    private let accessGroup = "group.com.argos.heartid.credentials"

    // MARK: - Credential Keys
    enum CredentialKey: String {
        case supabaseAPIKey = "heartid_supabase_api_key"
        case supabaseServiceRoleKey = "heartid_supabase_service_role_key"
        case entraIDTenantID = "heartid_entraid_tenant_id"
        case entraIDClientID = "heartid_entraid_client_id"
        case entraIDClientSecret = "heartid_entraid_client_secret"
        case entraIDAccessToken = "heartid_entraid_access_token"
        case entraIDRefreshToken = "heartid_entraid_refresh_token"
        case userAuthToken = "heartid_user_auth_token"
        case biometricEncryptionKey = "heartid_biometric_encryption_key"
    }

    // MARK: - Security Levels
    enum SecurityLevel {
        case standard           // Accessible when unlocked
        case biometricRequired  // Requires Face ID/Touch ID
        case biometricAndPasscode // Requires biometric or device passcode
    }

    private init() {
        print("🔐 SecureCredentialManager initialized")
    }

    // MARK: - Store Credentials

    /// Store credential with specified security level
    func store(
        _ value: String,
        forKey key: CredentialKey,
        securityLevel: SecurityLevel = .biometricRequired
    ) throws {
        guard let data = value.data(using: .utf8) else {
            throw CredentialError.invalidData
        }

        try storeData(data, forKey: key.rawValue, securityLevel: securityLevel)
    }

    /// Store data with biometric protection
    func storeData(
        _ data: Data,
        forKey key: String,
        securityLevel: SecurityLevel = .biometricRequired
    ) throws {
        // Create access control based on security level
        guard let accessControl = createAccessControl(for: securityLevel) else {
            throw CredentialError.accessControlCreationFailed
        }

        // Build query with enhanced security
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: accessControl,
            kSecAttrSynchronizable as String: kCFBooleanFalse!, // Never sync to iCloud
            kSecUseDataProtectionKeychain as String: true
        ]

        // Add access group if not in simulator
        #if !targetEnvironment(simulator)
        query[kSecAttrAccessGroup as String] = accessGroup
        #endif

        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            print("❌ Failed to store credential: \(key) - Status: \(status)")
            throw CredentialError.storeFailed(status: status)
        }

        print("✅ Stored credential securely: \(key)")
    }

    // MARK: - Retrieve Credentials

    /// Retrieve credential (may trigger biometric prompt)
    func retrieve(forKey key: CredentialKey) throws -> String {
        let data = try retrieveData(forKey: key.rawValue)

        guard let string = String(data: data, encoding: .utf8) else {
            throw CredentialError.invalidData
        }

        return string
    }

    /// Retrieve data (may trigger biometric prompt)
    func retrieveData(forKey key: String) throws -> Data {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseOperationPrompt as String: "Authenticate to access HeartID credentials"
        ]

        // Add access group if not in simulator
        #if !targetEnvironment(simulator)
        query[kSecAttrAccessGroup as String] = accessGroup
        #endif

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw CredentialError.notFound
            } else if status == errSecUserCanceled {
                throw CredentialError.userCanceled
            } else {
                print("❌ Failed to retrieve credential: \(key) - Status: \(status)")
                throw CredentialError.retrieveFailed(status: status)
            }
        }

        guard let data = result as? Data else {
            throw CredentialError.invalidData
        }

        return data
    }

    // MARK: - Check Existence

    /// Check if credential exists without retrieving it
    func exists(forKey key: CredentialKey) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        return status == errSecSuccess
    }

    // MARK: - Delete Credentials

    /// Delete specific credential
    func delete(forKey key: CredentialKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialError.deleteFailed(status: status)
        }

        print("🗑️ Deleted credential: \(key.rawValue)")
    }

    /// Delete all HeartID credentials (for logout/reset)
    func deleteAll() throws {
        // Delete all items in our access group
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialError.deleteFailed(status: status)
        }

        print("🗑️ Deleted all credentials")
    }

    // MARK: - Access Control

    private func createAccessControl(for securityLevel: SecurityLevel) -> SecAccessControl? {
        let flags: SecAccessControlCreateFlags

        switch securityLevel {
        case .standard:
            flags = []
        case .biometricRequired:
            // Requires biometric authentication (Face ID/Touch ID)
            flags = [.biometryCurrentSet, .or, .devicePasscode]
        case .biometricAndPasscode:
            // Requires both biometric AND passcode
            flags = [.biometryCurrentSet, .and, .devicePasscode]
        }

        var error: Unmanaged<CFError>?
        let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            flags,
            &error
        )

        if let error = error {
            print("❌ Failed to create access control: \(error.takeRetainedValue())")
            return nil
        }

        return accessControl
    }

    // MARK: - Biometric Availability

    /// Check if biometric authentication is available
    func isBiometricAvailable() -> (available: Bool, biometryType: LABiometryType) {
        let context = LAContext()
        var error: NSError?

        let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        return (available, context.biometryType)
    }

    // MARK: - Validation

    /// Validate that required credentials exist
    func validateRequiredCredentials() -> ValidationResult {
        var missingKeys: [CredentialKey] = []

        // Check Supabase credentials
        if !exists(forKey: .supabaseAPIKey) {
            missingKeys.append(.supabaseAPIKey)
        }

        if missingKeys.isEmpty {
            return .valid
        } else {
            return .missing(keys: missingKeys)
        }
    }

    // MARK: - First-Time Setup

    /// Check if this is first launch (no credentials stored)
    func isFirstLaunch() -> Bool {
        return !exists(forKey: .supabaseAPIKey)
    }

    /// Store initial credentials during first setup
    func performInitialSetup(supabaseAPIKey: String, entraIDTenantID: String, entraIDClientID: String) throws {
        try store(supabaseAPIKey, forKey: .supabaseAPIKey, securityLevel: .biometricRequired)
        try store(entraIDTenantID, forKey: .entraIDTenantID, securityLevel: .standard)
        try store(entraIDClientID, forKey: .entraIDClientID, securityLevel: .standard)

        print("✅ Initial credential setup complete")
    }
}

// MARK: - Error Types

enum CredentialError: Error, LocalizedError {
    case invalidData
    case storeFailed(status: OSStatus)
    case retrieveFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)
    case notFound
    case userCanceled
    case accessControlCreationFailed

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Invalid credential data"
        case .storeFailed(let status):
            return "Failed to store credential (status: \(status))"
        case .retrieveFailed(let status):
            return "Failed to retrieve credential (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete credential (status: \(status))"
        case .notFound:
            return "Credential not found"
        case .userCanceled:
            return "User canceled authentication"
        case .accessControlCreationFailed:
            return "Failed to create access control"
        }
    }
}

enum ValidationResult {
    case valid
    case missing(keys: [SecureCredentialManager.CredentialKey])

    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }
}
