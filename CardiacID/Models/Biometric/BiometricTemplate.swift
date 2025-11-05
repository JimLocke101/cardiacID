//
//  BiometricTemplate.swift
//  CardiacID
//
//  Ported from HeartID_0_7 Watch App
//  Created by HeartID Team on 10/27/25.
//

import Foundation

/// Represents a biometric template derived from cardiac signals
struct BiometricTemplate: Codable, Identifiable {
    let id: UUID
    let userId: String
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

    init(userId: String, ecgFeatures: ECGFeatures, ppgBaseline: PPGBaseline, qualityScore: Double, deviceInfo: DeviceInfo, sampleCount: Int = 3) {
        self.id = UUID()
        self.userId = userId
        self.createdAt = Date()
        self.updatedAt = Date()
        self.ecgFeatures = ecgFeatures
        self.ppgBaseline = ppgBaseline
        self.qualityScore = qualityScore
        self.confidenceLevel = min(qualityScore, 1.0)
        self.deviceInfo = deviceInfo
        self.sampleCount = sampleCount
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

    // Rhythm characteristics
    let rhythmPattern: [Double] // Normalized beat intervals
    let rhythmStability: Double

    // Respiratory sinus arrhythmia
    let respiratoryPattern: [Double]

    // Movement correlation factors
    let movementBaseline: Double

    private enum CodingKeys: String, CodingKey {
        case restingHeartRate, heartRateRange, hrvMean, hrvStdDev
        case rhythmPattern, rhythmStability, respiratoryPattern, movementBaseline
    }

    init(restingHeartRate: Double, heartRateRange: ClosedRange<Double>, hrvMean: Double, hrvStdDev: Double, rhythmPattern: [Double], rhythmStability: Double, respiratoryPattern: [Double], movementBaseline: Double) {
        self.restingHeartRate = restingHeartRate
        self.heartRateRange = heartRateRange
        self.hrvMean = hrvMean
        self.hrvStdDev = hrvStdDev
        self.rhythmPattern = rhythmPattern
        self.rhythmStability = rhythmStability
        self.respiratoryPattern = respiratoryPattern
        self.movementBaseline = movementBaseline
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(restingHeartRate, forKey: .restingHeartRate)
        try container.encode(["lower": heartRateRange.lowerBound, "upper": heartRateRange.upperBound], forKey: .heartRateRange)
        try container.encode(hrvMean, forKey: .hrvMean)
        try container.encode(hrvStdDev, forKey: .hrvStdDev)
        try container.encode(rhythmPattern, forKey: .rhythmPattern)
        try container.encode(rhythmStability, forKey: .rhythmStability)
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
        rhythmPattern = try container.decode([Double].self, forKey: .rhythmPattern)
        rhythmStability = try container.decode(Double.self, forKey: .rhythmStability)
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
        #if os(watchOS)
        return DeviceInfo(
            deviceType: "Apple Watch",
            deviceModel: "Unknown", // Will be detected at runtime
            osVersion: "watchOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            watchOSVersion: "watchOS 9+"
        )
        #else
        return DeviceInfo(
            deviceType: "iPhone",
            deviceModel: "Unknown",
            osVersion: "iOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            watchOSVersion: "N/A"
        )
        #endif
    }
}
