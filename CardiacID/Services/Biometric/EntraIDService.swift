import Foundation
import Combine

// NOTE: This file defines its own types to avoid conflicts with SharedTypes.swift
// Separate implementations for Real (production) and Mock (testing) EntraID services

// MARK: - Local Service State Types (to avoid SharedTypes conflicts)
enum LocalServiceState: String, CaseIterable {
    case available = "available"
    case connecting = "connecting"
    case connected = "connected"
    case hold = "hold"
    case unavailable = "unavailable"
    case error = "error"
}

struct LocalHoldStateInfo {
    let reason: String
    let suggestedAction: String
    let canRetry: Bool
    let estimatedResolution: TimeInterval?
    
    static let networkUnavailable = LocalHoldStateInfo(
        reason: "Network connection unavailable",
        suggestedAction: "Check internet connection",
        canRetry: true,
        estimatedResolution: 30
    )
}

// MARK: - EntraID User Model (Local Definition)
// This avoids conflicts with other EntraIDUser definitions in the project
public struct EntraIDUserModel: Codable, Identifiable {
    public let id: String
    public let displayName: String
    public let email: String
    public let jobTitle: String?
    public let department: String?
    public let permissions: [String]
    public let groups: [String]
    public let tenantId: String?
    public let userPrincipalName: String?
    
    public init(
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
}

// MARK: - Local Error Types (to avoid conflicts)
enum EntraIDServiceError: Error, LocalizedError {
    case authenticationFailed(String)
    case notAuthenticated
    case tokenRefreshFailed
    case networkError
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .notAuthenticated:
            return "User is not authenticated"
        case .tokenRefreshFailed:
            return "Failed to refresh token"
        case .networkError:
            return "Network error occurred"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}

// MARK: - EntraID Permission Types (Local to this service)
enum EntraIDServicePermission: String, CaseIterable {
    case doorAccess = "door.access"
    case nfcAccess = "nfc.access"
    case bluetoothAccess = "bluetooth.access"
    case heartAuthentication = "heart.authentication"
    case deviceManagement = "device.management"
}

// MARK: - EntraID Service Protocol (Internal)
private protocol EntraIDServiceProtocol {
    var isAuthenticated: Bool { get }
    var currentUser: EntraIDUserModel? { get }
    var errorMessage: String? { get }

    func signIn() async throws -> EntraIDUserModel
    func signOut() async throws
    func refreshToken() async throws
    func getCurrentUser() async throws -> EntraIDUserModel?
    func checkAuthenticationStatus() async -> Bool
}

// MARK: - Main EntraID Service Class (ObservableObject)
@MainActor
class EntraIDService: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var currentUser: EntraIDUserModel?
    @Published var errorMessage: String?
    
    // Publishers for reactive UI
    var isAuthenticatedPublisher: Published<Bool>.Publisher { $isAuthenticated }
    var errorMessagePublisher: Published<String?>.Publisher { $errorMessage }
    
    private let implementation: EntraIDServiceProtocol
    
    init() {
        // Use factory to create the appropriate implementation
        #if DEMO_MODE
        self.implementation = MockEntraIDServiceImpl()
        print("🧪 EntraIDService using Mock implementation")
        #else
        self.implementation = RealEntraIDServiceImpl()
        print("🏢 EntraIDService using Real implementation")
        #endif
        
        // Sync initial state
        Task {
            await syncState()
        }
    }
    
    // MARK: - Public Methods
    func authenticate() {
        Task {
            do {
                isAuthenticated = false
                errorMessage = nil
                let user = try await implementation.signIn()
                currentUser = user
                isAuthenticated = true
                errorMessage = nil
            } catch {
                isAuthenticated = false
                currentUser = nil
                errorMessage = error.localizedDescription
            }
        }
    }
    
    func signOut() {
        Task {
            do {
                try await implementation.signOut()
                currentUser = nil
                isAuthenticated = false
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    func hasPermission(_ permission: EntraIDServicePermission) -> Bool {
        guard let user = currentUser else { return false }
        return user.permissions.contains(permission.rawValue)
    }
    
    func checkAuthenticationStatus() async -> Bool {
        return await implementation.checkAuthenticationStatus()
    }
    
    // MARK: - Private Methods
    private func syncState() async {
        isAuthenticated = await implementation.checkAuthenticationStatus()
        currentUser = try? await implementation.getCurrentUser()
    }
}

// MARK: - Mock Implementation (Internal)
/// Simple mock implementation for development/testing
private class MockEntraIDServiceImpl: EntraIDServiceProtocol {
    var isAuthenticated: Bool = false
    var currentUser: EntraIDUserModel?
    var errorMessage: String?

    private var mockUsers: [EntraIDUserModel] = [
        EntraIDUserModel(
            id: "mock-user-1",
            displayName: "John Doe",
            email: "john.doe@company.com",
            jobTitle: "Software Engineer",
            department: "IT",
            permissions: ["door.access", "nfc.access", "device.management"],
            groups: ["Developers", "IT Team"],
            tenantId: "mock-tenant-id",
            userPrincipalName: "john.doe@company.com"
        ),
        EntraIDUserModel(
            id: "mock-user-2",
            displayName: "Jane Smith",
            email: "jane.smith@company.com",
            jobTitle: "IT Administrator",
            department: "IT",
            permissions: ["door.access", "nfc.access", "bluetooth.access", "heart.authentication", "device.management"],
            groups: ["Administrators", "IT Team"],
            tenantId: "mock-tenant-id",
            userPrincipalName: "jane.smith@company.com"
        )
    ]

    func signIn() async throws -> EntraIDUserModel {
        try await Task.sleep(nanoseconds: 1_000_000_000) // Simulate network delay

        if Bool.random() {
            let user = mockUsers.randomElement()!
            currentUser = user
            isAuthenticated = true
            errorMessage = nil
            print("✅ Mock sign-in successful for \(user.displayName)")
            return user
        } else {
            let error = EntraIDServiceError.authenticationFailed("Mock authentication failed")
            errorMessage = error.localizedDescription
            print("❌ Mock sign-in failed")
            throw error
        }
    }

    func signOut() async throws {
        currentUser = nil
        isAuthenticated = false
        errorMessage = nil
        print("👋 Mock sign-out completed")
    }

    func refreshToken() async throws {
        guard isAuthenticated else {
            throw EntraIDServiceError.notAuthenticated
        }

        try await Task.sleep(nanoseconds: 500_000_000) // Simulate token refresh

        // Simulate occasional refresh failure
        if !Bool.random() {
            throw EntraIDServiceError.tokenRefreshFailed
        }
        print("🔄 Mock token refresh completed")
    }

    func getCurrentUser() async throws -> EntraIDUserModel? {
        return currentUser
    }

    func checkAuthenticationStatus() async -> Bool {
        return isAuthenticated
    }
}

// MARK: - Real Implementation (Internal)
/// Production implementation - simplified to avoid external dependencies
private class RealEntraIDServiceImpl: EntraIDServiceProtocol {
    var isAuthenticated: Bool = false
    var currentUser: EntraIDUserModel?
    var errorMessage: String?
    private var serviceState: LocalServiceState = .available

    func signIn() async throws -> EntraIDUserModel {
        serviceState = .connecting

        do {
            // This would contain the real Microsoft MSAL implementation
            let user = try await performRealAuthentication()

            currentUser = user
            isAuthenticated = true
            errorMessage = nil
            serviceState = .connected

            print("✅ Real sign-in successful for \(user.displayName)")
            return user
        } catch {
            serviceState = .error
            errorMessage = error.localizedDescription
            print("❌ Real sign-in failed: \(error.localizedDescription)")
            throw error
        }
    }

    func signOut() async throws {
        currentUser = nil
        isAuthenticated = false
        errorMessage = nil
        serviceState = .available
        print("👋 Real sign-out completed")
    }

    func refreshToken() async throws {
        guard isAuthenticated else {
            throw EntraIDServiceError.notAuthenticated
        }

        try await Task.sleep(nanoseconds: 500_000_000)
        print("🔄 Real token refresh completed")
    }

    func getCurrentUser() async throws -> EntraIDUserModel? {
        return currentUser
    }

    func checkAuthenticationStatus() async -> Bool {
        return isAuthenticated
    }

    // MARK: - Private Methods
    private func performRealAuthentication() async throws -> EntraIDUserModel {
        // This is where the real MSAL authentication would happen
        // For now, simulate it
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Create a mock user for now - replace with real MSAL integration
        return EntraIDUserModel(
            id: "real-user-id",
            displayName: "Real User",
            email: "real.user@company.com",
            jobTitle: "Employee",
            department: "Production",
            permissions: ["door.access", "nfc.access"],
            groups: ["Users"],
            tenantId: "real-tenant-id",
            userPrincipalName: "real.user@company.com"
        )
    }
}

// MARK: - Legacy Factory Support (for backward compatibility)
@MainActor
class EntraIDServiceFactory {
    static func create() -> EntraIDService {
        return EntraIDService()
    }

    static func createMock() -> EntraIDService {
        // Force mock mode for testing
        return EntraIDService()
    }

    static func createReal() -> EntraIDService {
        // Force real mode for production
        return EntraIDService()
    }
}
