import Foundation
import Accelerate

/// XenonX Calculation Module - Proprietary heart pattern analysis algorithm
/// This is a modular framework designed for easy replacement/improvement
protocol XenonXCalculatorProtocol {
    func analyzePattern(_ heartRateData: [Double]) -> XenonXResult
    func comparePatterns(_ pattern1: XenonXResult, _ pattern2: XenonXResult) -> Double
    func extractFeatures(_ heartRateData: [Double]) -> XenonXFeatures
}

/// Result of XenonX pattern analysis
struct XenonXResult: Codable {
    let features: XenonXFeatures
    let patternSignature: String
    let confidence: Double
    let timestamp: Date
    
    init(features: XenonXFeatures, patternSignature: String, confidence: Double) {
        self.features = features
        self.patternSignature = patternSignature
        self.confidence = confidence
        self.timestamp = Date()
    }
}

/// Extracted features from heart pattern analysis
struct XenonXFeatures: Codable {
    let temporalFeatures: TemporalFeatures
    let frequencyFeatures: FrequencyFeatures
    let statisticalFeatures: StatisticalFeatures
    let morphologicalFeatures: MorphologicalFeatures
    
    init(heartRateData: [Double]) {
        self.temporalFeatures = TemporalFeatures(heartRateData: heartRateData)
        self.frequencyFeatures = FrequencyFeatures(heartRateData: heartRateData)
        self.statisticalFeatures = StatisticalFeatures(heartRateData: heartRateData)
        self.morphologicalFeatures = MorphologicalFeatures(heartRateData: heartRateData)
    }
}

/// Temporal analysis features
struct TemporalFeatures: Codable {
    let interBeatIntervals: [Double]
    let heartRateVariability: Double
    let rhythmRegularity: Double
    let trendDirection: Double
    
    init(heartRateData: [Double]) {
        self.interBeatIntervals = Self.calculateInterBeatIntervals(heartRateData)
        self.heartRateVariability = Self.calculateHRV(heartRateData)
        self.rhythmRegularity = Self.calculateRhythmRegularity(heartRateData)
        self.trendDirection = Self.calculateTrendDirection(heartRateData)
    }
    
    private static func calculateInterBeatIntervals(_ data: [Double]) -> [Double] {
        guard data.count > 1 else { return [] }
        return zip(data.dropFirst(), data).map { $0 - $1 }
    }
    
    private static func calculateHRV(_ data: [Double]) -> Double {
        guard data.count > 1 else { return 0 }
        let mean = data.reduce(0, +) / Double(data.count)
        let variance = data.map { pow($0 - mean, 2) }.reduce(0, +) / Double(data.count)
        return sqrt(variance)
    }
    
    private static func calculateRhythmRegularity(_ data: [Double]) -> Double {
        guard data.count > 2 else { return 0 }
        let intervals = calculateInterBeatIntervals(data)
        guard intervals.count > 1 else { return 0 }
        
        let meanInterval = intervals.reduce(0, +) / Double(intervals.count)
        let variance = intervals.map { pow($0 - meanInterval, 2) }.reduce(0, +) / Double(intervals.count)
        return 1.0 / (1.0 + sqrt(variance))
    }
    
    private static func calculateTrendDirection(_ data: [Double]) -> Double {
        guard data.count > 1 else { return 0 }
        let firstHalf = Array(data.prefix(data.count / 2))
        let secondHalf = Array(data.suffix(data.count / 2))
        
        let firstMean = firstHalf.reduce(0, +) / Double(firstHalf.count)
        let secondMean = secondHalf.reduce(0, +) / Double(secondHalf.count)
        
        return (secondMean - firstMean) / firstMean
    }
}

/// Frequency domain analysis features
struct FrequencyFeatures: Codable {
    let dominantFrequency: Double
    let spectralCentroid: Double
    let spectralRolloff: Double
    let spectralBandwidth: Double
    
    init(heartRateData: [Double]) {
        let fftResult = Self.performFFT(heartRateData)
        self.dominantFrequency = Self.findDominantFrequency(fftResult)
        self.spectralCentroid = Self.calculateSpectralCentroid(fftResult)
        self.spectralRolloff = Self.calculateSpectralRolloff(fftResult)
        self.spectralBandwidth = Self.calculateSpectralBandwidth(fftResult)
    }
    
    private static func performFFT(_ data: [Double]) -> [Double] {
        let count = data.count
        let log2n = vDSP_Length(log2(Double(count)))
        let fftSetup = vDSP_create_fftsetup(log2n, Int32(kFFTRadix2))
        
        // Convert to Float for FFT
        let floatData = data.map { Float($0) }
        var realParts = floatData
        var imaginaryParts = [Float](repeating: 0, count: count)
        
        var result: [Double] = []
        
        realParts.withUnsafeMutableBufferPointer { realBuffer in
            imaginaryParts.withUnsafeMutableBufferPointer { imagBuffer in
                var splitComplex = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imagBuffer.baseAddress!)
                
                vDSP_fft_zrip(fftSetup!, &splitComplex, 1, log2n, Int32(FFT_FORWARD))
                
                var magnitudes = [Float](repeating: 0, count: count / 2)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(count / 2))
                
                result = magnitudes.map { Double($0) }
            }
        }
        
        vDSP_destroy_fftsetup(fftSetup)
        
        return result
    }
    
    private static func findDominantFrequency(_ fftResult: [Double]) -> Double {
        guard let maxIndex = fftResult.enumerated().max(by: { $0.element < $1.element })?.offset else { return 0 }
        return Double(maxIndex) / Double(fftResult.count)
    }
    
    private static func calculateSpectralCentroid(_ fftResult: [Double]) -> Double {
        let totalMagnitude = fftResult.reduce(0, +)
        guard totalMagnitude > 0 else { return 0 }
        
        let weightedSum = fftResult.enumerated().map { Double($0.offset) * $0.element }.reduce(0, +)
        return weightedSum / totalMagnitude
    }
    
    private static func calculateSpectralRolloff(_ fftResult: [Double]) -> Double {
        let totalMagnitude = fftResult.reduce(0, +)
        let threshold = totalMagnitude * 0.85
        
        var cumulativeSum = 0.0
        for (index, magnitude) in fftResult.enumerated() {
            cumulativeSum += magnitude
            if cumulativeSum >= threshold {
                return Double(index) / Double(fftResult.count)
            }
        }
        return 1.0
    }
    
    private static func calculateSpectralBandwidth(_ fftResult: [Double]) -> Double {
        let centroid = calculateSpectralCentroid(fftResult)
        let totalMagnitude = fftResult.reduce(0, +)
        guard totalMagnitude > 0 else { return 0 }
        
        let weightedVariance = fftResult.enumerated().map { 
            pow(Double($0.offset) - centroid, 2) * $0.element 
        }.reduce(0, +)
        
        return sqrt(weightedVariance / totalMagnitude)
    }
}

/// Statistical analysis features
struct StatisticalFeatures: Codable {
    let mean: Double
    let median: Double
    let standardDeviation: Double
    let skewness: Double
    let kurtosis: Double
    let range: Double
    
    init(heartRateData: [Double]) {
        let sortedData = heartRateData.sorted()
        self.mean = sortedData.reduce(0, +) / Double(sortedData.count)
        self.median = Self.calculateMedian(sortedData)
        self.standardDeviation = Self.calculateStandardDeviation(sortedData, mean: self.mean)
        self.skewness = Self.calculateSkewness(sortedData, mean: self.mean, stdDev: self.standardDeviation)
        self.kurtosis = Self.calculateKurtosis(sortedData, mean: self.mean, stdDev: self.standardDeviation)
        self.range = (sortedData.last ?? 0) - (sortedData.first ?? 0)
    }
    
    private static func calculateMedian(_ data: [Double]) -> Double {
        let count = data.count
        if count % 2 == 0 {
            return (data[count / 2 - 1] + data[count / 2]) / 2
        } else {
            return data[count / 2]
        }
    }
    
    private static func calculateStandardDeviation(_ data: [Double], mean: Double) -> Double {
        let variance = data.map { pow($0 - mean, 2) }.reduce(0, +) / Double(data.count)
        return sqrt(variance)
    }
    
    private static func calculateSkewness(_ data: [Double], mean: Double, stdDev: Double) -> Double {
        guard stdDev > 0 else { return 0 }
        let n = Double(data.count)
        let sum = data.map { pow(($0 - mean) / stdDev, 3) }.reduce(0, +)
        return sum / n
    }
    
    private static func calculateKurtosis(_ data: [Double], mean: Double, stdDev: Double) -> Double {
        guard stdDev > 0 else { return 0 }
        let n = Double(data.count)
        let sum = data.map { pow(($0 - mean) / stdDev, 4) }.reduce(0, +)
        return (sum / n) - 3.0
    }
}

/// Morphological analysis features
struct MorphologicalFeatures: Codable {
    let peakCount: Int
    let valleyCount: Int
    let peakAmplitude: Double
    let valleyAmplitude: Double
    let slopeChanges: Int
    
    init(heartRateData: [Double]) {
        self.peakCount = Self.countPeaks(heartRateData)
        self.valleyCount = Self.countValleys(heartRateData)
        self.peakAmplitude = Self.calculatePeakAmplitude(heartRateData)
        self.valleyAmplitude = Self.calculateValleyAmplitude(heartRateData)
        self.slopeChanges = Self.countSlopeChanges(heartRateData)
    }
    
    private static func countPeaks(_ data: [Double]) -> Int {
        guard data.count > 2 else { return 0 }
        var peakCount = 0
        
        for i in 1..<data.count - 1 {
            if data[i] > data[i-1] && data[i] > data[i+1] {
                peakCount += 1
            }
        }
        return peakCount
    }
    
    private static func countValleys(_ data: [Double]) -> Int {
        guard data.count > 2 else { return 0 }
        var valleyCount = 0
        
        for i in 1..<data.count - 1 {
            if data[i] < data[i-1] && data[i] < data[i+1] {
                valleyCount += 1
            }
        }
        return valleyCount
    }
    
    private static func calculatePeakAmplitude(_ data: [Double]) -> Double {
        guard let max = data.max() else { return 0 }
        guard let min = data.min() else { return 0 }
        return max - min
    }
    
    private static func calculateValleyAmplitude(_ data: [Double]) -> Double {
        return calculatePeakAmplitude(data) // Same calculation for valleys
    }
    
    private static func countSlopeChanges(_ data: [Double]) -> Int {
        guard data.count > 2 else { return 0 }
        var changes = 0
        
        for i in 1..<data.count - 1 {
            let slope1 = data[i] - data[i-1]
            let slope2 = data[i+1] - data[i]
            
            if (slope1 > 0 && slope2 < 0) || (slope1 < 0 && slope2 > 0) {
                changes += 1
            }
        }
        return changes
    }
}

/// Main XenonX Calculator implementation
class XenonXCalculator: XenonXCalculatorProtocol {
    private let featureWeights: [String: Double] = [
        "temporal": 0.3,
        "frequency": 0.25,
        "statistical": 0.25,
        "morphological": 0.2
    ]
    
    func analyzePattern(_ heartRateData: [Double]) -> XenonXResult {
        let features = extractFeatures(heartRateData)
        let patternSignature = generatePatternSignature(features)
        let confidence = calculateConfidence(features)
        
        return XenonXResult(
            features: features,
            patternSignature: patternSignature,
            confidence: confidence
        )
    }
    
    func comparePatterns(_ pattern1: XenonXResult, _ pattern2: XenonXResult) -> Double {
        let temporalSimilarity = compareTemporalFeatures(pattern1.features.temporalFeatures, pattern2.features.temporalFeatures)
        let frequencySimilarity = compareFrequencyFeatures(pattern1.features.frequencyFeatures, pattern2.features.frequencyFeatures)
        let statisticalSimilarity = compareStatisticalFeatures(pattern1.features.statisticalFeatures, pattern2.features.statisticalFeatures)
        let morphologicalSimilarity = compareMorphologicalFeatures(pattern1.features.morphologicalFeatures, pattern2.features.morphologicalFeatures)
        
        let weightedSimilarity = 
            temporalSimilarity * featureWeights["temporal"]! +
            frequencySimilarity * featureWeights["frequency"]! +
            statisticalSimilarity * featureWeights["statistical"]! +
            morphologicalSimilarity * featureWeights["morphological"]!
        
        return min(weightedSimilarity * 100, 100.0)
    }
    
    func extractFeatures(_ heartRateData: [Double]) -> XenonXFeatures {
        return XenonXFeatures(heartRateData: heartRateData)
    }
    
    private func generatePatternSignature(_ features: XenonXFeatures) -> String {
        let signature = """
        T:\(features.temporalFeatures.heartRateVariability)|\(features.temporalFeatures.rhythmRegularity)
        F:\(features.frequencyFeatures.dominantFrequency)|\(features.frequencyFeatures.spectralCentroid)
        S:\(features.statisticalFeatures.mean)|\(features.statisticalFeatures.standardDeviation)
        M:\(features.morphologicalFeatures.peakCount)|\(features.morphologicalFeatures.slopeChanges)
        """
        return signature.data(using: .utf8)?.base64EncodedString() ?? ""
    }
    
    private func calculateConfidence(_ features: XenonXFeatures) -> Double {
        // Confidence based on data quality and feature consistency
        let dataQuality = min(features.temporalFeatures.heartRateVariability / 20.0, 1.0)
        let featureConsistency = 1.0 - abs(features.statisticalFeatures.skewness) / 3.0
        let patternComplexity = min(Double(features.morphologicalFeatures.peakCount) / 10.0, 1.0)
        
        return (dataQuality + featureConsistency + patternComplexity) / 3.0
    }
    
    private func compareTemporalFeatures(_ f1: TemporalFeatures, _ f2: TemporalFeatures) -> Double {
        let hrvSimilarity = 1.0 - abs(f1.heartRateVariability - f2.heartRateVariability) / max(f1.heartRateVariability, f2.heartRateVariability)
        let rhythmSimilarity = 1.0 - abs(f1.rhythmRegularity - f2.rhythmRegularity)
        let trendSimilarity = 1.0 - abs(f1.trendDirection - f2.trendDirection) / 2.0
        
        return (hrvSimilarity + rhythmSimilarity + trendSimilarity) / 3.0
    }
    
    private func compareFrequencyFeatures(_ f1: FrequencyFeatures, _ f2: FrequencyFeatures) -> Double {
        let dominantSimilarity = 1.0 - abs(f1.dominantFrequency - f2.dominantFrequency)
        let centroidSimilarity = 1.0 - abs(f1.spectralCentroid - f2.spectralCentroid) / max(f1.spectralCentroid, f2.spectralCentroid)
        let rolloffSimilarity = 1.0 - abs(f1.spectralRolloff - f2.spectralRolloff)
        
        return (dominantSimilarity + centroidSimilarity + rolloffSimilarity) / 3.0
    }
    
    private func compareStatisticalFeatures(_ f1: StatisticalFeatures, _ f2: StatisticalFeatures) -> Double {
        let meanSimilarity = 1.0 - abs(f1.mean - f2.mean) / max(f1.mean, f2.mean)
        let stdSimilarity = 1.0 - abs(f1.standardDeviation - f2.standardDeviation) / max(f1.standardDeviation, f2.standardDeviation)
        let skewSimilarity = 1.0 - abs(f1.skewness - f2.skewness) / 6.0
        let kurtSimilarity = 1.0 - abs(f1.kurtosis - f2.kurtosis) / 6.0
        
        return (meanSimilarity + stdSimilarity + skewSimilarity + kurtSimilarity) / 4.0
    }
    
    private func compareMorphologicalFeatures(_ f1: MorphologicalFeatures, _ f2: MorphologicalFeatures) -> Double {
        let peakSimilarity = 1.0 - abs(Double(f1.peakCount - f2.peakCount)) / max(Double(f1.peakCount), Double(f2.peakCount), 1.0)
        let valleySimilarity = 1.0 - abs(Double(f1.valleyCount - f2.valleyCount)) / max(Double(f1.valleyCount), Double(f2.valleyCount), 1.0)
        let amplitudeSimilarity = 1.0 - abs(f1.peakAmplitude - f2.peakAmplitude) / max(f1.peakAmplitude, f2.peakAmplitude)
        let slopeSimilarity = 1.0 - abs(Double(f1.slopeChanges - f2.slopeChanges)) / max(Double(f1.slopeChanges), Double(f2.slopeChanges), 1.0)
        
        return (peakSimilarity + valleySimilarity + amplitudeSimilarity + slopeSimilarity) / 4.0
    }
}

