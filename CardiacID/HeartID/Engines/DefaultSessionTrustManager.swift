//
//  DefaultSessionTrustManager.swift
//  CardiacID
//
//  Production implementation of SessionTrustManagerProtocol.
//  ObservableObject for SwiftUI binding.
//  Background timer auto-expires trust (no polling).
//
//  Expiry rules:
//    recentlyVerified → expired after 5 minutes idle
//    elevatedTrust    → expired after 15 minutes idle
//    denied           → stays denied until explicit re-verification
//

import Foundation
import Combine

@MainActor
final class DefaultSessionTrustManager: ObservableObject, SessionTrustManagerProtocol {

    @Published private(set) var state: SessionTrustState = .initial

    private var expiryTimer: Timer?

    private static let recentWindow: TimeInterval   = 300   // 5 min
    private static let elevatedWindow: TimeInterval  = 900   // 15 min

    // MARK: - SessionTrustManagerProtocol

    func recordVerification(_ result: HeartVerificationResult) {
        guard result.isAuthorized else {
            state.currentState         = .denied
            state.lastVerified         = result.timestamp
            state.lastConfidenceScore  = result.combinedScore
            cancelTimer()
            return
        }

        state.lastVerified        = result.timestamp
        state.lastConfidenceScore = result.combinedScore
        state.currentState        = result.combinedScore >= 0.90 ? .elevatedTrust : .recentlyVerified

        scheduleExpiry()
    }

    func currentTrust(for action: ProtectedAction) -> SessionTrustState {
        // Re-evaluate staleness inline before returning
        refreshIfNeeded()
        return state
    }

    func invalidate() {
        state = .initial
        cancelTimer()
    }

    /// Test-only: back-date lastVerified to simulate elapsed time.
    /// Visible to @testable imports only (internal access).
    func _testBackdateLastVerified(by interval: TimeInterval) {
        guard let current = state.lastVerified else { return }
        state.lastVerified = current.addingTimeInterval(-interval)
    }

    // MARK: - Timer-based auto-expiry

    private func scheduleExpiry() {
        cancelTimer()
        let window: TimeInterval = state.currentState == .elevatedTrust
            ? Self.elevatedWindow
            : Self.recentWindow

        expiryTimer = Timer.scheduledTimer(withTimeInterval: window, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.state.currentState != .denied && self.state.currentState != .unverified {
                    self.state.currentState = .expired
                }
            }
        }
    }

    private func cancelTimer() {
        expiryTimer?.invalidate()
        expiryTimer = nil
    }

    /// Belt-and-suspenders: if the timer somehow didn't fire (app was suspended),
    /// check elapsed time and expire if needed.
    private func refreshIfNeeded() {
        guard let verified = state.lastVerified else { return }
        guard state.currentState == .recentlyVerified || state.currentState == .elevatedTrust else { return }

        let age = Date().timeIntervalSince(verified)
        let limit: TimeInterval = state.currentState == .elevatedTrust
            ? Self.elevatedWindow
            : Self.recentWindow

        if age >= limit {
            state.currentState = .expired
            cancelTimer()
        }
    }

    deinit {
        expiryTimer?.invalidate()
    }
}
