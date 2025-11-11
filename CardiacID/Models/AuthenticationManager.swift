import Foundation
import HealthKit
import Combine

// MARK: - Auth Event (using the one from SuprabaseService)

// MARK: - Authentication State
enum AuthState: Equatable {
    case idle
    case authenticating
    case authenticated
    case warning
    case failed(String)
    
    var isAuthenticated: Bool {
        if case .authenticated = self {
            return true
        }
        return false
    }
    
    static func == (lhs: AuthState, rhs: AuthState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.authenticating, .authenticating), (.authenticated, .authenticated), (.warning, .warning):
            return true
        case (.failed(let lhsReason), .failed(let rhsReason)):
            return lhsReason == rhsReason
        default:
            return false
        }
    }
}

// MARK: - Cardiac Authentication Manager
class AuthenticationManager: ObservableObject {
    // Published properties
    @Published private(set) var authState: AuthState = .idle
    @Published private(set) var currentHeartRate: Int = 0
    @Published private(set) var lastVerificationTime: Date?
    @Published private(set) var isEnrolled: Bool = false
    @Published private(set) var isMonitoring: Bool = false
    @Published private(set) var lastAuthEvents: [AuthEvent] = []
    
    // Error publisher
    let errorPublisher = PassthroughSubject<String, Never>()
    
    // Health store
    private var healthStore: HKHealthStore?
    private var heartRateQuery: HKObserverQuery?
    private var cancellables = Set<AnyCancellable>()
    
    // Threshold settings
    private var sensitivityLevel: Int = 1 // 0 = low, 1 = medium, 2 = high
    private var baselinePattern: [Double] = []
    
    // Timer for continuous monitoring
    private var monitoringTimer: Timer?
    private var continuousMonitoring: Bool = true
    private var monitoringInterval: TimeInterval = 300 // 5 minutes by default
    
    init() {
        // Check if user is already enrolled
        isEnrolled = UserDefaults.standard.bool(forKey: "isEnrolled")
        
        // Load sensitivity setting
        sensitivityLevel = UserDefaults.standard.integer(forKey: "sensitivityLevel")
        
        // Load baseline pattern if available
        if let savedPattern = UserDefaults.standard.array(forKey: "baselinePattern") as? [Double] {
            baselinePattern = savedPattern
        }
        
        // Load monitoring settings
        continuousMonitoring = UserDefaults.standard.bool(forKey: "continuousMonitoring")
        if let interval = UserDefaults.standard.object(forKey: "monitoringInterval") as? TimeInterval {
            monitoringInterval = interval
        }
    }
    
    deinit {
        monitoringTimer?.invalidate()
    }
    
    // MARK: - Setup Methods
    
    func setupHealthStore() {
        // Initialize HealthKit store if available
        if HKHealthStore.isHealthDataAvailable() {
            healthStore = HKHealthStore()
            print("HealthKit store initialized successfully")
        } else {
            print("HealthKit is not available on this device - running in demo mode")
            // Don't send error for simulator, just run in demo mode
        }
    }
    
    func requestHealthKitPermissions() async -> Bool {
        guard let healthStore = healthStore else {
            errorPublisher.send("HealthKit is not available")
            return false
        }
        
        // Define the types to read
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!
        ]
        
        do {
            try await healthStore.requestAuthorization(toShare: Set<HKSampleType>(), read: typesToRead)
            return true
        } catch {
            let errorMsg = "Error requesting HealthKit authorization: \(error.localizedDescription)"
            print(errorMsg)
            errorPublisher.send(errorMsg)
            return false
        }
    }
    
    func refreshAuthenticationStatus() {
        // If user is authenticated, check if we need to re-verify based on time
        if case .authenticated = authState, let lastTime = lastVerificationTime {
            let timeElapsed = Date().timeIntervalSince(lastTime)
            
            // If more than monitoring interval has passed, re-authenticate
            if timeElapsed > monitoringInterval && continuousMonitoring {
                authenticate()
            }
        } else if authState == .idle && isEnrolled {
            // If idle but enrolled, start monitoring
            startMonitoring()
        }
    }
    
    // MARK: - Heart Rate Monitoring
    
    func startMonitoring() {
        // Check if we're in simulator or device without HealthKit
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit is not available - running in demo mode")
            authState = .idle
            return
        }
        
        guard let healthStore = healthStore else {
            print("HealthKit store not initialized - running in demo mode")
            authState = .idle
            return
        }
        
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            authState = .failed("Heart rate data type is not available")
            errorPublisher.send("Heart rate data type is not available")
            return
        }
        
        // Start the heart rate query
        let query = HKObserverQuery(sampleType: heartRateType, predicate: nil as NSPredicate?) { [weak self] (_, _, error) in
            if let error = error {
                let errorMsg = "Error observing heart rate: \(error.localizedDescription)"
                DispatchQueue.main.async {
                    self?.authState = .failed(errorMsg)
                    self?.errorPublisher.send(errorMsg)
                }
                return
            }
            
            self?.fetchLatestHeartRate()
        }
        
        heartRateQuery = query
        healthStore.execute(query)
        
        // Also start an immediate fetch
        fetchLatestHeartRate()
        
        // Setup continuous monitoring if enabled
        setupContinuousMonitoring()
        
        isMonitoring = true
    }
    
    private func setupContinuousMonitoring() {
        guard continuousMonitoring else { return }
        
        // Cancel any existing timer
        monitoringTimer?.invalidate()
        
        // Create a new timer to periodically check authentication
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: monitoringInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // If we're currently authenticated, refresh the status
            if case .authenticated = self.authState {
                self.authenticate()
            }
        }
    }
    
    func stopMonitoring() {
        // Stop the heart rate query if it exists
        if let healthStore = healthStore, let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        }
        
        // Stop the monitoring timer
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        
        isMonitoring = false
        authState = .idle
    }
    
    private func fetchLatestHeartRate() {
        guard let healthStore = healthStore else { return }
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        
        let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-60), end: nil, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        let query = HKSampleQuery(sampleType: heartRateType, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { [weak self] (_, samples, error) in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let error = error {
                    let errorMsg = "Error fetching heart rate: \(error.localizedDescription)"
                    self.authState = .failed(errorMsg)
                    self.errorPublisher.send(errorMsg)
                    return
                }
                
                guard let samples = samples, let sample = samples.first as? HKQuantitySample else {
                    // No recent heart rate samples
                    if case .authenticating = self.authState {
                        self.authState = .warning
                    }
                    return
                }
                
                let heartRate = Int(sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
                self.currentHeartRate = heartRate
                
                // If we're authenticating, use this heart rate for authentication
                if case .authenticating = self.authState {
                    self.verifyIdentity(withHeartRate: heartRate)
                }
            }
        }
        
        healthStore.execute(query)
    }
    
    // MARK: - Enrollment
    
    func setEnrolled(_ enrolled: Bool) {
        isEnrolled = enrolled
        UserDefaults.standard.set(enrolled, forKey: "isEnrolled")
    }
    
    func startEnrollment() async -> Bool {
        // Check and request permissions
        let permissionsGranted = await requestHealthKitPermissions()
        guard permissionsGranted else {
            return false
        }
        
        // Start collecting baseline pattern
        startMonitoring()
        authState = .authenticating
        
        // In a real implementation, we would collect multiple samples
        // over 2-3 minutes and process them into a baseline pattern
        
        // For this demo, we'll just simulate successful enrollment after a delay
        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        // Simulate a baseline pattern
        baselinePattern = [65.0, 68.0, 72.0, 70.0, 69.0]
        
        // Save the pattern
        UserDefaults.standard.set(baselinePattern, forKey: "baselinePattern")
        UserDefaults.standard.set(true, forKey: "isEnrolled")
        
        isEnrolled = true
        authState = .authenticated
        lastVerificationTime = Date()
        
        return true
    }
    
    // MARK: - Authentication
    
    func authenticate() {
        guard isEnrolled else {
            authState = .failed("User not enrolled")
            return
        }
        
        if !isMonitoring {
            startMonitoring()
        }
        
        authState = .authenticating
        
        // The actual verification will happen when heart rate data comes in
        // See verifyIdentity method
    }
    
    private func verifyIdentity(withHeartRate heartRate: Int) {
        guard !baselinePattern.isEmpty else {
            authState = .failed("No baseline pattern available")
            return
        }
        
        // In a real implementation, this would compare the current heart rate
        // pattern against the stored baseline using sophisticated algorithms
        
        // For this demo, we'll simulate authentication with a simple check
        let averageBaseline = baselinePattern.reduce(0, +) / Double(baselinePattern.count)
        let difference = abs(Double(heartRate) - averageBaseline)
        
        // Different thresholds based on sensitivity level
        let thresholds = [15.0, 10.0, 5.0] // Low, Medium, High sensitivity
        let threshold = thresholds[sensitivityLevel]
        
        if difference <= threshold {
            authState = .authenticated
            lastVerificationTime = Date()
            
            // Save this successful authentication
            saveAuthenticationEvent(success: true)
        } else {
            authState = .failed("Heart pattern does not match")
            
            // Save this failed authentication
            saveAuthenticationEvent(success: false)
        }
    }
    
    // MARK: - Settings
    
    func setSensitivityLevel(_ level: Int) {
        guard (0...2).contains(level) else { return }
        sensitivityLevel = level
        UserDefaults.standard.set(level, forKey: "sensitivityLevel")
    }
    
    // MARK: - Event Logging

    private func saveAuthenticationEvent(success: Bool) {
        // Create a new auth event with correct AuthEvent structure
        let event = AuthEvent(
            id: UUID().uuidString,
            userId: "current_user_id", // TODO: Get from actual auth context
            eventType: .biometricAuth,
            timestamp: Date(),
            deviceId: UIDevice.current.identifierForVendor?.uuidString,
            ipAddress: nil,
            location: nil,
            success: success,
            metadata: [
                "heartRate": "\(currentHeartRate)",
                "details": success ? "Authentication successful" : "Authentication failed"
            ]
        )

        // Add to the recent events list
        lastAuthEvents.insert(event, at: 0)

        // Limit the list to the 10 most recent events
        if lastAuthEvents.count > 10 {
            lastAuthEvents = Array(lastAuthEvents.prefix(10))
        }

        // In a real app, this would also save to Core Data or a remote database
        print("Authentication \(success ? "successful" : "failed") at \(Date())")
    }
    
    // MARK: - Continuous Authentication Settings
    
    func setContinuousMonitoring(enabled: Bool) {
        continuousMonitoring = enabled
        UserDefaults.standard.set(enabled, forKey: "continuousMonitoring")
        
        if enabled && isMonitoring {
            setupContinuousMonitoring()
        } else {
            monitoringTimer?.invalidate()
            monitoringTimer = nil
        }
    }
    
    func setMonitoringInterval(_ interval: TimeInterval) {
        guard interval >= 60 else { return } // Minimum 1 minute
        
        monitoringInterval = interval
        UserDefaults.standard.set(interval, forKey: "monitoringInterval")
        
        // Reset the timer if we're monitoring
        if continuousMonitoring && isMonitoring {
            setupContinuousMonitoring()
        }
    }
}
