// DemoModeManager.swift
// Central runtime switch for demo mode based on credentials

import Foundation

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
