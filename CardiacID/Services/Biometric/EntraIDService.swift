import Foundation
import Foundation
import Combine

// MARK: - Service State Management Types

/// Represents the current state of an external service or connector
public enum ServiceState: String, CaseIterable {
    case available = "available"
    case connecting = "connecting"
    case connected = "connected"
    case hold = "hold"
    case unavailable = "unavailable"
    case error = "error"
}

/// Information about why a service is in hold state
public struct HoldStateInfo {
    let reason: String
    let suggestedAction: String
    let canRetry: Bool
    let estimatedResolution: TimeInterval?
    
    static let missingCredentials = HoldStateInfo(
        reason: "Missing authentication credentials",
        suggestedAction: "Configure credentials in Settings",
        canRetry: true,
        estimatedResolution: nil
    )
    
    static let networkUnavailable = HoldStateInfo(
        reason: "Network connection unavailable",
        suggestedAction: "Check internet connection",
        canRetry: true,
        estimatedResolution: 30
    )
    
    static let serviceUnavailable = HoldStateInfo(
        reason: "External service temporarily unavailable",
        suggestedAction: "Service will retry automatically",
        canRetry: false,
        estimatedResolution: 60
    )
    
    static let permissionsRequired = HoldStateInfo(
        reason: "Required permissions not granted",
        suggestedAction: "Grant permissions in Settings",
        canRetry: true,
        estimatedResolution: nil
    )
    
    static let configurationRequired = HoldStateInfo(
        reason: "Service configuration incomplete",
        suggestedAction: "Complete setup in Settings",
        canRetry: true,
        estimatedResolution: nil
    )
}

/// Protocol for services that can be put on hold
@MainActor
public protocol HoldableService: ObservableObject {
    var serviceState: ServiceState { get }
    var holdInfo: HoldStateInfo? { get }
    var lastError: Error? { get }
    
    func putOnHold(reason: HoldStateInfo)
    func resumeFromHold() async throws
    func checkAvailability() async -> Bool
}

/// Mock Service State Manager
@MainActor
public class ServiceStateManager: ObservableObject {
    public static let shared = ServiceStateManager()
    
    @Published public var services: [String: ServiceState] = [:]
    @Published public var holdReasons: [String: HoldStateInfo] = [:]
    
    private init() {}
    
    public func registerService(_ serviceName: String, initialState: ServiceState = .available) {
        services[serviceName] = initialState
    }
    
    public func updateServiceState(_ serviceName: String, to state: ServiceState, holdInfo: HoldStateInfo? = nil) {
        services[serviceName] = state
        if let holdInfo = holdInfo {
            holdReasons[serviceName] = holdInfo
        } else {
            holdReasons.removeValue(forKey: serviceName)
        }
    }
    
    public func getServiceStatus(_ serviceName: String) -> (state: ServiceState, holdInfo: HoldStateInfo?) {
        let state = services[serviceName] ?? .unavailable
        let holdInfo = holdReasons[serviceName]
        return (state, holdInfo)
    }
    
    public func getAllServicesInHold() -> [String: HoldStateInfo] {
        return holdReasons
    }
    
    // Pre-defined service names
    public static let entraIDService = "EntraID Authentication"
    public static let bluetoothService = "Bluetooth Connectivity"
    public static let nfcService = "NFC Communication"
    public static let healthKitService = "HealthKit Integration"
    public static let supabaseService = "Supabase Backend"
    public static let passwordlessService = "Passwordless Authentication"
    public static let watchConnectivity = "Apple Watch Connectivity"
    
    public func setupDefaultServices() {
        registerService(Self.entraIDService)
        registerService(Self.bluetoothService)
        registerService(Self.nfcService)
        registerService(Self.healthKitService)
        registerService(Self.supabaseService)
        registerService(Self.passwordlessService)
        registerService(Self.watchConnectivity)
    }
}

/// Protocol defining EntraID authentication service capabilities
/// Available in both DEMO_MODE and PRODUCTION_MODE
@MainActor
protocol EntraIDService: ObservableObject {
    var isAuthenticated: Bool { get }
    var currentUser: EntraIDUser? { get }
    var errorMessage: String? { get }
    
    // Publishers for reactive UI
    var isAuthenticatedPublisher: Published<Bool>.Publisher { get }
    var errorMessagePublisher: Published<String?>.Publisher { get }

    func signIn() async throws -> EntraIDUser
    func signOut() async throws
    func refreshToken() async throws
    func getCurrentUser() async throws -> EntraIDUser?
    func checkAuthenticationStatus() async -> Bool
}

// MARK: - Mock Implementation
/// Mock implementation for development/testing
@MainActor
class MockEntraIDService: EntraIDService, HoldableService, ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var currentUser: EntraIDUser?
    @Published var errorMessage: String?
    @Published var serviceState: ServiceState = .available
    @Published var holdInfo: HoldStateInfo?
    @Published var lastError: Error?
    
    // Publishers for reactive UI
    var isAuthenticatedPublisher: Published<Bool>.Publisher { $isAuthenticated }
    var errorMessagePublisher: Published<String?>.Publisher { $errorMessage }
    
    private let serviceStateManager = ServiceStateManager.shared
    
    private var mockUsers: [EntraIDUser] = [
        EntraIDUser(
            id: "mock-user-1",
            displayName: "John Doe",
            email: "john.doe@company.com",
            jobTitle: "Software Engineer",
            department: "IT",
            permissions: ["user.read", "device.manage"],
            groups: ["Developers", "IT Team"],
            tenantId: "mock-tenant-id",
            userPrincipalName: "john.doe@company.com"
        ),
        EntraIDUser(
            id: "mock-user-2",
            displayName: "Jane Smith",
            email: "jane.smith@company.com",
            jobTitle: "IT Administrator", 
            department: "IT",
            permissions: ["user.read", "user.write", "admin.access", "device.manage"],
            groups: ["Administrators", "IT Team"],
            tenantId: "mock-tenant-id",
            userPrincipalName: "jane.smith@company.com"
        )
    ]
    
    init() {
        serviceStateManager.registerService(ServiceStateManager.entraIDService, initialState: .available)
    }
    
    func signIn() async throws -> EntraIDUser {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Simulate random success/failure for testing
        if Bool.random() {
            let user = mockUsers.randomElement()!
            currentUser = user
            isAuthenticated = true
            errorMessage = nil
            return user
        } else {
            throw APIError.authenticationError("Mock authentication failed")
        }
    }
    
    func signOut() async throws {
        currentUser = nil
        isAuthenticated = false
        errorMessage = nil
    }
    
    func refreshToken() async throws {
        guard isAuthenticated else {
            throw APIError.authenticationError("Not authenticated")
        }
        
        // Simulate token refresh
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Simulate occasional refresh failure
        if !Bool.random() {
            throw APIError.authenticationError("Token refresh failed")
        }
    }
    
    func getCurrentUser() async throws -> EntraIDUser? {
        return currentUser
    }
    
    func checkAuthenticationStatus() async -> Bool {
        return isAuthenticated
    }
    
    // MARK: - HoldableService Implementation
    
    func putOnHold(reason: HoldStateInfo) {
        holdInfo = reason
        serviceState = .hold
        isAuthenticated = false
        currentUser = nil
        errorMessage = reason.reason
        serviceStateManager.updateServiceState(
            ServiceStateManager.entraIDService,
            to: .hold,
            holdInfo: reason
        )
    }
    
    func resumeFromHold() async throws {
        guard serviceState == .hold else { return }
        
        serviceState = .connecting
        holdInfo = nil
        errorMessage = nil
        lastError = nil
        
        serviceStateManager.updateServiceState(
            ServiceStateManager.entraIDService,
            to: .connecting
        )
        
        // Simulate reconnection delay
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        serviceState = .available
        serviceStateManager.updateServiceState(
            ServiceStateManager.entraIDService,
            to: .available
        )
        
        print("✅ Mock EntraID service resumed from hold")
    }
    
    func checkAvailability() async -> Bool {
        // Mock always returns true for availability
        return true
    }
}

// MARK: - Factory Method
/// Factory to create the appropriate EntraID service based on configuration
class EntraIDServiceFactory {
    @MainActor
    static func create() -> any EntraIDService {
        #if DEMO_MODE
        return MockEntraIDService()
        #else
        return EntraIDAuthClient()
        #endif
    }
}
