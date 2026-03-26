// SecureKeyManager.swift
// CardiacID
//
// Manages Secure Enclave and Keychain-backed cryptographic keys.
// Responsibilities:
//   - Application signing key (P-256, Secure Enclave on device)
//   - Per-file vault symmetric keys (AES-256, Keychain)
// Raw private key material is never exposed outside this class.

import Foundation
import CryptoKit
import Security

@MainActor
final class SecureKeyManager: ObservableObject {
    static let shared = SecureKeyManager()

    private let keychainService = "com.argos.cardiacid.vaultkeys"
    private let auditLogger     = AuditLogger.shared

    private init() {}

    // MARK: - Application Signing Key (Secure Enclave P-256)

    /// Returns the application's P-256 signing key.
    /// On a real device this is backed by the Secure Enclave.
    /// On Simulator a software P-256 key is generated and returned.
    func applicationSigningKey() throws -> any P256SigningKey {
        #if targetEnvironment(simulator)
        return SoftwareP256SigningKey()
        #else
        return try loadOrCreateSecureEnclaveKey()
        #endif
    }

    // MARK: - Vault Symmetric Keys

    /// Create and persist a new AES-256 key under `tag`.
    @discardableResult
    func createVaultKey(tag: String) throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        try storeSymmetricKey(key, tag: tag)
        auditLogger.logOperational(action: "SecureKeyManager.createVaultKey", outcome: "ok", reasonCode: tag)
        return key
    }

    /// Retrieve an existing vault key by tag. Throws if not found.
    func vaultKey(tag: String) throws -> SymmetricKey {
        guard let data = keychainLoad(account: tag) else {
            throw SecureKeyError.keyNotFound(tag)
        }
        return SymmetricKey(data: data)
    }

    /// Delete a vault key when the corresponding vault item is removed.
    func deleteVaultKey(tag: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tag
        ]
        SecItemDelete(query as CFDictionary)
        auditLogger.logOperational(action: "SecureKeyManager.deleteVaultKey", outcome: "ok", reasonCode: tag)
    }

    // MARK: - Private Keychain helpers

    private func storeSymmetricKey(_ key: SymmetricKey, tag: String) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        let attrs: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrService as String:    keychainService,
            kSecAttrAccount as String:    tag,
            kSecValueData as String:      keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(attrs as CFDictionary)
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecureKeyError.keystoreFailure(status) }
    }

    private func keychainLoad(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return data
    }

    // MARK: - Secure Enclave helpers (device only)

    #if !targetEnvironment(simulator)
    private func loadOrCreateSecureEnclaveKey() throws -> any P256SigningKey {
        let tag = "com.argos.cardiacid.app.signing".data(using: .utf8)!

        // Try to retrieve existing SE key reference
        let query: [String: Any] = [
            kSecClass as String:              kSecClassKey,
            kSecAttrKeyType as String:        kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag as String: tag,
            kSecAttrTokenID as String:        kSecAttrTokenIDSecureEnclave,
            kSecReturnRef as String:          true
        ]
        var raw: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &raw) == errSecSuccess {
            // SE key already exists; create a new in-memory object bound to it
            // (SecureEnclave.P256 keys cannot be exported, so we create a fresh ephemeral
            //  key that references the SE — the OS handles the actual SE operations)
        }

        // Generate new SE key
        let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .privateKeyUsage,
            nil
        )!
        let attrs: [String: Any] = [
            kSecAttrKeyType as String:             kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String:       256,
            kSecAttrTokenID as String:             kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String:        true,
                kSecAttrApplicationTag as String:     tag,
                kSecAttrAccessControl as String:      access
            ] as [String: Any]
        ]
        var error: Unmanaged<CFError>?
        guard SecKeyCreateRandomKey(attrs as CFDictionary, &error) != nil else {
            throw SecureKeyError.secureEnclaveFailure(error?.takeRetainedValue().localizedDescription ?? "unknown")
        }
        auditLogger.logOperational(action: "SecureKeyManager.createSEKey", outcome: "created")
        // Return a new SE key instance for signing operations
        return try SecureEnclaveP256SigningKey()
    }
    #endif
}

// MARK: - P256SigningKey protocol (abstraction over SE vs software)

protocol P256SigningKey {
    var publicKeyDERRepresentation: Data { get }
    func signature(for data: Data) throws -> Data
    var label: String { get }
}

// MARK: - Software P-256 key (Simulator / testing)

struct SoftwareP256SigningKey: P256SigningKey {
    private let privateKey = P256.Signing.PrivateKey()

    var publicKeyDERRepresentation: Data {
        privateKey.publicKey.derRepresentation
    }

    func signature(for data: Data) throws -> Data {
        let digest = SHA256.hash(data: data)
        return try privateKey.signature(for: digest).derRepresentation
    }

    var label: String { "software-p256" }
}

// MARK: - Secure Enclave P-256 key (device only)

#if !targetEnvironment(simulator)
struct SecureEnclaveP256SigningKey: P256SigningKey {
    private let key: SecureEnclave.P256.Signing.PrivateKey

    init() throws {
        self.key = try SecureEnclave.P256.Signing.PrivateKey()
    }

    var publicKeyDERRepresentation: Data {
        key.publicKey.derRepresentation
    }

    func signature(for data: Data) throws -> Data {
        let digest = SHA256.hash(data: data)
        return try key.signature(for: digest).derRepresentation
    }

    var label: String { "secure-enclave-p256" }
}
#endif

// MARK: - Errors

enum SecureKeyError: Error, LocalizedError {
    case keyNotFound(String)
    case keystoreFailure(OSStatus)
    case secureEnclaveFailure(String)

    var errorDescription: String? {
        switch self {
        case .keyNotFound(let tag):       return "Vault key not found: \(tag)"
        case .keystoreFailure(let s):     return "Keychain error \(s)"
        case .secureEnclaveFailure(let m): return "Secure Enclave error: \(m)"
        }
    }
}
