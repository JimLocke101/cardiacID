import Foundation
import Combine

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
    static func create() -> any EntraIDService {
        #if DEMO_MODE
        return MockEntraIDService()
        #else
        return EntraIDAuthClient()
        #endif
    }
}
