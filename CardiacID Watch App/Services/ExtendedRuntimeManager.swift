//
//  ExtendedRuntimeManager.swift
//  CardiacID Watch App
//
//  Manages WKExtendedRuntimeSession to keep the Watch app active
//

import Foundation
import WatchKit

/// Manages Extended Runtime Sessions to prevent Watch app from being suspended
class ExtendedRuntimeManager: NSObject, ObservableObject {

    // MARK: - Singleton
    static let shared = ExtendedRuntimeManager()

    // MARK: - Published State (thread-safe)
    @Published private(set) var isSessionActive: Bool = false

    // MARK: - Private Properties
    private var extendedSession: WKExtendedRuntimeSession?
    private var isStarting = false

    // MARK: - Initialization

    private override init() {
        super.init()
        print("⌚️ ExtendedRuntimeManager initialized")
    }

    // MARK: - Public Methods

    /// Start an extended runtime session to keep the app active
    func startSession() {
        DispatchQueue.main.async { [weak self] in
            self?.startSessionOnMain()
        }
    }

    private func startSessionOnMain() {
        // Prevent multiple simultaneous start attempts
        guard !isStarting else {
            print("⌚️ ExtendedRuntimeManager: Already starting session")
            return
        }

        // Check if session is already running
        if let session = extendedSession, session.state == .running {
            print("⌚️ ExtendedRuntimeManager: Session already running")
            return
        }

        isStarting = true
        print("⌚️ ExtendedRuntimeManager: Starting session...")

        // Invalidate old session if exists
        extendedSession?.invalidate()
        extendedSession = nil

        // Create and start new session
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        extendedSession = session

        session.start()
    }

    /// Stop the extended runtime session
    func stopSession() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("⌚️ ExtendedRuntimeManager: Stopping session")
            self.extendedSession?.invalidate()
            self.extendedSession = nil
            self.isSessionActive = false
            self.isStarting = false
        }
    }
}

// MARK: - WKExtendedRuntimeSessionDelegate

extension ExtendedRuntimeManager: WKExtendedRuntimeSessionDelegate {

    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        DispatchQueue.main.async { [weak self] in
            print("⌚️ ExtendedRuntimeManager: ✅ Session started")
            self?.isSessionActive = true
            self?.isStarting = false
        }
    }

    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("⌚️ ExtendedRuntimeManager: Session expiring - will restart")
        // FIXED: Reset isStarting and isSessionActive in proper order
        // Wait for session to fully expire before restarting
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.isSessionActive = false
            self.isStarting = false
            self.extendedSession = nil
            self.startSession()
        }
    }

    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                 didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                 error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.isSessionActive = false
            self.isStarting = false
            self.extendedSession = nil

            print("⌚️ ExtendedRuntimeManager: Session invalidated - reason: \(reason.rawValue)")

            if let error = error {
                print("⌚️ ExtendedRuntimeManager: Error: \(error.localizedDescription)")
            }

            // Auto-restart unless user resigned frontmost or error occurred
            if reason != .resignedFrontmost && error == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.startSession()
                }
            }
        }
    }
}
