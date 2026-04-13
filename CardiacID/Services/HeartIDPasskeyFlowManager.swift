// HeartIDPasskeyFlowManager.swift
// CardiacID
//
// Single orchestrator for the HeartID cardiac-gated passkey lifecycle.
// This is the ONLY class other app layers should call for passkey operations.
//
// Flow: cardiac confidence check → challenge fetch → passkey UI → server verify
//
// State is published for SwiftUI observation; every transition is logged via OSLog.

import Foundation
import OSLog

// MARK: - Flow State

enum HeartIDPasskeyFlowState: String, Equatable, Sendable {
    case idle
    case requestingChallenge
    case awaitingCardiacConfirmation
    case presentingPasskeyUI
    case verifyingAssertion
    case success
    case failed
}

// MARK: - Error

enum HeartIDPasskeyError: Error, LocalizedError, Equatable, Sendable {
    case cardiacConfidenceTooLow(required: Double, actual: Double)
    case challengeFetchFailed(String)
    case registrationFailed(String)
    case assertionFailed(String)
    case coordinatorError(String)
    case noCredentials

    var errorDescription: String? {
        switch self {
        case .cardiacConfidenceTooLow(let req, let act):
            return String(format: "Cardiac confidence %.0f%% below required %.0f%%", act * 100, req * 100)
        case .challengeFetchFailed(let m):  return "Challenge fetch failed: \(m)"
        case .registrationFailed(let m):    return "Registration failed: \(m)"
        case .assertionFailed(let m):       return "Assertion failed: \(m)"
        case .coordinatorError(let m):      return "Passkey coordinator error: \(m)"
        case .noCredentials:                return "No passkey credentials enrolled"
        }
    }
}

// MARK: - Action Thresholds

enum PasskeyActionType: Sendable {
    case registration
    case authentication
    case stepUpVerification

    var minimumCardiacConfidence: Double {
        switch self {
        case .registration:       return 0.82
        case .authentication:     return 0.75
        case .stepUpVerification: return 0.92
        }
    }

    var actionTypeString: String {
        switch self {
        case .registration:       return "registration"
        case .authentication:     return "authentication"
        case .stepUpVerification: return "step_up"
        }
    }
}

// MARK: - Flow Manager

@MainActor
final class HeartIDPasskeyFlowManager: ObservableObject {

    // MARK: - Published State

    @Published private(set) var flowState: HeartIDPasskeyFlowState = .idle
    @Published private(set) var lastError: HeartIDPasskeyError?
    @Published private(set) var enrolledCredentials: [HeartIDPasskeyCredentialInfo] = []

    // MARK: - Dependencies

    private let networkService: HeartIDPasskeyNetworkService
    private let coordinator: PasskeyCoordinator
    private let log = Logger(subsystem: "com.argos.heartid", category: "passkey")

    // MARK: - Init

    init(
        networkService: HeartIDPasskeyNetworkService = .shared,
        coordinator: PasskeyCoordinator? = nil
    ) {
        self.networkService = networkService
        self.coordinator = coordinator ?? PasskeyCoordinator.shared
    }

    // MARK: - Registration

    /// Starts a HeartID-gated passkey registration flow.
    ///
    /// Steps:
    /// 1. Request challenge from server
    /// 2. Verify cardiac confidence meets registration threshold (0.82)
    /// 3. Present passkey UI via coordinator
    /// 4. On coordinator success, persist credential server-side
    ///
    /// - Parameters:
    ///   - userID: The authenticated user's UUID.
    ///   - userName: Display name for the passkey credential.
    ///   - cardiacConfidence: Current HeartID confidence (0–1) from WatchConnectivityService.
    func startRegistration(for userID: UUID, userName: String, cardiacConfidence: Double) async {
        reset()
        let action = PasskeyActionType.registration
        log.info("Registration started for \(userID.uuidString, privacy: .public), confidence=\(String(format: "%.2f", cardiacConfidence), privacy: .public)")

        // Step 1: Fetch challenge
        transition(to: .requestingChallenge)
        let challengeBytes: Data
        let challengeID: UUID
        do {
            (challengeBytes, challengeID) = try await networkService.fetchChallenge(
                userID: userID,
                actionType: action.actionTypeString,
                minimumCardiacConfidence: action.minimumCardiacConfidence
            )
        } catch {
            fail(.challengeFetchFailed(error.localizedDescription))
            return
        }

        // Step 2: Cardiac gate
        transition(to: .awaitingCardiacConfirmation)
        guard cardiacConfidence >= action.minimumCardiacConfidence else {
            fail(.cardiacConfidenceTooLow(required: action.minimumCardiacConfidence, actual: cardiacConfidence))
            return
        }
        log.info("Cardiac gate passed for registration (\(String(format: "%.2f", cardiacConfidence), privacy: .public) >= \(String(format: "%.2f", action.minimumCardiacConfidence), privacy: .public))")

        // Step 3: Passkey UI via coordinator
        transition(to: .presentingPasskeyUI)
        do {
            try await coordinator.initiateRegistration(userId: userID.uuidString)
        } catch {
            fail(.coordinatorError(error.localizedDescription))
            return
        }

        // Step 4: Persist credential
        transition(to: .verifyingAssertion)
        do {
            try await networkService.registerCredential(
                challengeID: challengeID,
                credentialID: challengeBytes,  // Placeholder — real credentialID from ASAuthorization
                attestationObject: Data(),
                clientDataJSON: Data(),
                cardiacConfidence: cardiacConfidence
            )
            transition(to: .success)
            log.info("Registration completed successfully")
            await loadEnrolledCredentials(for: userID)
        } catch {
            fail(.registrationFailed(error.localizedDescription))
        }
    }

    // MARK: - Authentication

    /// Starts a HeartID-gated passkey authentication (assertion) flow.
    ///
    /// - Parameters:
    ///   - userID: The authenticated user's UUID.
    ///   - credentialIDs: Allowed credential IDs for this user.
    ///   - cardiacConfidence: Current HeartID confidence (0–1).
    func startAuthentication(for userID: UUID, credentialIDs: [Data], cardiacConfidence: Double) async {
        reset()
        let action = PasskeyActionType.authentication
        log.info("Authentication started for \(userID.uuidString, privacy: .public)")

        guard !credentialIDs.isEmpty else {
            fail(.noCredentials)
            return
        }

        // Step 1: Fetch challenge
        transition(to: .requestingChallenge)
        let challengeID: UUID
        do {
            (_, challengeID) = try await networkService.fetchChallenge(
                userID: userID,
                actionType: action.actionTypeString,
                minimumCardiacConfidence: action.minimumCardiacConfidence
            )
        } catch {
            fail(.challengeFetchFailed(error.localizedDescription))
            return
        }

        // Step 2: Cardiac gate
        transition(to: .awaitingCardiacConfirmation)
        guard cardiacConfidence >= action.minimumCardiacConfidence else {
            fail(.cardiacConfidenceTooLow(required: action.minimumCardiacConfidence, actual: cardiacConfidence))
            return
        }
        log.info("Cardiac gate passed for authentication")

        // Step 3: Passkey UI
        transition(to: .presentingPasskeyUI)
        do {
            try await coordinator.initiateAssertion(userId: userID.uuidString)
        } catch {
            fail(.coordinatorError(error.localizedDescription))
            return
        }

        // Step 4: Verify with server
        transition(to: .verifyingAssertion)
        do {
            let verified = try await networkService.verifyAssertion(
                challengeID: challengeID,
                credentialID: credentialIDs[0],
                signature: Data(),
                authenticatorData: Data(),
                clientDataJSON: Data(),
                userHandle: Data(userID.uuidString.utf8),
                cardiacConfidence: cardiacConfidence
            )
            if verified {
                transition(to: .success)
                log.info("Assertion verified successfully")
            } else {
                fail(.assertionFailed("Server rejected assertion"))
            }
        } catch {
            fail(.assertionFailed(error.localizedDescription))
        }
    }

    // MARK: - Step-Up Verification

    /// Starts a high-assurance step-up passkey flow requiring 0.92 cardiac confidence.
    ///
    /// Used for sensitive operations: admin escalation, high-value transactions,
    /// hardware command authorization.
    ///
    /// - Parameters:
    ///   - userID: The authenticated user's UUID.
    ///   - credentialIDs: Allowed credential IDs.
    ///   - cardiacConfidence: Current HeartID confidence (0–1).
    ///   - actionDescription: Human-readable description of the action requiring step-up.
    func startStepUp(
        for userID: UUID,
        credentialIDs: [Data],
        cardiacConfidence: Double,
        actionDescription: String
    ) async {
        reset()
        let action = PasskeyActionType.stepUpVerification
        log.info("Step-up started: \(actionDescription, privacy: .public), confidence=\(String(format: "%.2f", cardiacConfidence), privacy: .public)")

        guard !credentialIDs.isEmpty else {
            fail(.noCredentials)
            return
        }

        // Step 1: Fetch challenge
        transition(to: .requestingChallenge)
        let challengeID: UUID
        do {
            (_, challengeID) = try await networkService.fetchChallenge(
                userID: userID,
                actionType: action.actionTypeString,
                minimumCardiacConfidence: action.minimumCardiacConfidence
            )
        } catch {
            fail(.challengeFetchFailed(error.localizedDescription))
            return
        }

        // Step 2: Cardiac gate (elevated threshold)
        transition(to: .awaitingCardiacConfirmation)
        guard cardiacConfidence >= action.minimumCardiacConfidence else {
            fail(.cardiacConfidenceTooLow(required: action.minimumCardiacConfidence, actual: cardiacConfidence))
            log.warning("Step-up rejected: \(String(format: "%.2f", cardiacConfidence), privacy: .public) < \(String(format: "%.2f", action.minimumCardiacConfidence), privacy: .public)")
            return
        }
        log.info("Step-up cardiac gate passed")

        // Step 3: Passkey UI
        transition(to: .presentingPasskeyUI)
        do {
            try await coordinator.initiateAssertion(userId: userID.uuidString)
        } catch {
            fail(.coordinatorError(error.localizedDescription))
            return
        }

        // Step 4: Verify
        transition(to: .verifyingAssertion)
        do {
            let verified = try await networkService.verifyAssertion(
                challengeID: challengeID,
                credentialID: credentialIDs[0],
                signature: Data(),
                authenticatorData: Data(),
                clientDataJSON: Data(),
                userHandle: Data(userID.uuidString.utf8),
                cardiacConfidence: cardiacConfidence
            )
            if verified {
                transition(to: .success)
                log.info("Step-up assertion verified: \(actionDescription, privacy: .public)")
            } else {
                fail(.assertionFailed("Server rejected step-up assertion"))
            }
        } catch {
            fail(.assertionFailed(error.localizedDescription))
        }
    }

    // MARK: - Credential Management

    /// Fetches all passkey credentials registered by the user.
    /// Updates the `enrolledCredentials` published property.
    func loadEnrolledCredentials(for userID: UUID) async {
        do {
            let creds = try await networkService.listUserCredentials(userID: userID)
            enrolledCredentials = creds
            log.info("Loaded \(creds.count) enrolled credentials for \(userID.uuidString, privacy: .public)")
        } catch {
            log.error("Failed to load credentials: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - State Helpers

    /// Resets the flow to idle with no error.
    func reset() {
        flowState = .idle
        lastError = nil
    }

    private func transition(to newState: HeartIDPasskeyFlowState) {
        let previous = flowState
        flowState = newState
        log.info("Flow: \(previous.rawValue, privacy: .public) → \(newState.rawValue, privacy: .public)")
    }

    private func fail(_ error: HeartIDPasskeyError) {
        lastError = error
        flowState = .failed
        log.error("Flow failed: \(error.localizedDescription, privacy: .public)")
    }
}
