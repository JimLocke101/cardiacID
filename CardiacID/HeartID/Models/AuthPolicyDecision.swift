//
//  AuthPolicyDecision.swift
//  CardiacID
//
//  Output from HeartAuthPolicyEngine after evaluating a verification result.
//  Pure value type — no UIKit, no SwiftUI, no dependencies on unwritten code.
//

import Foundation

/// The three possible outcomes of a policy evaluation.
enum PolicyDecision: String, Codable, Sendable {
    /// The verification score met or exceeded the action threshold.
    case allow          = "allow"
    /// The score was too low and no step-up is available or applicable.
    case deny           = "deny"
    /// The score was close but below threshold; a secondary factor can elevate it.
    case requireStepUp  = "require_step_up"
}

/// A complete policy evaluation record.
///
/// Produced by `HeartAuthPolicyEngine.evaluate(_:for:)`.
/// Immutable once created — safe to log, display, or transmit.
struct AuthPolicyDecision: Codable, Sendable, Equatable, Identifiable {

    let id: UUID
    let action: ProtectedAction
    let decision: PolicyDecision
    /// Human-readable explanation of why this decision was reached.
    let rationale: String
    let evaluatedAt: Date

    /// The score that was evaluated.
    let actualScore: Double
    /// The threshold the score was compared against.
    let requiredScore: Double

    // MARK: - Convenience

    var isAllowed: Bool { decision == .allow }

    // MARK: - Factories

    static func allow(
        action: ProtectedAction,
        score: Double,
        threshold: Double,
        rationale: String = "Score met or exceeded threshold."
    ) -> AuthPolicyDecision {
        AuthPolicyDecision(
            id: UUID(),
            action: action,
            decision: .allow,
            rationale: rationale,
            evaluatedAt: Date(),
            actualScore: score,
            requiredScore: threshold
        )
    }

    static func deny(
        action: ProtectedAction,
        score: Double,
        threshold: Double,
        rationale: String = "Score below threshold."
    ) -> AuthPolicyDecision {
        AuthPolicyDecision(
            id: UUID(),
            action: action,
            decision: .deny,
            rationale: rationale,
            evaluatedAt: Date(),
            actualScore: score,
            requiredScore: threshold
        )
    }

    static func stepUp(
        action: ProtectedAction,
        score: Double,
        threshold: Double,
        rationale: String = "Score in step-up range; secondary factor required."
    ) -> AuthPolicyDecision {
        AuthPolicyDecision(
            id: UUID(),
            action: action,
            decision: .requireStepUp,
            rationale: rationale,
            evaluatedAt: Date(),
            actualScore: score,
            requiredScore: threshold
        )
    }
}
