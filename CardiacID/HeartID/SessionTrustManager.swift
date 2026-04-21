// SessionTrustManager.swift
// CardiacID
//
// Tracks the current user assurance state across the app session.
// Uses TrustLevel from SessionTrustState.swift.

import Foundation

@MainActor
final class SessionTrustManager: ObservableObject {
    static let shared = SessionTrustManager()

    @Published private(set) var state: SessionTrustState = .initial

    private var expiryTimer: Timer?
    private let auditLogger = AuditLogger.shared

    private init() {}

    // MARK: - Public read-through

    var trustLevel: TrustLevel { state.currentState }
    var lastVerifiedAt: Date? { state.lastVerified }
    var lastConfidenceScore: Double { state.lastConfidenceScore }
    var lastVerifiedDescription: String { state.lastVerifiedDescription }
    var confidencePercentage: String { state.confidencePercentage }

    // MARK: - Record a completed verification

    func recordVerification(_ result: HeartVerificationResult) {
        guard result.isAuthorized else { deny(); return }

        let isAutoExtension = state.currentState == .recentlyVerified || state.currentState == .elevatedTrust
        let meetsAutoExtend = result.combinedScore >= SessionTrustState.autoExtendMinConfidence

        state.lastVerified         = result.timestamp
        state.lastConfidenceScore  = result.combinedScore
        state.currentState         = result.combinedScore >= 0.90 ? .elevatedTrust : .recentlyVerified

        // Auto-extend: if the session was already active and the Watch PPG
        // continues to confirm identity at ≥ 82%, reset the expiry timer
        // to the user's chosen session duration (1–4 hours from Settings).
        // This means the session stays alive as long as:
        //   1. The Watch remains on the user's wrist
        //   2. PPG confidence stays ≥ 82%
        //   3. Each background verification cycle confirms identity
        // Removing the Watch drops confidence to 0 → deny() → immediate revoke.
        scheduleExpiry()

        if isAutoExtension && meetsAutoExtend {
            auditLogger.logOperational(
                action:     "session.auto_extended",
                outcome:    state.currentState.rawValue,
                score:      result.combinedScore,
                reasonCode: "ppg_continuous_\(Int(SessionTrustState.userSessionWindow / 3600))h"
            )
        } else {
            auditLogger.logOperational(
                action:     "session.verified",
                outcome:    state.currentState.rawValue,
                score:      result.combinedScore,
                reasonCode: result.reasonCodes.first?.rawValue
            )
        }
    }

    func deny() {
        state.currentState = .denied
        expiryTimer?.invalidate()
        auditLogger.logOperational(action: "session.denied", outcome: "denied")
    }

    func reset() {
        state = .initial
        expiryTimer?.invalidate()
    }

    // MARK: - Trust gate

    func satisfiesTrust(for action: ProtectedAction) -> Bool {
        state.isValid(for: action)
    }

    // MARK: - Private

    private func scheduleExpiry() {
        expiryTimer?.invalidate()
        let window = state.currentState == .elevatedTrust
            ? SessionTrustState.elevatedWindow
            : SessionTrustState.standardWindow
        expiryTimer = Timer.scheduledTimer(withTimeInterval: window, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state.currentState != .denied else { return }
                self.state.currentState = .expired
                self.auditLogger.logOperational(action: "session.expired", outcome: "expired")
            }
        }
    }
}
