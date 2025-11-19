// WatchHeartRateService.swift
// Realistic heart rate service for Apple Watch using available APIs
// This would go in the Watch App target

import Foundation
import HealthKit
import Combine
import WatchKit

@MainActor
class WatchHeartRateService: NSObject, ObservableObject {
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    
    // Published properties
    @Published var currentHeartRate: Double = 0.0
    @Published var currentRMSSD: Double = 0.0
    @Published var currentSDNN: Double = 0.0
    @Published var isAuthorized = false
    @Published var isCapturing = false
    @Published var captureProgress: Double = 0.0
    
    // Internal state
    private var heartRateSamples: [HeartRateSample] = []
    private var captureCompletion: (([HeartRateSample]) -> Void)?
    private var captureTimer: Timer?
    private var captureStartTime: Date?
    private var captureDuration: TimeInterval = 15.0
    
    // HRV calculation buffers
    private var recentSamples: [HeartRateSample] = []
    private let maxRecentSamples = 20
    
    override init() {
        super.init()
        requestAuthorization()
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("❌ HealthKit not available on this device")
            return
        }
        
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let heartRateVariabilityType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        
        let typesToRead: Set<HKObjectType> = [heartRateType, heartRateVariabilityType]
        
        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { [weak self] success, error in
            DispatchQueue.main.async {
                self?.isAuthorized = success
                if let error = error {
                    print("❌ HealthKit authorization error: \(error.localizedDescription)")
                } else if success {
                    print("✅ HealthKit authorized")
                    self?.startBackgroundHeartRateQuery()
                }
            }
        }
    }
    
    // MARK: - Continuous Monitoring
    
    func startContinuousMonitoring() {
        guard isAuthorized else {
            print("❌ Cannot start monitoring - not authorized")
            return
        }
        
        // Create workout configuration for background heart rate monitoring
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .unknown
        
        do {
            // Create workout session (allows background heart rate access)
            workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            workoutSession?.delegate = self
            
            // Create live workout builder
            builder = workoutSession?.associatedWorkoutBuilder()
            builder?.delegate = self
            builder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            
            // Start the session
            workoutSession?.startActivity(with: Date())
            builder?.beginCollection(withStart: Date()) { success, error in
                DispatchQueue.main.async {
                    if success {
                        print("✅ Continuous heart rate monitoring started")
                    } else {
                        print("❌ Failed to start monitoring: \(error?.localizedDescription ?? "Unknown error")")
                    }
                }
            }
            
        } catch {
            print("❌ Failed to create workout session: \(error.localizedDescription)")
        }
    }
    
    func stopContinuousMonitoring() {
        builder?.endCollection(withEnd: Date()) { success, error in
            DispatchQueue.main.async {
                if success {
                    print("✅ Heart rate collection ended")
                } else {
                    print("❌ Error ending collection: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
        
        workoutSession?.end()
        workoutSession = nil
        builder = nil
        
        print("⏹️ Continuous monitoring stopped")
    }
    
    // MARK: - Authentication Capture
    
    func startAuthenticationCapture(duration: TimeInterval, completion: @escaping ([HeartRateSample]) -> Void) {
        guard !isCapturing else {
            print("❌ Already capturing")
            return
        }
        
        captureDuration = duration
        captureCompletion = completion
        captureStartTime = Date()
        isCapturing = true
        captureProgress = 0.0
        heartRateSamples.removeAll()
        
        // Start intensive monitoring for authentication
        startIntensiveHeartRateCapture()
        
        // Progress timer
        captureTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.updateCaptureProgress()
        }
        
        print("🔐 Authentication capture started for \(duration) seconds")
    }
    
    private func startIntensiveHeartRateCapture() {
        // Use workout session for intensive capture
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .unknown
        
        do {
            workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            workoutSession?.delegate = self
            
            builder = workoutSession?.associatedWorkoutBuilder()
            builder?.delegate = self
            builder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            
            workoutSession?.startActivity(with: Date())
            builder?.beginCollection(withStart: Date()) { success, error in
                if !success {
                    print("❌ Failed to start intensive capture: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
            
        } catch {
            print("❌ Failed to create authentication session: \(error.localizedDescription)")
        }
    }
    
    private func updateCaptureProgress() {
        guard let startTime = captureStartTime else { return }
        
        let elapsed = Date().timeIntervalSince(startTime)
        captureProgress = min(elapsed / captureDuration, 1.0)
        
        if elapsed >= captureDuration {
            finishCapture()
        }
    }
    
    private func finishCapture() {
        isCapturing = false
        captureTimer?.invalidate()
        captureTimer = nil
        
        // Stop workout session
        builder?.endCollection(withEnd: Date()) { _, _ in }
        workoutSession?.end()
        workoutSession = nil
        builder = nil
        
        print("✅ Authentication capture complete - \(heartRateSamples.count) samples")
        captureCompletion?(heartRateSamples)
        captureCompletion = nil
    }
    
    // MARK: - Background Heart Rate Query
    
    private func startBackgroundHeartRateQuery() {
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        
        // Query for real-time updates
        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: nil,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, error in
            self?.processHeartRateSamples(samples as? [HKQuantitySample] ?? [])
        }
        
        // Set update handler for real-time updates
        query.updateHandler = { [weak self] _, samples, _, _, error in
            self?.processHeartRateSamples(samples as? [HKQuantitySample] ?? [])
        }
        
        healthStore.execute(query)
    }
    
    private func processHeartRateSamples(_ samples: [HKQuantitySample]) {
        let newSamples = samples.map { sample in
            HeartRateSample(
                value: sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute())),
                timestamp: sample.startDate
            )
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update current heart rate
            if let latest = newSamples.last {
                self.currentHeartRate = latest.value
            }
            
            // Add to capture if active
            if self.isCapturing {
                self.heartRateSamples.append(contentsOf: newSamples)
            }
            
            // Add to recent samples for HRV calculation
            self.recentSamples.append(contentsOf: newSamples)
            if self.recentSamples.count > self.maxRecentSamples {
                self.recentSamples = Array(self.recentSamples.suffix(self.maxRecentSamples))
            }
            
            // Update HRV metrics
            self.updateHRVMetrics()
        }
    }
    
    // MARK: - HRV Calculations
    
    private func updateHRVMetrics() {
        guard recentSamples.count >= 10 else { return }
        
        let rrIntervals = calculateRRIntervals(from: recentSamples)
        currentRMSSD = calculateRMSSD(rrIntervals: rrIntervals)
        currentSDNN = calculateSDNN(rrIntervals: rrIntervals)
    }
    
    private func calculateRRIntervals(from samples: [HeartRateSample]) -> [Double] {
        return samples.compactMap { sample in
            guard sample.value > 0 else { return nil }
            return 60.0 / sample.value * 1000.0 // Convert BPM to RR interval in ms
        }
    }
    
    private func calculateRMSSD(rrIntervals: [Double]) -> Double {
        guard rrIntervals.count > 1 else { return 0.0 }
        
        let differences = zip(rrIntervals, rrIntervals.dropFirst()).map { abs($0.1 - $0.0) }
        let squaredDifferences = differences.map { $0 * $0 }
        let meanSquaredDifference = squaredDifferences.reduce(0, +) / Double(squaredDifferences.count)
        
        return sqrt(meanSquaredDifference)
    }
    
    private func calculateSDNN(rrIntervals: [Double]) -> Double {
        guard rrIntervals.count > 1 else { return 0.0 }
        
        let mean = rrIntervals.reduce(0, +) / Double(rrIntervals.count)
        let squaredDifferences = rrIntervals.map { ($0 - mean) * ($0 - mean) }
        let variance = squaredDifferences.reduce(0, +) / Double(squaredDifferences.count - 1)
        
        return sqrt(variance)
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchHeartRateService: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        DispatchQueue.main.async {
            print("🏃 Workout session state changed to: \(toState.rawValue)")
        }
    }
    
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            print("❌ Workout session failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchHeartRateService: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        // Process collected heart rate data
        for type in collectedTypes {
            if type == HKQuantityType.quantityType(forIdentifier: .heartRate) {
                let statistics = workoutBuilder.statistics(for: type)
                if let heartRateStats = statistics {
                    DispatchQueue.main.async { [weak self] in
                        if let averageHR = heartRateStats.averageQuantity() {
                            let bpm = averageHR.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
                            self?.currentHeartRate = bpm
                        }
                    }
                }
            }
        }
    }
    
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Handle workout events if needed
    }
}

// MARK: - Watch Connectivity Service (Watch Side)

class WatchConnectivityService: NSObject, ObservableObject {
    static let shared = WatchConnectivityService()
    
    private let session = WCSession.default
    @Published var isReachable = false
    @Published var isActivated = false
    
    private override init() {
        super.init()
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }
    }
    
    func sendMessage(type: String, data: [String: Any]) {
        guard session.activationState == .activated && session.isReachable else {
            print("❌ iPhone not reachable")
            return
        }
        
        var message = data
        message["type"] = type
        message["timestamp"] = Date().timeIntervalSince1970
        
        session.sendMessage(message, replyHandler: { reply in
            print("✅ Message sent successfully: \(reply)")
        }, errorHandler: { error in
            print("❌ Failed to send message: \(error.localizedDescription)")
        })
    }
    
    func sendHeartRateUpdate(heartRate: Double) {
        sendMessage(
            type: "heartRateUpdate",
            data: [
                "heartRate": heartRate,
                "source": "watch"
            ]
        )
    }
    
    func sendAuthenticationResult(success: Bool, confidence: Double, method: String) {
        sendMessage(
            type: "authenticationResult",
            data: [
                "result": success ? "success" : "failure",
                "confidence": confidence,
                "method": method
            ]
        )
    }
}

extension WatchConnectivityService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isActivated = activationState == .activated
            if let error = error {
                print("❌ Watch session activation error: \(error.localizedDescription)")
            }
        }
    }
    
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        print("⌚ Watch received message: \(message)")
        // Handle messages from iPhone
    }
}

// MARK: - Workout Manager (Simplified)

class WorkoutManager: NSObject, ObservableObject {
    @Published var running = false
    
    func togglePause() {
        running.toggle()
    }
}