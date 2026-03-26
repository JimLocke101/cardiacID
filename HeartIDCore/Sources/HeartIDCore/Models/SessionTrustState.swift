//
//  SessionTrustState.swift
//  HeartIDCore
//
//  Tracks the user's current HeartID assurance level across the app session.
//

import Foundation

// MARK: - Trust Level

/// The five discrete trust levels a user session can occupy.
public enum TrustLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case unverified       = "unverified"
    case recentlyVerified = "recently_verified"
    case elevatedTrust    = "elevated_trust"
    case expired          = "expired"
    case denied           = "denied"

    public var displayName: String {
        switch self {
        case .unverified:       return "Unverified"
        case .recentlyVerified: return "Recently Verified"
        case .elevatedTrust:    return "Elevated Trust"
        case .expired:          return "Expired"
        case .denied:           return "Denied"
        }
    }

    public var systemImage: String {
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

    public static func < (lhs: TrustLevel, rhs: TrustLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - Session Trust State

/// Snapshot of the session's trust status at a point in time.
public struct SessionTrustState: Codable, Sendable, Equatable {

    public var currentState: TrustLevel
    public var lastVerified: Date?
    public var lastConfidenceScore: Double

    // MARK: - Time windows

    /// How long elevated trust (≥90 % ECG) remains valid.
    public static let elevatedWindow: TimeInterval = 900       // 15 min
    /// How long standard trust remains valid for sensitive actions.
    public static let recentWindow: TimeInterval   = 300       // 5 min
    /// How long standard trust remains valid for low-security actions.
    public static let standardWindow: TimeInterval = 1800      // 30 min

    // MARK: - Query

    /// Returns true if this session snapshot satisfies the minimum trust for `action`.
    public func isValid(for action: ProtectedAction) -> Bool {
        guard let verified = lastVerified else { return false }
        guard currentState != .denied, currentState != .unverified, currentState != .expired else {
            return false
        }

        let age = Date().timeIntervalSince(verified)

        switch action {
        case .signInToApp, .beginPasskeyAssertion:
            return age < Self.standardWindow

        case .unlockProtectedFile, .authorizeSensitiveAction:
            return age < Self.recentWindow
                && (currentState == .recentlyVerified || currentState == .elevatedTrust)

        case .beginPasskeyRegistration, .authorizeHardwareCommand:
            return age < Self.elevatedWindow
                && currentState == .elevatedTrust
        }
    }

    // MARK: - Display helpers

    public var lastVerifiedDescription: String {
        guard let date = lastVerified else { return "Never" }
        let age = Int(Date().timeIntervalSince(date))
        switch age {
        case 0..<60:    return "\(age)s ago"
        case 60..<3600: return "\(age / 60)m ago"
        default:        return "\(age / 3600)h ago"
        }
    }

    public var confidencePercentage: String {
        String(format: "%.0f%%", lastConfidenceScore * 100)
    }

    // MARK: - Factory

    public static let initial = SessionTrustState(
        currentState: .unverified,
        lastVerified: nil,
        lastConfidenceScore: 0
    )

    public init(currentState: TrustLevel, lastVerified: Date?, lastConfidenceScore: Double) {
        self.currentState = currentState
        self.lastVerified = lastVerified
        self.lastConfidenceScore = lastConfidenceScore
    }
}
