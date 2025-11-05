//
//  TemplateStorageService.swift
//  CardiacID
//
//  Ported from HeartID_0_7 Watch App
//  Created by HeartID Team on 10/27/25.
//  Secure local template storage using Keychain
//

import Foundation
import Security

/// Secure storage for biometric templates
/// Always stores locally on device (never in cloud)
class TemplateStorageService {
    private let keychainService = "com.heartid.biometric.template"
    private let templateKey = "master_template"

    // MARK: - Template Storage

    func saveTemplate(_ template: BiometricTemplate) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(template)

        // Delete existing template first
        deleteTemplate()

        // Store in Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: templateKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw StorageError.saveFailed(status)
        }

        print("✅ Template saved securely to Keychain")
    }

    func loadTemplate() throws -> BiometricTemplate {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: templateKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data else {
            throw StorageError.notFound
        }

        let decoder = JSONDecoder()
        let template = try decoder.decode(BiometricTemplate.self, from: data)

        print("✅ Template loaded from Keychain")
        return template
    }

    func deleteTemplate() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: templateKey
        ]

        SecItemDelete(query as CFDictionary)
        print("🗑️ Template deleted from Keychain")
    }

    func hasTemplate() -> Bool {
        do {
            _ = try loadTemplate()
            return true
        } catch {
            return false
        }
    }
}

enum StorageError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case notFound
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save template (status: \(status))"
        case .notFound:
            return "No template found. Please enroll first."
        case .decodingFailed:
            return "Failed to decode template data."
        }
    }
}
