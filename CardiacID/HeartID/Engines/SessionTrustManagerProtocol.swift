//
//  SessionTrustManagerProtocol.swift
//  CardiacID
//
//  Protocol: tracks the user's HeartID assurance state across the session.
//  Auto-expires on idle: recentlyVerified → expired after 5 min,
//  elevatedTrust → expired after 15 min.
//

import Foundation

// MARK: - Protocol

/// Tracks current session trust level and auto-expires on idle.
/// Observable (SwiftUI-compatible) when implemented as a class.
protocol SessionTrustManagerProtocol: AnyObject {
    /// Record a completed HeartID verification.
    /// Updates trust level based on the combined score.
    func recordVerification(_ result: HeartVerificationResult)

    /// Return the current trust state snapshot, contextualised for an action.
    func currentTrust(for action: ProtectedAction) -> SessionTrustState

    /// Immediately expire / revoke all trust.
    func invalidate()
}
