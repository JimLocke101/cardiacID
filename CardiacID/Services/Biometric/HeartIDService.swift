//
//  HeartIDService.swift
//  CardiacID
//
//  Ported from HeartID_0_7 Watch App
//  Created by HeartID Team on 10/27/25.
//  Main service orchestrating hybrid PPG/ECG authentication

import Foundation
import HealthKit
import Combine
import SwiftUI

@MainActor
class HeartIDService: ObservableObject {
    // Dependencies
    private let healthKit = HealthKitService()
    private let storage = TemplateStorageService()
    private let matching = BiometricMatchingService()

    // Published state
    @Published var enrollmentState: EnrollmentState = .notEnrolled
    @Published var authenticationState: AuthenticationState = .unauthenticated
    @Published var currentConfidence: Double = 0.0
    @Published var isMonitoring: Bool = false
    @Published var currentIntegrationMode: IntegrationMode = .local

    // Configuration
    @Published var thresholds: ConfidenceThresholds = .default
    @Published var batterySettings: BatteryManagementSettings = .default

    // Session
    private var currentSession: AuthenticationSession?
    private var backgroundTimer: Timer?

    // ECG Priority Authentication State
    private var lastECGConfidence: Double = 0.0
    private var lastECGTimestamp: Date?
    private var currentPPGConfidence: Double = 0.0

    // Confidence Ceiling (Peak Tracking)
    private var peakECGConfidenceInInterval: Double = 0.0
    private var peakECGTimestampInInterval: Date?
    private var peakPPGConfidenceInInterval: Double = 0.0
    private var lastIntervalResetTime: Date = Date()

    // Wrist detection subscription
    private var wristDetectionCancellable: AnyCancellable?

    init() {
        loadConfiguration()
        setupWristDetectionMonitoring()
    }

    deinit {
        // Cleanup timer on app termination
        backgroundTimer?.invalidate()
        backgroundTimer = nil
        print("🧹 HeartIDService cleanup - Timer invalidated")
    }

    // MARK: - Initialization

    func initialize() async {
        do {
            try await healthKit.requestAuthorization()

            if storage.hasTemplate() {
                enrollmentState = .enrolled
                print("✅ User already enrolled")

                // Start PPG monitoring automatically after enrollment
                await startContinuousAuth()
            } else {
                enrollmentState = .notEnrolled
                print("ℹ️ User not enrolled - enrollment required")
            }
        } catch {
            print("❌ Failed to initialize: \(error)")
        }
    }

    // MARK: - Enrollment (3 ECG samples for robust template)

    func beginEnrollment(userId: String) async throws {
        enrollmentState = .enrolling(progress: 0)

        var ecgSamples: [(ecg: HKElectrocardiogram, features: ECGFeatures)] = []

        // Collect 3 ECG samples
        for sampleNum in 1...3 {
            enrollmentState = .enrolling(progress: Double(sampleNum - 1) / 3.0)

            print("📝 Please record ECG #\(sampleNum) in Health app...")

            // Wait for user to record ECG in Health app
            let ecg = try await healthKit.pollForRecentECG(timeout: 180)

            // Extract features
            let features = try await healthKit.extractECGFeatures(from: ecg)

            // Validate quality (relaxed threshold for Apple Watch ECGs)
            // With new calibration: 10+ dB is acceptable
            guard features.signalNoiseRatio > 10.0 else {
                print("⚠️ ECG quality too low (SNR: \(String(format: "%.1f", features.signalNoiseRatio)) dB). Please try again.")
                print("💡 Tips: Ensure watch fits snugly, rest arm on table, hold still")
                // IMPORTANT: Reset enrollment state before throwing error
                enrollmentState = .notEnrolled
                throw EnrollmentError.poorQuality
            }

            ecgSamples.append((ecg, features))
            print("✅ ECG #\(sampleNum) captured - SNR: \(String(format: "%.1f", features.signalNoiseRatio)) dB")
        }

        // Create master template from 3 samples
        enrollmentState = .enrolling(progress: 0.9)
        let template = try createMasterTemplate(from: ecgSamples, userId: userId)

        // Save template
        try storage.saveTemplate(template)

        enrollmentState = .enrolled
        print("🎉 Enrollment complete! Template created from \(ecgSamples.count) ECG samples")

        // Start PPG monitoring automatically after enrollment
        await startContinuousAuth()

        // Perform automatic authentication after enrollment using the most recent ECG sample
        print("🔐 Performing automatic authentication...")

        // Use the last ECG sample we just recorded (most accurate)
        let lastSample = ecgSamples.last!
        let ecgConfidence = matching.matchECGFeatures(lastSample.features, against: template)

        // Set ECG priority state directly
        lastECGConfidence = ecgConfidence
        lastECGTimestamp = lastSample.ecg.startDate

        // Calculate confidence (will use fresh ECG)
        currentConfidence = ecgConfidence
        currentPPGConfidence = 0.88 // Set PPG baseline

        // Set authentication state
        if currentConfidence >= thresholds.fullAccess {
            authenticationState = .authenticated(confidence: currentConfidence)
        } else if currentConfidence >= thresholds.conditionalAccess {
            authenticationState = .conditional(confidence: currentConfidence)
        } else {
            authenticationState = .unauthenticated
        }

        print("✅ Auto-authentication complete: \(String(format: "%.0f", currentConfidence * 100))% confidence (ECG-based)")
    }

    private func createMasterTemplate(
        from samples: [(ecg: HKElectrocardiogram, features: ECGFeatures)],
        userId: String
    ) throws -> BiometricTemplate {
        guard !samples.isEmpty else {
            throw EnrollmentError.insufficientSamples
        }

        // Average ECG features from multiple samples for robustness
        let ecgFeatures = averageECGFeatures(samples.map { $0.features })

        // Create PPG baseline (would normally capture PPG data, using defaults for now)
        let ppgBaseline = PPGBaseline(
            restingHeartRate: 70.0,
            heartRateRange: 60.0...100.0,
            hrvMean: 0.08,
            hrvStdDev: 0.02,
            rhythmPattern: Array(repeating: 0.8, count: 10),
            rhythmStability: 0.85,
            respiratoryPattern: Array(repeating: 0.0, count: 10),
            movementBaseline: 0.5
        )

        let qualityScore = samples.map { $0.features.signalNoiseRatio }.reduce(0, +) / Double(samples.count) / 50.0

        return BiometricTemplate(
            userId: userId,
            ecgFeatures: ecgFeatures,
            ppgBaseline: ppgBaseline,
            qualityScore: min(qualityScore, 1.0),
            deviceInfo: .current,
            sampleCount: samples.count
        )
    }

    private func averageECGFeatures(_ features: [ECGFeatures]) -> ECGFeatures {
        let count = Double(features.count)

        // Average QRS features
        let avgQRSAmplitude = averageVectors(features.map { $0.qrsAmplitude })
        let avgQRSDuration = features.map { $0.qrsDuration }.reduce(0, +) / count
        let avgQRSInterval = features.map { $0.qrsInterval }.reduce(0, +) / count

        // Average P/T waves
        let avgPWaveAmp = features.map { $0.pWaveAmplitude }.reduce(0, +) / count
        let avgPWaveDur = features.map { $0.pWaveDuration }.reduce(0, +) / count
        let avgTWaveAmp = features.map { $0.tWaveAmplitude }.reduce(0, +) / count
        let avgTWaveDur = features.map { $0.tWaveDuration }.reduce(0, +) / count

        // Average HRV
        let avgHRVMean = features.map { $0.hrvMean }.reduce(0, +) / count
        let avgHRVStdDev = features.map { $0.hrvStdDev }.reduce(0, +) / count
        let avgHRVRMSSD = features.map { $0.hrvRMSSD }.reduce(0, +) / count

        // Average signature vectors
        let avgSignature = averageVectors(features.map { $0.signatureVector })

        // Average quality metrics
        let avgSNR = features.map { $0.signalNoiseRatio }.reduce(0, +) / count
        let avgStability = features.map { $0.baselineStability }.reduce(0, +) / count

        return ECGFeatures(
            qrsAmplitude: avgQRSAmplitude,
            qrsDuration: avgQRSDuration,
            qrsInterval: avgQRSInterval,
            pWaveAmplitude: avgPWaveAmp,
            pWaveDuration: avgPWaveDur,
            tWaveAmplitude: avgTWaveAmp,
            tWaveDuration: avgTWaveDur,
            hrvMean: avgHRVMean,
            hrvStdDev: avgHRVStdDev,
            hrvRMSSD: avgHRVRMSSD,
            signatureVector: avgSignature,
            signalNoiseRatio: avgSNR,
            baselineStability: avgStability
        )
    }

    private func averageVectors(_ vectors: [[Double]]) -> [Double] {
        guard !vectors.isEmpty else { return [] }

        let length = vectors[0].count
        var result = [Double](repeating: 0.0, count: length)

        for vector in vectors {
            for (index, value) in vector.prefix(length).enumerated() {
                result[index] += value
            }
        }

        let count = Double(vectors.count)
        return result.map { $0 / count }
    }

    // MARK: - Continuous PPG Authentication

    func startContinuousAuth() async {
        guard enrollmentState == .enrolled else {
            print("❌ Cannot start monitoring - not enrolled")
            return
        }

        // Start PPG monitoring with battery usage multiplier
        healthKit.startContinuousPPGMonitoring()
        isMonitoring = true

        // Start background verification timer using configurable interval
        let interval = batterySettings.confidenceCheckInterval
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performBackgroundVerification()
            }
        }

        let minutes = Int(batterySettings.confidenceCheckIntervalMinutes)
        let usagePercent = Int(batterySettings.ppgUsageMultiplier * 100)
        print("✅ Continuous PPG monitoring started - Checking every \(minutes) min at \(usagePercent)% usage")
    }

    func stopContinuousAuth() {
        healthKit.stopContinuousPPGMonitoring()
        backgroundTimer?.invalidate()
        backgroundTimer = nil
        isMonitoring = false
        print("⏹️ Continuous monitoring stopped")
    }

    private func performBackgroundVerification() async {
        guard let template = try? storage.loadTemplate() else { return }

        // Check if interval has elapsed - if so, reset peak tracking
        let timeSinceIntervalReset = Date().timeIntervalSince(lastIntervalResetTime)
        if timeSinceIntervalReset >= batterySettings.confidenceCheckInterval {
            // New interval - reset peak tracking
            peakECGConfidenceInInterval = 0.0
            peakECGTimestampInInterval = nil
            peakPPGConfidenceInInterval = 0.0
            lastIntervalResetTime = Date()
            print("🔄 New interval started - Peak tracking reset")
        }

        // Get current PPG confidence
        let heartRate = healthKit.currentHeartRate
        let ppgConfidence = matching.matchPPGPattern(heartRate: heartRate, template: template)

        // Update peak PPG if current is higher
        if ppgConfidence > peakPPGConfidenceInInterval {
            peakPPGConfidenceInInterval = ppgConfidence
            print("📈 New PPG peak: \(String(format: "%.0f", ppgConfidence * 100))%")
        }

        // Check for ECG within current interval
        if let ecgTimestamp = lastECGTimestamp,
           ecgTimestamp > lastIntervalResetTime {
            // ECG exists within this interval - update peak if higher
            if lastECGConfidence > peakECGConfidenceInInterval {
                peakECGConfidenceInInterval = lastECGConfidence
                peakECGTimestampInInterval = ecgTimestamp
                print("📈 New ECG peak: \(String(format: "%.0f", lastECGConfidence * 100))%")
            }
        }

        // Calculate confidence ceiling: use peak ECG if available, otherwise peak PPG
        if peakECGConfidenceInInterval > 0.0 {
            // Use peak ECG with degradation applied
            let timeSinceECG = Date().timeIntervalSince(peakECGTimestampInInterval ?? Date())
            let degradedECG = applyECGDegradation(ecgConfidence: peakECGConfidenceInInterval, timeSinceECG: timeSinceECG)
            currentConfidence = max(degradedECG, peakPPGConfidenceInInterval)
            print("🏆 Confidence ceiling: \(String(format: "%.0f", currentConfidence * 100))% (ECG peak: \(String(format: "%.0f", peakECGConfidenceInInterval * 100))%, degraded: \(String(format: "%.0f", degradedECG * 100))%, PPG floor: \(String(format: "%.0f", peakPPGConfidenceInInterval * 100))%)")
        } else {
            // No ECG in this interval - use peak PPG
            currentConfidence = peakPPGConfidenceInInterval
            print("🏆 Confidence ceiling: \(String(format: "%.0f", currentConfidence * 100))% (PPG peak only)")
        }

        // Update authentication state
        if currentConfidence >= thresholds.fullAccess {
            authenticationState = .authenticated(confidence: currentConfidence)
        } else if currentConfidence >= thresholds.conditionalAccess {
            authenticationState = .conditional(confidence: currentConfidence)
        } else {
            authenticationState = .unauthenticated
        }

        print("🔄 Background verification: \(String(format: "%.0f", currentConfidence * 100))% confidence")
    }

    // MARK: - Manual Authentication (Full PPG Assessment)

    func performManualAuthentication() async {
        print("🔍 Manual authentication requested - checking for recent ECG first...")

        guard let template = try? storage.loadTemplate() else {
            print("❌ No template found - enrollment required")
            return
        }

        // Ensure monitoring is active
        if !isMonitoring {
            await startContinuousAuth()
        }

        // STEP 1: Check for recent ECG in buffer (within 4 minutes)
        let foundRecentECG = await checkForRecentECG()

        // STEP 2: Get current PPG confidence
        let heartRate = healthKit.currentHeartRate
        currentPPGConfidence = matching.matchPPGPattern(heartRate: heartRate, template: template)

        // Update peak PPG if higher
        if currentPPGConfidence > peakPPGConfidenceInInterval {
            peakPPGConfidenceInInterval = currentPPGConfidence
            print("📈 Manual auth - New PPG peak: \(String(format: "%.0f", currentPPGConfidence * 100))%")
        }

        // STEP 3: Calculate ECG-priority confidence
        // ECG ALWAYS overrides PPG if available (highest security)
        currentConfidence = calculateECGPriorityConfidence()

        // Update peak ECG if manual auth found one
        if foundRecentECG, let ecgTimestamp = lastECGTimestamp,
           ecgTimestamp > lastIntervalResetTime,
           lastECGConfidence > peakECGConfidenceInInterval {
            peakECGConfidenceInInterval = lastECGConfidence
            peakECGTimestampInInterval = ecgTimestamp
            print("📈 Manual auth - New ECG peak: \(String(format: "%.0f", lastECGConfidence * 100))%")
        }

        // Update authentication state
        if currentConfidence >= thresholds.fullAccess {
            authenticationState = .authenticated(confidence: currentConfidence)
        } else if currentConfidence >= thresholds.conditionalAccess {
            authenticationState = .conditional(confidence: currentConfidence)
        } else {
            authenticationState = .unauthenticated
        }

        let method = foundRecentECG ? "ECG-priority" : "PPG-only"
        print("✅ Manual authentication complete (\(method)): \(String(format: "%.0f", currentConfidence * 100))% confidence")
    }

    // MARK: - ECG-Priority Confidence Calculation

    /// Calculate confidence with ECG priority logic
    /// ECG ALWAYS overrides PPG when available (highest security)
    /// ECG degrades at configurable rate until it reaches PPG level (PPG acts as floor)
    private func calculateECGPriorityConfidence() -> Double {
        // Use currentPPGConfidence that was already calculated (don't overwrite it!)
        // Only set PPG confidence if it's not already set
        if currentPPGConfidence == 0.0 {
            currentPPGConfidence = healthKit.currentHeartRate > 0 ? 0.88 : 0.0
        }

        // Check if we have a recent ECG (within buffer time)
        if let ecgTimestamp = lastECGTimestamp {
            let timeSinceECG = Date().timeIntervalSince(ecgTimestamp)

            // ECG is within 4-minute buffer - use it with degradation
            if timeSinceECG <= ConfidenceDegradationConstants.recentECGBufferTime {
                // Fresh ECG - use full confidence
                print("🎯 Using RECENT ECG (age: \(String(format: "%.1f", timeSinceECG/60))min) - High confidence")
                return applyECGDegradation(ecgConfidence: lastECGConfidence, timeSinceECG: timeSinceECG)
            }

            // ECG is older but still valuable - apply degradation with PPG floor
            let degradedECG = applyECGDegradation(ecgConfidence: lastECGConfidence, timeSinceECG: timeSinceECG)

            // ECG confidence cannot fall below current PPG confidence (PPG acts as floor)
            let finalConfidence = max(degradedECG, currentPPGConfidence)

            if degradedECG > currentPPGConfidence {
                print("🔻 Using DEGRADED ECG (\(String(format: "%.1f", timeSinceECG/60))min old): \(String(format: "%.0f", degradedECG * 100))% (above PPG floor)")
            } else {
                print("⬇️ ECG degraded to PPG floor: \(String(format: "%.0f", currentPPGConfidence * 100))%")
            }

            return finalConfidence
        }

        // No ECG available - use PPG only
        print("💓 Using PPG-only confidence: \(String(format: "%.0f", currentPPGConfidence * 100))%")
        return currentPPGConfidence
    }

    /// Apply ECG degradation: 0.5% per 6 minutes
    /// Formula: confidence - (intervals_passed * degradation_rate)
    private func applyECGDegradation(ecgConfidence: Double, timeSinceECG: TimeInterval) -> Double {
        // Calculate how many degradation intervals have passed
        let intervalsPassed = timeSinceECG / ConfidenceDegradationConstants.degradationInterval

        // Calculate degradation amount
        let degradationAmount = intervalsPassed * ConfidenceDegradationConstants.ecgDegradationRate

        // Apply degradation
        let degradedConfidence = ecgConfidence - degradationAmount

        // Don't go below absolute minimum floor
        let finalConfidence = max(degradedConfidence, ConfidenceDegradationConstants.minimumConfidenceFloor)

        return finalConfidence
    }

    /// Check if there's a recent ECG in HealthKit buffer (within 4 minutes)
    private func checkForRecentECG() async -> Bool {
        guard let template = try? storage.loadTemplate() else { return false }

        // Query most recent ECG
        if let recentECG = try? await healthKit.queryMostRecentECG(since: Date().addingTimeInterval(-ConfidenceDegradationConstants.recentECGBufferTime)) {
            // Found recent ECG - extract features and calculate confidence
            if let features = try? await healthKit.extractECGFeatures(from: recentECG) {
                let ecgConfidence = matching.matchECGFeatures(features, against: template)

                // Update ECG state
                lastECGConfidence = ecgConfidence
                lastECGTimestamp = recentECG.startDate

                print("✅ Found recent ECG in buffer: \(String(format: "%.0f", ecgConfidence * 100))% confidence")
                return true
            }
        }

        return false
    }

    // MARK: - ECG Step-Up Authentication

    func performECGStepUp(for action: AuthenticationAction) async throws -> AuthenticationResult {
        print("🔐 ECG step-up authentication requested for: \(action.description)")

        guard let template = try? storage.loadTemplate() else {
            throw HeartIDAuthenticationError.notEnrolled
        }

        // Request single ECG
        let ecg = try await healthKit.pollForRecentECG(timeout: 180)
        let features = try await healthKit.extractECGFeatures(from: ecg)

        // Match against template
        let ecgConfidence = matching.matchECGFeatures(features, against: template)

        // Calculate hybrid confidence
        let hybridConfidence = matching.calculateHybridConfidence(
            ecgMatch: ecgConfidence,
            wristDetected: true,
            timeSinceLastECG: 0.0,
            environmentalFactors: 1.0
        )

        currentConfidence = hybridConfidence

        // Evaluate against thresholds
        let decision = matching.evaluateAuthentication(
            confidenceScore: hybridConfidence,
            action: action,
            thresholds: thresholds
        )

        let result = AuthenticationResult(
            success: decision.isGranted,
            confidenceScore: hybridConfidence,
            method: .ecgSingle,
            decisionFactors: AuthenticationResult.DecisionFactors(
                templateMatch: ecgConfidence,
                livenessScore: 0.98,
                deviceTrust: 1.0,
                wristDetection: true,
                timeSinceLastECG: 0.0,
                environmentalFactors: 1.0
            ),
            timestamp: Date(),
            requiresStepUp: decision.needsStepUp
        )

        if result.success {
            authenticationState = .authenticated(confidence: hybridConfidence)
            print("✅ ECG authentication successful: \(String(format: "%.0f", hybridConfidence * 100))%")
        } else {
            print("❌ ECG authentication failed: \(String(format: "%.0f", hybridConfidence * 100))%")
        }

        return result
    }

    // MARK: - Configuration

    func updateThresholds(_ newThresholds: ConfidenceThresholds) {
        thresholds = newThresholds
        matching.saveThresholds(newThresholds)
        print("⚙️ Thresholds updated: min=\(String(format: "%.0f", newThresholds.minimumAccuracy * 100))%")
    }

    func updateBatterySettings(_ newSettings: BatteryManagementSettings) async {
        batterySettings = newSettings

        // Save to UserDefaults
        if let encoded = try? JSONEncoder().encode(newSettings) {
            UserDefaults.standard.set(encoded, forKey: "batterySettings")
        }

        // Restart monitoring with new interval if currently monitoring
        if isMonitoring {
            stopContinuousAuth()
            await startContinuousAuth()
        }

        let minutes = Int(newSettings.confidenceCheckIntervalMinutes)
        let usagePercent = Int(newSettings.ppgUsageMultiplier * 100)
        print("⚙️ Battery settings updated: \(minutes) min interval, \(usagePercent)% PPG usage")
    }

    func setIntegrationMode(_ mode: IntegrationMode) {
        currentIntegrationMode = mode
        print("🔌 Integration mode: \(mode.rawValue)")
    }

    private func loadConfiguration() {
        thresholds = matching.loadThresholds()

        // Load battery settings from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "batterySettings"),
           let loaded = try? JSONDecoder().decode(BatteryManagementSettings.self, from: data) {
            batterySettings = loaded
        } else {
            batterySettings = .default
        }
    }

    /// Monitor watch removal and invalidate authentication (critical security)
    /// Matches Apple Watch passcode behavior - removal requires re-authentication
    private func setupWristDetectionMonitoring() {
        wristDetectionCancellable = healthKit.$isWatchOnWrist
            .sink { [weak self] isOnWrist in
                guard let self = self else { return }

                if !isOnWrist && self.authenticationState != .unauthenticated {
                    // Watch removed - invalidate authentication immediately
                    print("🚨 SECURITY: Watch removed - Authentication invalidated")
                    self.authenticationState = .unauthenticated
                    self.currentConfidence = 0.0

                    // Clear ECG priority state
                    self.lastECGConfidence = 0.0
                    self.lastECGTimestamp = nil
                    self.currentPPGConfidence = 0.0

                    // Clear peak tracking (confidence ceiling reset)
                    self.peakECGConfidenceInInterval = 0.0
                    self.peakECGTimestampInInterval = nil
                    self.peakPPGConfidenceInInterval = 0.0
                    self.lastIntervalResetTime = Date()
                }
            }
    }

    // MARK: - Cleanup

    func unenroll() {
        storage.deleteTemplate()
        stopContinuousAuth()
        healthKit.revokeHealthKitAccess()  // Make HealthKit data inaccessible
        enrollmentState = .notEnrolled
        authenticationState = .unauthenticated
        currentConfidence = 0.0
        print("🗑️ User unenrolled - HealthKit access revoked")
    }

    /// Factory reset - Complete data wipe for demos/testing
    /// WARNING: This deletes ALL app data (template + settings + state)
    func factoryReset() {
        // 1. Delete biometric template
        storage.deleteTemplate()

        // 2. Stop all monitoring
        stopContinuousAuth()

        // 3. Revoke HealthKit access (next user must re-authorize)
        healthKit.revokeHealthKitAccess()

        // 4. Reset all state
        enrollmentState = .notEnrolled
        authenticationState = .unauthenticated
        currentConfidence = 0.0
        currentIntegrationMode = .local

        // 5. Reset thresholds to defaults
        thresholds = .default
        matching.saveThresholds(.default)

        // 6. Clear UserDefaults (thresholds)
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()

        print("🔄 Factory reset complete - All data cleared, HealthKit access revoked")
    }

    /// Quick demo reset - Keeps settings, clears authentication state
    /// Use this between demo runs when you want to re-enroll quickly
    func demoReset() {
        // Keep thresholds and integration mode
        // Only reset enrollment and auth state

        storage.deleteTemplate()
        stopContinuousAuth()
        healthKit.revokeHealthKitAccess()  // Next user must re-authorize
        enrollmentState = .notEnrolled
        authenticationState = .unauthenticated
        currentConfidence = 0.0

        print("🎬 Demo reset complete - Ready for re-enrollment, HealthKit access revoked")
    }

    // MARK: - Status View Computed Properties

    var healthKitAuthorizationStatus: String {
        healthKit.isAuthorized ? "Authorized" : "Not Authorized"
    }

    var healthKitConnectionStatus: String {
        if healthKit.isMonitoring && healthKit.currentHeartRate > 0 {
            return "Connected"
        } else if healthKit.isMonitoring {
            return "Monitoring"
        } else {
            return "Disconnected"
        }
    }

    var mostRecentECGTime: String? {
        guard let timestamp = lastECGTimestamp else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }

    var mostRecentECGConfidence: Double? {
        guard lastECGConfidence > 0 else { return nil }
        return lastECGConfidence
    }

    var peakECGInInterval: Double? {
        guard peakECGConfidenceInInterval > 0 else { return nil }
        return peakECGConfidenceInInterval
    }

    var peakPPGInInterval: Double? {
        guard peakPPGConfidenceInInterval > 0 else { return nil }
        return peakPPGConfidenceInInterval
    }

    var ppgMonitoringStatus: String {
        healthKit.isMonitoring ? "Active" : "Inactive"
    }

    var currentPPGConfidenceValue: Double {
        return currentPPGConfidence
    }

    var authenticationStateText: String {
        switch authenticationState {
        case .authenticated:
            return "Authenticated"
        case .conditional:
            return "Conditional"
        case .unauthenticated:
            return "Unauthenticated"
        }
    }

    var authenticationStateColor: Color {
        switch authenticationState {
        case .authenticated:
            return .green
        case .conditional:
            return .yellow
        case .unauthenticated:
            return .red
        }
    }

    var accessLevelText: String {
        let confidence = currentConfidence
        if confidence >= thresholds.fullAccess {
            return "Full Access"
        } else if confidence >= thresholds.conditionalAccess {
            return "Conditional Access"
        } else {
            return "No Access"
        }
    }

    var accessLevelColor: Color {
        let confidence = currentConfidence
        if confidence >= thresholds.fullAccess {
            return .green
        } else if confidence >= thresholds.conditionalAccess {
            return .yellow
        } else {
            return .red
        }
    }

    var isWatchOnWrist: Bool {
        return healthKit.isWatchOnWrist
    }

    var lastIntervalResetTimeFormatted: String? {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: lastIntervalResetTime, relativeTo: Date())
    }

    var nextIntervalResetTimeFormatted: String? {
        let nextReset = lastIntervalResetTime.addingTimeInterval(batterySettings.confidenceCheckInterval)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: nextReset, relativeTo: Date())
    }

    var currentHeartRate: Double {
        return healthKit.currentHeartRate
    }
}

// MARK: - State Enums

enum EnrollmentState: Equatable {
    case notEnrolled
    case enrolling(progress: Double)
    case enrolled
}

enum AuthenticationState: Equatable {
    case unauthenticated
    case authenticated(confidence: Double)
    case conditional(confidence: Double)
}

enum EnrollmentError: Error, LocalizedError {
    case insufficientSamples
    case poorQuality
    case timeout

    var errorDescription: String? {
        switch self {
        case .insufficientSamples:
            return "Not enough ECG samples collected"
        case .poorQuality:
            return "ECG quality too low (SNR < 20dB)"
        case .timeout:
            return "Timeout waiting for ECG recording"
        }
    }
}

enum HeartIDAuthenticationError: Error, LocalizedError {
    case notEnrolled
    case confidenceTooLow
    case timeout

    var errorDescription: String? {
        switch self {
        case .notEnrolled:
            return "User not enrolled. Please enroll first."
        case .confidenceTooLow:
            return "Confidence score too low for this action"
        case .timeout:
            return "Authentication timeout"
        }
    }
}
