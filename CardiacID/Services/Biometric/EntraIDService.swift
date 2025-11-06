import Foundation
import Combine

/// Protocol defining EntraID authentication service capabilities
protocol EntraIDService: ObservableObject {
    var isAuthenticated: Bool { get }
    var currentUser: EntraIDUser? { get }
    var errorMessage: String? { get }
    
    func signIn() async throws
    func signOut() async throws  
    func refreshToken() async throws
    func getCurrentUser() async throws -> EntraIDUser?
    func checkAuthenticationStatus() async -> Bool
}

/// Mock implementation for development/testing
class MockEntraIDService: EntraIDService, ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var currentUser: EntraIDUser?
    @Published var errorMessage: String?
    
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
    
    func signIn() async throws {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Simulate random success/failure for testing
        if Bool.random() {
            currentUser = mockUsers.randomElement()
            isAuthenticated = true
            errorMessage = nil
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
}