//
//  HeartIDError.swift
//  HeartIDCore
//
//  Unified error type for the HeartID security layer.
//

import Foundation

public enum HeartIDError: Error, LocalizedError, Sendable {
    case policyDenied(String)
    case stepUpRequired(String)
    case verificationExpired
    case vaultLocked
    case keychainError(String)
    case encryptionError(String)
    case unknown(Error)

    public var errorDescription: String? {
        switch self {
        case .policyDenied(let r):    return "Policy denied: \(r)"
        case .stepUpRequired(let r):  return "Step-up required: \(r)"
        case .verificationExpired:    return "HeartID verification has expired"
        case .vaultLocked:            return "Vault is locked — verify with HeartID first"
        case .keychainError(let r):   return "Keychain error: \(r)"
        case .encryptionError(let r): return "Encryption error: \(r)"
        case .unknown(let e):         return "Unknown error: \(e.localizedDescription)"
        }
    }
}
