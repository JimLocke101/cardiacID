//
//  DefaultHeartIdentityEngine.swift
//  CardiacID
//
//  Production implementation of HeartIdentityEngineProtocol.
//  Adapts CardiacSignalInput (populated from WatchConnectivityService / HeartIDService)
//  into a normalised HeartVerificationResult.
//
//  Also includes a MockHeartIdentityEngine for testing.
//

import Foundation

// MARK: - Production Engine

/// Evaluates cardiac signal data received from the Watch biometric pipeline.
/// Does not perform biometric matching itself — that happens on-Watch.
/// This engine normalises the relayed confidence + liveness into a
/// HeartVerificationResult for downstream policy evaluation.
struct DefaultHeartIdentityEngine: HeartIdentityEngineProtocol {

    func evaluateIdentity(from input: CardiacSignalInput) async throws -> HeartVerificationResult {
        // Guard: Watch unreachable
        guard input.isWatchReachable else {
            return .denied(reason: .watchUnreachable)
        }

        // Guard: stale reading
        guard !input.isStale else {
            return .denied(reason: .staleReading)
        }

        // Guard: zero confidence means no enrolled template or sensor failure
        guard input.matchConfidence > 0 else {
            return .denied(reason: .notEnrolled)
        }

        // Derive liveness from active monitoring state + confidence floor.
        // PPG stream continuity while wrist-worn implies a live user.
        // Small positive offset capped at 1.0 reflects on-wrist certainty.
        let livenessBase: Double = input.isActivelyMonitoring ? 0.10 : 0.05
        let liveness = min(input.matchConfidence + livenessBase, 1.0)

        // Reason code
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

// MARK: - Adapter: WatchConnectivityService → CardiacSignalInput

extension CardiacSignalInput {
    /// Create a CardiacSignalInput snapshot from the current state of WatchConnectivityService.
    /// Call this from @MainActor context since WatchConnectivityService is @MainActor.
    @MainActor
    static func fromWatchConnectivity(_ wc: WatchConnectivityService) -> CardiacSignalInput {
        CardiacSignalInput(
            matchConfidence:      wc.liveBiometricConfidence,
            method:               wc.liveBiometricMethod,
            isActivelyMonitoring: wc.isWatchActivelyMonitoring,
            isAuthenticated:      wc.liveBiometricAuthenticated,
            sampleTimestamp:      wc.liveBiometricTimestamp,
            heartRate:            wc.lastHeartRate > 0 ? wc.lastHeartRate : nil,
            isWatchReachable:     wc.isReachable || wc.isEffectivelyConnected
        )
    }
}

// MARK: - Mock Engine (DEBUG only — never compiled into Release)

#if DEBUG
/// Debug/test-only mock engine. Returns configurable fixed results.
/// SECURITY: Gated by #if DEBUG. Not present in production binary.
struct MockHeartIdentityEngine: HeartIdentityEngineProtocol {
    var fixedMatch: Double
    var fixedLiveness: Double
    var fixedReasons: [HeartVerificationReasonCode]

    init(
        match: Double = 0.85,
        liveness: Double = 0.90,
        reasons: [HeartVerificationReasonCode] = [.success]
    ) {
        self.fixedMatch = match
        self.fixedLiveness = liveness
        self.fixedReasons = reasons
    }

    func evaluateIdentity(from input: CardiacSignalInput) async throws -> HeartVerificationResult {
        .verified(match: fixedMatch, liveness: fixedLiveness, reasons: fixedReasons)
    }

    static let denied = MockHeartIdentityEngine(match: 0, liveness: 0, reasons: [.watchUnreachable])
}
#endif
