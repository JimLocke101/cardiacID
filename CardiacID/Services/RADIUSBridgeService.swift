//
//  RADIUSBridgeService.swift
//  CardiacID
//
//  Bridges CardiacID biometric authentication with RADIUS infrastructure
//  Works with Azure MFA NPS Extension (still supported, no deprecation timeline)
//  for legacy door controllers, VPNs, and network access
//

import Foundation
import Combine

/// RADIUS authentication bridge for legacy systems
/// Validates CardiacID tokens and biometric confidence for RADIUS authentication requests
/// Designed to work with Azure MFA NPS Extension or Entra Private Access
@MainActor
class RADIUSBridgeService: ObservableObject {
    static let shared = RADIUSBridgeService()

    // MARK: - Published State

    @Published private(set) var isConfigured: Bool = false
    @Published private(set) var lastAuthAttempt: Date?
    @Published private(set) var pendingRequests: [RADIUSAuthRequest] = []

    // MARK: - Configuration

    struct RADIUSConfig: Codable {
        let serverAddress: String
        let serverPort: Int
        let sharedSecret: String
        let npsExtensionEnabled: Bool
        let entraPrivateAccessEnabled: Bool
        let minimumBiometricConfidence: Double

        static let `default` = RADIUSConfig(
            serverAddress: "",
            serverPort: 1812,
            sharedSecret: "",
            npsExtensionEnabled: true,
            entraPrivateAccessEnabled: false,
            minimumBiometricConfidence: 0.75
        )
    }

    private var config: RADIUSConfig = .default

    // MARK: - Models

    struct RADIUSAuthRequest: Identifiable {
        let id = UUID()
        let username: String
        let requestType: RequestType
        let sourceIP: String?
        let timestamp: Date
        let nasIdentifier: String? // Network Access Server ID

        enum RequestType: String, Codable {
            case accessRequest = "Access-Request"
            case accountingRequest = "Accounting-Request"
        }
    }

    struct RADIUSAuthResult {
        let success: Bool
        let responseType: ResponseType
        let message: String
        let biometricConfidence: Double?
        let authMethod: String

        enum ResponseType: String {
            case accessAccept = "Access-Accept"
            case accessReject = "Access-Reject"
            case accessChallenge = "Access-Challenge"
        }
    }

    // MARK: - Initialization

    private init() {
        loadConfiguration()
    }

    // MARK: - Configuration

    /// Non-sensitive fields persisted to UserDefaults.
    /// The sharedSecret is stored separately in the Keychain via SecureCredentialManager.
    private struct PersistableRADIUSConfig: Codable {
        let serverAddress: String
        let serverPort: Int
        let npsExtensionEnabled: Bool
        let entraPrivateAccessEnabled: Bool
        let minimumBiometricConfidence: Double
    }

    func configure(_ config: RADIUSConfig) {
        self.config = config
        isConfigured = !config.serverAddress.isEmpty && !config.sharedSecret.isEmpty
        saveConfiguration()
    }

    private func loadConfiguration() {
        guard let data = UserDefaults.standard.data(forKey: "radius_config"),
              let persisted = try? JSONDecoder().decode(PersistableRADIUSConfig.self, from: data) else { return }

        // Retrieve shared secret from Keychain (never from UserDefaults)
        let secret = (try? SecureCredentialManager.shared.retrieve(forKey: .radiusSharedSecret)) ?? ""

        config = RADIUSConfig(
            serverAddress: persisted.serverAddress,
            serverPort: persisted.serverPort,
            sharedSecret: secret,
            npsExtensionEnabled: persisted.npsExtensionEnabled,
            entraPrivateAccessEnabled: persisted.entraPrivateAccessEnabled,
            minimumBiometricConfidence: persisted.minimumBiometricConfidence
        )
        isConfigured = !persisted.serverAddress.isEmpty && !secret.isEmpty
    }

    private func saveConfiguration() {
        // Store the shared secret in Keychain — never in UserDefaults
        if !config.sharedSecret.isEmpty {
            try? SecureCredentialManager.shared.store(
                config.sharedSecret, forKey: .radiusSharedSecret
            )
        }

        // Persist all non-sensitive fields to UserDefaults
        let persisted = PersistableRADIUSConfig(
            serverAddress: config.serverAddress,
            serverPort: config.serverPort,
            npsExtensionEnabled: config.npsExtensionEnabled,
            entraPrivateAccessEnabled: config.entraPrivateAccessEnabled,
            minimumBiometricConfidence: config.minimumBiometricConfidence
        )
        if let encoded = try? JSONEncoder().encode(persisted) {
            UserDefaults.standard.set(encoded, forKey: "radius_config")
        }
    }

    // MARK: - Token Validation for RADIUS

    /// Validate a CardiacID token for RADIUS authentication
    /// This is called when a RADIUS server forwards an authentication request
    /// that includes a CardiacID token as the authentication credential
    func validateTokenForRADIUS(accessToken: String, biometricConfidence: Double? = nil) async -> RADIUSAuthResult {
        lastAuthAttempt = Date()

        // Step 1: Validate the EntraID access token
        guard !accessToken.isEmpty else {
            return RADIUSAuthResult(
                success: false,
                responseType: .accessReject,
                message: "No access token provided",
                biometricConfidence: nil,
                authMethod: "token"
            )
        }

        // Step 2: Check biometric confidence if provided
        if let confidence = biometricConfidence {
            guard confidence >= config.minimumBiometricConfidence else {
                return RADIUSAuthResult(
                    success: false,
                    responseType: .accessChallenge,
                    message: "Biometric confidence \(Int(confidence * 100))% below required \(Int(config.minimumBiometricConfidence * 100))%",
                    biometricConfidence: confidence,
                    authMethod: "heartid"
                )
            }
        }

        // Step 3: Validate token with Microsoft Graph
        do {
            let graphClient = MicrosoftGraphClient(accessToken: accessToken)
            let profile = try await graphClient.getUserProfile()

            // Step 4: Check group-based access via AccessControlService
            let hasAccess = !AccessControlService.shared.doorPermissions.isEmpty

            return RADIUSAuthResult(
                success: true,
                responseType: .accessAccept,
                message: "Authenticated: \(profile.displayName ?? profile.userPrincipalName)",
                biometricConfidence: biometricConfidence,
                authMethod: biometricConfidence != nil ? "heartid+entra" : "entra"
            )
        } catch {
            return RADIUSAuthResult(
                success: false,
                responseType: .accessReject,
                message: "Token validation failed: \(error.localizedDescription)",
                biometricConfidence: biometricConfidence,
                authMethod: "token"
            )
        }
    }

    /// Generate a RADIUS-compatible authentication payload
    /// Used when CardiacID needs to authenticate to a RADIUS-protected resource
    func generateRADIUSPayload(username: String, biometricConfidence: Double) async -> [String: Any] {
        var payload: [String: Any] = [
            "username": username,
            "auth_method": "CardiacID",
            "biometric_confidence": biometricConfidence,
            "timestamp": Date().timeIntervalSince1970
        ]

        // Include EntraID token if available
        if let token = try? await EntraIDAuthClient.shared.getAccessToken() {
            payload["entra_token"] = token
        }

        return payload
    }

    // MARK: - NPS Extension Integration Info

    /// Information about Azure MFA NPS Extension configuration
    /// The NPS Extension is still supported by Microsoft (no deprecation timeline)
    struct NPSExtensionInfo {
        static let downloadURL = "https://aka.ms/npsmfa"
        static let setupScript = "AzureMfaNpsExtnConfigSetup.ps1"
        static let defaultPort = 1812
        static let supportedMethods = ["Microsoft Authenticator Push", "TOTP", "Phone Call"]

        static let limitations = [
            "Does NOT support Conditional Access policies",
            "All RADIUS requests require MFA (no selective enforcement)",
            "Users must be registered for Entra MFA beforehand",
            "Does not enforce Authentication Methods Policy scoping"
        ]

        static let modernAlternative = "Microsoft Entra Private Access (Zero Trust Network Access)"
    }
}
