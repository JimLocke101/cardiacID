//
//  DefaultHeartAuthPolicyEngine.swift
//  HeartIDCore
//
//  Production implementation of HeartAuthPolicyEngineProtocol.
//  Fail closed: any error or missing data returns .deny.
//

import Foundation

public struct DefaultHeartAuthPolicyEngine: HeartAuthPolicyEngineProtocol {

    public let configuration: PolicyConfiguration

    public init(configuration: PolicyConfiguration = .loadFromDefaults()) {
        self.configuration = configuration
    }

    public func evaluate(result: HeartVerificationResult, for action: ProtectedAction) -> AuthPolicyDecision {
        let threshold = configuration.threshold(for: action)
        let score     = result.combinedScore

        guard score > 0 else {
            return .deny(
                action: action, score: score, threshold: threshold,
                rationale: "No valid biometric data. Fail closed."
            )
        }

        if score >= threshold {
            return .allow(
                action: action, score: score, threshold: threshold,
                rationale: "Score \(pct(score)) meets threshold \(pct(threshold))."
            )
        }

        let stepUpFloor = threshold * 0.80
        if score >= stepUpFloor {
            return .stepUp(
                action: action, score: score, threshold: threshold,
                rationale: "Score \(pct(score)) in step-up range (\(pct(stepUpFloor))–\(pct(threshold))). Secondary factor required."
            )
        }

        return .deny(
            action: action, score: score, threshold: threshold,
            rationale: "Score \(pct(score)) below minimum \(pct(stepUpFloor))."
        )
    }

    private func pct(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}
