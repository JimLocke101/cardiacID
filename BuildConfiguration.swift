//
//  BuildConfiguration.swift
//  CardiacID
//
//  Build configuration and platform detection
//

import Foundation

struct BuildConfiguration {
    static let shared = BuildConfiguration()
    
    // MARK: - Platform Detection
    
    var currentPlatform: Platform {
        #if os(iOS)
        return .iOS
        #elseif os(watchOS)
        return .watchOS
        #elseif os(macOS)
        return .macOS
        #elseif os(tvOS)
        return .tvOS
        #else
        return .unknown
        #endif
    }
    
    enum Platform: String, CaseIterable {
        case iOS = "iOS"
        case watchOS = "watchOS"
        case macOS = "macOS"
        case tvOS = "tvOS"
        case unknown = "Unknown"
        
        var supportsMSAL: Bool {
            switch self {
            case .iOS, .macOS:
                return true
            case .watchOS, .tvOS, .unknown:
                return false
            }
        }
        
        var supportsWatchConnectivity: Bool {
            switch self {
            case .iOS, .watchOS:
                return true
            case .macOS, .tvOS, .unknown:
                return false
            }
        }
        
        var supportsHealthKit: Bool {
            switch self {
            case .iOS, .watchOS:
                return true
            case .macOS, .tvOS, .unknown:
                return false
            }
        }
    }
    
    // MARK: - Build Information
    
    var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    
    var appVersion: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }
    
    var buildNumber: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }
    
    var bundleIdentifier: String {
        return Bundle.main.bundleIdentifier ?? "com.argos.cardiacid"
    }
    
    // MARK: - Feature Flags
    
    var enableMSAL: Bool {
        return currentPlatform.supportsMSAL
    }
    
    var enableWatchConnectivity: Bool {
        return currentPlatform.supportsWatchConnectivity
    }
    
    var enableHealthKit: Bool {
        return currentPlatform.supportsHealthKit
    }
    
    var enableMockData: Bool {
        return isDebugBuild || !enableMSAL
    }
    
    // MARK: - Logging Configuration
    
    var logLevel: LogLevel {
        if isDebugBuild {
            return .debug
        } else {
            return .info
        }
    }
    
    enum LogLevel: String, CaseIterable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        
        var shouldLog: Bool {
            switch self {
            case .debug:
                return BuildConfiguration.shared.isDebugBuild
            case .info, .warning, .error:
                return true
            }
        }
    }
    
    // MARK: - App Group Configuration
    
    var appGroupIdentifier: String {
        return "group.com.argos.cardiacid"
    }
    
    var keychainAccessGroup: String {
        return "group.com.argos.cardiacid"
    }
    
    // MARK: - URL Schemes
    
    var authRedirectScheme: String {
        return "cardiacid"
    }
    
    var authRedirectURI: String {
        return "\(authRedirectScheme)://auth"
    }
    
    // MARK: - Validation
    
    func validateConfiguration() -> [String] {
        var issues: [String] = []
        
        if !enableMSAL && currentPlatform == .iOS {
            issues.append("MSAL is required for iOS platform but is disabled")
        }
        
        if enableWatchConnectivity && !currentPlatform.supportsWatchConnectivity {
            issues.append("Watch Connectivity is enabled but not supported on \(currentPlatform.rawValue)")
        }
        
        if bundleIdentifier.contains("placeholder") {
            issues.append("Bundle identifier contains placeholder value")
        }
        
        return issues
    }
    
    // MARK: - Debug Information
    
    func printConfiguration() {
        guard isDebugBuild else { return }
        
        print("""
        🔧 CardiacID Build Configuration:
           Platform: \(currentPlatform.rawValue)
           Version: \(appVersion) (\(buildNumber))
           Bundle ID: \(bundleIdentifier)
           Debug Build: \(isDebugBuild)
           
        📱 Features:
           MSAL: \(enableMSAL)
           Watch Connectivity: \(enableWatchConnectivity)
           HealthKit: \(enableHealthKit)
           Mock Data: \(enableMockData)
           
        🔐 Security:
           App Group: \(appGroupIdentifier)
           Keychain Group: \(keychainAccessGroup)
           Auth Redirect: \(authRedirectURI)
           
        📝 Logging: \(logLevel.rawValue)
        """)
        
        let issues = validateConfiguration()
        if !issues.isEmpty {
            print("\n⚠️ Configuration Issues:")
            for issue in issues {
                print("   - \(issue)")
            }
        }
    }
}