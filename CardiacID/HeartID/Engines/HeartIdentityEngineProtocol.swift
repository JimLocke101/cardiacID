//
//  HeartIdentityEngineProtocol.swift
//  CardiacID
//
//  Protocol: receives cardiac signal input, produces HeartVerificationResult.
//  Implementations bridge to existing HeartIDService + WatchConnectivityService
//  or return mock data for testing.
//

import Foundation

// MARK: - Cardiac Signal Input

/// Clean adapter wrapping whatever cardiac data the existing project provides.
/// Populated from WatchConnectivityService live biometric fields or from
/// HeartIDService direct readings.
struct CardiacSignalInput: Sendable {
    /// Template-match confidence reported by the Watch biometric engine (0–1).
    let matchConfidence: Double
    /// Biometric method used ("ppg", "ecg", "hybrid").
    let method: String
    /// Whether the Watch is actively monitoring PPG.
    let isActivelyMonitoring: Bool
    /// Whether the Watch reports the user as authenticated.
    let isAuthenticated: Bool
    /// Timestamp of the biometric reading on the Watch.
    let sampleTimestamp: Date?
    /// Heart rate at time of reading (BPM), if available.
    let heartRate: Int?
    /// Whether the Watch is reachable right now.
    let isWatchReachable: Bool

    /// Maximum age (seconds) before a reading is considered stale.
    static let staleThreshold: TimeInterval = 120.0

    var isStale: Bool {
        guard let ts = sampleTimestamp else { return true }
        return Date().timeIntervalSince(ts) > Self.staleThreshold
    }
}

// MARK: - Protocol

/// Evaluates cardiac signal data and produces a normalised HeartVerificationResult.
/// Does NOT make policy decisions — that is HeartAuthPolicyEngineProtocol's job.
protocol HeartIdentityEngineProtocol: Sendable {
    /// Evaluate the provided cardiac signal and return a verification result.
    func evaluateIdentity(from input: CardiacSignalInput) async throws -> HeartVerificationResult
}
