//
//  ProtectedAction.swift
//  HeartIDCore
//
//  Actions that require HeartID policy approval before proceeding.
//

import Foundation

/// Every operation gated by the HeartID policy engine.
/// Each case carries a default confidence threshold and a human-readable label.
public enum ProtectedAction: String, Codable, Sendable, CaseIterable, Identifiable {

    case unlockProtectedFile      = "unlock_protected_file"
    case signInToApp              = "sign_in_to_app"
    case authorizeSensitiveAction = "authorize_sensitive_action"
    case authorizeHardwareCommand = "authorize_hardware_command"
    case beginPasskeyRegistration = "begin_passkey_registration"
    case beginPasskeyAssertion    = "begin_passkey_assertion"

    public var id: String { rawValue }

    // MARK: - Display

    public var displayName: String {
        switch self {
        case .unlockProtectedFile:      return "Unlock Protected File"
        case .signInToApp:              return "Sign In to App"
        case .authorizeSensitiveAction: return "Authorize Sensitive Action"
        case .authorizeHardwareCommand: return "Authorize Hardware Command"
        case .beginPasskeyRegistration: return "Register Passkey"
        case .beginPasskeyAssertion:    return "Passkey Sign-In"
        }
    }

    public var systemImage: String {
        switch self {
        case .unlockProtectedFile:      return "lock.doc.fill"
        case .signInToApp:              return "person.crop.circle.badge.checkmark"
        case .authorizeSensitiveAction: return "exclamationmark.shield.fill"
        case .authorizeHardwareCommand: return "cpu.fill"
        case .beginPasskeyRegistration: return "key.fill"
        case .beginPasskeyAssertion:    return "key.horizontal.fill"
        }
    }

    // MARK: - Default Policy Threshold

    /// Minimum `HeartVerificationResult.combinedScore` required by default policy.
    public var defaultThreshold: Double {
        switch self {
        case .signInToApp:              return 0.70
        case .unlockProtectedFile:      return 0.75
        case .beginPasskeyAssertion:    return 0.75
        case .authorizeSensitiveAction: return 0.80
        case .beginPasskeyRegistration: return 0.85
        case .authorizeHardwareCommand: return 0.85
        }
    }
}
