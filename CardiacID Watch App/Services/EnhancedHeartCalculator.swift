//
//  EnhancedHeartCalculator.swift
//  HeartID Watch App
//
//  Enhanced Heart Pattern Calculator combining XenonX and NASA algorithms
//  Provides multiple analysis methods for improved accuracy and reliability
//

import Foundation
import Accelerate

// MARK: - Enhanced Calculator Configuration
public struct EnhancedCalculatorConfig {
    public var useXenonX: Bool = true
    public var useNASA: Bool = true
    public var nasaWeight: Double = 0.7  // Weight for NASA algorithm (0.0-1.0)
    public var xenonXWeight: Double = 0.3  // Weight for XenonX algorithm (0.0-1.0)
    public var minimumConfidence: Double = 0.6
    public var enableFusion: Bool = true  // Enable algorithm fusion
    
    public init() {}
}

// MARK: - Enhanced Analysis Result
struct EnhancedAnalysisResult {
    let xenonXResult: XenonXResult?
    let nasaResult: NASAAuthResult?
    let fusedConfidence: Double
    let algorithmAgreement: Double
    let recommendedAction: AuthenticationAction
    let qualityScore: Double
    let timestamp: Date
    
    public enum AuthenticationAction: String, Codable {
        case accept = "accept"
        case reject = "reject"
        case requireMoreData = "require_more_data"
        case lowConfidence = "low_confidence"
    }
    
    init(xenonXResult: XenonXResult?, nasaResult: NASAAuthResult?, fusedConfidence: Double, algorithmAgreement: Double, recommendedAction: AuthenticationAction, qualityScore: Double) {
        self.xenonXResult = xenonXResult
        self.nasaResult = nasaResult
        self.fusedConfidence = fusedConfidence
        self.algorithmAgreement = algorithmAgreement
        self.recommendedAction = recommendedAction
        self.qualityScore = qualityScore
        self.timestamp = Date()
    }
}

// MARK: - Enhanced Heart Calculator
public class EnhancedHeartCalculator {
    private let config: EnhancedCalculatorConfig
    private let xenonXCalculator: XenonXCalculator
    private let nasaCalculator: NASACalculator
    private let nasaConfig: NASAConfig
    
    public init(config: EnhancedCalculatorConfig = EnhancedCalculatorConfig()) {
        self.config = config
        self.xenonXCalculator = XenonXCalculator()
        self.nasaCalculator = NASACalculator()
        self.nasaConfig = NASAConfig()
    }
    
    // MARK: - Public Analysis Methods
    
    /// Analyze heart pattern using enhanced multi-algorithm approach
    func analyzeHeartPattern(_ heartRateData: [Double], sampleRate: Double = 512.0) -> EnhancedAnalysisResult {
        var xenonXResult: XenonXResult?
        var nasaResult: NASAAuthResult?
        
        // Run XenonX analysis if enabled
        if config.useXenonX {
            xenonXResult = xenonXCalculator.analyzePattern(heartRateData)
        }
        
        // Run NASA analysis if enabled
        if config.useNASA {
            do {
                let preprocessedECG = try nasaCalculator.preprocessECG(series: heartRateData, fs: sampleRate)
                let rPeaks = try nasaCalculator.detectRPeaks(ecg: preprocessedECG, fs: sampleRate)
                let beats = nasaCalculator.segmentBeats(ecg: preprocessedECG, rPeaks: rPeaks, fs: sampleRate)
                let features = nasaCalculator.extractFeatures(from: beats, fs: sampleRate)
                
                // Create a mock model for testing (in production, this would be loaded from storage)
                let mockModel = createMockNASAModel(featureCount: features.first?.count ?? 20)
                nasaResult = nasaCalculator.authenticate(features: features, model: mockModel)
            } catch {
                print("NASA analysis failed: \(error)")
            }
        }
        
        // Fuse results if both algorithms are enabled
        let fusedResult = fuseAnalysisResults(xenonXResult: xenonXResult, nasaResult: nasaResult)
        
        return fusedResult
    }
    
    /// Compare two heart patterns using enhanced analysis
    public func compareHeartPatterns(_ pattern1: [Double], _ pattern2: [Double], sampleRate: Double = 512.0) -> Double {
        let result1 = analyzeHeartPattern(pattern1, sampleRate: sampleRate)
        let result2 = analyzeHeartPattern(pattern2, sampleRate: sampleRate)
        
        // Calculate similarity based on fused confidence and feature similarity
        let confidenceSimilarity = 1.0 - abs(result1.fusedConfidence - result2.fusedConfidence)
        let qualitySimilarity = 1.0 - abs(result1.qualityScore - result2.qualityScore)
        
        // If both have XenonX results, use their comparison
        var xenonXSimilarity: Double = 0.5
        if let xenonX1 = result1.xenonXResult, let xenonX2 = result2.xenonXResult {
            xenonXSimilarity = xenonXCalculator.comparePatterns(xenonX1, xenonX2)
        }
        
        // Weighted combination
        let overallSimilarity = (confidenceSimilarity * 0.3) + (qualitySimilarity * 0.3) + (xenonXSimilarity * 0.4)
        
        return max(0.0, min(1.0, overallSimilarity))
    }
    
    /// Extract comprehensive features using both algorithms
    public func extractComprehensiveFeatures(_ heartRateData: [Double], sampleRate: Double = 512.0) -> [String: Any] {
        var features: [String: Any] = [:]
        
        // XenonX features
        if config.useXenonX {
            let xenonXFeatures = xenonXCalculator.extractFeatures(heartRateData)
            features["xenonX"] = [
                "temporal": [
                    "interBeatIntervals": xenonXFeatures.temporalFeatures.interBeatIntervals,
                    "heartRateVariability": xenonXFeatures.temporalFeatures.heartRateVariability,
                    "rhythmRegularity": xenonXFeatures.temporalFeatures.rhythmRegularity
                ],
                "frequency": [
                    "dominantFrequency": xenonXFeatures.frequencyFeatures.dominantFrequency,
                    "spectralCentroid": xenonXFeatures.frequencyFeatures.spectralCentroid,
                    "spectralRolloff": xenonXFeatures.frequencyFeatures.spectralRolloff
                ],
                "statistical": [
                    "mean": xenonXFeatures.statisticalFeatures.mean,
                    "standardDeviation": xenonXFeatures.statisticalFeatures.standardDeviation,
                    "skewness": xenonXFeatures.statisticalFeatures.skewness
                ]
            ]
        }
        
        // NASA features
        if config.useNASA {
            do {
                let preprocessedECG = try nasaCalculator.preprocessECG(series: heartRateData, fs: sampleRate)
                let rPeaks = try nasaCalculator.detectRPeaks(ecg: preprocessedECG, fs: sampleRate)
                let beats = nasaCalculator.segmentBeats(ecg: preprocessedECG, rPeaks: rPeaks, fs: sampleRate)
                let nasaFeatures = nasaCalculator.extractFeatures(from: beats, fs: sampleRate)
                
                features["nasa"] = [
                    "featureCount": nasaFeatures.count,
                    "featureDimensions": nasaFeatures.first?.count ?? 0,
                    "beatCount": beats.count,
                    "rPeakCount": rPeaks.count
                ]
            } catch {
                features["nasa"] = ["error": error.localizedDescription]
            }
        }
        
        // Quality metrics
        features["quality"] = [
            "signalLength": heartRateData.count,
            "sampleRate": sampleRate,
            "duration": Double(heartRateData.count) / sampleRate
        ]
        
        return features
    }
    
    /// Train/enroll using both algorithms
    func enrollUser(_ trainingData: [[Double]], sampleRate: Double = 512.0) -> (xenonXModel: XenonXResult?, nasaModel: NASAUserModel?) {
        var xenonXModel: XenonXResult?
        var nasaModel: NASAUserModel?
        
        // Train XenonX model
        if config.useXenonX && !trainingData.isEmpty {
            let combinedData = trainingData.flatMap { $0 }
            xenonXModel = xenonXCalculator.analyzePattern(combinedData)
        }
        
        // Train NASA model
        if config.useNASA && !trainingData.isEmpty {
            do {
                var allFeatures: [[[Double]]] = []
                
                for data in trainingData {
                    let preprocessedECG = try nasaCalculator.preprocessECG(series: data, fs: sampleRate)
                    let rPeaks = try nasaCalculator.detectRPeaks(ecg: preprocessedECG, fs: sampleRate)
                    let beats = nasaCalculator.segmentBeats(ecg: preprocessedECG, rPeaks: rPeaks, fs: sampleRate)
                    let features = nasaCalculator.extractFeatures(from: beats, fs: sampleRate)
                    allFeatures.append(features)
                }
                
                nasaModel = nasaCalculator.enroll(from: allFeatures)
            } catch {
                print("NASA enrollment failed: \(error)")
            }
        }
        
        return (xenonXModel, nasaModel)
    }
    
    // MARK: - Private Methods
    
    private func fuseAnalysisResults(xenonXResult: XenonXResult?, nasaResult: NASAAuthResult?) -> EnhancedAnalysisResult {
        var fusedConfidence: Double = 0.0
        var algorithmAgreement: Double = 0.0
        var recommendedAction: EnhancedAnalysisResult.AuthenticationAction = .reject
        var qualityScore: Double = 0.0
        
        if let xenonX = xenonXResult, let nasa = nasaResult {
            // Both algorithms available - fuse results
            let xenonXConfidence = xenonX.confidence
            let nasaConfidence = nasa.confidence
            
            // Weighted fusion
            fusedConfidence = (xenonXConfidence * config.xenonXWeight) + (nasaConfidence * config.nasaWeight)
            
            // Calculate algorithm agreement
            let confidenceDiff = abs(xenonXConfidence - nasaConfidence)
            algorithmAgreement = max(0.0, 1.0 - confidenceDiff)
            
            // Quality score (average of both)
            qualityScore = (xenonX.confidence + nasa.confidence) / 2.0
            
            // Decision logic
            if fusedConfidence >= config.minimumConfidence && algorithmAgreement >= 0.7 {
                recommendedAction = .accept
            } else if fusedConfidence >= 0.4 && algorithmAgreement >= 0.5 {
                recommendedAction = .requireMoreData
            } else if fusedConfidence >= 0.2 {
                recommendedAction = .lowConfidence
            } else {
                recommendedAction = .reject
            }
            
        } else if let xenonX = xenonXResult {
            // Only XenonX available
            fusedConfidence = xenonX.confidence
            algorithmAgreement = 1.0  // Single algorithm
            qualityScore = xenonX.confidence
            recommendedAction = xenonX.confidence >= config.minimumConfidence ? .accept : .reject
            
        } else if let nasa = nasaResult {
            // Only NASA available
            fusedConfidence = nasa.confidence
            algorithmAgreement = 1.0  // Single algorithm
            qualityScore = nasa.qualityScore
            recommendedAction = nasa.accepted ? .accept : .reject
            
        } else {
            // No algorithms available
            fusedConfidence = 0.0
            algorithmAgreement = 0.0
            qualityScore = 0.0
            recommendedAction = .reject
        }
        
        return EnhancedAnalysisResult(
            xenonXResult: xenonXResult,
            nasaResult: nasaResult,
            fusedConfidence: fusedConfidence,
            algorithmAgreement: algorithmAgreement,
            recommendedAction: recommendedAction,
            qualityScore: qualityScore
        )
    }
    
    private func createMockNASAModel(featureCount: Int) -> NASAUserModel {
        // Create a mock model for testing
        // In production, this would be loaded from secure storage
        let featureMean = Array(repeating: 0.0, count: featureCount)
        let featureStd = Array(repeating: 1.0, count: featureCount)
        let featureRange = Array(repeating: 2.5, count: featureCount)
        
        let gmmParams = NASAGMMParameters(
            weights: [1.0],
            means: [featureMean],
            covDiag: [Array(repeating: 1.0, count: featureCount)]
        )
        
        return NASAUserModel(
            featureMean: featureMean,
            featureStd: featureStd,
            featureRange: featureRange,
            gmm: gmmParams
        )
    }
}

// MARK: - Enhanced Calculator Extensions

extension EnhancedHeartCalculator {
    /// Get algorithm status and capabilities
    public func getAlgorithmStatus() -> [String: Any] {
        return [
            "xenonXEnabled": config.useXenonX,
            "nasaEnabled": config.useNASA,
            "fusionEnabled": config.enableFusion,
            "nasaWeight": config.nasaWeight,
            "xenonXWeight": config.xenonXWeight,
            "minimumConfidence": config.minimumConfidence
        ]
    }
    
    /// Update configuration
    public func updateConfig(_ newConfig: EnhancedCalculatorConfig) {
        // In a real implementation, this would update the internal config
        // For now, we'll just print the change
        print("Enhanced calculator config updated: NASA weight = \(newConfig.nasaWeight), XenonX weight = \(newConfig.xenonXWeight)")
    }
    
    /// Get detailed analysis report
    public func getAnalysisReport(_ heartRateData: [Double], sampleRate: Double = 512.0) -> [String: Any] {
        let result = analyzeHeartPattern(heartRateData, sampleRate: sampleRate)
        
        var report: [String: Any] = [
            "timestamp": result.timestamp,
            "fusedConfidence": result.fusedConfidence,
            "algorithmAgreement": result.algorithmAgreement,
            "recommendedAction": result.recommendedAction.rawValue,
            "qualityScore": result.qualityScore
        ]
        
        if let xenonX = result.xenonXResult {
            report["xenonX"] = [
                "confidence": xenonX.confidence,
                "patternSignature": xenonX.patternSignature,
                "timestamp": xenonX.timestamp
            ]
        }
        
        if let nasa = result.nasaResult {
            report["nasa"] = [
                "accepted": nasa.accepted,
                "confidence": nasa.confidence,
                "votes": nasa.votes,
                "totalVotes": nasa.totalVotes,
                "meanLL": nasa.meanLL,
                "qualityScore": nasa.qualityScore
            ]
        }
        
        return report
    }
}
