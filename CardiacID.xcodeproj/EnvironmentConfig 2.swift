import Foundation

/// Environment configuration for CardiacID app
struct EnvironmentConfig {
    static let current = EnvironmentConfig()
    
    private init() {} // Singleton
    
    // MARK: - App Configuration
    
    /// Bundle identifier for the CardiacID app
    var bundleIdentifier: String {
        return Bundle.main.bundleIdentifier ?? "com.heartid.cardiacid"
    }
    
    /// App version
    var appVersion: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    /// Build number
    var buildNumber: String {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    // MARK: - Azure AD / EntraID Configuration
    
    /// Microsoft Azure AD authority URL
    let entraIDAuthority = "https://login.microsoftonline.com"
    
    /// Redirect URI for Azure AD authentication
    /// Format: msauth.{bundle-identifier}://auth
    var entraIDRedirectURI: String {
        return "msauth.\(bundleIdentifier)://auth"
    }
    
    /// Microsoft Graph API base URL
    let microsoftGraphBaseURL = "https://graph.microsoft.com/v1.0"
    
    /// Azure AD scopes for authentication
    let entraIDScopes = [
        "User.Read",
        "User.ReadBasic.All",
        "Application.Read.All",
        "Group.Read.All",
        "Directory.Read.All"
    ]
    
    // MARK: - Supabase Configuration
    
    /// Supabase project URL
    /// Replace with your actual Supabase project URL
    let supabaseURL = "https://your-project-id.supabase.co"
    
    /// Supabase Auth URL
    var supabaseAuthURL: String {
        return "\(supabaseURL)/auth/v1"
    }
    
    /// Supabase REST API URL
    var supabaseRestURL: String {
        return "\(supabaseURL)/rest/v1"
    }
    
    /// Supabase Storage URL
    var supabaseStorageURL: String {
        return "\(supabaseURL)/storage/v1"
    }
    
    // MARK: - HeartID Specific Configuration
    
    /// Heart pattern authentication settings
    struct HeartAuthConfig {
        static let minimumConfidence: Double = 0.75
        static let minimumQualityScore: Double = 0.70
        static let sampleDurationSeconds: Double = 10.0
        static let maxRetryAttempts: Int = 3
        static let authenticationTimeout: TimeInterval = 30.0
    }
    
    /// Bluetooth configuration for door locks
    struct BluetoothConfig {
        static let scanTimeoutSeconds: Double = 10.0
        static let connectionTimeoutSeconds: Double = 15.0
        static let maxConcurrentConnections: Int = 3
        static let rssiThreshold: Int = -80
    }
    
    /// NFC configuration
    struct NFCConfig {
        static let sessionTimeoutSeconds: Double = 60.0
        static let maxRetryAttempts: Int = 3
        static let tagDataFormatVersion: String = "1.0"
    }
    
    // MARK: - Security Configuration
    
    /// Encryption settings
    struct SecurityConfig {
        static let keySize: Int = 256
        static let keyDerivationIterations: Int = 10000
        static let tokenExpiryHours: Int = 24
        static let biometricPromptTimeout: TimeInterval = 30.0
    }
    
    /// Keychain configuration
    struct KeychainConfig {
        static let serviceName = "com.heartid.cardiacid.keychain"
        static let accessGroup: String? = nil // Set if using shared keychain
    }
    
    // MARK: - API Endpoints
    
    /// API endpoint configurations
    struct APIEndpoints {
        // Microsoft Graph endpoints
        static let userProfile = "/me"
        static let userGroups = "/me/memberOf"
        static let applications = "/me/ownedObjects"
        
        // Supabase endpoints
        static let biometricTemplates = "/biometric_templates"
        static let authEvents = "/auth_events"
        static let devices = "/devices"
        static let users = "/users"
    }
    
    // MARK: - Development/Debug Configuration
    
    /// Debug settings (only active in debug builds)
    struct DebugConfig {
        #if DEBUG
        static let enableLogging = true
        static let enableMockServices = false
        static let logLevel: LogLevel = .verbose
        static let enableNetworkLogging = true
        #else
        static let enableLogging = false
        static let enableMockServices = false
        static let logLevel: LogLevel = .error
        static let enableNetworkLogging = false
        #endif
        
        enum LogLevel: String {
            case verbose = "VERBOSE"
            case debug = "DEBUG"
            case info = "INFO"
            case warning = "WARNING"
            case error = "ERROR"
        }
    }
    
    // MARK: - Feature Flags
    
    /// Feature flags for enabling/disabling functionality
    struct FeatureFlags {
        static let enableEntraIDAuth = true
        static let enableSupabaseSync = true
        static let enableBluetoothDoorLocks = true
        static let enableNFCAuth = true
        static let enableAppleWatchSync = true
        static let enableBiometricFallback = true
        static let enableOfflineMode = true
        static let enableAnalytics = false // Set to true for production
    }
    
    // MARK: - URL Scheme Handlers
    
    /// Supported URL schemes for the app
    var supportedURLSchemes: [String] {
        return [
            "cardiacid",
            "heartid",
            "msauth.\(bundleIdentifier)"
        ]
    }
    
    // MARK: - Validation Methods
    
    /// Validates the current configuration
    func validateConfiguration() -> [String] {
        var errors: [String] = []
        
        // Validate Supabase URL
        if supabaseURL.contains("your-project-id") {
            errors.append("Supabase URL not configured - update with your actual project URL")
        }
        
        // Validate bundle identifier
        if bundleIdentifier.isEmpty {
            errors.append("Bundle identifier not found")
        }
        
        // Validate URL schemes
        if !validateURLSchemes() {
            errors.append("URL schemes not properly configured in Info.plist")
        }
        
        return errors
    }
    
    private func validateURLSchemes() -> Bool {
        guard let urlTypes = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] else {
            return false
        }
        
        let configuredSchemes = urlTypes.compactMap { urlType in
            urlType["CFBundleURLSchemes"] as? [String]
        }.flatMap { $0 }
        
        return supportedURLSchemes.allSatisfy { scheme in
            configuredSchemes.contains(scheme)
        }
    }
    
    // MARK: - Environment Detection
    
    var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    
    var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    var deviceModel: String {
        return UIDevice.current.model
    }
    
    var systemVersion: String {
        return UIDevice.current.systemVersion
    }
}

// MARK: - Configuration Validation Extension

extension EnvironmentConfig {
    
    /// Prints current configuration (for debugging)
    func printConfiguration() {
        guard DebugConfig.enableLogging else { return }
        
        print("🔧 CardiacID Configuration:")
        print("   Bundle ID: \(bundleIdentifier)")
        print("   Version: \(appVersion) (\(buildNumber))")
        print("   Environment: \(isDebugBuild ? "Debug" : "Release")")
        print("   Device: \(deviceModel) (iOS \(systemVersion))")
        print("   Simulator: \(isSimulator)")
        print("   Supabase: \(supabaseURL)")
        print("   Redirect URI: \(entraIDRedirectURI)")
        
        let validationErrors = validateConfiguration()
        if !validationErrors.isEmpty {
            print("⚠️ Configuration Warnings:")
            validationErrors.forEach { print("   - \($0)") }
        } else {
            print("✅ Configuration validated successfully")
        }
    }
}

// MARK: - Usage Examples

/*
 Usage Examples:
 
 // Access configuration
 let config = EnvironmentConfig.current
 
 // Get URLs
 let authority = config.entraIDAuthority
 let redirectURI = config.entraIDRedirectURI
 let supabaseURL = config.supabaseURL
 
 // Check features
 if EnvironmentConfig.FeatureFlags.enableEntraIDAuth {
     // Initialize EntraID authentication
 }
 
 // Validate configuration
 let errors = config.validateConfiguration()
 if !errors.isEmpty {
     // Handle configuration errors
 }
 
 // Debug configuration
 config.printConfiguration()
 */