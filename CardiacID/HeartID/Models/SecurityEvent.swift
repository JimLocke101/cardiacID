//
//  SecurityEvent.swift
//  CardiacID
//
//  Structured audit record for a protected-action attempt.
//  Pure value type — no UIKit, no SwiftUI, no dependencies on unwritten code.
//  Never contains raw biometric signal data or cryptographic key material.
//

import Foundation

/// An immutable record of one protected-action attempt, its policy outcome,
/// and the session state at the time of evaluation.
struct SecurityEvent: Codable, Sendable, Equatable, Identifiable {

    let id: UUID
    let timestamp: Date

    /// The action that was attempted.
    let action: ProtectedAction

    /// The policy engine's decision for this attempt.
    let decision: PolicyDecision

    /// Session trust level at the instant this event was created.
    let sessionStateAtTime: TrustLevel

    /// Machine-readable reason code explaining the decision (from HeartVerificationReasonCode).
    let reasonCode: String

    // MARK: - Convenience initialiser

    init(
        action: ProtectedAction,
        decision: PolicyDecision,
        sessionState: TrustLevel,
        reasonCode: String
    ) {
        self.id                 = UUID()
        self.timestamp          = Date()
        self.action             = action
        self.decision           = decision
        self.sessionStateAtTime = sessionState
        self.reasonCode         = reasonCode
    }

    // MARK: - Full memberwise (for decoding / testing)

    init(
        id: UUID,
        timestamp: Date,
        action: ProtectedAction,
        decision: PolicyDecision,
        sessionStateAtTime: TrustLevel,
        reasonCode: String
    ) {
        self.id                 = id
        self.timestamp          = timestamp
        self.action             = action
        self.decision           = decision
        self.sessionStateAtTime = sessionStateAtTime
        self.reasonCode         = reasonCode
    }
}
