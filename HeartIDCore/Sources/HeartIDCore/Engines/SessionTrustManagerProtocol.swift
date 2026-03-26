//
//  SessionTrustManagerProtocol.swift
//  HeartIDCore
//
//  Protocol: tracks the user's HeartID assurance state across the session.
//

import Foundation

/// Tracks current session trust level and auto-expires on idle.
/// Observable (SwiftUI-compatible) when implemented as a class.
@MainActor
public protocol SessionTrustManagerProtocol: AnyObject {
    /// Record a completed HeartID verification.
    func recordVerification(_ result: HeartVerificationResult)

    /// Return the current trust state snapshot, contextualised for an action.
    func currentTrust(for action: ProtectedAction) -> SessionTrustState

    /// Immediately expire / revoke all trust.
    func invalidate()
}
