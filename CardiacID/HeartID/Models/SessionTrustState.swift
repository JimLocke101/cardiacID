//
//  SessionTrustState.swift
//  CardiacID
//
//  Tracks the user's current HeartID assurance level across the app session.
//  Pure value types — no UIKit, no SwiftUI, no dependencies on unwritten code.
//

import Foundation

// MARK: - Trust Level

/// The five discrete trust levels a user session can occupy.
enum TrustLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case unverified       = "unverified"
    case recentlyVerified = "recently_verified"
    case elevatedTrust    = "elevated_trust"
    case expired          = "expired"
    case denied           = "denied"

    var displayName: String {
        switch self {
        case .unverified:       return "Unverified"
        case .recentlyVerified: return "Recently Verified"
        case .elevatedTrust:    return "Elevated Trust"
        case .expired:          return "Expired"
        case .denied:           return "Denied"
        }
    }

    var systemImage: String {
        switch self {
        case .unverified:       return "shield"
        case .recentlyVerified: return "checkmark.shield"
        case .elevatedTrust:    return "shield.fill"
        case .expired:          return "shield.slash"
        case .denied:           return "xmark.shield.fill"
        }
    }

    // Comparable: elevatedTrust > recentlyVerified > unverified > expired > denied
    private var sortOrder: Int {
        switch self {
        case .elevatedTrust:    return 4
        case .recentlyVerified: return 3
        case .unverified:       return 2
        case .expired:          return 1
        case .denied:           return 0
        }
    }

    static func < (lhs: TrustLevel, rhs: TrustLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - Session Trust State

/// Snapshot of the session's trust status at a point in time.
/// Used by SessionTrustManager as its observable state, and by
/// SecurityEvent to record what the session looked like at log time.
struct SessionTrustState: Codable, Sendable, Equatable {

    var currentState: TrustLevel
    var lastVerified: Date?
    var lastConfidenceScore: Double

    // MARK: - Time windows

    /// How long elevated trust (≥90 % ECG) remains valid.
    static let elevatedWindow: TimeInterval = 900       // 15 min
    /// How long standard trust remains valid for sensitive actions.
    static let recentWindow: TimeInterval   = 300       // 5 min
    /// How long standard trust remains valid for low-security actions.
    static let standardWindow: TimeInterval = 1800      // 30 min

    // MARK: - Query

    /// Returns true if this session snapshot satisfies the minimum trust for `action`.
    func isValid(for action: ProtectedAction) -> Bool {
        guard let verified = lastVerified else { return false }
        guard currentState != .denied, currentState != .unverified, currentState != .expired else {
            return false
        }

        let age = Date().timeIntervalSince(verified)

        switch action {
        // Low-security: any non-expired trust within 30 min
        case .signInToApp, .beginPasskeyAssertion:
            return age < Self.standardWindow

        // Sensitive: recent or elevated trust within 5 min
        case .unlockProtectedFile, .authorizeSensitiveAction:
            return age < Self.recentWindow
                && (currentState == .recentlyVerified || currentState == .elevatedTrust)

        // High-value: elevated trust within 15 min
        case .beginPasskeyRegistration, .authorizeHardwareCommand:
            return age < Self.elevatedWindow
                && currentState == .elevatedTrust
        }
    }

    // MARK: - Display helpers

    var lastVerifiedDescription: String {
        guard let date = lastVerified else { return "Never" }
        let age = Int(Date().timeIntervalSince(date))
        switch age {
        case 0..<60:    return "\(age)s ago"
        case 60..<3600: return "\(age / 60)m ago"
        default:        return "\(age / 3600)h ago"
        }
    }

    var confidencePercentage: String {
        String(format: "%.0f%%", lastConfidenceScore * 100)
    }

    // MARK: - Factory

    static let initial = SessionTrustState(
        currentState: .unverified,
        lastVerified: nil,
        lastConfidenceScore: 0
    )
}
