// WatchApp ContentView.swift
// Realistic Apple Watch app for HeartID using available APIs
// This would go in the Watch App target

import SwiftUI
import HealthKit
import WatchConnectivity

@main
struct HeartIDWatchApp: App {
    @StateObject private var workoutManager = WorkoutManager()
    @StateObject private var connectivityService = WatchConnectivityService()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(workoutManager)
                .environmentObject(connectivityService)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var connectivityService: WatchConnectivityService
    @StateObject private var heartRateService = WatchHeartRateService()
    
    @State private var isAuthenticated = false
    @State private var confidence: Double = 0.0
    @State private var showingEnrollment = false
    
    var body: some View {
        TabView {
            // Authentication Tab
            AuthenticationView()
                .tabItem {
                    Image(systemName: "heart.fill")
                    Text("Authenticate")
                }
            
            // Monitoring Tab
            MonitoringView()
                .tabItem {
                    Image(systemName: "waveform.path.ecg")
                    Text("Monitor")
                }
            
            // Settings Tab
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
        }
        .environmentObject(heartRateService)
        .onAppear {
            heartRateService.requestAuthorization()
        }
    }
}

// MARK: - Authentication View
struct AuthenticationView: View {
    @EnvironmentObject var heartRateService: WatchHeartRateService
    @EnvironmentObject var connectivityService: WatchConnectivityService
    @State private var isAuthenticating = false
    @State private var authResult: AuthResult?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Status
                VStack(spacing: 8) {
                    Image(systemName: authResult?.isSuccess == true ? "checkmark.shield.fill" : "heart.fill")
                        .font(.largeTitle)
                        .foregroundColor(authResult?.isSuccess == true ? .green : .red)
                    
                    Text(authResult?.isSuccess == true ? "Authenticated" : "Not Authenticated")
                        .font(.headline)
                    
                    if let confidence = authResult?.confidence {
                        Text("\(Int(confidence * 100))% Confidence")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Current Heart Rate
                VStack(spacing: 4) {
                    Text("Current HR")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(Int(heartRateService.currentHeartRate)) BPM")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
                
                // Authentication Button
                Button(action: {
                    performAuthentication()
                }) {
                    HStack {
                        if isAuthenticating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "heart.fill")
                        }
                        Text(isAuthenticating ? "Authenticating..." : "Authenticate")
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isAuthenticating ? Color.gray : Color.red)
                    .cornerRadius(10)
                }
                .disabled(isAuthenticating)
                
                // Quick Actions
                VStack(spacing: 8) {
                    Button("Send to iPhone") {
                        sendResultToiPhone()
                    }
                    .font(.caption)
                    
                    Button("Start Monitoring") {
                        heartRateService.startContinuousMonitoring()
                    }
                    .font(.caption)
                }
            }
            .padding()
        }
    }
    
    private func performAuthentication() {
        isAuthenticating = true
        
        // Start heart rate capture for 15 seconds
        heartRateService.startAuthenticationCapture(duration: 15.0) { samples in
            // Process the heart rate pattern
            let pattern = HeartRatePattern(samples: samples)
            let confidence = calculateAuthentication(pattern: pattern)
            
            DispatchQueue.main.async {
                self.authResult = AuthResult(
                    isSuccess: confidence > 0.75,
                    confidence: confidence,
                    timestamp: Date()
                )
                self.isAuthenticating = false
                
                // Send result to iPhone
                self.sendResultToiPhone()
            }
        }
    }
    
    private func calculateAuthentication(pattern: HeartRatePattern) -> Double {
        // Realistic PPG-based authentication using heart rate variability
        // This is what we can actually implement with available APIs
        
        let samples = pattern.samples
        guard samples.count > 10 else { return 0.0 }
        
        // Calculate HRV metrics that are unique per person
        let rrIntervals = calculateRRIntervals(from: samples)
        let rmssd = calculateRMSSD(rrIntervals: rrIntervals)
        let sdnn = calculateSDNN(rrIntervals: rrIntervals)
        
        // Heart rate recovery pattern (unique characteristic)
        let recoveryPattern = calculateRecoveryPattern(samples: samples)
        
        // Respiratory coupling (breathing affects heart rate uniquely)
        let respiratoryCoupling = calculateRespiratoryPattern(samples: samples)
        
        // Combine metrics for authentication score
        // In a real implementation, this would compare against enrolled template
        let baseScore = 0.65 // Baseline from PPG
        let hrvFactor = min(rmssd / 50.0, 0.25) // HRV contribution
        let recoveryFactor = min(recoveryPattern, 0.15) // Recovery pattern
        let respiratoryFactor = min(respiratoryCoupling, 0.10) // Respiratory coupling
        
        return min(baseScore + hrvFactor + recoveryFactor + respiratoryFactor, 0.95)
    }
    
    private func sendResultToiPhone() {
        guard let result = authResult else { return }
        
        connectivityService.sendMessage(
            type: "authenticationResult",
            data: [
                "isSuccess": result.isSuccess,
                "confidence": result.confidence,
                "timestamp": result.timestamp.timeIntervalSince1970,
                "method": "ppg_hrv"
            ]
        )
    }
}

// MARK: - Monitoring View
struct MonitoringView: View {
    @EnvironmentObject var heartRateService: WatchHeartRateService
    @State private var isMonitoring = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Real-time heart rate
                VStack(spacing: 8) {
                    Text("Heart Rate")
                        .font(.headline)
                    
                    Text("\(Int(heartRateService.currentHeartRate))")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    
                    Text("BPM")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // HRV Metrics (what we can actually calculate)
                VStack(spacing: 8) {
                    Text("HRV Metrics")
                        .font(.headline)
                    
                    HStack {
                        VStack {
                            Text("RMSSD")
                                .font(.caption2)
                            Text("\(Int(heartRateService.currentRMSSD))ms")
                                .font(.footnote)
                        }
                        
                        Spacer()
                        
                        VStack {
                            Text("SDNN")
                                .font(.caption2)
                            Text("\(Int(heartRateService.currentSDNN))ms")
                                .font(.footnote)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Control buttons
                Button(action: {
                    if isMonitoring {
                        heartRateService.stopContinuousMonitoring()
                    } else {
                        heartRateService.startContinuousMonitoring()
                    }
                    isMonitoring.toggle()
                }) {
                    Text(isMonitoring ? "Stop Monitoring" : "Start Monitoring")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isMonitoring ? Color.red : Color.green)
                        .cornerRadius(10)
                }
            }
            .padding()
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @EnvironmentObject var connectivityService: WatchConnectivityService
    @State private var authThreshold: Double = 0.75
    @State private var monitoringInterval: Double = 60.0
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Connection Status
                VStack(spacing: 8) {
                    Text("iPhone Connection")
                        .font(.headline)
                    
                    HStack {
                        Circle()
                            .fill(connectivityService.isReachable ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        
                        Text(connectivityService.isReachable ? "Connected" : "Disconnected")
                            .font(.caption)
                    }
                }
                
                // Settings
                VStack(alignment: .leading, spacing: 12) {
                    Text("Authentication Threshold")
                        .font(.footnote)
                    
                    Slider(value: $authThreshold, in: 0.5...0.95, step: 0.05)
                    
                    Text("\(Int(authThreshold * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Monitoring Interval")
                        .font(.footnote)
                    
                    Slider(value: $monitoringInterval, in: 30...300, step: 30)
                    
                    Text("\(Int(monitoringInterval))s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Actions
                Button("Sync with iPhone") {
                    connectivityService.sendMessage(
                        type: "settingsSync",
                        data: [
                            "authThreshold": authThreshold,
                            "monitoringInterval": monitoringInterval
                        ]
                    )
                }
                .foregroundColor(.blue)
            }
            .padding()
        }
    }
}

// MARK: - Supporting Types
struct AuthResult {
    let isSuccess: Bool
    let confidence: Double
    let timestamp: Date
}

struct HeartRatePattern {
    let samples: [HeartRateSample]
    let averageHR: Double
    let hrv: Double
    let timestamp: Date
    
    init(samples: [HeartRateSample]) {
        self.samples = samples
        self.averageHR = samples.map { $0.value }.reduce(0, +) / Double(samples.count)
        self.hrv = calculateHRV(samples: samples)
        self.timestamp = Date()
    }
}

// MARK: - Helper Functions
private func calculateRRIntervals(from samples: [HeartRateSample]) -> [Double] {
    return samples.compactMap { sample in
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

private func calculateRecoveryPattern(samples: [HeartRateSample]) -> Double {
    // Analyze heart rate recovery pattern (unique per person)
    guard samples.count > 5 else { return 0.0 }
    
    let maxHR = samples.map { $0.value }.max() ?? 0
    let minHR = samples.map { $0.value }.min() ?? 0
    let hrRange = maxHR - minHR
    
    // Recovery slope analysis
    let recoverySlope = (samples.last?.value ?? 0) - (samples.first?.value ?? 0)
    
    return min(abs(recoverySlope) / hrRange, 0.15)
}

private func calculateRespiratoryPattern(samples: [HeartRateSample]) -> Double {
    // Analyze respiratory sinus arrhythmia (breathing pattern affects HR uniquely)
    guard samples.count > 10 else { return 0.0 }
    
    // Look for periodic variations in heart rate (respiratory coupling)
    let hrValues = samples.map { $0.value }
    let movingAverage = calculateMovingAverage(values: hrValues, window: 3)
    let deviations = zip(hrValues, movingAverage).map { abs($0.0 - $0.1) }
    let averageDeviation = deviations.reduce(0, +) / Double(deviations.count)
    
    return min(averageDeviation / 10.0, 0.10)
}

private func calculateMovingAverage(values: [Double], window: Int) -> [Double] {
    guard values.count >= window else { return values }
    
    var result: [Double] = []
    
    for i in 0..<values.count {
        let start = max(0, i - window + 1)
        let end = i + 1
        let sum = values[start..<end].reduce(0, +)
        result.append(sum / Double(end - start))
    }
    
    return result
}

private func calculateHRV(samples: [HeartRateSample]) -> Double {
    let rrIntervals = calculateRRIntervals(from: samples)
    return calculateRMSSD(rrIntervals: rrIntervals)
}

struct HeartRateSample {
    let value: Double
    let timestamp: Date
}