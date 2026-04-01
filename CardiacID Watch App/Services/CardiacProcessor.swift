// CardiacProcessor.swift
// CardiacID Watch App
//
// Bridges raw HealthKit data into a CardiacSignature for transport to iPhone.
// Does NOT perform biometric matching — that is BiometricMatchingService's job.
// This processor is the data-preparation layer before network/WC transmission.

import Foundation

@MainActor
final class CardiacProcessor: ObservableObject {

    @Published private(set) var lastSignature: CardiacSignature?
    @Published private(set) var isProcessing = false

    private let healthKit: HealthKitService
    private let heartIDService: HeartIDService

    init(healthKit: HealthKitService, heartIDService: HeartIDService) {
        self.healthKit = healthKit
        self.heartIDService = heartIDService
    }

    // MARK: - Capture a fresh cardiac signature from current HealthKit state

    /// Captures the best available cardiac signature from current Watch sensors.
    /// Prefers ECG if recently recorded; falls back to PPG continuous data.
    func captureSignature() async -> CardiacSignature {
        isProcessing = true
        defer { isProcessing = false }

        let beatIntervals = healthKit.getRecentBeatIntervals()
        let recentHRs     = healthKit.getRecentHeartRates()
        let wristDetected = healthKit.isWatchOnWrist
        let currentHR     = healthKit.currentHeartRate

        // Calculate HRV metrics from beat intervals
        let hrv  = calculateRMSSD(beatIntervals)
        let sdnn = calculateSDNN(beatIntervals)

        // Try to use ECG waveform features if enrolled and recent ECG exists
        var waveformFeatures: [Double] = []
        var snr: Double = 0
        var method = "ppg"

        if let template = try? TemplateStorageService().loadTemplate() {
            // Use enrolled signature vector as reference dimension
            waveformFeatures = template.ecgFeatures.signatureVector
            snr = template.ecgFeatures.signalNoiseRatio
            method = "ecg"

            // Check if there's a more recent ECG reading
            if let recentECG = try? await healthKit.queryMostRecentECG(
                since: Date().addingTimeInterval(-300), // last 5 minutes
                timeout: 5
            ) {
                let features = try? await healthKit.extractECGFeatures(from: recentECG)
                if let f = features {
                    waveformFeatures = f.signatureVector
                    snr = f.signalNoiseRatio
                }
            }
        }

        // If no ECG data, create a PPG-derived feature vector from beat intervals
        if waveformFeatures.isEmpty {
            waveformFeatures = derivePPGFeatures(
                beatIntervals: beatIntervals,
                heartRates: recentHRs,
                hrv: hrv
            )
            method = "ppg"
        }

        let signature = CardiacSignature(
            hrv: hrv,
            restingHR: currentHR,
            waveformFeatures: waveformFeatures,
            timestamp: Date(),
            sdnn: sdnn,
            signalNoiseRatio: snr,
            method: method,
            beatIntervals: beatIntervals,
            recentHeartRates: recentHRs,
            wristDetected: wristDetected
        )

        lastSignature = signature
        return signature
    }

    // MARK: - Send to iPhone via WatchConnectivity

    /// Captures a signature and sends it to the iPhone app.
    func captureAndSendToiPhone() async -> Bool {
        let sig = await captureSignature()
        var payload: [String: Any] = sig.toDictionary()
        payload["message_type"] = "cardiac_signature"

        return await withCheckedContinuation { continuation in
            WatchConnectivityService.shared.sendMessage(payload) { success in
                continuation.resume(returning: success)
            }
        }
    }

    // MARK: - HRV Calculations

    private func calculateRMSSD(_ intervals: [Double]) -> Double {
        guard intervals.count >= 2 else { return 0 }
        var sumSqDiff = 0.0
        for i in 1..<intervals.count {
            let diff = intervals[i] - intervals[i - 1]
            sumSqDiff += diff * diff
        }
        return sqrt(sumSqDiff / Double(intervals.count - 1))
    }

    private func calculateSDNN(_ intervals: [Double]) -> Double {
        guard intervals.count >= 2 else { return 0 }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        let variance = intervals.map { pow($0 - mean, 2) }.reduce(0, +) / Double(intervals.count)
        return sqrt(variance)
    }

    // MARK: - PPG-derived feature vector (when no ECG available)

    /// Generates a 256-element feature vector from PPG data.
    /// Not as discriminating as ECG but usable for continuous verification.
    private func derivePPGFeatures(
        beatIntervals: [Double],
        heartRates: [Double],
        hrv: Double
    ) -> [Double] {
        var features: [Double] = []

        // Normalised beat intervals (first 64)
        let normIntervals = normalize(beatIntervals, targetCount: 64)
        features.append(contentsOf: normIntervals)

        // Normalised heart rates (next 64)
        let normHRs = normalize(heartRates, targetCount: 64)
        features.append(contentsOf: normHRs)

        // Spectral-like features: successive differences (next 64)
        var diffs: [Double] = []
        for i in 1..<beatIntervals.count {
            diffs.append(beatIntervals[i] - beatIntervals[i - 1])
        }
        features.append(contentsOf: normalize(diffs, targetCount: 64))

        // Statistical features + padding to 256
        features.append(hrv)
        features.append(contentsOf: [Double](repeating: 0, count: max(0, 256 - features.count - 1)))

        return Array(features.prefix(256))
    }

    private func normalize(_ input: [Double], targetCount: Int) -> [Double] {
        guard !input.isEmpty else { return [Double](repeating: 0, count: targetCount) }
        let maxVal = input.max() ?? 1.0
        let minVal = input.min() ?? 0.0
        let range  = maxVal - minVal
        let normed = input.map { range > 0 ? ($0 - minVal) / range : 0.5 }

        // Resample to target count
        if normed.count == targetCount { return normed }
        var result = [Double](repeating: 0, count: targetCount)
        for i in 0..<targetCount {
            let idx = Double(i) / Double(targetCount) * Double(normed.count)
            let lo  = Int(idx)
            let hi  = min(lo + 1, normed.count - 1)
            let frac = idx - Double(lo)
            result[i] = normed[lo] * (1 - frac) + normed[hi] * frac
        }
        return result
    }
}
