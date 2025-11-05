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
    
    func butterworthFilter(_ x: [Double], fs: Double, cutoff: Double, type: FilterType) -> [Double] {
        let rc = 1.0 / (2.0 * Double.pi * cutoff)
        let dt = 1.0 / fs
        let alpha = dt / (rc + dt)
        var y = Array(repeating: 0.0, count: x.count)
        
        switch type {
        case .high:
            var prev = x.first ?? 0
            var yh = 0.0
            for i in 1..<x.count {
                let xi = x[i]
                yh = alpha * (yh + xi - prev)
                y[i] = yh
                prev = xi
            }
        case .low:
            var yl = 0.0
            for i in 0..<x.count {
                yl = yl + alpha * (x[i] - yl)
                y[i] = yl
            }
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
    
    func adaptivePeaks(_ x: [Double], refractory: Int) -> [Int] {
        var peaks: [Int] = []
        var thr = (x.max() ?? 1.0) * 0.4
        var last = -refractory
        
        for i in 1..<(x.count-1) {
            if x[i] > thr && x[i] > x[i-1] && x[i] > x[i+1] && (i - last) > refractory {
                peaks.append(i)
                last = i
                thr = 0.9 * thr + 0.1 * x[i]
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
    
    private func extractBeatFeatures(_ beat: [Double], fs: Double) -> [Double] {
        let R = beat.max() ?? 0
        let Ridx = beat.firstIndex(of: R) ?? 128
        
        // Define analysis windows around R-peak
        let pre = max(0, Ridx - 20)
        let post = min(beat.count - 1, Ridx + 20)
        
        // Extract NASA-style features
        var features: [Double] = []
        
        // 1. Amplitude features
        features.append(R) // R amplitude
        features.append(beat[pre]) // P amplitude
        features.append(beat[post]) // T amplitude
        features.append(R / max(beat[pre], 1e-6)) // R/P ratio
        features.append(R / max(beat[post], 1e-6)) // R/T ratio
        
        // 2. Temporal features
        features.append(Double(Ridx) / fs) // R position
        features.append(Double(post - pre) / fs) // QRS duration
        features.append(slope(beat, start: pre, end: Ridx)) // Pre-R slope
        features.append(slope(beat, start: Ridx, end: post)) // Post-R slope
        
        // 3. Morphological features
        features.append(widthAtHalfMax(beat, center: Ridx) / fs) // QRS width
        features.append(area(beat, start: pre, end: post)) // QRS area
        features.append(area(beat, start: post, end: min(beat.count-1, post+20))) // T area
        
        // 4. Energy features
        features.append(vDSP.dot(beat, beat)) // Total energy
        features.append(energyInBand(beat, start: pre, end: post)) // QRS energy
        
        // 5. Spectral features (simplified)
        let spectralFeatures = extractSpectralFeatures(beat)
        features.append(contentsOf: spectralFeatures)
        
        return features
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
        
        // Calculate confidence and quality
        let confidence = min(1.0, max(0.0, (voteRatio + (ll + 20) / 40) / 2))
        let qualityScore = calculateQualityScore(features: features)
        
        // NASA decision logic
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
