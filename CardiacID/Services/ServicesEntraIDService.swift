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

/// EntraID User model
struct EntraIDUser: Codable, Identifiable {
    let id: String
    let displayName: String
    let email: String
    let jobTitle: String?
    let department: String?
    let permissions: [String]
    let groups: [String]
    let tenantId: String?
    let userPrincipalName: String?
    
    init(
        id: String,
        displayName: String,
        email: String,
        jobTitle: String? = nil,
        department: String? = nil,
        permissions: [String] = [],
        groups: [String] = [],
        tenantId: String? = nil,
        userPrincipalName: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.jobTitle = jobTitle
        self.department = department
        self.permissions = permissions
        self.groups = groups
        self.tenantId = tenantId
        self.userPrincipalName = userPrincipalName
    }
    
    // MARK: - Computed Properties
    
    var fullDisplayName: String {
        if let title = jobTitle {
            return "\(displayName) (\(title))"
        }
        return displayName
    }
    
    var hasAdminPermissions: Bool {
        return permissions.contains { $0.lowercased().contains("admin") }
    }
    
    var initials: String {
        let components = displayName.components(separatedBy: " ")
        let initials = components.compactMap { $0.first }.map { String($0) }
        return initials.joined()
    }
}

/// Default implementation of EntraIDService using EntraIDAuthClient
extension EntraIDAuthClient: EntraIDService {
    func signIn() async throws {
        try await signInInteractively()
    }
    
    func signOut() async throws {
        try await signOutUser()
    }
    
    func refreshToken() async throws {
        try await acquireTokenSilently()
    }
    
    func getCurrentUser() async throws -> EntraIDUser? {
        return currentUser
    }
    
    func checkAuthenticationStatus() async -> Bool {
        return isAuthenticated
    }
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