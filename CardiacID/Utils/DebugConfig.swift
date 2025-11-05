import Foundation

/// Debug configuration for HeartID Mobile app
/// Uses EnvironmentConfig for build-time settings with conditional compilation
struct DebugConfig {
    // Load from environment config (configured via .xcconfig files)
    private static let envConfig = EnvironmentConfig.current

    /// Enable/disable debug logging (conditional compilation + runtime config)
    static var isDebugEnabled: Bool {
        #if DEBUG
        return envConfig.enableDebugLogging
        #else
        return false // Always disabled in production builds
        #endif
    }

    /// Enable/disable verbose logging (conditional compilation + runtime config)
    static var isVerboseLogging: Bool {
        #if DEBUG
        return envConfig.enableVerboseLogging
        #else
        return false // Always disabled in production builds
        #endif
    }

    /// Enable/disable network request logging
    static var isNetworkLoggingEnabled: Bool {
        #if DEBUG
        return envConfig.enableNetworkLogging
        #else
        return false // Always disabled in production builds
        #endif
    }

    /// Enable/disable authentication logging
    static var isAuthLoggingEnabled: Bool {
        #if DEBUG
        return true
        #else
        return false // Always disabled in production builds
        #endif
    }

    /// Enable/disable watch connectivity logging
    static var isWatchLoggingEnabled: Bool {
        #if DEBUG
        return true
        #else
        return false // Always disabled in production builds
        #endif
    }

    /// Enable/disable health data logging
    static var isHealthLoggingEnabled: Bool {
        #if DEBUG
        return true
        #else
        return false // Always disabled in production builds
        #endif
    }

    /// Enable/disable UI state logging
    static var isUIStateLoggingEnabled: Bool {
        #if DEBUG
        return true
        #else
        return false // Always disabled in production builds
        #endif
    }

    /// Mock data for testing (controlled by environment config)
    static var useMockData: Bool {
        #if DEBUG
        return envConfig.useMockData
        #else
        return false // Never use mock data in production
        #endif
    }

    /// Simulate network delays for testing
    static var simulateNetworkDelay: Bool {
        #if DEBUG
        return false // Can be enabled via environment config if needed
        #else
        return false
        #endif
    }

    /// Network delay in seconds (if simulation is enabled)
    static let networkDelaySeconds: Double = 1.0

    /// Enable/disable crash reporting
    static var isCrashReportingEnabled: Bool {
        return envConfig.enableCrashReporting
    }

    /// Enable/disable analytics
    static var isAnalyticsEnabled: Bool {
        return envConfig.enableAnalytics
    }

    /// App version for debugging
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

    /// Build number for debugging
    static let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"

    /// Debug info string
    static var debugInfo: String {
        return "HeartID Mobile v\(appVersion) (\(buildNumber)) - Environment: \(envConfig.environment.rawValue)"
    }

    /// Check if running in simulator
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// Check if running in debug mode
    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// Check if running in production environment
    static var isProduction: Bool {
        return envConfig.environment.isProduction
    }

    /// Print configuration summary (debug builds only)
    static func printConfiguration() {
        #if DEBUG
        print("""
        📋 HeartID Debug Configuration:
           Version: \(appVersion) (\(buildNumber))
           Environment: \(envConfig.environment.rawValue)
           Debug Logging: \(isDebugEnabled)
           Network Logging: \(isNetworkLoggingEnabled)
           Mock Data: \(useMockData)
           Simulator: \(isSimulator)
           SSL Pinning: \(envConfig.enableSSLPinning)
           Analytics: \(isAnalyticsEnabled)
           Crash Reporting: \(isCrashReportingEnabled)
        """)
        #endif
    }
}



