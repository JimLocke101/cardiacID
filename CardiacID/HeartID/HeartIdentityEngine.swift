// HeartIdentityEngine.swift
// CardiacID
//
// Receives cardiac identity/liveness data from WatchConnectivityService,
// normalises it into a HeartVerificationResult for downstream policy evaluation.
// Does NOT make policy decisions — that is HeartAuthPolicyEngine's job.

import Foundation
import Combine

@MainActor
final class HeartIdentityEngine: ObservableObject {
    static let shared = HeartIdentityEngine()

    @Published private(set) var lastResult: HeartVerificationResult?
    @Published private(set) var isVerifying: Bool = false

    private let watchConnectivity = WatchConnectivityService.shared
    private let auditLogger       = AuditLogger.shared

    private let staleThreshold: TimeInterval = 120.0

    private init() {}

    // MARK: - Primary Entry Point

    func verify() async -> HeartVerificationResult {
        isVerifying = true
        defer { isVerifying = false }

        let result = buildResult()
        lastResult = result

        auditLogger.logOperational(
            action:     "HeartID.verify",
            outcome:    result.isAuthorized ? "authorized" : "denied",
            score:      result.combinedScore,
            reasonCode: result.reasonCodes.first?.rawValue
        )

        return result
    }

    // MARK: - Private

    private func buildResult() -> HeartVerificationResult {
        let liveConfidence = watchConnectivity.liveBiometricConfidence
        let liveTimestamp  = watchConnectivity.liveBiometricTimestamp
        let isReachable    = watchConnectivity.isReachable

        if let ts = liveTimestamp, Date().timeIntervalSince(ts) > staleThreshold {
            return .denied(reason: .staleReading)
        }

        guard isReachable, liveConfidence > 0 else {
            return .denied(reason: .watchUnreachable)
        }

        let livenessScore = min(liveConfidence + 0.05, 1.0)
        let codes: [HeartVerificationReasonCode] = (liveConfidence * 0.75 + livenessScore * 0.25) >= 0.70
            ? [.success] : [.lowConfidence]

        return .verified(match: liveConfidence, liveness: livenessScore, reasons: codes)
    }
}
