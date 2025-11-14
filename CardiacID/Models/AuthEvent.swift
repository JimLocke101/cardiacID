//
//  AuthEvent.swift
//  CardiacID
//
//  Authentication event tracking model
//

import Foundation

/// Represents an authentication event in the system
struct AuthEvent: Identifiable, Codable {
    let id: String
    let userId: String
    let eventType: EventType
    let timestamp: Date
    let deviceId: String?
    let ipAddress: String?
    let location: String?
    let success: Bool
    let metadata: [String: String]?

    enum EventType: String, Codable {
        case signIn = "sign_in"
        case signOut = "sign_out"
        case biometricAuth = "biometric_auth"
        case passwordAuth = "password_auth"
        case tokenRefresh = "token_refresh"
        case failedAttempt = "failed_attempt"
        case accountLocked = "account_locked"
        case passwordReset = "password_reset"
        case authentication = "authentication"
        case enrollment = "enrollment"
        case revocation = "revocation"
    }

    init(
        id: String = UUID().uuidString,
        userId: String,
        eventType: EventType,
        timestamp: Date = Date(),
        deviceId: String? = nil,
        ipAddress: String? = nil,
        location: String? = nil,
        success: Bool = true,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.userId = userId
        self.eventType = eventType
        self.timestamp = timestamp
        self.deviceId = deviceId
        self.ipAddress = ipAddress
        self.location = location
        self.success = success
        self.metadata = metadata
    }
}
