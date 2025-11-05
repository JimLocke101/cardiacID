import Foundation
import Combine

/// Manager for coordinating authentication services and managing authentication state
class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var authenticationState: AuthenticationState = .idle
    @Published var currentUser: UserProfile?
    @Published var errorMessage: String?
    
    private let authenticationService: AuthenticationService
    private let healthKitService: HealthKitService
    private let dataManager: DataManager
    // SupabaseService not available in watch app
    private let backgroundTaskService: BackgroundTaskService
    private let bluetoothNFCService: BluetoothNFCService
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        self.authenticationService = AuthenticationService()
        self.healthKitService = HealthKitService()
        self.dataManager = DataManager()
        // Supabase service not available in watch app
        self.backgroundTaskService = BackgroundTaskService()
        self.bluetoothNFCService = BluetoothNFCService()
        
        setupServices()
        setupBindings()
    }
    
    // MARK: - Setup
    
    private func setupServices() {
        // Set up service dependencies
        // Supabase service not available in watch app
        
        // Load current user
        currentUser = dataManager.userProfile
        isAuthenticated = currentUser?.isEnrolled ?? false
    }
    
    private func setupBindings() {
        // Bind authentication service state
        authenticationService.$isAuthenticated
            .assign(to: \.isAuthenticated, on: self)
            .store(in: &cancellables)
        
        authenticationService.$isUserEnrolled
            .sink { [weak self] isEnrolled in
                self?.isAuthenticated = isEnrolled
            }
            .store(in: &cancellables)
        
        // Bind error messages
        authenticationService.$errorMessage
            .assign(to: \.errorMessage, on: self)
            .store(in: &cancellables)
        
        healthKitService.$errorMessage
            .sink { [weak self] error in
                if let error = error {
                    self?.errorMessage = error
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Authentication Flow
    
    /// Start enrollment process
    func startEnrollment() {
        authenticationState = .enrolling
        
        // Start heart rate capture
        healthKitService.startHeartRateCapture()
        
        // Listen for completion
        healthKitService.heartRatePublisher
            .sink { [weak self] samples in
                self?.completeEnrollment(with: samples)
            }
            .store(in: &cancellables)
    }
    
    /// Complete enrollment with heart rate samples
    private func completeEnrollment(with samples: [HeartRateSample]) {
        let heartRateData = samples.map { $0.value }
        
        // Validate data
        guard healthKitService.validateHeartRateData(samples) else {
            authenticationState = .error("Invalid heart rate data")
            return
        }
        
        // Complete enrollment
        let success = authenticationService.completeEnrollment(with: heartRateData)
        
        if success {
            authenticationState = .enrolled
            currentUser = dataManager.userProfile
        } else {
            authenticationState = .error(authenticationService.errorMessage ?? "Enrollment failed")
        }
    }
    
    /// Start authentication process
    func startAuthentication() {
        guard authenticationService.isUserEnrolled else {
            authenticationState = .error("User not enrolled")
            return
        }
        
        authenticationState = .authenticating
        
        // Start heart rate capture
        healthKitService.startHeartRateCapture()
        
        // Listen for completion
        healthKitService.heartRatePublisher
            .sink { [weak self] samples in
                self?.completeAuthentication(with: samples)
            }
            .store(in: &cancellables)
    }
    
    /// Complete authentication with heart rate samples
    private func completeAuthentication(with samples: [HeartRateSample]) {
        let heartRateData = samples.map { $0.value }
        
        // Validate data
        guard healthKitService.validateHeartRateData(samples) else {
            authenticationState = .error("Invalid heart rate data")
            return
        }
        
        // Complete authentication
        let result = authenticationService.completeAuthentication(with: heartRateData)
        
        switch result {
        case .success, .approved:
            authenticationState = .authenticated
        case .retryRequired:
            authenticationState = .retryRequired
        case .failure, .failed:
            authenticationState = .error("Authentication failed")
        case .pending:
            authenticationState = .error("Authentication pending")
        case .cancelled:
            authenticationState = .error("Authentication cancelled")
        case .systemUnavailable:
            authenticationState = .error("System unavailable")
        }
    }
    
    /// Retry authentication
    func retryAuthentication() {
        startAuthentication()
    }
    
    /// Logout user
    func logout() {
        authenticationService.endCurrentSession()
        authenticationState = .idle
        isAuthenticated = false
    }
    
    // MARK: - Background Authentication
    
    /// Perform background authentication
    func performBackgroundAuthentication() {
        guard authenticationService.isUserEnrolled else { return }
        
        // This would be called by the background task service
        let result = authenticationService.performBackgroundAuthentication()
        
        switch result {
        case .success, .approved:
            isAuthenticated = true
        case .retryRequired, .failure, .failed, .pending, .cancelled, .systemUnavailable:
            isAuthenticated = false
        }
    }
    
    // MARK: - Data Synchronization
    
    /// Sync all data to Supabase
    func syncAllData() {
        // Supabase service not available in watch app
        // Data synchronization would be handled by the iOS companion app
    }
    
    // MARK: - Error Handling
    
    func clearError() {
        errorMessage = nil
        authenticationService.clearError()
        healthKitService.clearError()
        // Supabase service not available in watch app
        bluetoothNFCService.clearError()
    }
    
    // MARK: - Service Access
    
    var healthKit: HealthKitService { healthKitService }
    var authentication: AuthenticationService { authenticationService }
    var data: DataManager { dataManager }
    // Supabase service not available in watch app
    var background: BackgroundTaskService { backgroundTaskService }
    var bluetoothNFC: BluetoothNFCService { bluetoothNFCService }
}

// MARK: - Authentication State

enum AuthenticationState {
    case idle
    case enrolling
    case enrolled
    case authenticating
    case authenticated
    case retryRequired
    case error(String)
    
    var isActive: Bool {
        switch self {
        case .enrolling, .authenticating:
            return true
        default:
            return false
        }
    }
    
    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .enrolling: return "Enrolling"
        case .enrolled: return "Enrolled"
        case .authenticating: return "Authenticating"
        case .authenticated: return "Authenticated"
        case .retryRequired: return "Retry Required"
        case .error: return "Error"
        }
    }
}