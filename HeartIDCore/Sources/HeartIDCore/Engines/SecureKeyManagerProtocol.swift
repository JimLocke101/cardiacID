//
//  SecureKeyManagerProtocol.swift
//  HeartIDCore
//
//  Protocol: manages Keychain-backed symmetric vault keys.
//
//  CRITICAL ARCHITECTURE RULE:
//  The Secure Enclave cannot be directly gated by HeartID scores.
//  HeartID acts as policy gate that decides whether to PROCEED to LAContext.
//  LAContext (Face ID / passcode) is the actual SE unlock mechanism.
//

import Foundation
import CryptoKit

// MARK: - Protocol

public protocol SecureKeyManagerProtocol: Sendable {
    func retrieveOrCreateVaultKey() async throws -> SymmetricKey
    func wrapKey(_ key: SymmetricKey) async throws -> Data
    func unwrapKey(_ wrappedKey: Data) async throws -> SymmetricKey
}

// MARK: - Errors

public enum SecureKeyManagerError: Error, LocalizedError, Sendable {
    case keyNotFound
    case keychainError(OSStatus)
    case wrapFailed
    case unwrapFailed
    case laContextDenied(String)

    public var errorDescription: String? {
        switch self {
        case .keyNotFound:           return "Vault key not found in Keychain"
        case .keychainError(let s):  return "Keychain error: \(s)"
        case .wrapFailed:            return "Failed to wrap key"
        case .unwrapFailed:          return "Failed to unwrap key"
        case .laContextDenied(let r): return "Biometric/passcode denied: \(r)"
        }
    }
}
