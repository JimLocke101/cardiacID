//
//  HeartIdentityEngineProtocol.swift
//  HeartIDCore
//
//  Protocol: receives cardiac signal input, produces HeartVerificationResult.
//

import Foundation

// MARK: - Cardiac Signal Input

/// Clean adapter wrapping whatever cardiac data the existing project provides.
/// Populated from WatchConnectivityService live biometric fields or from
/// HeartIDService direct readings.
public struct CardiacSignalInput: Sendable {
    /// Template-match confidence reported by the Watch biometric engine (0–1).
    public let matchConfidence: Double
    /// Biometric method used ("ppg", "ecg", "hybrid").
    public let method: String
    /// Whether the Watch is actively monitoring PPG.
    public let isActivelyMonitoring: Bool
    /// Whether the Watch reports the user as authenticated.
    public let isAuthenticated: Bool
    /// Timestamp of the biometric reading on the Watch.
    public let sampleTimestamp: Date?
    /// Heart rate at time of reading (BPM), if available.
    public let heartRate: Int?
    /// Whether the Watch is reachable right now.
    public let isWatchReachable: Bool

    /// Maximum age (seconds) before a reading is considered stale.
    public static let staleThreshold: TimeInterval = 120.0

    public var isStale: Bool {
        guard let ts = sampleTimestamp else { return true }
        return Date().timeIntervalSince(ts) > Self.staleThreshold
    }

    public init(
        matchConfidence: Double,
        method: String,
        isActivelyMonitoring: Bool,
        isAuthenticated: Bool,
        sampleTimestamp: Date?,
        heartRate: Int?,
        isWatchReachable: Bool
    ) {
        self.matchConfidence = matchConfidence
        self.method = method
        self.isActivelyMonitoring = isActivelyMonitoring
        self.isAuthenticated = isAuthenticated
        self.sampleTimestamp = sampleTimestamp
        self.heartRate = heartRate
        self.isWatchReachable = isWatchReachable
    }
}

// MARK: - Protocol

/// Evaluates cardiac signal data and produces a normalised HeartVerificationResult.
/// Does NOT make policy decisions — that is HeartAuthPolicyEngineProtocol's job.
public protocol HeartIdentityEngineProtocol: Sendable {
    func evaluateIdentity(from input: CardiacSignalInput) async throws -> HeartVerificationResult
}
