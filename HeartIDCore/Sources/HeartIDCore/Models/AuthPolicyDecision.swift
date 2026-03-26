//
//  AuthPolicyDecision.swift
//  HeartIDCore
//
//  Output from HeartAuthPolicyEngine after evaluating a verification result.
//

import Foundation

/// The three possible outcomes of a policy evaluation.
public enum PolicyDecision: String, Codable, Sendable {
    case allow          = "allow"
    case deny           = "deny"
    case requireStepUp  = "require_step_up"
}

/// A complete policy evaluation record.
public struct AuthPolicyDecision: Codable, Sendable, Equatable, Identifiable {

    public let id: UUID
    public let action: ProtectedAction
    public let decision: PolicyDecision
    public let rationale: String
    public let evaluatedAt: Date
    public let actualScore: Double
    public let requiredScore: Double

    public var isAllowed: Bool { decision == .allow }

    public init(
        id: UUID = UUID(),
        action: ProtectedAction,
        decision: PolicyDecision,
        rationale: String,
        evaluatedAt: Date = Date(),
        actualScore: Double,
        requiredScore: Double
    ) {
        self.id = id
        self.action = action
        self.decision = decision
        self.rationale = rationale
        self.evaluatedAt = evaluatedAt
        self.actualScore = actualScore
        self.requiredScore = requiredScore
    }

    // MARK: - Factories

    public static func allow(
        action: ProtectedAction,
        score: Double,
        threshold: Double,
        rationale: String = "Score met or exceeded threshold."
    ) -> AuthPolicyDecision {
        AuthPolicyDecision(
            action: action,
            decision: .allow,
            rationale: rationale,
            actualScore: score,
            requiredScore: threshold
        )
    }

    public static func deny(
        action: ProtectedAction,
        score: Double,
        threshold: Double,
        rationale: String = "Score below threshold."
    ) -> AuthPolicyDecision {
        AuthPolicyDecision(
            action: action,
            decision: .deny,
            rationale: rationale,
            actualScore: score,
            requiredScore: threshold
        )
    }

    public static func stepUp(
        action: ProtectedAction,
        score: Double,
        threshold: Double,
        rationale: String = "Score in step-up range; secondary factor required."
    ) -> AuthPolicyDecision {
        AuthPolicyDecision(
            action: action,
            decision: .requireStepUp,
            rationale: rationale,
            actualScore: score,
            requiredScore: threshold
        )
    }
}
