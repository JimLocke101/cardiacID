//
//  DeviceCodeFlowService.swift
//  CardiacID Watch App
//
//  OAuth 2.0 Device Authorization Grant (RFC 8628) for watchOS
//  Used when iPhone is unreachable and Watch needs to authenticate independently
//  MSAL is unavailable on watchOS, so this uses raw URLSession
//

import Foundation

/// OAuth 2.0 Device Code Flow for watchOS standalone authentication
/// Fallback path when iPhone is unreachable and no cached token exists
@MainActor
class DeviceCodeFlowService: ObservableObject {
    static let shared = DeviceCodeFlowService()

    // MARK: - Published State

    @Published private(set) var userCode: String?
    @Published private(set) var verificationURI: String?
    @Published private(set) var isPolling: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var flowState: DeviceCodeFlowState = .idle

    enum DeviceCodeFlowState: Equatable {
        case idle
        case requestingCode
        case displayingCode(userCode: String, verificationURI: String)
        case polling
        case authenticated
        case failed(String)
        case expired
    }

    // MARK: - Configuration (from MSALConfiguration values)

    private let tenantId = "71fec99d-2fb1-4c59-b8a0-32d27906433f"
    private let clientId = "c6414bc9-b537-4305-b277-a86f63fdb5ed"
    private let scopes = "User.Read openid profile offline_access"

    private let deviceCodeEndpoint: String
    private let tokenEndpoint: String

    // MARK: - Internal State

    private var pollingTimer: Timer?
    private var pollingInterval: TimeInterval = 5.0
    private var deviceCode: String?
    private var expiresAt: Date?

    private init() {
        deviceCodeEndpoint = "https://login.microsoftonline.com/\(tenantId)/oauth2/v2.0/devicecode"
        tokenEndpoint = "https://login.microsoftonline.com/\(tenantId)/oauth2/v2.0/token"
    }

    // MARK: - Step 1: Request Device Code

    /// Request a device code from Microsoft Entra ID
    /// Returns the user_code and verification_uri for the user to complete auth on another device
    func requestDeviceCode() async throws {
        flowState = .requestingCode
        errorMessage = nil

        guard let url = URL(string: deviceCodeEndpoint) else {
            flowState = .failed("Invalid endpoint URL")
            throw DeviceCodeError.requestFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let encodedScopes = scopes.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? scopes
        let body = "client_id=\(clientId)&scope=\(encodedScopes)"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            flowState = .failed("Device code request failed (HTTP \(statusCode))")
            throw DeviceCodeError.requestFailed
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let userCode = json["user_code"] as? String,
              let verificationURI = json["verification_uri"] as? String,
              let deviceCode = json["device_code"] as? String,
              let expiresIn = json["expires_in"] as? Int,
              let interval = json["interval"] as? Int else {
            flowState = .failed("Invalid device code response")
            throw DeviceCodeError.invalidResponse
        }

        self.userCode = userCode
        self.verificationURI = verificationURI
        self.deviceCode = deviceCode
        self.pollingInterval = TimeInterval(interval)
        self.expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))

        flowState = .displayingCode(userCode: userCode, verificationURI: verificationURI)
        print("Watch: Device Code Flow - Code: \(userCode), URI: \(verificationURI)")
    }

    // MARK: - Step 2: Poll for Token

    /// Start polling the token endpoint for authorization completion
    func startPolling() {
        guard deviceCode != nil else { return }

        flowState = .polling
        isPolling = true

        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.pollForToken()
            }
        }
    }

    /// Stop the polling timer
    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        isPolling = false
    }

    private func pollForToken() async {
        guard let deviceCode = deviceCode else { return }

        // Check expiration
        if let expiresAt = expiresAt, Date() > expiresAt {
            stopPolling()
            flowState = .expired
            errorMessage = "Device code expired. Please try again."
            return
        }

        guard let url = URL(string: tokenEndpoint) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "grant_type=urn:ietf:params:oauth:grant-type:device_code&client_id=\(clientId)&device_code=\(deviceCode)"
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            // Check for error responses (expected during polling)
            if let error = json["error"] as? String {
                switch error {
                case "authorization_pending":
                    // User hasn't completed auth yet - keep polling
                    return
                case "slow_down":
                    // Server wants us to slow down
                    pollingInterval += 5
                    stopPolling()
                    startPolling()
                    return
                case "expired_token":
                    stopPolling()
                    flowState = .expired
                    errorMessage = "Device code expired. Please try again."
                    return
                case "authorization_declined":
                    stopPolling()
                    flowState = .failed("Authorization was denied")
                    errorMessage = "Authorization was denied by the user."
                    return
                default:
                    let description = json["error_description"] as? String ?? error
                    stopPolling()
                    flowState = .failed(description)
                    errorMessage = description
                    return
                }
            }

            // Success - extract tokens
            if let accessToken = json["access_token"] as? String {
                let refreshToken = json["refresh_token"] as? String ?? ""
                let expiresIn = json["expires_in"] as? Int ?? 3600

                stopPolling()

                // Store tokens in SecureCredentialManager
                do {
                    try SecureCredentialManager.shared.store(accessToken, forKey: .entraIDAccessToken)
                    if !refreshToken.isEmpty {
                        try SecureCredentialManager.shared.store(refreshToken, forKey: .entraIDRefreshToken)
                    }

                    flowState = .authenticated
                    errorMessage = nil

                    // Notify other services of successful authentication
                    NotificationCenter.default.post(
                        name: .init("DeviceCodeFlowAuthenticated"),
                        object: nil,
                        userInfo: [
                            "accessToken": accessToken,
                            "expiresIn": expiresIn,
                            "method": "device_code_flow"
                        ]
                    )

                    print("Watch: Device Code Flow - Authentication successful! Token expires in \(expiresIn)s")
                } catch {
                    flowState = .failed("Failed to store token: \(error.localizedDescription)")
                    errorMessage = "Authentication succeeded but failed to store token."
                    print("Watch: Device Code Flow - Token storage failed: \(error)")
                }
            }
        } catch {
            // Network error - keep trying (don't stop polling)
            print("Watch: Device Code Flow polling error: \(error.localizedDescription)")
        }
    }

    // MARK: - Token Refresh via Device Code Flow

    /// Refresh the access token using the stored refresh token
    /// Falls back to full Device Code Flow if refresh fails
    func refreshAccessToken() async throws -> String {
        guard let refreshToken = try? SecureCredentialManager.shared.retrieve(forKey: .entraIDRefreshToken),
              !refreshToken.isEmpty else {
            throw DeviceCodeError.noRefreshToken
        }

        guard let url = URL(string: tokenEndpoint) else {
            throw DeviceCodeError.requestFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "grant_type=refresh_token&client_id=\(clientId)&refresh_token=\(refreshToken)&scope=\(scopes.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? scopes)"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw DeviceCodeError.tokenRefreshFailed
        }

        // Store refreshed tokens
        try SecureCredentialManager.shared.store(accessToken, forKey: .entraIDAccessToken)
        if let newRefreshToken = json["refresh_token"] as? String {
            try SecureCredentialManager.shared.store(newRefreshToken, forKey: .entraIDRefreshToken)
        }

        return accessToken
    }

    // MARK: - Convenience: Check Token Availability

    /// Check if a valid cached token exists
    var hasValidToken: Bool {
        return SecureCredentialManager.shared.exists(forKey: .entraIDAccessToken)
    }

    /// Get the cached access token if available
    func getCachedToken() -> String? {
        return try? SecureCredentialManager.shared.retrieve(forKey: .entraIDAccessToken)
    }

    // MARK: - Reset

    /// Reset the Device Code Flow to idle state
    func reset() {
        stopPolling()
        userCode = nil
        verificationURI = nil
        deviceCode = nil
        expiresAt = nil
        flowState = .idle
        errorMessage = nil
    }
}

// MARK: - Errors

enum DeviceCodeError: Error, LocalizedError {
    case requestFailed
    case invalidResponse
    case expired
    case authorizationDenied
    case tokenRefreshFailed
    case noRefreshToken

    var errorDescription: String? {
        switch self {
        case .requestFailed: return "Failed to request device code from Entra ID"
        case .invalidResponse: return "Invalid response from authorization server"
        case .expired: return "Device code has expired"
        case .authorizationDenied: return "Authorization was denied"
        case .tokenRefreshFailed: return "Failed to refresh access token"
        case .noRefreshToken: return "No refresh token available"
        }
    }
}
