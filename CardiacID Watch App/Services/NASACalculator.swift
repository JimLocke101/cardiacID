//
//  NASACalculator.swift
//  HeartID Watch App
//
//  NASA HeartBeatID Algorithm Implementation
//  Based on NASA's biometric verification/identification method
//  Implements statistical modeling with Gaussian Mixture Models (GMM)
//

import Foundation
import Accelerate

// MARK: - NASA Algorithm Configuration
public struct NASAConfig {
    public var minBeatsForVerify: Int = 15
    public var panTompkinsBandpass: (low: Double, high: Double) = (5.0, 15.0)
    public var panTompkinsIntegrationWindow: TimeInterval = 0.150
    public var refractory: TimeInterval = 0.200
    public var votePassRatio: Double = 0.7
    public var gmmThreshold: Double = -20.0
    public var enrollmentBeats: Int = 60
    public var gmmComponents: Int = 3
    public var maxGMMIterations: Int = 50
    
    public init() {}
}

// MARK: - NASA Data Structures
public struct NASAGMMParameters: Codable, Sendable {
    public var weights: [Double]
    public var means: [[Double]]
    public var covDiag: [[Double]]
    
    public init(weights: [Double], means: [[Double]], covDiag: [[Double]]) {
        self.weights = weights
        self.means = means
        self.covDiag = covDiag
    }
}

public struct NASAUserModel: Codable, Sendable {
    public var featureMean: [Double]
    public var featureStd: [Double]
    public var featureRange: [Double]
    public var gmm: NASAGMMParameters
    public var qualityThreshold: Double = 0.8
    
    public init(featureMean: [Double], featureStd: [Double], featureRange: [Double], gmm: NASAGMMParameters) {
        self.featureMean = featureMean
        self.featureStd = featureStd
        self.featureRange = featureRange
        self.gmm = gmm
    }
}

public struct NASAAuthResult: Sendable {
    public let accepted: Bool
    public let votes: Int
    public let totalVotes: Int
    public let meanLL: Double
    public let confidence: Double
    public let qualityScore: Double
    
    public init(accepted: Bool, votes: Int, totalVotes: Int, meanLL: Double, confidence: Double, qualityScore: Double) {
        self.accepted = accepted
        self.votes = votes
        self.totalVotes = totalVotes
        self.meanLL = meanLL
        self.confidence = confidence
        self.qualityScore = qualityScore
    }
}

// MARK: - NASA Heart Pattern Calculator
public class NASACalculator {
    private let config: NASAConfig
    private let processor = NASAECGProcessor()
    private let extractor = NASAFeatureExtractor()
    private let auth = NASAAuthEngine()
    
    public init(config: NASAConfig = NASAConfig()) {
        self.config = config
    }
    
    // MARK: - Public API
    public func preprocessECG(series: [Double], fs: Double) throws -> [Double] {
        return try processor.preprocessECG(series: series, fs: fs, config: config)
    }
    
    public func detectRPeaks(ecg: [Double], fs: Double) throws -> [Int] {
        return try processor.detectRPeaks(ecg: ecg, fs: fs, config: config)
    }
    
    public func segmentBeats(ecg: [Double], rPeaks: [Int], fs: Double, pre: Double = 0.2, post: Double = 0.4) -> [[Double]] {
        return processor.segmentBeats(ecg: ecg, rPeaks: rPeaks, fs: fs, pre: pre, post: post)
    }
    
    public func extractFeatures(from beats: [[Double]], fs: Double) -> [[Double]] {
        return extractor.extractFeatures(from: beats, fs: fs)
    }
    
    public func authenticate(features: [[Double]], model: NASAUserModel) -> NASAAuthResult {
        return auth.authenticate(features: features, model: model, config: config)
    }
    
    public func enroll(from featureBatches: [[[Double]]]) -> NASAUserModel {
        let allFeats = featureBatches.flatMap { $0 }
        let D = allFeats.first?.count ?? 0
        
        // Calculate feature statistics
        var mu = Array(repeating: 0.0, count: D)
        var sd = Array(repeating: 0.0, count: D)
        
        for d in 0..<D {
            let col = allFeats.map { $0[d] }
            mu[d] = col.mean()
            sd[d] = max(col.std(), 1e-6)
        }
        
        // Calculate feature ranges (NASA style)
        let r = sd.map { 2.5 * $0 + 1e-6 }
        
        // Normalize features for GMM training
        let z = allFeats.map { vDSP.divide(vDSP.subtract($0, mu), sd) }
        
        // Fit GMM
        let gmm = NASAGMM.fit(dataset: z, components: config.gmmComponents, maxIters: config.maxGMMIterations)
        
        return NASAUserModel(
            featureMean: mu,
            featureStd: sd,
            featureRange: r,
            gmm: gmm.parameters
        )
    }
    
    public func calculateQualityScore(beats: [[Double]]) -> Double {
        guard !beats.isEmpty else { return 0.0 }
        
        var qualityScores: [Double] = []
        
        for beat in beats {
            // Calculate beat quality based on:
            // 1. Signal-to-noise ratio
            // 2. Morphology consistency
            // 3. Amplitude stability
            
            let amplitude = beat.max() ?? 0.0
            let noise = calculateNoiseLevel(beat)
            let snr = amplitude / max(noise, 1e-6)
            
            // Morphology consistency (variance in normalized beat)
            let normalizedBeat = normalizeBeat(beat)
            let morphologyVar = normalizedBeat.variance()
            
            // Quality score (0-1)
            let quality = min(1.0, snr / 10.0) * (1.0 - min(1.0, morphologyVar))
            qualityScores.append(quality)
        }
        
        return qualityScores.mean()
    }
    
    // MARK: - Private Helper Methods
    private func calculateNoiseLevel(_ signal: [Double]) -> Double {
        guard signal.count > 10 else { return 0.0 }
        
        // Use first and last 10% of signal as noise estimate
        let noiseLength = max(1, signal.count / 10)
        let noiseSamples = Array(signal.prefix(noiseLength)) + Array(signal.suffix(noiseLength))
        return noiseSamples.std()
    }
    
    private func normalizeBeat(_ beat: [Double]) -> [Double] {
        let mean = beat.mean()
        let std = max(beat.std(), 1e-6)
        return beat.map { ($0 - mean) / std }
    }
}

// MARK: - NASA ECG Processor
final class NASAECGProcessor {
    func preprocessECG(series: [Double], fs: Double, config: NASAConfig) throws -> [Double] {
        var x = series
        
        // High-pass filter to remove baseline wander
        x = butterworthFilter(x, fs: fs, cutoff: 0.5, type: .high)
        
        // Band-pass filter for QRS detection (Pan-Tompkins)
        x = bandpass(x, fs: fs, low: config.panTompkinsBandpass.low, high: config.panTompkinsBandpass.high)
        
        return x
    }
    
    func detectRPeaks(ecg: [Double], fs: Double, config: NASAConfig) throws -> [Int] {
        // Pan-Tompkins algorithm
        let d = derivative(ecg, fs: fs)
        let s = vDSP.multiply(d, d)
        let win = Int(config.panTompkinsIntegrationWindow * fs)
        let m = movingAverage(s, window: max(win, 1))
        let refractorySamples = Int(config.refractory * fs)
        
        return adaptivePeaks(m, refractory: refractorySamples)
    }
    
    func segmentBeats(ecg: [Double], rPeaks: [Int], fs: Double, pre: Double, post: Double) -> [[Double]] {
        let preS = Int(pre * fs)
        let postS = Int(post * fs)
        var beats: [[Double]] = []
        
        for r in rPeaks {
            let a = max(0, r - preS)
            let b = min(ecg.count, r + postS)
            
            if b - a == preS + postS {
                beats.append(Array(ecg[a..<b]))
            }
        }
        
        // Normalize and resample beats
        beats = beats.map { beat in
            let mu = beat.mean()
            let sd = max(beat.std(), 1e-6)
            let z = beat.map { ($0 - mu) / sd }
            return resample(z, to: 256)
        }
        
        return beats
    }
    
    // MARK: - Filtering Methods
    enum FilterType { case low, high }
    
    /// Second-order Butterworth IIR filter (bilinear transform).
    ///
    /// Implements the standard bilinear-transformed 2nd-order Butterworth
    /// transfer function, which is the minimum required for Pan-Tompkins
    /// QRS detection (the original paper uses cascaded integer-coefficient
    /// filters, but a 2nd-order Butterworth is the closest continuous-time
    /// equivalent suitable for variable sampling rates like Apple Watch ECG).
    ///
    /// Reference: Butterworth, S. "On the Theory of Filter Amplifiers",
    ///            Wireless Engineer, vol. 7, 1930, pp. 536–541.
    func butterworthFilter(_ x: [Double], fs: Double, cutoff: Double, type: FilterType) -> [Double] {
        guard x.count > 2 else { return x }

        // Pre-warp the cutoff frequency for the bilinear transform
        let wc = tan(Double.pi * cutoff / fs)
        let wc2 = wc * wc
        let sqrt2 = 1.4142135623730951 // sqrt(2) — Butterworth Q factor

        // 2nd-order Butterworth coefficients via bilinear transform
        let k: Double
        let a0, a1, a2, b1, b2: Double

        switch type {
        case .low:
            k = 1.0 / (1.0 + sqrt2 * wc + wc2)
            a0 = wc2 * k
            a1 = 2.0 * a0
            a2 = a0
            b1 = 2.0 * (wc2 - 1.0) * k
            b2 = (1.0 - sqrt2 * wc + wc2) * k
        case .high:
            k = 1.0 / (1.0 + sqrt2 * wc + wc2)
            a0 = k
            a1 = -2.0 * k
            a2 = k
            b1 = 2.0 * (wc2 - 1.0) * k
            b2 = (1.0 - sqrt2 * wc + wc2) * k
        }

        // Direct Form II transposed
        var y = Array(repeating: 0.0, count: x.count)
        var z1 = 0.0, z2 = 0.0
        for i in 0..<x.count {
            let xi = x[i]
            y[i] = a0 * xi + z1
            z1 = a1 * xi - b1 * y[i] + z2
            z2 = a2 * xi - b2 * y[i]
        }

        return y
    }
    
    func bandpass(_ x: [Double], fs: Double, low: Double, high: Double) -> [Double] {
        let lp = butterworthFilter(x, fs: fs, cutoff: high, type: .low)
        let bp = butterworthFilter(lp, fs: fs, cutoff: low, type: .high)
        return bp
    }
    
    func derivative(_ x: [Double], fs: Double) -> [Double] {
        let n = x.count
        guard n >= 5 else { return x }
        
        var y = Array(repeating: 0.0, count: n)
        for i in 2..<(n-2) {
            y[i] = (2*x[i+1] + x[i+2] - 2*x[i-1] - x[i-2]) * fs / 8.0
        }
        
        return y
    }
    
    func movingAverage(_ x: [Double], window: Int) -> [Double] {
        guard window > 1 else { return x }
        
        var y = Array(repeating: 0.0, count: x.count)
        var sum = 0.0
        
        for i in 0..<x.count {
            sum += x[i]
            if i >= window {
                sum -= x[i-window]
            }
            y[i] = sum / Double(min(i+1, window))
        }
        
        return y
    }
    
    /// Pan-Tompkins adaptive dual-threshold peak detection.
    ///
    /// Implements the original 1985 algorithm's dual threshold with signal/noise
    /// peak tracking and search-back mechanism for missed beats.
    ///
    /// Reference: Pan & Tompkins, "A Real-Time QRS Detection Algorithm",
    ///            IEEE Trans. Biomed. Eng., BME-32(3), March 1985, pp. 230–236.
    func adaptivePeaks(_ x: [Double], refractory: Int) -> [Int] {
        guard x.count > 2 else { return [] }

        var peaks: [Int] = []

        // Pan-Tompkins dual threshold initialisation
        // SPK = running estimate of signal (QRS) peak level
        // NPK = running estimate of noise peak level
        // Threshold 1 = NPK + 0.25 * (SPK - NPK)
        // Threshold 2 = 0.5 * Threshold 1  (for search-back)
        let initMax = x.max() ?? 1.0
        var SPK = initMax * 0.5   // signal peak estimate
        var NPK = initMax * 0.1   // noise peak estimate
        var thr1 = NPK + 0.25 * (SPK - NPK)
        var thr2 = 0.5 * thr1    // search-back threshold

        var lastPeakIdx = -refractory

        for i in 1..<(x.count - 1) {
            // Local maximum check
            guard x[i] > x[i - 1] && x[i] > x[i + 1] else { continue }

            // Refractory period (200 ms default)
            guard (i - lastPeakIdx) > refractory else { continue }

            if x[i] > thr1 {
                // Classified as signal peak (QRS)
                peaks.append(i)
                SPK = 0.125 * x[i] + 0.875 * SPK  // Pan-Tompkins Eq. (1)
                lastPeakIdx = i
            } else {
                // Classified as noise peak
                NPK = 0.125 * x[i] + 0.875 * NPK  // Pan-Tompkins Eq. (2)
            }

            // Update thresholds — Pan-Tompkins Eq. (3) & (4)
            thr1 = NPK + 0.25 * (SPK - NPK)
            thr2 = 0.5 * thr1
        }

        // Search-back: if RR interval exceeds 166% of running average,
        // look for peaks above thr2 in the missed interval.
        if peaks.count >= 2 {
            var rrIntervals: [Int] = []
            for j in 1..<peaks.count {
                rrIntervals.append(peaks[j] - peaks[j - 1])
            }
            let rrAvg = Double(rrIntervals.reduce(0, +)) / Double(rrIntervals.count)

            var insertions: [(idx: Int, pos: Int)] = []
            for j in 1..<peaks.count {
                let gap = peaks[j] - peaks[j - 1]
                if Double(gap) > 1.66 * rrAvg {
                    // Search back for the highest peak above thr2 in the gap
                    let searchStart = peaks[j - 1] + refractory
                    let searchEnd = peaks[j] - refractory
                    if searchStart < searchEnd {
                        var bestIdx = searchStart
                        var bestVal = x[searchStart]
                        for k in searchStart...searchEnd where k < x.count {
                            if x[k] > bestVal {
                                bestVal = x[k]
                                bestIdx = k
                            }
                        }
                        if bestVal > thr2 {
                            insertions.append((j, bestIdx))
                        }
                    }
                }
            }
            // Insert search-back peaks in reverse order to keep indices valid
            for ins in insertions.reversed() {
                peaks.insert(ins.pos, at: ins.idx)
            }
        }

        return peaks
    }
    
    func resample(_ x: [Double], to M: Int) -> [Double] {
        let N = x.count
        guard N > 1 else { return Array(repeating: x.first ?? 0.0, count: M) }
        
        var out = Array(repeating: 0.0, count: M)
        for m in 0..<M {
            let t = Double(m) * (Double(N-1) / Double(M-1))
            let i = Int(t)
            let frac = t - Double(i)
            out[m] = (1-frac) * x[i] + frac * x[min(i+1, N-1)]
        }
        
        return out
    }
}

// MARK: - NASA Feature Extractor
final class NASAFeatureExtractor {
    func extractFeatures(from beats: [[Double]], fs: Double) -> [[Double]] {
        return beats.map { beat in
            extractBeatFeatures(beat, fs: fs)
        }
    }
    
    /// Extracts a comprehensive feature vector from a single normalised heartbeat.
    ///
    /// NASA HeartBeatID (US Patent 8,924,736 — TOP2-202) specifies "at least 192
    /// statistical parameters" including peak amplitudes, time intervals,
    /// depolarization–repolarization vector angles and lengths from PQRST waves.
    ///
    /// This implementation extracts features in 8 groups to approach that count:
    ///   1. Amplitude (10)          — PQRST peaks and ratios
    ///   2. Temporal (12)           — inter-peak intervals and durations
    ///   3. Morphological (14)      — slopes, widths, areas, curvatures
    ///   4. Energy (8)              — total, per-segment, ratios
    ///   5. Spectral (8)            — band power ratios, dominant frequency
    ///   6. Statistical (12)        — moments, entropy, zero-crossings
    ///   7. Wavelet coefficients (64)— multi-resolution decomposition
    ///   8. Cross-segment (8)       — inter-segment correlations
    /// Total: ~136 features (extensible toward 192 with multi-lead data)
    private func extractBeatFeatures(_ beat: [Double], fs: Double) -> [Double] {
        let N = beat.count
        guard N > 40 else { return Array(repeating: 0, count: 136) }

        let R = beat.max() ?? 0
        let Ridx = beat.firstIndex(of: R) ?? (N / 2)

        // Locate approximate P and T wave regions
        let pRegionEnd   = max(0, Ridx - 15)
        let pRegionStart = max(0, Ridx - 40)
        let tRegionStart = min(N - 1, Ridx + 15)
        let tRegionEnd   = min(N - 1, Ridx + 50)
        let qrsStart     = max(0, Ridx - 10)
        let qrsEnd       = min(N - 1, Ridx + 10)

        let pAmp = pRegionStart < pRegionEnd ? beat[pRegionStart...pRegionEnd].max() ?? 0 : 0
        let tAmp = tRegionStart < tRegionEnd ? beat[tRegionStart...tRegionEnd].max() ?? 0 : 0
        let qAmp = qrsStart < Ridx ? beat[qrsStart..<Ridx].min() ?? 0 : 0
        let sAmp = Ridx < qrsEnd ? beat[(Ridx+1)...qrsEnd].min() ?? 0 : 0

        var f: [Double] = []

        // --- 1. Amplitude features (10) ---
        f.append(R)
        f.append(pAmp)
        f.append(qAmp)
        f.append(sAmp)
        f.append(tAmp)
        f.append(R / max(abs(pAmp), 1e-6))       // R/P ratio
        f.append(R / max(abs(tAmp), 1e-6))       // R/T ratio
        f.append(abs(R - qAmp))                   // R-Q amplitude
        f.append(abs(R - sAmp))                   // R-S amplitude
        f.append(abs(pAmp - tAmp))                // P-T amplitude difference

        // --- 2. Temporal features (12) ---
        f.append(Double(Ridx) / Double(N))        // Normalised R position
        f.append(Double(qrsEnd - qrsStart) / fs)  // QRS duration
        f.append(Double(pRegionEnd - pRegionStart) / fs)  // P wave duration
        f.append(Double(tRegionEnd - tRegionStart) / fs)  // T wave duration
        f.append(Double(Ridx - pRegionEnd) / fs)  // PR interval
        f.append(Double(tRegionStart - Ridx) / fs) // ST interval
        f.append(Double(tRegionEnd - pRegionStart) / fs) // QT interval
        // Inter-peak time ratios
        let prInterval = max(Double(Ridx - pRegionEnd), 1)
        let rtInterval = max(Double(tRegionStart - Ridx), 1)
        f.append(prInterval / rtInterval)
        f.append(Double(qrsEnd - qrsStart) / max(Double(tRegionEnd - pRegionStart), 1)) // QRS/QT ratio
        f.append(slope(beat, start: pRegionStart, end: pRegionEnd)) // P wave slope
        f.append(slope(beat, start: qrsStart, end: Ridx))          // Pre-R slope
        f.append(slope(beat, start: Ridx, end: qrsEnd))            // Post-R slope

        // --- 3. Morphological features (14) ---
        f.append(widthAtHalfMax(beat, center: Ridx) / fs)
        f.append(area(beat, start: pRegionStart, end: pRegionEnd))  // P area
        f.append(area(beat, start: qrsStart, end: qrsEnd))         // QRS area
        f.append(area(beat, start: tRegionStart, end: tRegionEnd)) // T area
        // Curvature at key points (second derivative)
        if Ridx > 1 && Ridx < N - 1 {
            f.append(beat[Ridx - 1] - 2 * beat[Ridx] + beat[Ridx + 1]) // R curvature
        } else { f.append(0) }
        if pRegionEnd > 1 && pRegionEnd < N - 1 {
            f.append(beat[pRegionEnd - 1] - 2 * beat[pRegionEnd] + beat[pRegionEnd + 1])
        } else { f.append(0) }
        // Symmetry ratios
        let preR  = Array(beat[max(0, Ridx - 20)..<Ridx])
        let postR = Array(beat[Ridx..<min(N, Ridx + 20)])
        f.append(preR.reduce(0, +) / max(postR.reduce(0, +), 1e-6))  // Pre/post R area ratio
        f.append(abs(slope(beat, start: qrsStart, end: Ridx)) / max(abs(slope(beat, start: Ridx, end: qrsEnd)), 1e-6)) // Slope ratio
        // Baseline level estimates
        f.append(beat[max(0, pRegionStart)])
        f.append(beat[min(N - 1, tRegionEnd)])
        f.append(beat[qrsStart])
        f.append(beat[min(N - 1, qrsEnd)])
        f.append(beat[Ridx] - (beat[qrsStart] + beat[min(N - 1, qrsEnd)]) / 2) // R height above baseline
        f.append(tAmp - (beat[tRegionStart] + beat[min(N - 1, tRegionEnd)]) / 2) // T height above baseline

        // --- 4. Energy features (8) ---
        let totalEnergy = vDSP.dot(beat, beat)
        f.append(totalEnergy)
        f.append(energyInBand(beat, start: pRegionStart, end: pRegionEnd))
        f.append(energyInBand(beat, start: qrsStart, end: qrsEnd))
        f.append(energyInBand(beat, start: tRegionStart, end: tRegionEnd))
        f.append(energyInBand(beat, start: qrsStart, end: qrsEnd) / max(totalEnergy, 1e-6)) // QRS/total ratio
        f.append(energyInBand(beat, start: tRegionStart, end: tRegionEnd) / max(totalEnergy, 1e-6))
        f.append(energyInBand(beat, start: pRegionStart, end: pRegionEnd) / max(energyInBand(beat, start: tRegionStart, end: tRegionEnd), 1e-6))
        f.append(sqrt(totalEnergy / Double(N)))  // RMS amplitude

        // --- 5. Spectral features (8) ---
        f.append(contentsOf: extractSpectralFeatures(beat))
        // Additional spectral: band ratios
        let mean = beat.mean()
        let centered = beat.map { $0 - mean }
        let q1 = centered.prefix(N/4).map { $0*$0 }.reduce(0,+)
        let q2 = centered.dropFirst(N/4).prefix(N/4).map { $0*$0 }.reduce(0,+)
        let q3 = centered.dropFirst(N/2).prefix(N/4).map { $0*$0 }.reduce(0,+)
        let q4 = centered.suffix(N/4).map { $0*$0 }.reduce(0,+)
        f.append(q1 / max(q3, 1e-6))
        f.append(q2 / max(q4, 1e-6))
        f.append((q1 + q2) / max(q3 + q4, 1e-6))
        f.append(max(q1, q2, q3, q4) / max(min(q1, q2, q3, q4), 1e-6)) // Peak-to-trough band ratio

        // --- 6. Statistical features (12) ---
        let mu = beat.mean()
        let sigma = beat.std()
        f.append(mu)
        f.append(sigma)
        // Skewness
        let skew = beat.map { pow(($0 - mu) / max(sigma, 1e-6), 3) }.reduce(0, +) / Double(N)
        f.append(skew)
        // Kurtosis
        let kurt = beat.map { pow(($0 - mu) / max(sigma, 1e-6), 4) }.reduce(0, +) / Double(N) - 3.0
        f.append(kurt)
        // Zero-crossing rate
        var zc = 0
        for i in 1..<N { if (beat[i] >= mu) != (beat[i-1] >= mu) { zc += 1 } }
        f.append(Double(zc) / Double(N))
        // Percentiles
        let sorted = beat.sorted()
        f.append(sorted[N / 4])          // 25th percentile
        f.append(sorted[N / 2])          // Median
        f.append(sorted[3 * N / 4])      // 75th percentile
        f.append(sorted[3*N/4] - sorted[N/4])  // IQR
        f.append(sorted.last! - sorted.first!)  // Range
        // Entropy (Shannon, discretised into 20 bins)
        var entropy = 0.0
        let binCount = 20
        let range = (sorted.last! - sorted.first!) + 1e-10
        var bins = Array(repeating: 0, count: binCount)
        for v in beat { bins[min(Int((v - sorted.first!) / range * Double(binCount)), binCount - 1)] += 1 }
        for b in bins {
            let p = Double(b) / Double(N)
            if p > 0 { entropy -= p * log2(p) }
        }
        f.append(entropy)
        // Autocorrelation at lag 1
        var ac = 0.0
        for i in 1..<N { ac += (beat[i] - mu) * (beat[i-1] - mu) }
        f.append(ac / (Double(N - 1) * max(sigma * sigma, 1e-10)))

        // --- 7. Wavelet-like coefficients (64) ---
        // Multi-resolution decomposition using Haar wavelet (simplest orthogonal basis).
        // NASA uses more sophisticated wavelets, but Haar captures the key
        // multi-scale morphological structure for 64 coefficients.
        var wavelet: [Double] = []
        var level = beat
        for _ in 0..<6 {  // 6 levels of decomposition
            guard level.count >= 2 else { break }
            var approx: [Double] = []
            var detail: [Double] = []
            for j in stride(from: 0, to: level.count - 1, by: 2) {
                approx.append((level[j] + level[j + 1]) / 2.0)
                detail.append((level[j] - level[j + 1]) / 2.0)
            }
            // Keep first few detail coefficients from each level
            wavelet.append(contentsOf: detail.prefix(12))
            level = approx
        }
        // Pad or truncate to exactly 64
        while wavelet.count < 64 { wavelet.append(0) }
        f.append(contentsOf: wavelet.prefix(64))

        // --- 8. Cross-segment correlations (8) ---
        let seg1 = Array(beat[pRegionStart..<max(pRegionStart+1, pRegionEnd)])
        let seg2 = Array(beat[qrsStart..<max(qrsStart+1, qrsEnd)])
        let seg3 = Array(beat[tRegionStart..<max(tRegionStart+1, tRegionEnd)])
        f.append(crossCorrelation(seg1, seg2))
        f.append(crossCorrelation(seg2, seg3))
        f.append(crossCorrelation(seg1, seg3))
        f.append(crossCorrelation(preR, postR))
        // Normalised segment energies
        let totalSeg = max(seg1.map{$0*$0}.reduce(0,+) + seg2.map{$0*$0}.reduce(0,+) + seg3.map{$0*$0}.reduce(0,+), 1e-10)
        f.append(seg1.map{$0*$0}.reduce(0,+) / totalSeg)
        f.append(seg2.map{$0*$0}.reduce(0,+) / totalSeg)
        f.append(seg3.map{$0*$0}.reduce(0,+) / totalSeg)
        f.append(Double(N) / fs)  // Beat period

        return f
    }

    private func crossCorrelation(_ a: [Double], _ b: [Double]) -> Double {
        let n = min(a.count, b.count)
        guard n > 0 else { return 0 }
        let ma = a.prefix(n).reduce(0, +) / Double(n)
        let mb = b.prefix(n).reduce(0, +) / Double(n)
        var num = 0.0, da = 0.0, db = 0.0
        for i in 0..<n {
            let ai = (i < a.count ? a[i] : 0) - ma
            let bi = (i < b.count ? b[i] : 0) - mb
            num += ai * bi
            da += ai * ai
            db += bi * bi
        }
        return num / max(sqrt(da * db), 1e-10)
    }
    
    private func slope(_ x: [Double], start: Int, end: Int) -> Double {
        guard end > start else { return 0 }
        return (x[end] - x[start]) / Double(end - start)
    }
    
    private func widthAtHalfMax(_ x: [Double], center: Int) -> Double {
        let peak = x[center]
        let half = peak / 2
        
        var l = center
        while l > 0 && x[l] > half {
            l -= 1
        }
        
        var r = center
        while r < x.count - 1 && x[r] > half {
            r += 1
        }
        
        return Double(r - l)
    }
    
    private func area(_ x: [Double], start: Int, end: Int) -> Double {
        guard end > start else { return 0 }
        
        var s = 0.0
        for i in start..<end {
            s += (x[i] + x[i+1]) * 0.5
        }
        return s
    }
    
    private func energyInBand(_ x: [Double], start: Int, end: Int) -> Double {
        guard end > start else { return 0 }
        
        var energy = 0.0
        for i in start..<end {
            energy += x[i] * x[i]
        }
        return energy
    }
    
    private func extractSpectralFeatures(_ beat: [Double]) -> [Double] {
        // Simplified spectral analysis
        let n = beat.count
        guard n > 4 else { return Array(repeating: 0.0, count: 4) }
        
        // Calculate simple frequency domain features
        let mean = beat.mean()
        let centered = beat.map { $0 - mean }
        
        // Power in different frequency bands (simplified)
        let lowFreq = centered.prefix(n/4).map { $0 * $0 }.reduce(0, +)
        let midFreq = centered.dropFirst(n/4).prefix(n/2).map { $0 * $0 }.reduce(0, +)
        let highFreq = centered.suffix(n/4).map { $0 * $0 }.reduce(0, +)
        
        let totalPower = lowFreq + midFreq + highFreq
        
        return [
            lowFreq / max(totalPower, 1e-6),
            midFreq / max(totalPower, 1e-6),
            highFreq / max(totalPower, 1e-6),
            sqrt(totalPower) // RMS
        ]
    }
}

// MARK: - NASA Authentication Engine
final class NASAAuthEngine {
    func authenticate(features: [[Double]], model: NASAUserModel, config: NASAConfig) -> NASAAuthResult {
        guard let first = features.first else {
            return NASAAuthResult(
                accepted: false,
                votes: 0,
                totalVotes: 0,
                meanLL: -.infinity,
                confidence: 0.0,
                qualityScore: 0.0
            )
        }
        
        let D = first.count
        
        // Normalize features
        let z = features.map { vDSP.divide(vDSP.subtract($0, model.featureMean), model.featureStd) }
        
        // NASA-style range voting
        let rPrime = zip(model.featureRange, model.featureStd).map { $0 / $1 }
        var totalVotes = 0
        let totalPossible = z.count * D
        
        for zi in z {
            for d in 0..<D {
                if abs(zi[d]) <= rPrime[d] {
                    totalVotes += 1
                }
            }
        }
        
        let voteRatio = Double(totalVotes) / Double(totalPossible)
        
        // GMM log-likelihood
        let gmm = NASAGMM(parameters: model.gmm)
        let ll = gmm.meanLogLikelihood(dataset: z)
        
        // Calculate confidence using calibrated sigmoid mapping.
        //
        // NASA HeartBeatID uses a vote-pass ratio (acceptance gate) combined with
        // GMM log-likelihood (statistical fit). The confidence score maps these
        // two metrics into a [0,1] range using a calibrated formula:
        //
        //   confidence = sigmoid(voteRatio, center=votePassRatio)
        //              × sigmoid(ll, center=gmmThreshold)
        //
        // This ensures:
        //   - vote ratio at exactly the threshold → 0.50 from that component
        //   - GMM LL at exactly the threshold → 0.50 from that component
        //   - Both well above threshold → approaches 1.0
        //   - Either below threshold → drops sharply toward 0.0
        let voteConfidence = 1.0 / (1.0 + exp(-12.0 * (voteRatio - config.votePassRatio)))
        let gmmConfidence  = 1.0 / (1.0 + exp(-0.3 * (ll - config.gmmThreshold)))
        let confidence     = min(1.0, max(0.0, voteConfidence * gmmConfidence))
        let qualityScore   = calculateQualityScore(features: features)

        // NASA decision logic: dual-gate (both conditions must pass)
        let accepted = (voteRatio >= config.votePassRatio) && (ll >= config.gmmThreshold)
        
        return NASAAuthResult(
            accepted: accepted,
            votes: totalVotes,
            totalVotes: totalPossible,
            meanLL: ll,
            confidence: confidence,
            qualityScore: qualityScore
        )
    }
    
    private func calculateQualityScore(features: [[Double]]) -> Double {
        guard !features.isEmpty else { return 0.0 }
        
        // Calculate feature consistency
        let featureCount = features.first?.count ?? 0
        var consistencyScores: [Double] = []
        
        for d in 0..<featureCount {
            let values = features.map { $0[d] }
            let mean = values.mean()
            let std = values.std()
            let consistency = 1.0 - min(1.0, std / max(abs(mean), 1e-6))
            consistencyScores.append(consistency)
        }
        
        return consistencyScores.mean()
    }
}

// MARK: - NASA Gaussian Mixture Model
final class NASAGMM {
    let parameters: NASAGMMParameters
    
    init(parameters: NASAGMMParameters) {
        self.parameters = parameters
    }
    
    static func fit(dataset X: [[Double]], components K: Int, maxIters: Int = 50) -> NASAGMM {
        precondition(!X.isEmpty)
        
        let N = X.count
        let D = X[0].count
        
        // Initialize with k-means++
        var means = kmeansInit(X, K: K)
        var weights = Array(repeating: 1.0 / Double(K), count: K)
        var cov = Array(repeating: Array(repeating: 1.0, count: D), count: K)
        
        // EM algorithm
        for _ in 0..<maxIters {
            // E-step: calculate responsibilities
            var resp = Array(repeating: Array(repeating: 0.0, count: K), count: N)
            
            for i in 0..<N {
                var den = 0.0
                for k in 0..<K {
                    let p = weights[k] * NASAGMM.diagGaussianPDF(x: X[i], mu: means[k], varDiag: cov[k])
                    resp[i][k] = p
                    den += p
                }
                
                if den > 1e-12 {
                    for k in 0..<K {
                        resp[i][k] /= den
                    }
                }
            }
            
            // M-step: update parameters
            for k in 0..<K {
                let Nk = resp.reduce(0.0) { $0 + $1[k] }
                weights[k] = max(Nk / Double(N), 1e-9)
                
                // Update means
                var mu = Array(repeating: 0.0, count: D)
                for i in 0..<N {
                    mu = vDSP.add(mu, vDSP.multiply(resp[i][k], X[i]))
                }
                if Nk > 1e-9 {
                    mu = vDSP.divide(mu, Nk)
                }
                means[k] = mu
                
                // Update covariances
                var varDiag = Array(repeating: 0.0, count: D)
                for i in 0..<N {
                    let diff = vDSP.subtract(X[i], mu)
                    let sq = vDSP.multiply(diff, diff)
                    varDiag = vDSP.add(varDiag, vDSP.multiply(resp[i][k], sq))
                }
                if Nk > 1e-9 {
                    varDiag = vDSP.divide(varDiag, Nk)
                }
                varDiag = varDiag.map { max($0, 1e-6) }
                cov[k] = varDiag
            }
        }
        
        return NASAGMM(parameters: NASAGMMParameters(weights: weights, means: means, covDiag: cov))
    }
    
    func meanLogLikelihood(dataset X: [[Double]]) -> Double {
        let K = parameters.weights.count
        var total = 0.0
        
        for x in X {
            var s = 0.0
            for k in 0..<K {
                s += parameters.weights[k] * NASAGMM.diagGaussianPDF(x: x, mu: parameters.means[k], varDiag: parameters.covDiag[k])
            }
            total += log(max(s, 1e-30))
        }
        
        return total / Double(X.count)
    }
    
    private static func kmeansInit(_ X: [[Double]], K: Int) -> [[Double]] {
        var centers: [[Double]] = []
        centers.append(X[Int.random(in: 0..<X.count)])
        
        while centers.count < K {
            var dists = [Double](repeating: 0, count: X.count)
            for i in 0..<X.count {
                let nearest = centers.map { l2sq(X[i], $0) }.min() ?? 0
                dists[i] = nearest
            }
            
            let sum = dists.reduce(0, +)
            let r = Double.random(in: 0..<sum)
            var acc = 0.0
            
            for i in 0..<X.count {
                acc += dists[i]
                if acc >= r {
                    centers.append(X[i])
                    break
                }
            }
        }
        
        return centers
    }
    
    private static func l2sq(_ a: [Double], _ b: [Double]) -> Double {
        vDSP.sum(vDSP.multiply(vDSP.subtract(a, b), vDSP.subtract(a, b)))
    }
    
    private static func diagGaussianPDF(x: [Double], mu: [Double], varDiag: [Double]) -> Double {
        let D = x.count
        let diff = vDSP.subtract(x, mu)
        var z = 0.0
        
        for d in 0..<D {
            z += diff[d] * diff[d] / varDiag[d]
        }
        
        let logDet = varDiag.reduce(0.0) { $0 + log($1) }
        let logNorm = -0.5 * (Double(D) * log(2 * Double.pi) + logDet)
        
        return exp(logNorm - 0.5 * z)
    }
}

// MARK: - Extensions
extension Array where Element == Double {
    // mean() function is defined in Extensions.swift
    
    func std() -> Double {
        guard count > 1 else { return 0 }
        let m = mean()
        let v = self.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(count - 1)
        return sqrt(Swift.max(v, 0))
    }
    
    func variance() -> Double {
        guard count > 1 else { return 0 }
        let m = mean()
        return self.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(count - 1)
    }
}

extension vDSP {
    static func subtract(_ a: [Double], _ b: [Double]) -> [Double] {
        var out = [Double](repeating: 0, count: a.count)
        vDSP_vsubD(b, 1, a, 1, &out, 1, vDSP_Length(a.count))
        return out
    }
    
    static func add(_ a: [Double], _ b: [Double]) -> [Double] {
        var out = [Double](repeating: 0, count: a.count)
        vDSP_vaddD(a, 1, b, 1, &out, 1, vDSP_Length(a.count))
        return out
    }
    
    static func multiply(_ a: [Double], _ b: [Double]) -> [Double] {
        var out = [Double](repeating: 0, count: a.count)
        vDSP_vmulD(a, 1, b, 1, &out, 1, vDSP_Length(a.count))
        return out
    }
    
    static func multiply(_ a: [Double], _ b: Double) -> [Double] {
        a.map { $0 * b }
    }
    
    static func divide(_ a: [Double], _ b: [Double]) -> [Double] {
        zip(a, b).map { $0 / ($1 == 0 ? 1e-6 : $1) }
    }
    
    static func dot(_ a: [Double], _ b: [Double]) -> Double {
        var result = 0.0
        vDSP_dotprD(a, 1, b, 1, &result, vDSP_Length(a.count))
        return result
    }
    
    static func sum(_ a: [Double]) -> Double {
        var result = 0.0
        vDSP_sveD(a, 1, &result, vDSP_Length(a.count))
        return result
    }
}
