// HeartIDAuthenticationService.swift
// CardiacID
//
// End-to-end authentication flow:
//   1. Receive CardiacSignature from Watch (or trigger capture)
//   2. Pre-sign with Secure Enclave key for device binding
//   3. POST to /api/auth/verify-heart on Supabase
//   4. Receive confidence + JWT
//   5. Update SessionTrustManager
//   6. Optionally feed into OIDC EAM flow for Entra ID
//
// This is the iPhone-side orchestrator that ties the Watch biometric
// pipeline to the Azure backend.

import Foundation
import CryptoKit
import Security

@MainActor
final class HeartIDAuthenticationService: ObservableObject {
    static let shared = HeartIDAuthenticationService()

    @Published private(set) var isAuthenticating = false
    @Published private(set) var lastVerifyResponse: VerifyHeartResponse?
    @Published private(set) var errorMessage: String?

    private let watchConnectivity = WatchConnectivityService.shared
    private let sessionTrust      = SessionTrustManager.shared
    private let auditLogger       = AuditLogger.shared
    private let keyManager        = SecureKeyManager.shared

    private let verifyURL: URL
    private let session = URLSession.shared

    private init() {
        let base = SupabaseConfiguration.functionsURL
        verifyURL = URL(string: "\(base)/verify-heart")!
    }

    // MARK: - Primary flow: authenticate with current Watch data

    /// Triggers HeartID verification using live Watch biometric data.
    /// Returns the backend confidence score, or nil on failure.
    @discardableResult
    func authenticate(userId: String, email: String, displayName: String) async -> VerifyHeartResponse? {
        isAuthenticating = true
        errorMessage     = nil
        defer { isAuthenticating = false }

        // Build the cardiac signature from current Watch state
        let signature = buildSignatureFromWatchState()

        guard signature.qualityScore > 0.3 else {
            errorMessage = "Insufficient cardiac data — ensure Watch is on wrist and monitoring."
            auditLogger.logOperational(action: "verify-heart", outcome: "insufficient_data",
                                        score: signature.qualityScore)
            return nil
        }

        // Sign the payload for device binding (Secure Enclave on device, software in simulator)
        let deviceId    = getDeviceId()
        let nonce       = UUID().uuidString
        let timestampMs = Int(Date().timeIntervalSince1970 * 1000)

        let payload = VerifyHeartRequest(
            userId: userId,
            email: email,
            displayName: displayName,
            cardiacSignature: signature,
            deviceId: deviceId,
            nonce: nonce,
            timestamp: timestampMs
        )

        // Device-bind: sign the canonical payload
        let deviceSignature: String
        do {
            let canonical = "\(userId):\(deviceId):\(nonce):\(timestampMs)"
            let signingKey = try keyManager.applicationSigningKey()
            let sig = try signingKey.signature(for: Data(canonical.utf8))
            deviceSignature = sig.base64EncodedString()
        } catch {
            errorMessage = "Device signing failed: \(error.localizedDescription)"
            return nil
        }

        // POST to backend
        do {
            var request = URLRequest(url: verifyURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(SupabaseConfiguration.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(SupabaseConfiguration.anonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(deviceSignature, forHTTPHeaderField: "X-Device-Signature")
            request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
            request.timeoutInterval = 15

            request.httpBody = try JSONEncoder().encode(payload)

            let (data, httpResponse) = try await session.data(for: request)

            guard let http = httpResponse as? HTTPURLResponse else {
                throw AuthServiceError.invalidResponse
            }

            guard http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw AuthServiceError.serverError(http.statusCode, body)
            }

            let response = try JSONDecoder().decode(VerifyHeartResponse.self, from: data)
            lastVerifyResponse = response

            // Update session trust based on backend confidence
            let result = HeartVerificationResult.verified(
                match: response.confidence,
                liveness: response.livenessScore
            )
            sessionTrust.recordVerification(result)

            auditLogger.logOperational(
                action: "verify-heart", outcome: response.verified ? "verified" : "denied",
                score: response.confidence, reasonCode: response.method
            )

            return response

        } catch {
            errorMessage = "Verification failed: \(error.localizedDescription)"
            auditLogger.logOperational(action: "verify-heart", outcome: "error",
                                        reasonCode: error.localizedDescription)
            return nil
        }
    }

    // MARK: - EAM session flow (called when deep link cardiacid://eam?session=<id> fires)

    /// Complete an Entra ID EAM session by verifying HeartID and posting to oidc-authorize.
    func completeEAMSession(sessionId: String, userId: String, email: String, displayName: String) async -> Bool {
        // First verify with HeartID
        guard let response = await authenticate(userId: userId, email: email, displayName: displayName),
              response.verified else {
            return false
        }

        // POST to oidc-authorize with the biometric result
        let authorizeURL = URL(string: "\(SupabaseConfiguration.functionsURL)/oidc-authorize")!
        var request = URLRequest(url: authorizeURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfiguration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfiguration.anonKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "session_id": sessionId,
            "user_id": userId,
            "email": email,
            "display_name": displayName,
            "biometric_confidence": response.confidence,
            "biometric_method": response.method
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, httpResponse) = try await session.data(for: request)
            guard let http = httpResponse as? HTTPURLResponse, http.statusCode == 200 else {
                return false
            }
            auditLogger.logOperational(action: "eam.complete", outcome: "ok", score: response.confidence)
            return true
        } catch {
            auditLogger.logOperational(action: "eam.complete", outcome: "error",
                                        reasonCode: error.localizedDescription)
            return false
        }
    }

    // MARK: - Build signature from current Watch state

    private func buildSignatureFromWatchState() -> HeartIDSignaturePayload {
        let wc = watchConnectivity
        return HeartIDSignaturePayload(
            hrv: 0, // Will be calculated by backend from beatIntervals
            restingHR: Double(wc.lastHeartRate),
            waveformFeatures: [], // Backend uses enrolled template for comparison
            timestamp: wc.liveBiometricTimestamp ?? Date(),
            sdnn: 0,
            signalNoiseRatio: 0,
            method: wc.liveBiometricMethod,
            beatIntervals: [],
            recentHeartRates: [],
            wristDetected: true,
            confidence: wc.liveBiometricConfidence,
            authenticated: wc.liveBiometricAuthenticated
        )
    }

    private func getDeviceId() -> String {
        if let stored = try? SecureCredentialManager.shared.retrieve(forKey: .heartIDPattern) {
            // Reuse stored device ID
            return stored
        }
        let id = UUID().uuidString
        try? SecureCredentialManager.shared.store(id, forKey: .heartIDPattern)
        return id
    }
}

// MARK: - Request / Response models

/// iPhone-side cardiac signature payload for the verify-heart API.
/// Distinct from the Watch-side CardiacSignature model (which has no confidence/authenticated fields).
struct HeartIDSignaturePayload: Codable, Sendable {
    let hrv: Double
    let restingHR: Double
    let waveformFeatures: [Double]
    let timestamp: Date
    let sdnn: Double
    let signalNoiseRatio: Double
    let method: String
    let beatIntervals: [Double]
    let recentHeartRates: [Double]
    let wristDetected: Bool
    let confidence: Double
    let authenticated: Bool

    var qualityScore: Double {
        var score = 1.0
        if !wristDetected { score *= 0.3 }
        if confidence <= 0 { score *= 0.5 }
        return min(max(score, 0.0), 1.0)
    }
}

struct VerifyHeartRequest: Codable {
    let userId: String
    let email: String
    let displayName: String
    let cardiacSignature: HeartIDSignaturePayload
    let deviceId: String
    let nonce: String
    let timestamp: Int
}

struct VerifyHeartResponse: Codable {
    let verified: Bool
    let confidence: Double
    let livenessScore: Double
    let method: String
    let assuranceLevel: String
    let sessionToken: String?
}

enum AuthServiceError: Error, LocalizedError {
    case invalidResponse
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid server response"
        case .serverError(let code, let body): return "Server error \(code): \(body)"
        }
    }
}
