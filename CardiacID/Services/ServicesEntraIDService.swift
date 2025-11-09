import Foundation
import Combine

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
