import Foundation

/// Application configuration and settings
struct AppConfiguration {
    
    // MARK: - Heart Rate Capture
    static let minCaptureDuration: TimeInterval = 9.0
    static let maxCaptureDuration: TimeInterval = 16.0
    static let defaultCaptureDuration: TimeInterval = 12.0
    
    // MARK: - Pattern Analysis
    static let minPatternSamples = 10
    static let maxPatternSamples = 50
    static let minConfidenceThreshold: Double = 0.7
    
    // MARK: - Authentication Thresholds
    static let defaultSecurityThreshold: Double = 90.0
    static let defaultRetryThreshold: Double = 80.0
    static let maxRetryAttempts = 3
    
    // MARK: - Background Tasks
    static let backgroundTaskIdentifier = "com.heartid.background.authentication"
    static let notificationIdentifier = "com.heartid.authentication"
    static let minBackgroundInterval: TimeInterval = 600 // 10 minutes
    static let maxBackgroundInterval: TimeInterval = 3600 // 1 hour
    
    // MARK: - Performance Settings
    static let maxConcurrentOperations = 3
    static let cacheSizeLimit = 100 // MB
    static let timeoutDuration: TimeInterval = 30.0
    static let backgroundTaskTimeout: TimeInterval = 10.0
    
    // MARK: - Security Settings
    static let encryptionAlgorithm = "AES-GCM"
    static let keySize = 256 // bits
    static let hashAlgorithm = "SHA-256"
    static let maxSessionDuration: TimeInterval = 3600 // 1 hour
    static let requireReauthentication = true
    
    // MARK: - UserDefaults Keys
    static let encryptionKey = "HeartID_Encryption_Key_2024"
    static let userDefaultsKey = "HeartID_UserProfile"
    static let preferencesKey = "HeartID_UserPreferences"
}
