//
//  DefaultHeartAuthPolicyEngine.swift
//  CardiacID
//
//  Production implementation of HeartAuthPolicyEngineProtocol.
//  Stores thresholds in PolicyConfiguration (UserDefaults-loadable).
//  Fail closed: any error or missing data returns .deny.
//

import Foundation

struct DefaultHeartAuthPolicyEngine: HeartAuthPolicyEngineProtocol {

    /// Current policy configuration.
    /// Loaded from UserDefaults on init; falls back to production defaults.
    let configuration: PolicyConfiguration

    init(configuration: PolicyConfiguration = .loadFromDefaults()) {
        self.configuration = configuration
    }

    // MARK: - HeartAuthPolicyEngineProtocol

    func evaluate(result: HeartVerificationResult, for action: ProtectedAction) -> AuthPolicyDecision {
        let threshold = configuration.threshold(for: action)
        let score     = result.combinedScore

        // Fail closed: score of zero or negative is always deny
        guard score > 0 else {
            return .deny(
                action: action, score: score, threshold: threshold,
                rationale: "No valid biometric data. Fail closed."
            )
        }

        // Allow: score meets or exceeds threshold
        if score >= threshold {
            return .allow(
                action: action, score: score, threshold: threshold,
                rationale: "Score \(pct(score)) meets threshold \(pct(threshold))."
            )
        }

        // Step-up zone: score is within 80–100% of threshold
        let stepUpFloor = threshold * 0.80
        if score >= stepUpFloor {
            return .stepUp(
                action: action, score: score, threshold: threshold,
                rationale: "Score \(pct(score)) in step-up range (\(pct(stepUpFloor))–\(pct(threshold))). Secondary factor required."
            )
        }

        // Deny: score too far below threshold
        return .deny(
            action: action, score: score, threshold: threshold,
            rationale: "Score \(pct(score)) below minimum \(pct(stepUpFloor))."
        )
    }

    private func pct(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}
