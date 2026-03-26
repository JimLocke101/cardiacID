//
//  HeartAuthPolicyEngineProtocol.swift
//  CardiacID
//
//  Protocol: evaluates a HeartVerificationResult against configurable
//  per-action thresholds. Returns allow / deny / requireStepUp.
//  Fail closed: if result is nil or evaluation throws, return .deny.
//

import Foundation

// MARK: - Policy Configuration

/// Loadable threshold configuration.
/// Persisted to UserDefaults for dev/debug override; defaults to safe production values.
struct PolicyConfiguration: Codable, Sendable, Equatable {
    var thresholds: [String: Double]

    /// Production-safe defaults.
    static let production = PolicyConfiguration(thresholds: [
        ProtectedAction.unlockProtectedFile.rawValue:      0.75,
        ProtectedAction.signInToApp.rawValue:              0.70,
        ProtectedAction.authorizeHardwareCommand.rawValue:  0.90,
        ProtectedAction.authorizeSensitiveAction.rawValue:  0.80,
        ProtectedAction.beginPasskeyRegistration.rawValue:  0.80,
        ProtectedAction.beginPasskeyAssertion.rawValue:     0.80,
    ])

    func threshold(for action: ProtectedAction) -> Double {
        thresholds[action.rawValue] ?? 0.80
    }

    mutating func setThreshold(_ value: Double, for action: ProtectedAction) {
        thresholds[action.rawValue] = min(max(value, 0.50), 1.00)
    }

    // MARK: - UserDefaults persistence

    private static let userDefaultsKey = "com.heartid.policyConfiguration"

    static func loadFromDefaults() -> PolicyConfiguration {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let config = try? JSONDecoder().decode(PolicyConfiguration.self, from: data)
        else { return .production }
        return config
    }

    func saveToDefaults() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }

    static func resetDefaults() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}

// MARK: - Protocol

/// Evaluates a verification result against policy for a protected action.
/// Fail closed: missing or invalid input always produces .deny.
protocol HeartAuthPolicyEngineProtocol: Sendable {
    /// Evaluate the verification result for the given action.
    /// Must never throw — returns .deny on any internal error.
    func evaluate(result: HeartVerificationResult, for action: ProtectedAction) -> AuthPolicyDecision
}
