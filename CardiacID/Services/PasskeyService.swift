//
//  PasskeyService.swift
//  CardiacID
//
//  DOD-Level Passkey Authentication Service
//  Implements WebAuthn/FIDO2 passkey authentication with Watch trigger support
//
//  Created: 2025-01-27
//  Security Level: DOD-Approved
//

import Foundation
import AuthenticationServices
import Combine
import CryptoKit

/// DOD-Level Passkey Authentication Service
/// Handles WebAuthn/FIDO2 passkey registration and authentication
/// Supports Watch-triggered authentication requests
@MainActor
class PasskeyService: NSObject, ObservableObject {
    static let shared = PasskeyService()
    
    // MARK: - Published Properties
    @Published var isAuthenticated = false
    @Published var isRegistering = false
    @Published var isAuthenticating = false
    @Published var errorMessage: String?
    @Published var lastAuthResult: PasskeyAuthResult?
    
    // MARK: - Configuration
    /// Relying Party Identifier (your domain)
    /// CRITICAL: Must match your Associated Domains entitlement
    private let relyingPartyIdentifier: String
    
    // MARK: - Publishers
    private let authResultSubject = PassthroughSubject<PasskeyAuthResult, Never>()
    private let registrationSubject = PassthroughSubject<PasskeyRegistrationResult, Never>()
    
    var authResultPublisher: AnyPublisher<PasskeyAuthResult, Never> {
        authResultSubject.eraseToAnyPublisher()
    }
    
    var registrationPublisher: AnyPublisher<PasskeyRegistrationResult, Never> {
        registrationSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    private override init() {
        // CRITICAL: Set your actual domain here
        // This must match the Associated Domains entitlement
        // For production, use your actual domain (e.g., "cardiacid.com")
        self.relyingPartyIdentifier = "cardiacid.com"
        
        super.init()
        print("🔐 PasskeyService: Initialized with Relying Party: \(relyingPartyIdentifier)")
    }
    
    // MARK: - Passkey Registration
    
    /// Register a new passkey for the user
    /// - Parameters:
    ///   - username: User's username/email
    ///   - userID: Unique user identifier (Data)
    ///   - challenge: Server-provided challenge (Data)
    /// - Returns: Registration result
    func registerPasskey(
        username: String,
        userID: Data,
        challenge: Data
    ) async throws -> PasskeyRegistrationResult {
        guard !isRegistering else {
            throw PasskeyError.registrationInProgress
        }
        
        isRegistering = true
        errorMessage = nil
        
        print("🔐 PasskeyService: Starting registration for \(username)")
        
        return try await withCheckedThrowingContinuation { continuation in
            let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
                relyingPartyIdentifier: relyingPartyIdentifier
            )
            
            let request = provider.createCredentialRegistrationRequest(
                challenge: challenge,
                name: username,
                userID: userID
            )
            
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            
            // Store continuation for delegate callback
            self.registrationContinuation = continuation
            
            controller.performRequests()
        }
    }
    
    // MARK: - Passkey Authentication
    
    /// Authenticate using an existing passkey
    /// - Parameter challenge: Server-provided challenge (Data)
    /// - Returns: Authentication result
    func authenticate(challenge: Data) async throws -> PasskeyAuthResult {
        guard !isAuthenticating else {
            throw PasskeyError.authenticationInProgress
        }
        
        isAuthenticating = true
        errorMessage = nil
        
        print("🔐 PasskeyService: Starting authentication")
        
        return try await withCheckedThrowingContinuation { continuation in
            let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
                relyingPartyIdentifier: relyingPartyIdentifier
            )
            
            let request = provider.createCredentialAssertionRequest(
                challenge: challenge
            )
            
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            
            // Store continuation for delegate callback
            self.authContinuation = continuation
            
            controller.performRequests()
        }
    }
    
    // MARK: - Watch-Triggered Authentication
    
    /// Handle authentication request from Watch
    /// This is called when Watch sends "passkey_authenticate" message
    func handleWatchAuthenticationRequest(challenge: Data) async {
        print("🔐 PasskeyService: Received authentication request from Watch")
        
        do {
            let result = try await authenticate(challenge: challenge)
            print("✅ PasskeyService: Authentication successful - User: \(result.userID?.base64EncodedString() ?? "unknown")")
            
            // Publish result
            authResultSubject.send(result)
            lastAuthResult = result
            isAuthenticated = result.success
            
        } catch {
            print("❌ PasskeyService: Authentication failed - \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            isAuthenticated = false
            
            // Publish error result
            let errorResult = PasskeyAuthResult(
                success: false,
                credentialID: nil,
                userID: nil,
                signature: nil,
                clientDataJSON: nil,
                authenticatorData: nil,
                error: error.localizedDescription
            )
            authResultSubject.send(errorResult)
        }
    }
    
    // MARK: - Private Properties
    
    private var registrationContinuation: CheckedContinuation<PasskeyRegistrationResult, Error>?
    private var authContinuation: CheckedContinuation<PasskeyAuthResult, Error>?
}

// MARK: - ASAuthorizationControllerDelegate

extension PasskeyService: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        print("🔐 PasskeyService: Authorization completed")
        
        if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration {
            // Registration completed
            handleRegistrationSuccess(credential: credential)
        } else if let assertion = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
            // Authentication completed
            handleAuthenticationSuccess(assertion: assertion)
        }
    }
    
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        print("❌ PasskeyService: Authorization failed - \(error.localizedDescription)")
        
        errorMessage = error.localizedDescription
        isRegistering = false
        isAuthenticating = false
        
        // Handle cancellation vs actual error
        if let authError = error as? ASAuthorizationError {
            switch authError.code {
            case .canceled:
                print("🔐 PasskeyService: User canceled authentication")
                // Don't treat cancellation as error
                registrationContinuation?.resume(throwing: PasskeyError.userCanceled)
                authContinuation?.resume(throwing: PasskeyError.userCanceled)
            default:
                registrationContinuation?.resume(throwing: error)
                authContinuation?.resume(throwing: error)
            }
        } else {
            registrationContinuation?.resume(throwing: error)
            authContinuation?.resume(throwing: error)
        }
        
        registrationContinuation = nil
        authContinuation = nil
    }
    
    // MARK: - Private Helpers
    
    private func handleRegistrationSuccess(credential: ASAuthorizationPlatformPublicKeyCredentialRegistration) {
        print("✅ PasskeyService: Registration successful")
        
        let result = PasskeyRegistrationResult(
            success: true,
            credentialID: credential.credentialID,
            rawClientDataJSON: credential.rawClientDataJSON,
            rawAttestationObject: credential.rawAttestationObject,
            error: nil
        )
        
        isRegistering = false
        registrationContinuation?.resume(returning: result)
        registrationContinuation = nil
        
        // Publish result
        registrationSubject.send(result)
    }
    
    private func handleAuthenticationSuccess(assertion: ASAuthorizationPlatformPublicKeyCredentialAssertion) {
        print("✅ PasskeyService: Authentication successful")
        
        let result = PasskeyAuthResult(
            success: true,
            credentialID: assertion.credentialID,
            userID: assertion.userID,
            signature: assertion.signature,
            clientDataJSON: assertion.rawClientDataJSON,
            authenticatorData: assertion.rawAuthenticatorData,
            error: nil
        )
        
        isAuthenticating = false
        isAuthenticated = true
        lastAuthResult = result
        authContinuation?.resume(returning: result)
        authContinuation = nil
        
        // Publish result
        authResultSubject.send(result)
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension PasskeyService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Return the main window
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            fatalError("No window available for passkey presentation")
        }
        return window
    }
}

// MARK: - Result Types

/// Passkey registration result
struct PasskeyRegistrationResult {
    let success: Bool
    let credentialID: Data
    let rawClientDataJSON: Data
    let rawAttestationObject: Data?  // Optional since it may not always be available
    let error: String?
}

/// Passkey authentication result
struct PasskeyAuthResult {
    let success: Bool
    let credentialID: Data?
    let userID: Data?
    let signature: Data?
    let clientDataJSON: Data?
    let authenticatorData: Data?
    let error: String?
}

// MARK: - Error Types

enum PasskeyError: LocalizedError {
    case registrationInProgress
    case authenticationInProgress
    case userCanceled
    case invalidConfiguration
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .registrationInProgress:
            return "Registration is already in progress"
        case .authenticationInProgress:
            return "Authentication is already in progress"
        case .userCanceled:
            return "User canceled authentication"
        case .invalidConfiguration:
            return "Invalid passkey configuration"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}
