import Foundation

/// Represents an authentication event in the system
struct AuthEvent: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let success: Bool
    let details: String
    let heartRate: Int?
    let userId: String?
    let deviceId: String?
    let authenticationMethod: AuthenticationMethod
    let location: String?
    
    enum AuthenticationMethod: String, Codable, CaseIterable {
        case heartAuthentication = "heart_authentication"
        case biometric = "biometric"
        case password = "password"
        case mfa = "mfa"
        case enterprise = "enterprise"
        case nfc = "nfc"
        case bluetooth = "bluetooth"
    }
    
    init(
        timestamp: Date = Date(),
        success: Bool,
        details: String,
        heartRate: Int? = nil,
        userId: String? = nil,
        deviceId: String? = nil,
        authenticationMethod: AuthenticationMethod = .heartAuthentication,
        location: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.success = success
        self.details = details
        self.heartRate = heartRate
        self.userId = userId
        self.deviceId = deviceId
        self.authenticationMethod = authenticationMethod
        self.location = location
    }
    
    // MARK: - Computed Properties
    
    var isRecent: Bool {
        let oneHourAgo = Date().addingTimeInterval(-3600)
        return timestamp > oneHourAgo
    }
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    var statusText: String {
        return success ? "Success" : "Failed"
    }
    
    var statusColor: String {
        return success ? "green" : "red"
    }
}

// MARK: - Extensions

extension AuthEvent {
    /// Creates a successful authentication event
    static func success(
        details: String = "Authentication successful",
        heartRate: Int? = nil,
        userId: String? = nil,
        deviceId: String? = nil,
        method: AuthenticationMethod = .heartAuthentication
    ) -> AuthEvent {
        return AuthEvent(
            success: true,
            details: details,
            heartRate: heartRate,
            userId: userId,
            deviceId: deviceId,
            authenticationMethod: method
        )
    }
    
    /// Creates a failed authentication event
    static func failure(
        details: String = "Authentication failed",
        heartRate: Int? = nil,
        userId: String? = nil,
        deviceId: String? = nil,
        method: AuthenticationMethod = .heartAuthentication
    ) -> AuthEvent {
        return AuthEvent(
            success: false,
            details: details,
            heartRate: heartRate,
            userId: userId,
            deviceId: deviceId,
            authenticationMethod: method
        )
    }
}