// CardiacSignature.swift
// CardiacID Watch App
//
// Compact, transport-ready representation of a cardiac biometric reading.
// Created by CardiacProcessor from raw HealthKit data.
// Sent to iPhone via WatchConnectivity, then forwarded to the backend
// for identity verification against the enrolled template.

import Foundation

struct CardiacSignature: Codable, Sendable {
    /// Heart rate variability — RMSSD of successive RR interval differences (seconds).
    let hrv: Double
    /// Resting heart rate at time of capture (BPM).
    let restingHR: Double
    /// 256-element cardiac waveform feature vector (ECG signature or PPG-derived).
    let waveformFeatures: [Double]
    /// Timestamp of the biometric reading on the Watch.
    let timestamp: Date

    // MARK: - Extended metadata (populated when available)

    /// SDNN — standard deviation of NN intervals (seconds).
    let sdnn: Double
    /// Signal-to-noise ratio of the ECG in dB (0 if PPG-only).
    let signalNoiseRatio: Double
    /// Capture method: "ecg" or "ppg"
    let method: String
    /// Beat-to-beat intervals used for HRV (seconds).
    let beatIntervals: [Double]
    /// Recent heart rate samples (BPM) for rhythm analysis.
    let recentHeartRates: [Double]
    /// Whether the Watch detected the user's wrist during capture.
    let wristDetected: Bool

    // MARK: - Quality

    /// Overall quality score (0–1). Derived from SNR, sample count, wrist detection.
    var qualityScore: Double {
        var score = 1.0
        if !wristDetected { score *= 0.3 }
        if signalNoiseRatio < 15.0 && method == "ecg" { score *= 0.7 }
        if beatIntervals.count < 10 { score *= Double(beatIntervals.count) / 10.0 }
        return min(max(score, 0.0), 1.0)
    }

    // MARK: - Serialisation for WatchConnectivity

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "hrv": hrv,
            "restingHR": restingHR,
            "waveformFeatures": waveformFeatures,
            "timestamp": timestamp.timeIntervalSince1970,
            "sdnn": sdnn,
            "signalNoiseRatio": signalNoiseRatio,
            "method": method,
            "beatIntervals": beatIntervals,
            "recentHeartRates": recentHeartRates,
            "wristDetected": wristDetected
        ]
        // Truncate waveform for large payloads (WC message limit ~65 KB)
        if let json = try? JSONEncoder().encode(self), json.count > 50_000 {
            dict["waveformFeatures"] = Array(waveformFeatures.prefix(128))
        }
        return dict
    }

    static func fromDictionary(_ dict: [String: Any]) -> CardiacSignature? {
        guard let hrv = dict["hrv"] as? Double,
              let restingHR = dict["restingHR"] as? Double,
              let features = dict["waveformFeatures"] as? [Double],
              let ts = dict["timestamp"] as? TimeInterval else { return nil }
        return CardiacSignature(
            hrv: hrv, restingHR: restingHR, waveformFeatures: features,
            timestamp: Date(timeIntervalSince1970: ts),
            sdnn: dict["sdnn"] as? Double ?? 0,
            signalNoiseRatio: dict["signalNoiseRatio"] as? Double ?? 0,
            method: dict["method"] as? String ?? "ppg",
            beatIntervals: dict["beatIntervals"] as? [Double] ?? [],
            recentHeartRates: dict["recentHeartRates"] as? [Double] ?? [],
            wristDetected: dict["wristDetected"] as? Bool ?? true
        )
    }
}
