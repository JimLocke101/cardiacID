//
//  BiometricTemplate.swift
//  CardiacID Watch App
//
//  Ported from HeartID_0_7 - Enterprise-Ready Biometric Authentication
//  Created by HeartID Team on 10/27/25.
//  Enhanced for DOD-level security with AES-256 encryption support
//

import Foundation

/// Represents a biometric template derived from cardiac signals
/// Stored encrypted in Keychain with AES-256
struct BiometricTemplate: Codable, Identifiable {
    let id: UUID
    let userId: String
    let firstName: String
    let lastName: String
    let createdAt: Date
    let updatedAt: Date

    // ECG-derived features (256-bit cardiac signature)
    let ecgFeatures: ECGFeatures

    // PPG-derived features for continuous monitoring
    let ppgBaseline: PPGBaseline

    // Quality metrics
    let qualityScore: Double
    let confidenceLevel: Double

    // Metadata
    let deviceInfo: DeviceInfo
    let sampleCount: Int // Number of ECGs used to create template

    // Enterprise Integration
    let enterpriseUserId: String? // For EntraID, PACS, etc.
    let departmentId: String? // For organizational access control
    let accessLevel: String? // For role-based access control

    init(
        userId: String,
        firstName: String,
        lastName: String,
        ecgFeatures: ECGFeatures,
        ppgBaseline: PPGBaseline,
        qualityScore: Double,
        deviceInfo: DeviceInfo,
        sampleCount: Int = 3,
        enterpriseUserId: String? = nil,
        departmentId: String? = nil,
        accessLevel: String? = nil
    ) {
        self.id = UUID()
        self.userId = userId
        self.firstName = firstName
        self.lastName = lastName
        self.createdAt = Date()
        self.updatedAt = Date()
        self.ecgFeatures = ecgFeatures
        self.ppgBaseline = ppgBaseline
        self.qualityScore = qualityScore
        self.confidenceLevel = min(qualityScore, 1.0)
        self.deviceInfo = deviceInfo
        self.sampleCount = sampleCount
        self.enterpriseUserId = enterpriseUserId
        self.departmentId = departmentId
        self.accessLevel = accessLevel
    }

    var fullName: String {
        "\(firstName) \(lastName)"
    }
}

/// ECG-derived biometric features (high accuracy, 96-99%)
struct ECGFeatures: Codable {
    // QRS complex morphology (primary identification features)
    let qrsAmplitude: [Double]
    let qrsDuration: Double
    let qrsInterval: Double

    // P-wave characteristics
    let pWaveAmplitude: Double
    let pWaveDuration: Double

    // T-wave characteristics
    let tWaveAmplitude: Double
    let tWaveDuration: Double

    // Heart rate variability (HRV) from ECG
    let hrvMean: Double
    let hrvStdDev: Double
    let hrvRMSSD: Double // Root mean square of successive differences

    // Template signature (256-bit vector)
    let signatureVector: [Double]

    // Signal quality
    let signalNoiseRatio: Double
    let baselineStability: Double
}

/// PPG-derived baseline for continuous monitoring (85-92% accuracy)
struct PPGBaseline: Codable {
    // Heart rate patterns
    let restingHeartRate: Double
    let heartRateRange: ClosedRange<Double>

    // Heart rate variability from PPG
    let hrvMean: Double
    let hrvStdDev: Double
    let hrvRMSSD: Double  // Root Mean Square of Successive Differences
    let hrvSDNN: Double   // Standard Deviation of NN intervals

    // Rhythm characteristics
    let rhythmPattern: [Double] // Normalized beat intervals
    let rhythmStability: Double
    let heartRateVariability: Double  // Characteristic HR fluctuation pattern

    // Respiratory sinus arrhythmia
    let respiratoryPattern: [Double]

    // Movement correlation factors
    let movementBaseline: Double

    private enum CodingKeys: String, CodingKey {
        case restingHeartRate, heartRateRange, hrvMean, hrvStdDev, hrvRMSSD, hrvSDNN
        case rhythmPattern, rhythmStability, heartRateVariability, respiratoryPattern, movementBaseline
    }

    init(
        restingHeartRate: Double,
        heartRateRange: ClosedRange<Double>,
        hrvMean: Double,
        hrvStdDev: Double,
        hrvRMSSD: Double = 0.035,  // Default typical value
        hrvSDNN: Double = 0.050,   // Default typical value
        rhythmPattern: [Double],
        rhythmStability: Double,
        heartRateVariability: Double = 5.0,  // Default typical HR fluctuation
        respiratoryPattern: [Double],
        movementBaseline: Double
    ) {
        self.restingHeartRate = restingHeartRate
        self.heartRateRange = heartRateRange
        self.hrvMean = hrvMean
        self.hrvStdDev = hrvStdDev
        self.hrvRMSSD = hrvRMSSD
        self.hrvSDNN = hrvSDNN
        self.rhythmPattern = rhythmPattern
        self.rhythmStability = rhythmStability
        self.heartRateVariability = heartRateVariability
        self.respiratoryPattern = respiratoryPattern
        self.movementBaseline = movementBaseline
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(restingHeartRate, forKey: .restingHeartRate)
        try container.encode(["lower": heartRateRange.lowerBound, "upper": heartRateRange.upperBound], forKey: .heartRateRange)
        try container.encode(hrvMean, forKey: .hrvMean)
        try container.encode(hrvStdDev, forKey: .hrvStdDev)
        try container.encode(hrvRMSSD, forKey: .hrvRMSSD)
        try container.encode(hrvSDNN, forKey: .hrvSDNN)
        try container.encode(rhythmPattern, forKey: .rhythmPattern)
        try container.encode(rhythmStability, forKey: .rhythmStability)
        try container.encode(heartRateVariability, forKey: .heartRateVariability)
        try container.encode(respiratoryPattern, forKey: .respiratoryPattern)
        try container.encode(movementBaseline, forKey: .movementBaseline)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        restingHeartRate = try container.decode(Double.self, forKey: .restingHeartRate)
        let rangeDict = try container.decode([String: Double].self, forKey: .heartRateRange)
        heartRateRange = (rangeDict["lower"] ?? 60)...(rangeDict["upper"] ?? 100)
        hrvMean = try container.decode(Double.self, forKey: .hrvMean)
        hrvStdDev = try container.decode(Double.self, forKey: .hrvStdDev)
        hrvRMSSD = try container.decodeIfPresent(Double.self, forKey: .hrvRMSSD) ?? 0.035  // Default for backward compatibility
        hrvSDNN = try container.decodeIfPresent(Double.self, forKey: .hrvSDNN) ?? 0.050
        rhythmPattern = try container.decode([Double].self, forKey: .rhythmPattern)
        rhythmStability = try container.decode(Double.self, forKey: .rhythmStability)
        heartRateVariability = try container.decodeIfPresent(Double.self, forKey: .heartRateVariability) ?? 5.0
        respiratoryPattern = try container.decode([Double].self, forKey: .respiratoryPattern)
        movementBaseline = try container.decode(Double.self, forKey: .movementBaseline)
    }
}

struct DeviceInfo: Codable {
    let deviceType: String
    let deviceModel: String
    let osVersion: String
    let watchOSVersion: String

    static var current: DeviceInfo {
        DeviceInfo(
            deviceType: "Apple Watch",
            deviceModel: "Series 4+", // ECG-capable devices
            osVersion: "watchOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            watchOSVersion: "watchOS 11+"
        )
    }
}
