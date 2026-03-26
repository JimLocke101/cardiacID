//
//  DefaultSessionTrustManager.swift
//  HeartIDCore
//
//  Production implementation of SessionTrustManagerProtocol.
//  ObservableObject for SwiftUI binding. Background timer auto-expires trust.
//

import Foundation
import Combine

@MainActor
public final class DefaultSessionTrustManager: ObservableObject, SessionTrustManagerProtocol {

    @Published public private(set) var state: SessionTrustState = .initial

    private var expiryTimer: Timer?

    private static let recentWindow: TimeInterval   = 300   // 5 min
    private static let elevatedWindow: TimeInterval  = 900   // 15 min

    public init() {}

    // MARK: - SessionTrustManagerProtocol

    public func recordVerification(_ result: HeartVerificationResult) {
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

    public func currentTrust(for action: ProtectedAction) -> SessionTrustState {
        refreshIfNeeded()
        return state
    }

    public func invalidate() {
        state = .initial
        cancelTimer()
    }

    /// Test-only: back-date lastVerified to simulate elapsed time.
    public func _testBackdateLastVerified(by interval: TimeInterval) {
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
