//
//  SecureKeyManagerProtocol.swift
//  CardiacID
//
//  Protocol: manages Keychain-backed symmetric vault keys.
//
//  CRITICAL ARCHITECTURE RULE:
//  The Secure Enclave cannot be directly gated by HeartID scores.
//  The correct pattern is:
//    1. HeartID pre-checks BEFORE calling LAContext
//    2. LAContext (Face ID / passcode) is the actual SE unlock mechanism
//    3. HeartID acts as policy gate that decides whether to PROCEED to LAContext
//    4. Never attempt to bypass or replace LAContext for SE operations
//

import Foundation
import CryptoKit

// MARK: - Protocol

/// Manages Keychain-backed vault keys for file encryption.
///
/// Implementation rules:
/// - Use `kSecAttrAccessibleWhenUnlocked` for vault keys
/// - Use `LAContext` for SE-backed key retrieval (not HeartID directly)
/// - Never return `SymmetricKey` across async contexts unnecessarily
/// - Never log key material
protocol SecureKeyManagerProtocol: Sendable {
    /// Retrieve the vault master key, creating it if it does not exist.
    /// The Keychain entry is protected by `kSecAttrAccessibleWhenUnlocked`.
    /// On devices with Secure Enclave, retrieval requires LAContext.
    func retrieveOrCreateVaultKey() async throws -> SymmetricKey

    /// Wrap (encrypt) a per-file symmetric key using the vault master key.
    func wrapKey(_ key: SymmetricKey) async throws -> Data

    /// Unwrap (decrypt) a per-file symmetric key using the vault master key.
    func unwrapKey(_ wrappedKey: Data) async throws -> SymmetricKey
}

// MARK: - Errors

enum SecureKeyManagerError: Error, LocalizedError, Sendable {
    case keyNotFound
    case keychainError(OSStatus)
    case wrapFailed
    case unwrapFailed
    case laContextDenied(String)

    var errorDescription: String? {
        switch self {
        case .keyNotFound:           return "Vault key not found in Keychain"
        case .keychainError(let s):  return "Keychain error: \(s)"
        case .wrapFailed:            return "Failed to wrap key"
        case .unwrapFailed:          return "Failed to unwrap key"
        case .laContextDenied(let r): return "Biometric/passcode denied: \(r)"
        }
    }
}
