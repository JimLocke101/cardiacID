//
//  AuthenticationModels.swift
//  CardiacID
//
//  Ported from HeartID_0_7 Watch App
//  Created by HeartID Team on 10/27/25.
//

import Foundation

// MARK: - Confidence Degradation Constants

/// Global constants for confidence decay rates
struct ConfidenceDegradationConstants {
    /// ECG confidence degradation rate: 0.001% per 6 minutes (very slow degradation)
    /// Can be adjusted as needed for different security profiles
    static let ecgDegradationRate: Double = 0.00001 // 0.001% per interval

    /// Time interval for degradation: 6 minutes (360 seconds)
    static let degradationInterval: TimeInterval = 360.0 // 6 minutes

    /// Maximum time to consider ECG "recent" for auto-use: 4 minutes
    static let recentECGBufferTime: TimeInterval = 240.0 // 4 minutes

    /// Minimum confidence floor (PPG level acts as floor)
    /// ECG confidence will not decay below current PPG confidence
    static let minimumConfidenceFloor: Double = 0.70 // 70% absolute minimum
}

// MARK: - Battery Management Settings

/// Configurable battery management settings for background PPG monitoring
struct BatteryManagementSettings: Codable {
    /// PPG usage multiplier: 0.2 (20%) to 1.0 (100%)
    /// Lower values reduce battery drain but may affect confidence accuracy
    var ppgUsageMultiplier: Double // 0.2 to 1.0

    /// Confidence check interval in minutes
    /// Default: 15 minutes, adjustable for battery optimization
    var confidenceCheckIntervalMinutes: Double // Minutes between checks

    static var `default`: BatteryManagementSettings {
        BatteryManagementSettings(
            ppgUsageMultiplier: 1.0, // 100% usage (full monitoring)
            confidenceCheckIntervalMinutes: 15.0 // Every 15 minutes
        )
    }

    static var balanced: BatteryManagementSettings {
        BatteryManagementSettings(
            ppgUsageMultiplier: 0.6, // 60% usage
            confidenceCheckIntervalMinutes: 20.0 // Every 20 minutes
        )
    }

    static var powerSaver: BatteryManagementSettings {
        BatteryManagementSettings(
            ppgUsageMultiplier: 0.2, // 20% usage (minimum)
            confidenceCheckIntervalMinutes: 30.0 // Every 30 minutes
        )
    }

    /// Calculate actual confidence check interval in seconds
    var confidenceCheckInterval: TimeInterval {
        return confidenceCheckIntervalMinutes * 60.0
    }
}

/// Authentication result with detailed decision factors
struct AuthenticationResult {
    let success: Bool
    let confidenceScore: Double
    let method: AuthenticationMethod
    let decisionFactors: DecisionFactors
    let timestamp: Date
    let requiresStepUp: Bool

    enum AuthenticationMethod {
        case ppgContinuous
        case ecgSingle
        case ecgMultiple
        case hybrid
    }

    struct DecisionFactors {
        let templateMatch: Double
        let livenessScore: Double
        let deviceTrust: Double
        let wristDetection: Bool
        let timeSinceLastECG: TimeInterval
        let environmentalFactors: Double
    }
}

/// Confidence scoring thresholds (configurable 88-99%)
struct ConfidenceThresholds: Codable {
    var fullAccess: Double // Default 0.85 (85%)
    var conditionalAccess: Double // Default 0.75 (75%)
    var requireStepUp: Double // Default 0.75 (75%)
    var minimumAccuracy: Double // Configurable 0.88-0.99 (88-99%)

    static var `default`: ConfidenceThresholds {
        ConfidenceThresholds(
            fullAccess: 0.85,
            conditionalAccess: 0.75,
            requireStepUp: 0.75,
            minimumAccuracy: 0.96 // 96% for single ECG (default)
        )
    }

    static var highSecurity: ConfidenceThresholds {
        ConfidenceThresholds(
            fullAccess: 0.92,
            conditionalAccess: 0.85,
            requireStepUp: 0.85,
            minimumAccuracy: 0.98 // 98% for ultra-high security
        )
    }

    static var lowFriction: ConfidenceThresholds {
        ConfidenceThresholds(
            fullAccess: 0.80,
            conditionalAccess: 0.70,
            requireStepUp: 0.70,
            minimumAccuracy: 0.88 // 88% minimum
        )
    }
}

/// Authentication session state
struct AuthenticationSession: Codable {
    let sessionId: UUID
    let userId: String
    let startTime: Date
    var lastVerification: Date
    var confidenceScore: Double
    var authMethod: String
    var isActive: Bool

    // Continuous authentication state
    var backgroundVerificationCount: Int
    var nextVerificationDue: Date

    // Risk factors
    var locationConsistent: Bool
    var behaviorNormal: Bool
    var deviceTrusted: Bool

    init(userId: String, confidenceScore: Double, authMethod: String) {
        self.sessionId = UUID()
        self.userId = userId
        self.startTime = Date()
        self.lastVerification = Date()
        self.confidenceScore = confidenceScore
        self.authMethod = authMethod
        self.isActive = true
        self.backgroundVerificationCount = 0
        self.nextVerificationDue = Date().addingTimeInterval(900) // 15 minutes
        self.locationConsistent = true
        self.behaviorNormal = true
        self.deviceTrusted = true
    }
}

/// Enterprise integration mode
enum IntegrationMode: String, Codable, CaseIterable {
    case local = "Local Only"
    case entraID = "Microsoft Entra ID"
    case pacs = "Physical Access Control"
    case healthcare = "Healthcare Patient ID"
    case custom = "Custom Enterprise"

    var isDemo: Bool {
        switch self {
        case .local:
            return false
        default:
            return false // All modes are now production-ready
        }
    }
}

/// Action requiring authentication
struct AuthenticationAction {
    let actionType: ActionType
    let requiredConfidence: Double
    let requiresECG: Bool
    let description: String

    enum ActionType {
        case doorAccess
        case documentAccess
        case highValueTransaction
        case criticalSystemAccess
        case generalAccess
    }
}
