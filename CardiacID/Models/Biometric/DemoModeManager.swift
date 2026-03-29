// DemoModeManager.swift
// Central runtime switch for demo mode based on credentials
//
// SECURITY: Entire class is gated behind #if DEBUG.
// In Release builds, isDemoEnabled is always false and evaluateCredentials is a no-op.
// Hardcoded credentials never exist in the production binary.

import Foundation

#if DEBUG
final class DemoModeManager {
    static let shared = DemoModeManager()
    private init() {}

    private let demoEmail = "john.doe@acme.com"
    private let demoPassword = "~password1234argos2020~"

    private(set) var isDemoEnabled: Bool = false

    func evaluateCredentials(email: String, password: String) {
        isDemoEnabled = (email.lowercased() == demoEmail.lowercased() && password == demoPassword)
        if isDemoEnabled {
            UserDefaults.standard.set(true, forKey: "DemoModeEnabled")
        } else {
            UserDefaults.standard.removeObject(forKey: "DemoModeEnabled")
        }
    }

    func loadPersisted() {
        isDemoEnabled = UserDefaults.standard.bool(forKey: "DemoModeEnabled")
    }
}
#else
// Production stub: demo mode is permanently disabled.
// No hardcoded credentials exist in this build.
final class DemoModeManager {
    static let shared = DemoModeManager()
    private init() {}

    var isDemoEnabled: Bool { false }

    func evaluateCredentials(email: String, password: String) {
        // No-op in production. Credentials are never evaluated.
    }

    func loadPersisted() {
        // No-op in production.
    }
}
#endif
