//
//  BiometricFallbackChainService.swift
//  CardiacID
//
//  Orchestrates the biometric fallback chain:
//  HeartID (Watch) -> Face ID/Touch ID (iPhone) -> FIDO2 Passkey -> EntraID Interactive
//
//  Automatically triggered when Watch HeartID confidence drops below threshold
//  or when Watch becomes unreachable.
//

import Foundation
import Combine
import LocalAuthentication
import Security

/// Deterministic biometric fallback chain for authentication
/// Each step attempts auth, and on failure logs the event and moves to the next method
@MainActor
class BiometricFallbackChainService: ObservableObject {
    static let shared = BiometricFallbackChainService()

    // MARK: - Published State

    @Published private(set) var currentMethod: FallbackMethod = .heartID
    @Published private(set) var isAuthenticating: Bool = false
    @Published private(set) var lastResult: FallbackAuthResult?
    @Published private(set) var fallbackHistory: [FallbackEvent] = []

    // MARK: - Dependencies

    private let watchConnectivity = WatchConnectivityService.shared
    private let entraIDClient = EntraIDAuthClient.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Thresholds

    private let heartIDMinConfidence: Double = 0.70
    private let heartIDTimeout: TimeInterval = 15.0
    /// Maximum age of a Watch biometric reading before it is considered stale.
    /// Readings older than this are skipped and the chain falls to Step 2.
    private let biometricMaxAge: TimeInterval = 120.0

    // MARK: - Types

    enum FallbackMethod: String, CaseIterable, Codable {
        case heartID = "HeartID"
        case faceIDTouchID = "Face ID / Touch ID"
        case fido2Passkey = "FIDO2 Passkey"
        case entraIDInteractive = "EntraID Interactive"
    }

    struct FallbackAuthResult {
        let success: Bool
        let method: FallbackMethod
        let confidence: Double?
        let fallbacksUsed: [FallbackMethod]
        let error: String?
    }

    struct FallbackEvent: Identifiable {
        let id = UUID()
        let method: FallbackMethod
        let success: Bool
        let reason: String
        let timestamp: Date
    }

    // MARK: - Initialization

    private init() {
        setupFallbackTrigger()
    }

    /// Listen for HeartIDFallbackRequired notification to auto-trigger the fallback chain
    private func setupFallbackTrigger() {
        NotificationCenter.default.publisher(for: .heartIDFallbackRequired)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self, !self.isAuthenticating else { return }
                let reason = notification.userInfo?["reason"] as? String ?? "Unknown"
                print("BiometricFallback: Triggered - reason: \(reason)")

                Task { @MainActor in
                    _ = await self.authenticate()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Authentication Chain

    /// Execute the full fallback chain
    /// Returns the result of the first successful method, or failure if all methods fail
    func authenticate() async -> FallbackAuthResult {
        isAuthenticating = true
        var fallbacksUsed: [FallbackMethod] = []

        defer { isAuthenticating = false }

        // Step 1: HeartID (Watch)
        currentMethod = .heartID
        if watchConnectivity.isEffectivelyConnected {
            // Verify the biometric reading is fresh enough to trust
            if let readingAge = watchConnectivity.liveBiometricTimestamp.map({ Date().timeIntervalSince($0) }),
               readingAge <= biometricMaxAge {
                let confidence = watchConnectivity.liveBiometricConfidence
                if confidence >= heartIDMinConfidence && watchConnectivity.liveBiometricAuthenticated {
                    let result = FallbackAuthResult(
                        success: true, method: .heartID,
                        confidence: confidence, fallbacksUsed: [], error: nil
                    )
                    lastResult = result
                    logEvent(method: .heartID, success: true, reason: "Confidence \(Int(confidence * 100))% (\(Int(readingAge))s old)")
                    return result
                }
                logEvent(method: .heartID, success: false,
                         reason: "Confidence \(Int(confidence * 100))% below \(Int(heartIDMinConfidence * 100))% threshold")
            } else {
                let age = watchConnectivity.liveBiometricTimestamp.map { Int(Date().timeIntervalSince($0)) } ?? -1
                logEvent(method: .heartID, success: false,
                         reason: age >= 0 ? "Biometric reading stale (\(age)s > \(Int(biometricMaxAge))s limit)" : "No biometric reading available")
            }
        } else {
            logEvent(method: .heartID, success: false, reason: "Watch unreachable")
        }
        fallbacksUsed.append(.heartID)

        // Step 2: Face ID / Touch ID (iPhone)
        currentMethod = .faceIDTouchID
        let biometricResult = await attemptDeviceBiometric()
        if biometricResult {
            let result = FallbackAuthResult(
                success: true, method: .faceIDTouchID,
                confidence: 1.0, fallbacksUsed: fallbacksUsed, error: nil
            )
            lastResult = result
            logEvent(method: .faceIDTouchID, success: true, reason: "Device biometric verified")
            return result
        }
        fallbacksUsed.append(.faceIDTouchID)

        // Step 3: FIDO2 Passkey
        currentMethod = .fido2Passkey
        let passkeyResult = await attemptPasskeyAuth()
        if passkeyResult {
            let result = FallbackAuthResult(
                success: true, method: .fido2Passkey,
                confidence: 1.0, fallbacksUsed: fallbacksUsed, error: nil
            )
            lastResult = result
            logEvent(method: .fido2Passkey, success: true, reason: "Passkey verified")
            return result
        }
        fallbacksUsed.append(.fido2Passkey)

        // Step 4: EntraID Interactive Login
        currentMethod = .entraIDInteractive
        do {
            _ = try await entraIDClient.signIn()
            let result = FallbackAuthResult(
                success: true, method: .entraIDInteractive,
                confidence: 1.0, fallbacksUsed: fallbacksUsed, error: nil
            )
            lastResult = result
            logEvent(method: .entraIDInteractive, success: true, reason: "Interactive auth completed")
            return result
        } catch {
            logEvent(method: .entraIDInteractive, success: false, reason: error.localizedDescription)
        }
        fallbacksUsed.append(.entraIDInteractive)

        // All methods failed
        let result = FallbackAuthResult(
            success: false, method: .entraIDInteractive,
            confidence: nil, fallbacksUsed: fallbacksUsed,
            error: "All authentication methods failed"
        )
        lastResult = result
        return result
    }

    // MARK: - Individual Auth Attempts

    /// Attempt Face ID / Touch ID authentication
    private func attemptDeviceBiometric() async -> Bool {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            logEvent(method: .faceIDTouchID, success: false,
                     reason: error?.localizedDescription ?? "Biometric not available")
            return false
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "CardiacID heart verification unavailable - verify with device biometric"
            )
            if !success {
                logEvent(method: .faceIDTouchID, success: false, reason: "Biometric evaluation returned false")
            }
            return success
        } catch {
            logEvent(method: .faceIDTouchID, success: false, reason: error.localizedDescription)
            return false
        }
    }

    /// Attempt FIDO2 Passkey authentication
    private func attemptPasskeyAuth() async -> Bool {
        do {
            // Generate a random challenge
            var challengeBytes = [UInt8](repeating: 0, count: 32)
            let status = SecRandomCopyBytes(kSecRandomDefault, 32, &challengeBytes)
            guard status == errSecSuccess else {
                logEvent(method: .fido2Passkey, success: false, reason: "Failed to generate challenge")
                return false
            }
            let challenge = Data(challengeBytes)

            let passkeyResult = try await PasskeyService.shared.authenticate(challenge: challenge)
            if passkeyResult.success {
                return true
            }
            logEvent(method: .fido2Passkey, success: false,
                     reason: passkeyResult.error ?? "Passkey auth returned failure")
            return false
        } catch {
            logEvent(method: .fido2Passkey, success: false, reason: error.localizedDescription)
            return false
        }
    }

    // MARK: - Event Logging

    private func logEvent(method: FallbackMethod, success: Bool, reason: String) {
        let event = FallbackEvent(method: method, success: success, reason: reason, timestamp: Date())
        fallbackHistory.append(event)

        let symbol = success ? "+" : "-"
        print("BiometricFallback: [\(symbol)] \(method.rawValue) - \(reason)")

        // Log to Supabase auth_events table
        Task {
            await logToSupabase(event)
        }
    }

    private func logToSupabase(_ event: FallbackEvent) async {
        do {
            try await AppSupabaseClient.shared.logAuthEvent(
                eventType: event.success ? "authentication" : "fallback_triggered",
                method: event.method.rawValue,
                success: event.success,
                confidence: nil,
                failureReason: event.success ? nil : event.reason,
                metadata: [
                    "fallback_chain": true,
                    "method": event.method.rawValue,
                    "timestamp": event.timestamp.timeIntervalSince1970
                ]
            )
        } catch {
            print("BiometricFallback: Failed to log to Supabase: \(error)")
        }
    }

    // MARK: - History Management

    /// Clear fallback history
    func clearHistory() {
        fallbackHistory.removeAll()
    }
}
