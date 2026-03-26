//
//  HeartAuthPolicyEngineProtocol.swift
//  HeartIDCore
//
//  Protocol: evaluates a HeartVerificationResult against configurable
//  per-action thresholds. Returns allow / deny / requireStepUp.
//  Fail closed: if result is nil or evaluation throws, return .deny.
//

import Foundation

// MARK: - Policy Configuration

/// Loadable threshold configuration.
/// Persisted to UserDefaults for dev/debug override; defaults to safe production values.
public struct PolicyConfiguration: Codable, Sendable, Equatable {
    public var thresholds: [String: Double]

    public init(thresholds: [String: Double]) {
        self.thresholds = thresholds
    }

    /// Production-safe defaults.
    public static let production = PolicyConfiguration(thresholds: [
        ProtectedAction.unlockProtectedFile.rawValue:      0.75,
        ProtectedAction.signInToApp.rawValue:              0.70,
        ProtectedAction.authorizeHardwareCommand.rawValue:  0.90,
        ProtectedAction.authorizeSensitiveAction.rawValue:  0.80,
        ProtectedAction.beginPasskeyRegistration.rawValue:  0.80,
        ProtectedAction.beginPasskeyAssertion.rawValue:     0.80,
    ])

    public func threshold(for action: ProtectedAction) -> Double {
        thresholds[action.rawValue] ?? 0.80
    }

    public mutating func setThreshold(_ value: Double, for action: ProtectedAction) {
        thresholds[action.rawValue] = min(max(value, 0.50), 1.00)
    }

    // MARK: - UserDefaults persistence

    private static let userDefaultsKey = "com.heartid.policyConfiguration"

    public static func loadFromDefaults() -> PolicyConfiguration {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let config = try? JSONDecoder().decode(PolicyConfiguration.self, from: data)
        else { return .production }
        return config
    }

    public func saveToDefaults() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }

    public static func resetDefaults() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}

// MARK: - Protocol

/// Evaluates a verification result against policy for a protected action.
/// Fail closed: missing or invalid input always produces .deny.
public protocol HeartAuthPolicyEngineProtocol: Sendable {
    func evaluate(result: HeartVerificationResult, for action: ProtectedAction) -> AuthPolicyDecision
}
