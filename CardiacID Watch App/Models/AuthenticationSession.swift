import Foundation

/// Authentication result enum
enum AuthenticationResult: String, CaseIterable, Codable {
    case success = "success"
    case failure = "failure"
    case pending = "pending"
    case cancelled = "cancelled"
    case failed = "failed"
    case approved = "approved"
    case retryRequired = "retryRequired"
    case systemUnavailable = "systemUnavailable"
    
    var isSuccessful: Bool {
        return self == .success || self == .approved
    }
    
    var message: String {
        switch self {
        case .success, .approved:
            return "Authentication successful"
        case .failure, .failed:
            return "Authentication failed"
        case .pending:
            return "Authentication pending"
        case .cancelled:
            return "Authentication cancelled"
        case .retryRequired:
            return "Retry required"
        case .systemUnavailable:
            return "System unavailable"
        }
    }
    
    var requiresRetry: Bool {
        return self == .retryRequired
    }
}

/// Represents an authentication session
class AuthenticationSession: ObservableObject {
    @Published var sessionId: UUID
    @Published var startTime: Date
    @Published var endTime: Date?
    @Published var isActive: Bool
    @Published var attempts: [AuthenticationAttempt]
    @Published var successCount: Int
    @Published var failureCount: Int
    
    init() {
        self.sessionId = UUID()
        self.startTime = Date()
        self.endTime = nil
        self.isActive = true
        self.attempts = []
        self.successCount = 0
        self.failureCount = 0
    }
    
    /// Start a new session
    func startSession() {
        self.sessionId = UUID()
        self.startTime = Date()
        self.endTime = nil
        self.isActive = true
        self.attempts.removeAll()
        self.successCount = 0
        self.failureCount = 0
    }
    
    /// End the current session
    func endSession() {
        self.endTime = Date()
        self.isActive = false
    }
    
    /// Reset the session
    func resetSession() {
        self.sessionId = UUID()
        self.startTime = Date()
        self.endTime = nil
        self.isActive = true
        self.attempts.removeAll()
        self.successCount = 0
        self.failureCount = 0
    }
    
    /// Record an authentication attempt
    func recordAttempt(_ result: AuthenticationResult) {
        let attempt = AuthenticationAttempt(
            result: result,
            confidenceScore: 0, // This would be set by the calling code
            patternMatch: 0, // This would be set by the calling code
            duration: 0, // This would be calculated by the calling code
            timestamp: Date()
        )
        
        attempts.append(attempt)
        
        if result.isSuccessful {
            successCount += 1
        } else {
            failureCount += 1
        }
    }
    
    /// Get session duration
    var duration: TimeInterval {
        let endTime = self.endTime ?? Date()
        return endTime.timeIntervalSince(startTime)
    }
    
    /// Get success rate for this session
    var successRate: Double {
        let totalAttempts = attempts.count
        guard totalAttempts > 0 else { return 0 }
        return Double(successCount) / Double(totalAttempts) * 100
    }
    
    /// Get average confidence score for this session
    var averageConfidence: Double {
        guard !attempts.isEmpty else { return 0 }
        let totalConfidence = attempts.map { $0.confidenceScore }.reduce(0, +)
        return totalConfidence / Double(attempts.count)
    }
    
    /// Get average pattern match for this session
    var averagePatternMatch: Double {
        guard !attempts.isEmpty else { return 0 }
        let totalMatch = attempts.map { $0.patternMatch }.reduce(0, +)
        return totalMatch / Double(attempts.count)
    }
}

/// Represents a single authentication attempt
struct AuthenticationAttempt: Identifiable, Codable {
    let id: UUID
    let result: AuthenticationResult
    let confidenceScore: Double
    let patternMatch: Double
    let duration: TimeInterval
    let timestamp: Date
    
    init(result: AuthenticationResult, confidenceScore: Double, patternMatch: Double, duration: TimeInterval, timestamp: Date = Date()) {
        self.id = UUID()
        self.result = result
        self.confidenceScore = confidenceScore
        self.patternMatch = patternMatch
        self.duration = duration
        self.timestamp = timestamp
    }
}

/// Data structure for syncing authentication attempts to Supabase
struct AuthenticationAttemptData: Codable {
    let id: UUID
    let user_id: UUID
    let result: AuthenticationResult
    let confidenceScore: Double
    let patternMatch: Double
    let duration: TimeInterval
    let timestamp: Date
    let created_at: Date
    
    init(id: UUID, user_id: UUID, result: AuthenticationResult, confidenceScore: Double, patternMatch: Double, duration: TimeInterval, timestamp: Date, created_at: Date = Date()) {
        self.id = id
        self.user_id = user_id
        self.result = result
        self.confidenceScore = confidenceScore
        self.patternMatch = patternMatch
        self.duration = duration
        self.timestamp = timestamp
        self.created_at = created_at
    }
}

// MARK: - App Statistics

struct AppStatistics: Codable {
    let launchCount: Int
    let firstLaunchDate: Date?
    let lastAuthenticationDate: Date?
    let isUserEnrolled: Bool
    
    init(launchCount: Int, firstLaunchDate: Date?, lastAuthenticationDate: Date?, isUserEnrolled: Bool) {
        self.launchCount = launchCount
        self.firstLaunchDate = firstLaunchDate
        self.lastAuthenticationDate = lastAuthenticationDate
        self.isUserEnrolled = isUserEnrolled
    }
}
