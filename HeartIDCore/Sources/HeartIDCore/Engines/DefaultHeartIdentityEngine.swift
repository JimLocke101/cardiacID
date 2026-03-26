//
//  DefaultHeartIdentityEngine.swift
//  HeartIDCore
//
//  Production implementation of HeartIdentityEngineProtocol.
//  Normalises relayed confidence + liveness into a HeartVerificationResult.
//
//  Also includes MockHeartIdentityEngine for testing.
//

import Foundation

// MARK: - Production Engine

public struct DefaultHeartIdentityEngine: HeartIdentityEngineProtocol {

    public init() {}

    public func evaluateIdentity(from input: CardiacSignalInput) async throws -> HeartVerificationResult {
        guard input.isWatchReachable else {
            return .denied(reason: .watchUnreachable)
        }

        guard !input.isStale else {
            return .denied(reason: .staleReading)
        }

        guard input.matchConfidence > 0 else {
            return .denied(reason: .notEnrolled)
        }

        let livenessBase: Double = input.isActivelyMonitoring ? 0.10 : 0.05
        let liveness = min(input.matchConfidence + livenessBase, 1.0)

        let combined = input.matchConfidence * 0.75 + liveness * 0.25
        let reasons: [HeartVerificationReasonCode] = combined >= 0.70
            ? [.success]
            : [.lowConfidence]

        return .verified(
            match: input.matchConfidence,
            liveness: liveness,
            reasons: reasons
        )
    }
}

// MARK: - Mock Engine (for testing / debug)

/// Returns configurable test results. Thread-safe.
public struct MockHeartIdentityEngine: HeartIdentityEngineProtocol {
    public var fixedMatch: Double
    public var fixedLiveness: Double
    public var fixedReasons: [HeartVerificationReasonCode]

    public init(
        match: Double = 0.85,
        liveness: Double = 0.90,
        reasons: [HeartVerificationReasonCode] = [.success]
    ) {
        self.fixedMatch = match
        self.fixedLiveness = liveness
        self.fixedReasons = reasons
    }

    public func evaluateIdentity(from input: CardiacSignalInput) async throws -> HeartVerificationResult {
        .verified(match: fixedMatch, liveness: fixedLiveness, reasons: fixedReasons)
    }

    public static let denied = MockHeartIdentityEngine(match: 0, liveness: 0, reasons: [.watchUnreachable])
}
