//
//  PasskeyCoordinator.swift
//  CardiacID
//
//  HeartID-gated coordinator for WebAuthn passkey registration and assertion.
//  This is a STUB LAYER — no real WebAuthn server exists yet.
//  No live network calls are made.
//
//  ┌──────────────────────────────────────────────────────────────────────┐
//  │ TODO — Backend Integration Requirements                             │
//  │                                                                      │
//  │ Before this coordinator can perform real passkey flows:              │
//  │                                                                      │
//  │ 1. Relying Party (RP) server URL                                    │
//  │    A WebAuthn-compliant server must expose registration and          │
//  │    assertion endpoints (e.g. /webauthn/register/begin,              │
//  │    /webauthn/register/complete, /webauthn/authenticate/begin,       │
//  │    /webauthn/authenticate/complete).                                 │
//  │                                                                      │
//  │ 2. Associated Domains entitlement                                   │
//  │    The app must declare `webcredentials:<your-rp-domain>`           │
//  │    in its entitlements. Currently set to:                            │
//  │      webcredentials:cardiacid.com                                    │
//  │                                                                      │
//  │ 3. Apple App Site Association (AASA) file                           │
//  │    Deploy a valid AASA at:                                           │
//  │      https://<your-rp-domain>/.well-known/apple-app-site-association│
//  │    It must contain a "webcredentials" entry listing the app's       │
//  │    bundle identifier (ARGOS.CardiacID).                              │
//  │                                                                      │
//  │ 4. FIDO2 assertion endpoint                                         │
//  │    The server must validate authenticator assertions and return      │
//  │    a signed authentication token or session cookie.                  │
//  │                                                                      │
//  │ 5. Replace MockPasskeyService with a real implementation of         │
//  │    PasskeyServiceProtocol that calls the endpoints above.           │
//  └──────────────────────────────────────────────────────────────────────┘
//

import Foundation

// MARK: - HeartIDError

/// Unified error type for the HeartID security layer.
enum HeartIDError: Error, LocalizedError, Sendable {
    case policyDenied(String)
    case stepUpRequired(String)
    case verificationExpired
    case vaultLocked
    case keychainError(String)
    case encryptionError(String)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .policyDenied(let r):    return "Policy denied: \(r)"
        case .stepUpRequired(let r):  return "Step-up required: \(r)"
        case .verificationExpired:    return "HeartID verification has expired"
        case .vaultLocked:            return "Vault is locked — verify with HeartID first"
        case .keychainError(let r):   return "Keychain error: \(r)"
        case .encryptionError(let r): return "Encryption error: \(r)"
        case .unknown(let e):         return "Unknown error: \(e.localizedDescription)"
        }
    }
}

// MARK: - Passkey Data Types (stub models for the server protocol)

struct PasskeyRegistrationChallenge: Sendable {
    let challengeData: Data
    let relyingPartyId: String
    let userId: String
    let userName: String
}

struct PasskeyRegistrationResponse: Sendable {
    let credentialId: Data
    let clientDataJSON: Data
    let attestationObject: Data
}

struct PasskeyAssertionChallenge: Sendable {
    let challengeData: Data
    let relyingPartyId: String
    let allowedCredentialIds: [Data]
}

struct PasskeyAssertionResponse: Sendable {
    let credentialId: Data
    let clientDataJSON: Data
    let authenticatorData: Data
    let signature: Data
    let userHandle: Data?
}

struct PasskeyAssertionResult: Sendable {
    let verified: Bool
    let userId: String
    let sessionToken: String?
}

// MARK: - PasskeyServiceProtocol

protocol PasskeyServiceProtocol: Sendable {
    func beginRegistration(for userId: String) async throws -> PasskeyRegistrationChallenge
    func completeRegistration(_ response: PasskeyRegistrationResponse) async throws
    func beginAssertion(for userId: String) async throws -> PasskeyAssertionChallenge
    func completeAssertion(_ response: PasskeyAssertionResponse) async throws -> PasskeyAssertionResult
}

// MARK: - MockPasskeyService

/// Simulates WebAuthn server responses with a 0.5 s artificial delay.
/// Replace with a real implementation when RP server is deployed.
struct MockPasskeyService: PasskeyServiceProtocol {

    private func simulateNetwork() async {
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 s
    }

    func beginRegistration(for userId: String) async throws -> PasskeyRegistrationChallenge {
        await simulateNetwork()
        return PasskeyRegistrationChallenge(
            challengeData: Data("mock-reg-challenge-\(userId)".utf8),
            relyingPartyId: "cardiacid.com",
            userId: userId,
            userName: "\(userId)@cardiacid.com"
        )
    }

    func completeRegistration(_ response: PasskeyRegistrationResponse) async throws {
        await simulateNetwork()
        // Stub: server would validate attestation here
    }

    func beginAssertion(for userId: String) async throws -> PasskeyAssertionChallenge {
        await simulateNetwork()
        return PasskeyAssertionChallenge(
            challengeData: Data("mock-assert-challenge-\(userId)".utf8),
            relyingPartyId: "cardiacid.com",
            allowedCredentialIds: []
        )
    }

    func completeAssertion(_ response: PasskeyAssertionResponse) async throws -> PasskeyAssertionResult {
        await simulateNetwork()
        return PasskeyAssertionResult(
            verified: true,
            userId: "mock-user",
            sessionToken: "mock-session-\(UUID().uuidString.prefix(8))"
        )
    }
}

// MARK: - PasskeyCoordinator

/// HeartID-gated passkey flow coordinator.
///
/// Both `initiateRegistration` and `initiateAssertion` check
/// `SessionTrustManager` + `HeartAuthPolicyEngineProtocol` before
/// proceeding to the passkey service. If the session is denied or
/// expired, the call throws `HeartIDError` immediately.
@MainActor
final class PasskeyCoordinator: ObservableObject {
    static let shared = PasskeyCoordinator()

    // MARK: - Published state

    @Published private(set) var state: CoordinatorState = .idle
    @Published private(set) var lastError: String?

    enum CoordinatorState: Equatable {
        case idle
        case checkingPolicy
        case awaitingChallenge
        case awaitingUserGesture
        case completingWithServer
        case success
        case failed(String)

        var displayLabel: String {
            switch self {
            case .idle:                  return "Ready"
            case .checkingPolicy:        return "Checking HeartID policy…"
            case .awaitingChallenge:     return "Fetching challenge…"
            case .awaitingUserGesture:   return "Waiting for passkey…"
            case .completingWithServer:  return "Verifying with server…"
            case .success:               return "Success"
            case .failed(let msg):       return "Failed: \(msg)"
            }
        }

        var isTerminal: Bool {
            switch self { case .success, .failed: return true; default: return false }
        }
    }

    // MARK: - Dependencies

    private let sessionTrustManager: DefaultSessionTrustManager
    private let policyEngine: any HeartAuthPolicyEngineProtocol
    private let auditLogger: any AuditLoggerProtocol
    private let passkeyService: any PasskeyServiceProtocol

    private init() {
        self.sessionTrustManager = DefaultSessionTrustManager()
        self.policyEngine = DefaultHeartAuthPolicyEngine()
        self.auditLogger = DefaultAuditLogger()
        // Production: real WebAuthn RP server calls via Supabase Edge Functions.
        // Falls back to MockPasskeyService() if WebAuthnPasskeyService is unavailable.
        self.passkeyService = WebAuthnPasskeyService()
    }

    // MARK: - Registration

    /// Initiate a HeartID-gated passkey registration flow.
    ///
    /// Flow:
    /// 1. Check SessionTrustManager for current trust state
    /// 2. If denied/expired → throw HeartIDError.policyDenied
    /// 3. If stepUp required → throw HeartIDError.stepUpRequired
    /// 4. If allowed → call passkey service to begin + complete registration
    func initiateRegistration(userId: String = "default-user") async throws {
        state = .checkingPolicy
        lastError = nil

        let trustState = sessionTrustManager.currentTrust(for: .beginPasskeyRegistration)
        let decision = evaluateTrust(trustState, for: .beginPasskeyRegistration)

        try enforceDecision(decision, action: .beginPasskeyRegistration)

        // HeartID approved — proceed to passkey flow
        state = .awaitingChallenge
        let challenge = try await passkeyService.beginRegistration(for: userId)

        state = .awaitingUserGesture
        // In a real implementation, ASAuthorizationController would present
        // the system passkey UI here. The mock simulates instant completion.
        let response = PasskeyRegistrationResponse(
            credentialId: Data("mock-cred-\(userId)".utf8),
            clientDataJSON: challenge.challengeData,
            attestationObject: Data("mock-attestation".utf8)
        )

        state = .completingWithServer
        try await passkeyService.completeRegistration(response)

        state = .success
        await auditLogger.log(SecurityEvent(
            action: .beginPasskeyRegistration,
            decision: .allow,
            sessionState: trustState.currentState,
            reasonCode: "registration_complete"
        ))
    }

    // MARK: - Assertion

    /// Initiate a HeartID-gated passkey assertion (sign-in) flow.
    ///
    /// Same gating pattern as registration.
    func initiateAssertion(userId: String = "default-user") async throws {
        state = .checkingPolicy
        lastError = nil

        let trustState = sessionTrustManager.currentTrust(for: .beginPasskeyAssertion)
        let decision = evaluateTrust(trustState, for: .beginPasskeyAssertion)

        try enforceDecision(decision, action: .beginPasskeyAssertion)

        state = .awaitingChallenge
        let challenge = try await passkeyService.beginAssertion(for: userId)

        state = .awaitingUserGesture
        let response = PasskeyAssertionResponse(
            credentialId: Data("mock-cred-\(userId)".utf8),
            clientDataJSON: challenge.challengeData,
            authenticatorData: Data("mock-auth-data".utf8),
            signature: Data("mock-sig".utf8),
            userHandle: Data(userId.utf8)
        )

        state = .completingWithServer
        let result = try await passkeyService.completeAssertion(response)

        if result.verified {
            state = .success
            await auditLogger.log(SecurityEvent(
                action: .beginPasskeyAssertion,
                decision: .allow,
                sessionState: trustState.currentState,
                reasonCode: "assertion_complete"
            ))
        } else {
            let msg = "Server rejected assertion"
            state = .failed(msg)
            lastError = msg
            await auditLogger.log(SecurityEvent(
                action: .beginPasskeyAssertion,
                decision: .deny,
                sessionState: trustState.currentState,
                reasonCode: "assertion_rejected"
            ))
        }
    }

    // MARK: - Reset

    func reset() {
        state = .idle
        lastError = nil
    }

    // MARK: - Private: policy evaluation

    /// Build an AuthPolicyDecision from the current SessionTrustState.
    /// This uses the session's last confidence score to synthesize
    /// a HeartVerificationResult for the policy engine.
    private func evaluateTrust(
        _ trust: SessionTrustState,
        for action: ProtectedAction
    ) -> AuthPolicyDecision {
        // Synthesize a HeartVerificationResult from the session snapshot
        let result = HeartVerificationResult.verified(
            match: trust.lastConfidenceScore,
            liveness: min(trust.lastConfidenceScore + 0.05, 1.0),
            reasons: trust.currentState == .denied ? [.lowConfidence] : [.success]
        )
        return policyEngine.evaluate(result: result, for: action)
    }

    /// Enforce the policy decision. Throws if not .allow.
    private func enforceDecision(
        _ decision: AuthPolicyDecision,
        action: ProtectedAction
    ) throws {
        switch decision.decision {
        case .allow:
            break // proceed

        case .deny:
            let msg = decision.rationale
            state = .failed(msg)
            lastError = msg
            Task {
                await auditLogger.log(SecurityEvent(
                    action: action,
                    decision: .deny,
                    sessionState: sessionTrustManager.state.currentState,
                    reasonCode: "policy_denied"
                ))
            }
            throw HeartIDError.policyDenied(msg)

        case .requireStepUp:
            let msg = decision.rationale
            state = .failed(msg)
            lastError = msg
            Task {
                await auditLogger.log(SecurityEvent(
                    action: action,
                    decision: .requireStepUp,
                    sessionState: sessionTrustManager.state.currentState,
                    reasonCode: "step_up_required"
                ))
            }
            throw HeartIDError.stepUpRequired(msg)
        }
    }
}
