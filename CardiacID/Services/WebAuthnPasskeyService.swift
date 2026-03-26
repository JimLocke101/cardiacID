//
//  WebAuthnPasskeyService.swift
//  CardiacID
//
//  Production implementation of PasskeyServiceProtocol that communicates
//  with the WebAuthn Relying Party Supabase Edge Functions.
//
//  Endpoints:
//    POST /webauthn-register   (action: begin | complete)
//    POST /webauthn-authenticate (action: begin | complete)
//
//  Replaces MockPasskeyService for live passkey flows.
//

import Foundation

// MARK: - Configuration

struct WebAuthnConfiguration: Sendable {
    let baseURL: URL
    let relyingPartyId: String

    static let production = WebAuthnConfiguration(
        baseURL: URL(string: "https://iufsxauhrnaunglfxtly.supabase.co/functions/v1")!,
        relyingPartyId: "cardiacid.com"
    )
}

// MARK: - WebAuthnPasskeyService

final class WebAuthnPasskeyService: PasskeyServiceProtocol, @unchecked Sendable {

    private let config: WebAuthnConfiguration
    private let session: URLSession

    init(
        config: WebAuthnConfiguration = .production,
        session: URLSession = .shared
    ) {
        self.config = config
        self.session = session
    }

    // MARK: - Registration

    func beginRegistration(for userId: String) async throws -> PasskeyRegistrationChallenge {
        let url = config.baseURL.appendingPathComponent("webauthn-register")
        let body: [String: Any] = [
            "action": "begin",
            "userId": userId,
            "userName": "\(userId)@cardiacid.com",
            "displayName": userId
        ]

        let response: BeginRegistrationResponse = try await post(url: url, body: body)

        guard let challengeData = Data(base64URLEncoded: response.options.challenge) else {
            throw WebAuthnError.invalidChallenge
        }

        return PasskeyRegistrationChallenge(
            challengeData: challengeData,
            relyingPartyId: response.options.rp.id,
            userId: response.options.user.id,
            userName: response.options.user.name
        )
    }

    func completeRegistration(_ response: PasskeyRegistrationResponse) async throws {
        let url = config.baseURL.appendingPathComponent("webauthn-register")
        let body: [String: Any] = [
            "action": "complete",
            "challengeId": response.credentialId.base64URLEncodedString(),
            "credential": [
                "id": response.credentialId.base64URLEncodedString(),
                "rawId": response.credentialId.base64URLEncodedString(),
                "type": "public-key",
                "response": [
                    "clientDataJSON": response.clientDataJSON.base64URLEncodedString(),
                    "attestationObject": response.attestationObject.base64URLEncodedString()
                ]
            ]
        ]

        let result: CompletionResponse = try await post(url: url, body: body)
        guard result.verified else {
            throw WebAuthnError.registrationFailed(result.error ?? "Unknown error")
        }
    }

    // MARK: - Assertion

    func beginAssertion(for userId: String) async throws -> PasskeyAssertionChallenge {
        let url = config.baseURL.appendingPathComponent("webauthn-authenticate")
        let body: [String: Any] = [
            "action": "begin",
            "userId": userId
        ]

        let response: BeginAssertionResponse = try await post(url: url, body: body)

        guard let challengeData = Data(base64URLEncoded: response.options.challenge) else {
            throw WebAuthnError.invalidChallenge
        }

        let allowedIds = (response.options.allowCredentials ?? []).compactMap { cred in
            Data(base64URLEncoded: cred.id)
        }

        return PasskeyAssertionChallenge(
            challengeData: challengeData,
            relyingPartyId: response.options.rpId,
            allowedCredentialIds: allowedIds
        )
    }

    func completeAssertion(_ response: PasskeyAssertionResponse) async throws -> PasskeyAssertionResult {
        let url = config.baseURL.appendingPathComponent("webauthn-authenticate")
        let body: [String: Any] = [
            "action": "complete",
            "challengeId": response.credentialId.base64URLEncodedString(),
            "credential": [
                "id": response.credentialId.base64URLEncodedString(),
                "rawId": response.credentialId.base64URLEncodedString(),
                "type": "public-key",
                "response": [
                    "clientDataJSON": response.clientDataJSON.base64URLEncodedString(),
                    "authenticatorData": response.authenticatorData.base64URLEncodedString(),
                    "signature": response.signature.base64URLEncodedString(),
                    "userHandle": response.userHandle?.base64URLEncodedString()
                ]
            ]
        ]

        let result: AssertionCompletionResponse = try await post(url: url, body: body)
        return PasskeyAssertionResult(
            verified: result.verified,
            userId: result.userId ?? "",
            sessionToken: result.sessionToken
        )
    }

    // MARK: - Networking

    private func post<T: Decodable>(url: URL, body: [String: Any]) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, httpResponse) = try await session.data(for: request)

        guard let http = httpResponse as? HTTPURLResponse else {
            throw WebAuthnError.networkError("Invalid response")
        }

        guard (200...299).contains(http.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown"
            throw WebAuthnError.serverError(http.statusCode, errorBody)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Response Types

private struct BeginRegistrationResponse: Decodable {
    let options: RegistrationOptions
    let challengeId: String

    struct RegistrationOptions: Decodable {
        let challenge: String
        let rp: RelyingParty
        let user: UserEntity

        struct RelyingParty: Decodable {
            let id: String
            let name: String
        }

        struct UserEntity: Decodable {
            let id: String
            let name: String
            let displayName: String
        }
    }
}

private struct BeginAssertionResponse: Decodable {
    let options: AssertionOptions
    let challengeId: String

    struct AssertionOptions: Decodable {
        let challenge: String
        let rpId: String
        let timeout: Int?
        let allowCredentials: [AllowedCredential]?

        struct AllowedCredential: Decodable {
            let id: String
            let type: String
        }
    }
}

private struct CompletionResponse: Decodable {
    let verified: Bool
    let credentialId: String?
    let userId: String?
    let error: String?
}

private struct AssertionCompletionResponse: Decodable {
    let verified: Bool
    let userId: String?
    let sessionToken: String?
    let credentialId: String?
}

// MARK: - Errors

enum WebAuthnError: Error, LocalizedError {
    case invalidChallenge
    case registrationFailed(String)
    case assertionFailed(String)
    case networkError(String)
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidChallenge:          return "Invalid challenge data from server"
        case .registrationFailed(let r): return "Registration failed: \(r)"
        case .assertionFailed(let r):    return "Assertion failed: \(r)"
        case .networkError(let r):       return "Network error: \(r)"
        case .serverError(let c, let r): return "Server error \(c): \(r)"
        }
    }
}

// MARK: - Base64URL Data extensions

private extension Data {
    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64 += "="
        }
        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
