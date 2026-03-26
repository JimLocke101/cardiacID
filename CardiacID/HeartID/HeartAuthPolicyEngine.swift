// HeartAuthPolicyEngine.swift
// CardiacID
//
// Evaluates a HeartVerificationResult against configurable per-action policies.
// Returns AuthPolicyDecision (allow / deny / requireStepUp).

import Foundation

@MainActor
final class HeartAuthPolicyEngine: ObservableObject {
    static let shared = HeartAuthPolicyEngine()

    @Published var customThresholds: [ProtectedAction: Double] = [:]

    private let auditLogger = AuditLogger.shared

    private init() {}

    // MARK: - Evaluate

    func evaluate(
        _ result: HeartVerificationResult,
        for action: ProtectedAction
    ) -> AuthPolicyDecision {
        let required = effectiveThreshold(for: action)
        let actual   = result.combinedScore

        let decision: AuthPolicyDecision
        switch actual {
        case required...:
            decision = .allow(action: action, score: actual, threshold: required)
        case (required * 0.80)..<required:
            decision = .stepUp(action: action, score: actual, threshold: required,
                               rationale: "Score \(pct(actual)) in step-up range (\(pct(required * 0.80))–\(pct(required))). Secondary factor required.")
        default:
            decision = .deny(action: action, score: actual, threshold: required,
                             rationale: "Score \(pct(actual)) below minimum \(pct(required)).")
        }

        auditLogger.logOperational(
            action:     "policy.\(action.rawValue)",
            outcome:    decision.decision.rawValue,
            score:      actual,
            reasonCode: result.reasonCodes.first?.rawValue
        )

        return decision
    }

    // MARK: - Threshold management

    func effectiveThreshold(for action: ProtectedAction) -> Double {
        customThresholds[action] ?? action.defaultThreshold
    }

    func setThreshold(_ threshold: Double, for action: ProtectedAction) {
        customThresholds[action] = min(max(threshold, 0.50), 1.00)
    }

    func resetThresholds() {
        customThresholds = [:]
    }

    var policySummary: [(action: ProtectedAction, threshold: Double, isCustom: Bool)] {
        ProtectedAction.allCases.map { action in
            (action, effectiveThreshold(for: action), customThresholds[action] != nil)
        }
    }

    private func pct(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}
