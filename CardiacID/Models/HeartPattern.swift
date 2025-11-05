import Foundation

/// Model representing a heart pattern for biometric authentication
struct HeartPattern: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let heartRateData: [Double] // Heart rate values over time
    let duration: TimeInterval // Duration of capture (9-16 seconds)
    let encryptedIdentifier: String // Encrypted pattern identifier
    let qualityScore: Double
    let confidence: Double
    let deviceId: String?
    
    init(heartRateData: [Double], duration: TimeInterval, encryptedIdentifier: String, qualityScore: Double = 0.0, confidence: Double = 0.0, deviceId: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.heartRateData = heartRateData
        self.duration = duration
        self.encryptedIdentifier = encryptedIdentifier
        self.qualityScore = qualityScore
        self.confidence = confidence
        self.deviceId = deviceId
    }
    
    // MARK: - Computed Properties
    
    var averageHeartRate: Double {
        guard !heartRateData.isEmpty else { return 0 }
        return heartRateData.reduce(0, +) / Double(heartRateData.count)
    }
    
    var isValid: Bool {
        return qualityScore > 0.7 && confidence > 0.7
    }
    
    var patternHash: String {
        let data = heartRateData.map { String($0) }.joined(separator: ",")
        return data.data(using: .utf8)?.base64EncodedString() ?? ""
    }
    
    /// Calculates the pattern's unique characteristics
    var patternCharacteristics: PatternCharacteristics {
        return PatternCharacteristics(
            averageRate: heartRateData.reduce(0, +) / Double(heartRateData.count),
            variability: calculateVariability(),
            rhythmPattern: analyzeRhythmPattern(),
            amplitudePattern: analyzeAmplitudePattern()
        )
    }
    
    private func calculateVariability() -> Double {
        guard heartRateData.count > 1 else { return 0 }
        let mean = heartRateData.reduce(0, +) / Double(heartRateData.count)
        let variance = heartRateData.map { pow($0 - mean, 2) }.reduce(0, +) / Double(heartRateData.count)
        return sqrt(variance)
    }
    
    private func analyzeRhythmPattern() -> [Double] {
        // Analyze the rhythm pattern - this would be enhanced with XenonX algorithm
        return heartRateData.enumerated().map { index, value in
            if index == 0 { return 0 }
            return value - heartRateData[index - 1]
        }
    }
    
    private func analyzeAmplitudePattern() -> [Double] {
        // Analyze amplitude variations - normalized values
        let maxValue = heartRateData.max() ?? 1
        let minValue = heartRateData.min() ?? 1
        let range = maxValue - minValue
        
        return heartRateData.map { value in
            return range > 0 ? (value - minValue) / range : 0
        }
    }
}

/// Characteristics extracted from a heart pattern
struct PatternCharacteristics: Codable {
    let averageRate: Double
    let variability: Double
    let rhythmPattern: [Double]
    let amplitudePattern: [Double]
    
    /// Calculates similarity score with another pattern (0-100%)
    func similarityScore(with other: PatternCharacteristics) -> Double {
        let rateSimilarity = 1 - abs(averageRate - other.averageRate) / max(averageRate, other.averageRate)
        let variabilitySimilarity = 1 - abs(variability - other.variability) / max(variability, other.variability)
        let rhythmSimilarity = calculateArraySimilarity(rhythmPattern, other.rhythmPattern)
        let amplitudeSimilarity = calculateArraySimilarity(amplitudePattern, other.amplitudePattern)
        
        return (rateSimilarity + variabilitySimilarity + rhythmSimilarity + amplitudeSimilarity) / 4 * 100
    }
    
    private func calculateArraySimilarity(_ array1: [Double], _ array2: [Double]) -> Double {
        guard !array1.isEmpty && !array2.isEmpty else { return 0 }
        
        let minLength = min(array1.count, array2.count)
        let array1Prefix = Array(array1.prefix(minLength))
        let array2Prefix = Array(array2.prefix(minLength))
        
        var sum: Double = 0
        for i in 0..<minLength {
            let val1 = array1Prefix[i]
            let val2 = array2Prefix[i]
            let maxVal = max(val1, val2)
            if maxVal > 0 {
                let similarity = 1 - abs(val1 - val2) / maxVal
                sum += similarity
            }
        }
        
        return sum / Double(minLength)
    }
}