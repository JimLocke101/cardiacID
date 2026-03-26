//
//  HeartVerificationResult.swift
//  HeartIDCore
//
//  Normalised output from HeartIdentityEngine.
//

import Foundation

// MARK: - Reason Codes

/// Machine-readable reason codes that explain why a verification
/// succeeded or failed. Logged by AuditLogger; never contains raw biometric data.
public enum HeartVerificationReasonCode: String, Codable, Sendable, CaseIterable {
    case success              = "success"
    case watchUnreachable     = "watch_unreachable"
    case staleReading         = "stale_reading"
    case lowConfidence        = "low_confidence"
    case livenessCheckFailed  = "liveness_check_failed"
    case notEnrolled          = "not_enrolled"
    case templateMismatch     = "template_mismatch"
    case wristRemoved         = "wrist_removed"
    case sensorError          = "sensor_error"
    case timeout              = "timeout"
}

// MARK: - Verification Result

/// The single, canonical output of a HeartID verification cycle.
///
/// `matchConfidence`   — how closely the live signal matches the enrolled template (0–1).
/// `livenessConfidence` — probability that the signal comes from a live, wrist-worn user (0–1).
/// `combinedScore`      — weighted blend consumed by the policy engine (computed, 0–1).
public struct HeartVerificationResult: Codable, Sendable, Equatable, Identifiable {

    public let id: UUID
    public let timestamp: Date

    /// Raw template-match confidence from the Watch biometric engine.
    public let matchConfidence: Double

    /// Liveness confidence derived from PPG/ECG stream continuity and wrist detection.
    public let livenessConfidence: Double

    /// Ordered list of reason codes explaining the outcome.
    public let reasonCodes: [HeartVerificationReasonCode]

    // MARK: - Computed

    /// Weighted blend: 75 % match + 25 % liveness.
    public var combinedScore: Double {
        matchConfidence * 0.75 + livenessConfidence * 0.25
    }

    /// Convenience: true when the combined score meets the minimum viable threshold (70 %).
    public var isAuthorized: Bool {
        combinedScore >= 0.70
    }

    /// True when liveness confidence indicates a live, wrist-worn user.
    public var isLive: Bool {
        livenessConfidence >= 0.60
    }

    // MARK: - Memberwise Init

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        matchConfidence: Double,
        livenessConfidence: Double,
        reasonCodes: [HeartVerificationReasonCode]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.matchConfidence = matchConfidence
        self.livenessConfidence = livenessConfidence
        self.reasonCodes = reasonCodes
    }

    // MARK: - Factories

    /// A result representing an unavailable or failed verification.
    public static func denied(reason: HeartVerificationReasonCode) -> HeartVerificationResult {
        HeartVerificationResult(
            matchConfidence: 0,
            livenessConfidence: 0,
            reasonCodes: [reason]
        )
    }

    /// A result representing a successful verification with known scores.
    public static func verified(
        match: Double,
        liveness: Double,
        reasons: [HeartVerificationReasonCode] = [.success]
    ) -> HeartVerificationResult {
        HeartVerificationResult(
            matchConfidence: max(0, min(1, match)),
            livenessConfidence: max(0, min(1, liveness)),
            reasonCodes: reasons
        )
    }
}
