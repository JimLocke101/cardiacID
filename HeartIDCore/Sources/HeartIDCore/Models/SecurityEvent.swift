//
//  SecurityEvent.swift
//  HeartIDCore
//
//  Structured audit record for a protected-action attempt.
//  Never contains raw biometric signal data or cryptographic key material.
//

import Foundation

/// An immutable record of one protected-action attempt, its policy outcome,
/// and the session state at the time of evaluation.
public struct SecurityEvent: Codable, Sendable, Equatable, Identifiable {

    public let id: UUID
    public let timestamp: Date
    public let action: ProtectedAction
    public let decision: PolicyDecision
    public let sessionStateAtTime: TrustLevel
    public let reasonCode: String

    public init(
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

    public init(
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
