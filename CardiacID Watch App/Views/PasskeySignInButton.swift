//
//  PasskeySignInButton.swift
//  CardiacID Watch App
//
//  Watch-triggered FIDO2 Authentication Button
//  Uses HeartID biometrics to gate FIDO2 operations directly on Watch
//
//  Created: 2025-01-27
//  Updated: 2026-01-12 - Implemented Watch-native FIDO2 with HeartID gating
//  Security Level: DOD-Approved
//

import SwiftUI
import WatchConnectivity

struct PasskeySignInButton: View {
    @EnvironmentObject var watchConnectivity: WatchConnectivityService
    @EnvironmentObject var heartIDService: HeartIDService
    @StateObject private var fido2Service = WatchFIDO2Service.shared

    @State private var isAuthenticating = false
    @State private var authenticationStatus: String?
    @State private var showError = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    @State private var successMessage: String?
    @State private var authenticationMethod: String = ""
    @State private var showRegistrationPrompt = false

    /// Minimum confidence threshold for FIDO2 operations
    private let minimumConfidenceThreshold: Double = 0.70  // 70% minimum

    /// Full access threshold
    private let fullAccessThreshold: Double = 0.85  // 85% for full access

    var body: some View {
        Button(action: {
            triggerFIDO2Authentication()
        }) {
            MenuButton(
                icon: buttonIcon,
                title: "Sign In",
                subtitle: authenticationSubtitle,
                color: authenticationColor
            )
        }
        .disabled(isAuthenticating)
        .alert("Authentication Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Unknown error occurred")
        }
        .alert("Authentication Successful", isPresented: $showSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(successMessage ?? "You are now authenticated")
        }
        .alert("Register Device?", isPresented: $showRegistrationPrompt) {
            Button("Register", role: .none) {
                Task {
                    await registerFIDO2Credential()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("No FIDO2 credential found on this Watch. Would you like to register this device for passwordless authentication?")
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("PasskeyAuthenticationResult"))) { notification in
            handleAuthenticationResult(notification)
        }
    }

    // MARK: - UI Properties

    private var buttonIcon: String {
        if fido2Service.isRegistered {
            return "key.fill"
        } else {
            return "key"
        }
    }

    private var authenticationSubtitle: String {
        if isAuthenticating {
            return authenticationMethod.isEmpty ? "Authenticating..." : authenticationMethod
        }

        // Show FIDO2 + HeartID status
        if heartIDService.enrollmentState == .enrolled {
            let confidenceText: String
            switch heartIDService.authenticationState {
            case .authenticated(let confidence):
                confidenceText = "\(Int(confidence * 100))%"
            case .conditional(let confidence):
                confidenceText = "\(Int(confidence * 100))%"
            case .unauthenticated:
                confidenceText = "Ready"
            }

            if fido2Service.isRegistered {
                return "FIDO2 + HeartID: \(confidenceText)"
            } else {
                return "HeartID: \(confidenceText) (Tap to register)"
            }
        }

        if fido2Service.isRegistered {
            return "FIDO2 Ready"
        }

        return "Tap to Setup"
    }

    private var authenticationColor: Color {
        if isAuthenticating {
            return .orange
        }

        // Color based on HeartID + FIDO2 status
        if heartIDService.enrollmentState == .enrolled {
            switch heartIDService.authenticationState {
            case .authenticated:
                return fido2Service.isRegistered ? .green : .blue
            case .conditional:
                return .yellow
            case .unauthenticated:
                return .blue
            }
        }

        return fido2Service.isRegistered ? .blue : .gray
    }

    // MARK: - FIDO2 Authentication Flow

    /// Main authentication trigger - gates FIDO2 operations with HeartID
    private func triggerFIDO2Authentication() {
        isAuthenticating = true
        authenticationStatus = "Checking authentication..."

        print("⌚️ Watch: FIDO2 Sign In triggered")

        // Check 1: HeartID must be enrolled
        guard heartIDService.enrollmentState == .enrolled else {
            errorMessage = "Please enroll with HeartID first before using FIDO2 authentication."
            showError = true
            isAuthenticating = false
            return
        }

        // Check 2: HeartID must have valid authentication
        guard hasValidHeartIDAuthentication() else {
            errorMessage = "HeartID confidence is below \(Int(minimumConfidenceThreshold * 100))%. Please authenticate with HeartID first."
            showError = true
            isAuthenticating = false
            return
        }

        // Check 3: FIDO2 credential must exist (or prompt registration)
        if !fido2Service.isRegistered {
            isAuthenticating = false
            showRegistrationPrompt = true
            return
        }

        // Proceed with FIDO2 authentication
        Task {
            await performFIDO2Authentication()
        }
    }

    /// Check if HeartID authentication is valid
    private func hasValidHeartIDAuthentication() -> Bool {
        switch heartIDService.authenticationState {
        case .authenticated(let confidence):
            return confidence >= minimumConfidenceThreshold
        case .conditional(let confidence):
            return confidence >= minimumConfidenceThreshold
        case .unauthenticated:
            return false
        }
    }

    /// Perform FIDO2 authentication using HeartID-gated signature
    private func performFIDO2Authentication() async {
        authenticationMethod = "FIDO2 + HeartID..."

        let confidence = heartIDService.currentConfidence
        let userName = heartIDService.enrolledUserName ?? "User"

        print("🔐 Watch: Performing FIDO2 authentication gated by HeartID (\(Int(confidence * 100))%)")

        // Generate challenge (in production, get from server)
        let challenge = generateChallenge()

        do {
            // Perform FIDO2 authentication (gated by HeartID confidence)
            let response = try await fido2Service.authenticate(
                challenge: challenge,
                heartIDConfidence: confidence
            )

            print("✅ Watch: FIDO2 signature generated successfully")

            // Determine access level
            let accessLevel: String
            if confidence >= fullAccessThreshold {
                accessLevel = "full"
            } else {
                accessLevel = "conditional"
            }

            // Send to iPhone/Server for verification
            if watchConnectivity.isConnected {
                var message = response.toDictionary()
                message["message_type"] = "fido2_authenticate"
                message["heartid_confidence"] = confidence
                message["user_name"] = userName
                message["access_level"] = accessLevel
                message["timestamp"] = Date().timeIntervalSince1970

                watchConnectivity.sendMessage(message) { success in
                    if success {
                        print("✅ Watch: FIDO2 assertion sent to iPhone for verification")
                    }
                }
            }

            // Complete authentication locally
            await MainActor.run {
                isAuthenticating = false
                authenticationMethod = ""

                if confidence >= fullAccessThreshold {
                    successMessage = "FIDO2 Authenticated\n\(userName)\nHeartID: \(Int(confidence * 100))%\nFull Access Granted"
                } else {
                    successMessage = "FIDO2 Authenticated\n\(userName)\nHeartID: \(Int(confidence * 100))%\nConditional Access"
                }
                showSuccess = true
            }

            print("✅ Watch: FIDO2 authentication complete - \(accessLevel) access")

            // Post notification for other components
            NotificationCenter.default.post(
                name: .init("FIDO2AuthenticationComplete"),
                object: nil,
                userInfo: [
                    "success": true,
                    "confidence": confidence,
                    "userName": userName,
                    "accessLevel": accessLevel,
                    "method": "fido2_heartid",
                    "credentialID": response.credentialID.base64EncodedString()
                ]
            )

        } catch {
            print("❌ Watch: FIDO2 authentication failed - \(error.localizedDescription)")

            await MainActor.run {
                isAuthenticating = false
                authenticationMethod = ""
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    // MARK: - FIDO2 Registration

    /// Register a new FIDO2 credential on the Watch
    private func registerFIDO2Credential() async {
        isAuthenticating = true
        authenticationMethod = "Registering FIDO2..."

        let confidence = heartIDService.currentConfidence
        let userName = heartIDService.enrolledUserName ?? "User"

        print("🔐 Watch: Registering FIDO2 credential")

        // Generate registration data (in production, get from server)
        let challenge = generateChallenge()
        let userID = Data(userName.utf8)

        do {
            let response = try await fido2Service.register(
                challenge: challenge,
                userID: userID,
                userName: userName,
                heartIDConfidence: confidence
            )

            print("✅ Watch: FIDO2 credential registered successfully")

            // Send to iPhone/Server for storage
            if watchConnectivity.isConnected {
                var message = response.toDictionary()
                message["message_type"] = "fido2_register"
                message["user_name"] = userName
                message["timestamp"] = Date().timeIntervalSince1970

                watchConnectivity.sendMessage(message) { success in
                    if success {
                        print("✅ Watch: FIDO2 registration sent to iPhone")
                    }
                }
            }

            await MainActor.run {
                isAuthenticating = false
                authenticationMethod = ""
                successMessage = "FIDO2 Credential Registered\n\nThis Watch is now set up for passwordless authentication."
                showSuccess = true
            }

        } catch {
            print("❌ Watch: FIDO2 registration failed - \(error.localizedDescription)")

            await MainActor.run {
                isAuthenticating = false
                authenticationMethod = ""
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    // MARK: - Legacy Passkey Fallback

    /// Handle authentication result from iPhone passkey (fallback)
    private func handleAuthenticationResult(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let success = userInfo["success"] as? Bool else {
            return
        }

        isAuthenticating = false
        authenticationMethod = ""

        if success {
            print("✅ Watch: iPhone passkey authentication successful")
            successMessage = "Passkey Authentication Successful"
            showSuccess = true
        } else {
            print("❌ Watch: iPhone passkey authentication failed")
            if let message = userInfo["message"] as? [String: Any],
               let error = message["error"] as? String {
                errorMessage = error
            } else {
                errorMessage = "Authentication failed"
            }
            showError = true
        }
    }

    // MARK: - Helpers

    /// Generate cryptographic challenge
    private func generateChallenge() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        return Data(bytes)
    }
}

#Preview {
    PasskeySignInButton()
        .environmentObject(WatchConnectivityService.shared)
        .environmentObject(HeartIDService())
}
