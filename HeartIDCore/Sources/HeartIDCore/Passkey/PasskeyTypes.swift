//
//  PasskeyTypes.swift
//  HeartIDCore
//
//  WebAuthn/FIDO2 data types and service protocol for passkey flows.
//  These types define the contract between the app and a WebAuthn Relying Party.
//

import Foundation

// MARK: - Registration

public struct PasskeyRegistrationChallenge: Sendable {
    public let challengeData: Data
    public let relyingPartyId: String
    public let userId: String
    public let userName: String

    public init(challengeData: Data, relyingPartyId: String, userId: String, userName: String) {
        self.challengeData = challengeData
        self.relyingPartyId = relyingPartyId
        self.userId = userId
        self.userName = userName
    }
}

public struct PasskeyRegistrationResponse: Sendable {
    public let credentialId: Data
    public let clientDataJSON: Data
    public let attestationObject: Data

    public init(credentialId: Data, clientDataJSON: Data, attestationObject: Data) {
        self.credentialId = credentialId
        self.clientDataJSON = clientDataJSON
        self.attestationObject = attestationObject
    }
}

// MARK: - Assertion

public struct PasskeyAssertionChallenge: Sendable {
    public let challengeData: Data
    public let relyingPartyId: String
    public let allowedCredentialIds: [Data]

    public init(challengeData: Data, relyingPartyId: String, allowedCredentialIds: [Data]) {
        self.challengeData = challengeData
        self.relyingPartyId = relyingPartyId
        self.allowedCredentialIds = allowedCredentialIds
    }
}

public struct PasskeyAssertionResponse: Sendable {
    public let credentialId: Data
    public let clientDataJSON: Data
    public let authenticatorData: Data
    public let signature: Data
    public let userHandle: Data?

    public init(credentialId: Data, clientDataJSON: Data, authenticatorData: Data, signature: Data, userHandle: Data?) {
        self.credentialId = credentialId
        self.clientDataJSON = clientDataJSON
        self.authenticatorData = authenticatorData
        self.signature = signature
        self.userHandle = userHandle
    }
}

public struct PasskeyAssertionResult: Sendable {
    public let verified: Bool
    public let userId: String
    public let sessionToken: String?

    public init(verified: Bool, userId: String, sessionToken: String?) {
        self.verified = verified
        self.userId = userId
        self.sessionToken = sessionToken
    }
}

// MARK: - Service Protocol

/// Defines the contract for communicating with a WebAuthn Relying Party server.
/// Implementations must call the RP's registration and assertion endpoints.
public protocol PasskeyServiceProtocol: Sendable {
    func beginRegistration(for userId: String) async throws -> PasskeyRegistrationChallenge
    func completeRegistration(_ response: PasskeyRegistrationResponse) async throws
    func beginAssertion(for userId: String) async throws -> PasskeyAssertionChallenge
    func completeAssertion(_ response: PasskeyAssertionResponse) async throws -> PasskeyAssertionResult
}

// MARK: - Mock Implementation

/// Simulates WebAuthn server responses with a 0.5s artificial delay.
public struct MockPasskeyService: PasskeyServiceProtocol {

    public init() {}

    private func simulateNetwork() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    public func beginRegistration(for userId: String) async throws -> PasskeyRegistrationChallenge {
        await simulateNetwork()
        return PasskeyRegistrationChallenge(
            challengeData: Data("mock-reg-challenge-\(userId)".utf8),
            relyingPartyId: "cardiacid.com",
            userId: userId,
            userName: "\(userId)@cardiacid.com"
        )
    }

    public func completeRegistration(_ response: PasskeyRegistrationResponse) async throws {
        await simulateNetwork()
    }

    public func beginAssertion(for userId: String) async throws -> PasskeyAssertionChallenge {
        await simulateNetwork()
        return PasskeyAssertionChallenge(
            challengeData: Data("mock-assert-challenge-\(userId)".utf8),
            relyingPartyId: "cardiacid.com",
            allowedCredentialIds: []
        )
    }

    public func completeAssertion(_ response: PasskeyAssertionResponse) async throws -> PasskeyAssertionResult {
        await simulateNetwork()
        return PasskeyAssertionResult(
            verified: true,
            userId: "mock-user",
            sessionToken: "mock-session-\(UUID().uuidString.prefix(8))"
        )
    }
}
