import Foundation

/// User profile and enrollment data
struct UserProfile: Codable {
    let id: UUID
    let enrollmentDate: Date
    let encryptedHeartPattern: String
    let securityLevel: SecurityLevel
    let isEnrolled: Bool
    let lastAuthenticationDate: Date?
    let totalAuthentications: Int
    let successfulAuthentications: Int
    
    init(encryptedHeartPattern: String, securityLevel: SecurityLevel = .medium) {
        self.id = UUID()
        self.enrollmentDate = Date()
        self.encryptedHeartPattern = encryptedHeartPattern
        self.securityLevel = securityLevel
        self.isEnrolled = true
        self.lastAuthenticationDate = nil
        self.totalAuthentications = 0
        self.successfulAuthentications = 0
    }
    
    // Private initializer for internal updates
    private init(id: UUID, enrollmentDate: Date, encryptedHeartPattern: String, securityLevel: SecurityLevel, isEnrolled: Bool, lastAuthenticationDate: Date?, totalAuthentications: Int, successfulAuthentications: Int) {
        self.id = id
        self.enrollmentDate = enrollmentDate
        self.encryptedHeartPattern = encryptedHeartPattern
        self.securityLevel = securityLevel
        self.isEnrolled = isEnrolled
        self.lastAuthenticationDate = lastAuthenticationDate
        self.totalAuthentications = totalAuthentications
        self.successfulAuthentications = successfulAuthentications
    }
    
    /// Update profile after successful authentication
    func updateAfterAuthentication() -> UserProfile {
        return UserProfile(
            id: self.id,
            enrollmentDate: self.enrollmentDate,
            encryptedHeartPattern: self.encryptedHeartPattern,
            securityLevel: self.securityLevel,
            isEnrolled: self.isEnrolled,
            lastAuthenticationDate: Date(),
            totalAuthentications: self.totalAuthentications + 1,
            successfulAuthentications: self.successfulAuthentications + 1
        )
    }
    
    /// Update profile after failed authentication
    func updateAfterFailedAuthentication() -> UserProfile {
        return UserProfile(
            id: self.id,
            enrollmentDate: self.enrollmentDate,
            encryptedHeartPattern: self.encryptedHeartPattern,
            securityLevel: self.securityLevel,
            isEnrolled: self.isEnrolled,
            lastAuthenticationDate: self.lastAuthenticationDate,
            totalAuthentications: self.totalAuthentications + 1,
            successfulAuthentications: self.successfulAuthentications
        )
    }
    
    var successRate: Double {
        guard totalAuthentications > 0 else { return 0 }
        return Double(successfulAuthentications) / Double(totalAuthentications) * 100
    }
    
    var daysSinceEnrollment: Int {
        return Calendar.current.dateComponents([.day], from: enrollmentDate, to: Date()).day ?? 0
    }
}

/// User preferences and settings
struct UserPreferences: Codable {
    var securityLevel: SecurityLevel
    var enableNotifications: Bool
    var enableAlarms: Bool
    var backgroundAuthenticationEnabled: Bool
    var authenticationFrequency: AuthenticationFrequency
    var enableBluetooth: Bool
    var enableNFC: Bool
    
    init() {
        self.securityLevel = .medium
        self.enableNotifications = true
        self.enableAlarms = true
        self.backgroundAuthenticationEnabled = true
        self.authenticationFrequency = .medium
        self.enableBluetooth = true
        self.enableNFC = true
    }
}

/// Security level settings
enum SecurityLevel: String, CaseIterable, Codable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case maximum = "Maximum"
    
    var threshold: Double {
        switch self {
        case .low:
            return 70.0
        case .medium:
            return 80.0
        case .high:
            return 90.0
        case .maximum:
            return 95.0
        }
    }
    
    var retryThreshold: Int {
        switch self {
        case .low:
            return 3
        case .medium:
            return 2
        case .high:
            return 1
        case .maximum:
            return 1
        }
    }
    
    var description: String {
        switch self {
        case .low:
            return "Lower security, more lenient matching"
        case .medium:
            return "Balanced security and usability"
        case .high:
            return "Higher security, stricter matching"
        case .maximum:
            return "Maximum security, most precise matching"
        }
    }
}

/// Authentication frequency settings
enum AuthenticationFrequency: String, CaseIterable, Codable {
    case low = "Low (2-3 times/hour)"
    case medium = "Medium (3-4 times/hour)"
    case high = "High (4-5 times/hour)"
    case maximum = "Maximum (5-6 times/hour)"
    
    var minIntervalMinutes: Int {
        switch self {
        case .low:
            return 20
        case .medium:
            return 15
        case .high:
            return 12
        case .maximum:
            return 10
        }
    }
    
    var maxIntervalMinutes: Int {
        switch self {
        case .low:
            return 30
        case .medium:
            return 20
        case .high:
            return 15
        case .maximum:
            return 12
        }
    }
}

// AuthenticationResult moved to separate file AuthenticationResult.swift

// AppConfiguration moved to Utils/AppConfiguration.swift to avoid duplication

