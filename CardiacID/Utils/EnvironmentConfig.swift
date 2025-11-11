//
//  EnvironmentConfig.swift
//  HeartID Mobile
//
//  Runtime environment configuration
//  Reads from Info.plist which is populated from .xcconfig files
//  SECURITY: Contains NO secrets - only configuration values
//

import Foundation

/// Environment configuration loaded from build settings
struct EnvironmentConfig {
    // MARK: - Singleton
    static let current = EnvironmentConfig()

    // MARK: - Environment
    let environment: Environment
    let isDebug: Bool

    // MARK: - Feature Flags
    let enableDebugLogging: Bool
    let enableVerboseLogging: Bool
    let enableNetworkLogging: Bool
    let useMockData: Bool

    // MARK: - API Configuration
    let supabaseURL: String
    let supabaseProjectID: String
    let supabaseAnonKey: String

    // MARK: - EntraID Configuration
    let entraIDAuthority: String
    let entraIDTenantType: String

    // MARK: - App Configuration
    let appScheme: String
    let bundleIDSuffix: String

    // MARK: - Security
    let enableSSLPinning: Bool

    // MARK: - Analytics
    let enableAnalytics: Bool
    let enableCrashReporting: Bool

    // MARK: - Initialization

    private init() {
        // Load from Info.plist (populated from .xcconfig)
        let bundle = Bundle.main

        // Environment
        let envString = bundle.object(forInfoDictionaryKey: "HEARTID_ENVIRONMENT") as? String ?? "Debug"
        self.environment = Environment(rawValue: envString) ?? .debug

        #if DEBUG
        self.isDebug = true
        #else
        self.isDebug = false
        #endif

        // Feature Flags
        self.enableDebugLogging = bundle.boolValue(forKey: "HEARTID_ENABLE_DEBUG_LOGGING", default: false)
        self.enableVerboseLogging = bundle.boolValue(forKey: "HEARTID_ENABLE_VERBOSE_LOGGING", default: false)
        self.enableNetworkLogging = bundle.boolValue(forKey: "HEARTID_ENABLE_NETWORK_LOGGING", default: false)
        self.useMockData = bundle.boolValue(forKey: "HEARTID_USE_MOCK_DATA", default: false)

        // API Configuration
        self.supabaseURL = bundle.object(forInfoDictionaryKey: "HEARTID_SUPABASE_URL") as? String ?? "https://xytycgdlafncjszhgems.supabase.co"
        self.supabaseProjectID = bundle.object(forInfoDictionaryKey: "HEARTID_SUPABASE_PROJECT_ID") as? String ?? "xytycgdlafncjszhgems"
        self.supabaseAnonKey = bundle.object(forInfoDictionaryKey: "HEARTID_SUPABASE_ANON_KEY") as? String ?? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh5dHljZ2RsYWZuY2pzemhnZW1zIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjIzOTc2MDIsImV4cCI6MjA3Nzk3MzYwMn0.F1uiQX0U_H78C8JATrwlpKys9UzUyaM_nMZUHNrvp7I"

        // EntraID Configuration
        self.entraIDAuthority = bundle.object(forInfoDictionaryKey: "HEARTID_ENTRAID_AUTHORITY") as? String ?? "https://login.microsoftonline.com"
        self.entraIDTenantType = bundle.object(forInfoDictionaryKey: "HEARTID_ENTRAID_TENANT_TYPE") as? String ?? "common"

        // App Configuration
        self.appScheme = bundle.object(forInfoDictionaryKey: "HEARTID_APP_SCHEME") as? String ?? "heartid"
        self.bundleIDSuffix = bundle.object(forInfoDictionaryKey: "HEARTID_BUNDLE_ID_SUFFIX") as? String ?? ""

        // Security
        self.enableSSLPinning = bundle.boolValue(forKey: "HEARTID_ENABLE_SSL_PINNING", default: false)

        // Analytics
        self.enableAnalytics = bundle.boolValue(forKey: "HEARTID_ENABLE_ANALYTICS", default: false)
        self.enableCrashReporting = bundle.boolValue(forKey: "HEARTID_ENABLE_CRASH_REPORTING", default: false)

        // Print configuration on init (debug only)
        #if DEBUG
        print("""
        🔧 Environment Configuration Loaded:
           Environment: \(environment.rawValue)
           Supabase URL: \(supabaseURL)
           EntraID Authority: \(entraIDAuthority)
           Debug Logging: \(enableDebugLogging)
           SSL Pinning: \(enableSSLPinning)
        """)
        #endif
    }

    // MARK: - Computed Properties

    /// Get redirect URI for OAuth (dynamically constructed)
    var entraIDRedirectURI: String {
        return "\(appScheme)://auth"
    }

    /// Full Supabase REST API URL
    var supabaseRestURL: String {
        return "\(supabaseURL)/rest/v1"
    }

    /// Full Supabase Auth URL
    var supabaseAuthURL: String {
        return "\(supabaseURL)/auth/v1"
    }

    /// Full EntraID authorization endpoint
    func entraIDAuthorizationEndpoint(tenantID: String) -> String {
        return "\(entraIDAuthority)/\(tenantID)/oauth2/v2.0/authorize"
    }

    /// Full EntraID token endpoint
    func entraIDTokenEndpoint(tenantID: String) -> String {
        return "\(entraIDAuthority)/\(tenantID)/oauth2/v2.0/token"
    }

    // MARK: - Validation

    /// Validate that all required configuration is present
    func validate() -> ValidationResult {
        var errors: [String] = []

        if supabaseURL.isEmpty {
            errors.append("Supabase URL not configured")
        }

        if supabaseProjectID.isEmpty {
            errors.append("Supabase Project ID not configured")
        }

        if entraIDAuthority.isEmpty {
            errors.append("EntraID Authority not configured")
        }

        if errors.isEmpty {
            return .valid
        } else {
            return .invalid(errors: errors)
        }
    }

    // MARK: - Supporting Types

    enum Environment: String {
        case debug = "Debug"
        case staging = "Staging"
        case production = "Production"

        var isProduction: Bool {
            return self == .production
        }
    }

    enum ValidationResult {
        case valid
        case invalid(errors: [String])

        var isValid: Bool {
            if case .valid = self { return true }
            return false
        }
    }
}

// MARK: - Bundle Extension

private extension Bundle {
    /// Helper to get boolean value from Info.plist
    func boolValue(forKey key: String, default defaultValue: Bool) -> Bool {
        guard let value = object(forInfoDictionaryKey: key) as? String else {
            return defaultValue
        }
        return value.uppercased() == "YES" || value == "1" || value.uppercased() == "TRUE"
    }
}
