//
//  HeartIDServiceLocator.swift
//  CardiacID
//
//  Central dependency container for all HeartID security layer services.
//  Instantiated once at app startup, injected via SwiftUI @EnvironmentObject.
//
//  Production wiring:
//    identityEngine  → DefaultHeartIdentityEngine (bridges WatchConnectivityService)
//    policyEngine    → DefaultHeartAuthPolicyEngine (PolicyConfiguration from UserDefaults)
//    keyManager      → DefaultSecureKeyManager (Keychain + AES-GCM wrap)
//    sessionTrust    → DefaultSessionTrustManager (timer-based expiry)
//    auditLogger     → DefaultAuditLogger (OSLog, actor-isolated)
//    vault           → HeartIDFileVault (AES-GCM, encrypted manifest)
//    passkeyCoord    → PasskeyCoordinator (mock server until backend deployed)
//

import Foundation
import SwiftUI

@MainActor
final class HeartIDServiceLocator: ObservableObject {

    // MARK: - Engines (protocol-typed for testability)

    let identityEngine: any HeartIdentityEngineProtocol
    let policyEngine: any HeartAuthPolicyEngineProtocol
    let keyManager: any SecureKeyManagerProtocol
    let auditLogger: any AuditLoggerProtocol

    // MARK: - Stateful managers (ObservableObject — need concrete types for SwiftUI)

    let sessionTrust: DefaultSessionTrustManager
    let vault: HeartIDFileVault
    let passkeyCoordinator: PasskeyCoordinator

    // MARK: - Singleton access for views that use @StateObject

    static let shared = HeartIDServiceLocator()

    // MARK: - Production init

    private init() {
        let keyMgr   = DefaultSecureKeyManager()
        let auditLog = DefaultAuditLogger()
        let policy   = DefaultHeartAuthPolicyEngine()

        self.identityEngine     = DefaultHeartIdentityEngine()
        self.policyEngine       = policy
        self.keyManager         = keyMgr
        self.auditLogger        = auditLog
        self.sessionTrust       = DefaultSessionTrustManager()
        self.vault              = HeartIDFileVault(keyManager: keyMgr, auditLogger: auditLog)
        self.passkeyCoordinator = PasskeyCoordinator.shared
    }

    // MARK: - Test init (inject mocks)

    init(
        identityEngine: any HeartIdentityEngineProtocol,
        policyEngine: any HeartAuthPolicyEngineProtocol,
        keyManager: any SecureKeyManagerProtocol,
        auditLogger: any AuditLoggerProtocol,
        sessionTrust: DefaultSessionTrustManager,
        vault: HeartIDFileVault,
        passkeyCoordinator: PasskeyCoordinator
    ) {
        self.identityEngine     = identityEngine
        self.policyEngine       = policyEngine
        self.keyManager         = keyManager
        self.auditLogger        = auditLogger
        self.sessionTrust       = sessionTrust
        self.vault              = vault
        self.passkeyCoordinator = passkeyCoordinator
    }

    // MARK: - Convenience: run a full HeartID verification cycle

    /// Verify → evaluate → record session → return decision.
    func verifyAndEvaluate(
        for action: ProtectedAction,
        using input: CardiacSignalInput
    ) async -> AuthPolicyDecision {
        let result: HeartVerificationResult
        do {
            result = try await identityEngine.evaluateIdentity(from: input)
        } catch {
            return .deny(action: action, score: 0, threshold: policyEngine.evaluate(
                result: .denied(reason: .watchUnreachable), for: action
            ).requiredScore, rationale: "Identity engine error: \(error.localizedDescription)")
        }

        let decision = policyEngine.evaluate(result: result, for: action)
        sessionTrust.recordVerification(result)

        await auditLogger.log(SecurityEvent(
            action: action,
            decision: decision.decision,
            sessionState: sessionTrust.state.currentState,
            reasonCode: result.reasonCodes.first?.rawValue ?? "unknown"
        ))

        return decision
    }
}
