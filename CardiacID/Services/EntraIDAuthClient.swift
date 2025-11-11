//
//  EntraIDAuthClient.swift
//  HeartID Mobile
//
//  Production EntraID (Azure AD) authentication using Microsoft Authentication Library (MSAL)
//  Replaces mock EntraIDService with real OAuth 2.0 implementation
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(MSAL)
import MSAL
#endif
import Combine

// Using existing SecureCredentialManager and EnvironmentConfig from their respective files

class MicrosoftGraphClient {
    private let accessToken: String
    private let baseURL = "https://graph.microsoft.com/v1.0"
    
    init(accessToken: String) {
        self.accessToken = accessToken
    }
    
    // MARK: - User Profile
    
    func getUserProfile() async throws -> GraphUserProfile {
        let url = URL(string: "\(baseURL)/me")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GraphAPIError.requestFailed
        }

        return try JSONDecoder().decode(GraphUserProfile.self, from: data)
    }

    // MARK: - Applications

    func getUserApplications() async throws -> [GraphApplication] {
        let url = URL(string: "\(baseURL)/me/ownedObjects")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GraphAPIError.requestFailed
        }

        struct ApplicationsResponse: Codable {
            let value: [GraphApplication]
        }

        let applicationsResponse = try JSONDecoder().decode(ApplicationsResponse.self, from: data)
        return applicationsResponse.value
    }

    // MARK: - Groups

    func getUserGroups() async throws -> [GraphGroup] {
        let url = URL(string: "\(baseURL)/me/memberOf")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GraphAPIError.requestFailed
        }

        struct GroupsResponse: Codable {
            let value: [GraphGroup]
        }

        let groupsResponse = try JSONDecoder().decode(GroupsResponse.self, from: data)
        return groupsResponse.value
    }

    // MARK: - Directory Objects (for permissions)

    func getDirectoryObjects() async throws -> [GraphDirectoryObject] {
        let url = URL(string: "\(baseURL)/me/getMemberObjects")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["securityEnabledOnly": true]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GraphAPIError.requestFailed
        }

        struct DirectoryObjectsResponse: Codable {
            let value: [String]
        }

        let objectsResponse = try JSONDecoder().decode(DirectoryObjectsResponse.self, from: data)

        return objectsResponse.value.map { GraphDirectoryObject(id: $0) }
    }
}

struct GraphUserProfile: Codable {
    let id: String
    let displayName: String?
    let mail: String?
    let userPrincipalName: String
    let jobTitle: String?
    let department: String?
}

enum GraphAPIError: LocalizedError {
    case requestFailed
    case invalidResponse
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "Microsoft Graph API request failed"
        case .invalidResponse:
            return "Invalid response from Microsoft Graph API"
        case .decodingError:
            return "Failed to decode Microsoft Graph API response"
        }
    }
}

// MARK: - EntraIDUser Model
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

/// Production EntraID authentication client using MSAL
@MainActor
class EntraIDAuthClient: NSObject, EntraIDService, HoldableService, ObservableObject {
    // MARK: - Singleton
    static let shared = EntraIDAuthClient()

    // MARK: - Dependencies
    private let credentialManager = SecureCredentialManager.shared
    private let environmentConfig = EnvironmentConfig.current
    private let serviceStateManager = ServiceStateManager.shared

    // MARK: - MSAL Configuration
    #if canImport(MSAL)
    private var msalApplication: MSALPublicClientApplication?
    private var webViewParameters: MSALWebviewParameters?
    #else
    private var msalApplication: Any?
    private var webViewParameters: Any?
    #endif

    // MARK: - Published State
    @Published private(set) var isAuthenticated = false
    @Published private(set) var currentUser: EntraIDUser?
    @Published private(set) var errorMessage: String?
    @Published private(set) var serviceState: ServiceState = .available
    @Published private(set) var holdInfo: HoldStateInfo?
    @Published private(set) var lastError: Error?
    
    // Publishers for reactive UI
    var isAuthenticatedPublisher: Published<Bool>.Publisher { $isAuthenticated }
    var errorMessagePublisher: Published<String?>.Publisher { $errorMessage }

    // MARK: - Configuration
    private var tenantId: String {
        return (try? credentialManager.retrieve(forKey: .entraIDTenantID)) ?? ""
    }

    private var clientId: String {
        return (try? credentialManager.retrieve(forKey: .entraIDClientID)) ?? ""
    }

    private var redirectUri: String {
        return environmentConfig.entraIDRedirectURI
    }

    // MARK: - Initialization

    override init() {
        super.init()
        
        // Register with service state manager
        serviceStateManager.registerService(ServiceStateManager.entraIDService, initialState: .available)
        
        Task {
            await initializeMSAL()
        }
    }

    private func initializeMSAL() async {
        guard !tenantId.isEmpty && !clientId.isEmpty else {
            print("⚠️ EntraID credentials not configured")
            print("💡 Please configure tenant ID and client ID in CredentialSetupView")
            
            // Put service on hold due to missing credentials
            await putOnHoldAsync(reason: .missingCredentials)
            return
        }

        updateServiceState(.connecting)

        #if canImport(MSAL)
        do {
            // Create MSAL authority
            let authorityURL = URL(string: "\(environmentConfig.entraIDAuthority)/\(tenantId)")!
            let authority = try MSALAADAuthority(url: authorityURL)

            // Create MSAL configuration
            let msalConfiguration = MSALPublicClientApplicationConfig(
                clientId: clientId,
                redirectUri: redirectUri,
                authority: authority
            )

            // Additional configuration
            msalConfiguration.knownAuthorities = [authority]

            // Initialize MSAL application
            self.msalApplication = try MSALPublicClientApplication(configuration: msalConfiguration)

            print("✅ MSAL initialized successfully")
            print("   Tenant: \(tenantId)")
            print("   Client ID: \(clientId)")
            print("   Redirect URI: \(redirectUri)")

            updateServiceState(.available)

            // Check for cached accounts
            await checkCachedAccount()

        } catch {
            print("❌ Failed to initialize MSAL: \(error)")
            errorMessage = "MSAL initialization failed: \(error.localizedDescription)"
            lastError = error
            await putOnHoldAsync(reason: .configurationRequired)
        }
        #else
        // MSAL not available, put service on hold
        await putOnHoldAsync(reason: HoldStateInfo(
            reason: "MSAL framework not available",
            suggestedAction: "Add MSAL package dependency",
            canRetry: false,
            estimatedResolution: nil
        ))
        #endif
    }

    // MARK: - Authentication

    /// Sign in with interactive authentication
    func signIn() async throws -> EntraIDUser {
        #if canImport(MSAL)
        guard let msalApplication = msalApplication as? MSALPublicClientApplication else {
            throw EntraIDError.notConfigured
        }

        // Get presenting view controller
        #if canImport(UIKit)
        guard let windowScene = await UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let viewController = await windowScene.windows.first?.rootViewController else {
            throw EntraIDError.noViewController
        }
        #else
        // For non-UIKit platforms, handle differently
        throw EntraIDError.noViewController
        #endif

        // Create web view parameters
        let webParameters = MSALWebviewParameters(authPresentationViewController: viewController)

        // Define scopes for Microsoft Graph API
        let scopes = [
            "User.Read",
            "Application.Read.All",
            "Group.Read.All"
        ]

        // Create interactive parameters
        let interactiveParameters = MSALInteractiveTokenParameters(scopes: scopes, webviewParameters: webParameters)

        do {
            // Acquire token interactively
            let result = try await msalApplication.acquireToken(with: interactiveParameters)

            // Store access token in secure storage
            try credentialManager.store(
                result.accessToken,
                forKey: .entraIDAccessToken,
                securityLevel: .biometricRequired
            )

            // Create user from account
            let user = try await createUserFromAccount(result.account)

            await MainActor.run {
                self.currentUser = user
                self.isAuthenticated = true
            }

            print("✅ EntraID sign in successful: \(user.email)")
            return user

        } catch {
            print("❌ EntraID sign in failed: \(error)")
            lastError = error
            await putOnHoldAsync(reason: .networkUnavailable)
            throw EntraIDError.authenticationFailed(error)
        }
        #else
        throw EntraIDError.notConfigured
        #endif
    }

    // MARK: - HoldableService Implementation
    
    func putOnHold(reason: HoldStateInfo) {
        Task { @MainActor in
            holdInfo = reason
            updateServiceState(.hold)
            isAuthenticated = false
            currentUser = nil
            errorMessage = reason.reason
        }
    }
    
    private func putOnHoldAsync(reason: HoldStateInfo) async {
        await MainActor.run {
            holdInfo = reason
            updateServiceState(.hold)
            isAuthenticated = false
            currentUser = nil
            errorMessage = reason.reason
        }
    }
    
    func resumeFromHold() async throws {
        guard serviceState == .hold else { return }
        
        updateServiceState(.connecting)
        holdInfo = nil
        errorMessage = nil
        lastError = nil
        
        // Attempt to reinitialize
        await initializeMSAL()
        
        if serviceState == .available {
            print("✅ EntraID service resumed from hold")
        }
    }
    
    func checkAvailability() async -> Bool {
        // Check if we can reach the authority endpoint
        guard !tenantId.isEmpty,
              let authorityURL = URL(string: "\(environmentConfig.entraIDAuthority)/\(tenantId)") else {
            return false
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: authorityURL)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode < 500
            }
            return false
        } catch {
            return false
        }
    }
    
    private func updateServiceState(_ state: ServiceState) {
        serviceState = state
        serviceStateManager.updateServiceState(
            ServiceStateManager.entraIDService,
            to: state,
            holdInfo: holdInfo
        )
    }

    /// Sign in silently using cached account
    func signInSilently() async throws -> EntraIDUser {
        #if canImport(MSAL)
        guard let msalApplication = msalApplication as? MSALPublicClientApplication else {
            throw EntraIDError.notConfigured
        }

        // Get all accounts
        let accounts = try msalApplication.allAccounts()

        guard let account = accounts.first else {
            throw EntraIDError.noAccountFound
        }

        // Define scopes
        let scopes = [
            "User.Read",
            "Application.Read.All",
            "Group.Read.All"
        ]

        // Create silent parameters
        let silentParameters = MSALSilentTokenParameters(scopes: scopes, account: account)

        do {
            // Acquire token silently
            let result = try await msalApplication.acquireTokenSilent(with: silentParameters)

            // Store access token
            try credentialManager.store(
                result.accessToken,
                forKey: .entraIDAccessToken,
                securityLevel: .biometricRequired
            )

            // Create user from account
            let user = try await createUserFromAccount(result.account)

            await MainActor.run {
                self.currentUser = user
                self.isAuthenticated = true
            }

            print("✅ EntraID silent sign in successful")
            return user

        } catch {
            print("❌ EntraID silent sign in failed: \(error)")
            // If silent fails, try interactive
            throw EntraIDError.authenticationFailed(error)
        }
        #else
        throw EntraIDError.notConfigured
        #endif
    }

    /// Sign out current user
    func signOut() async throws {
        #if canImport(MSAL)
        guard let msalApplication = msalApplication as? MSALPublicClientApplication else {
            throw EntraIDError.notConfigured
        }

        do {
            // Get all accounts
            let accounts = try msalApplication.allAccounts()

            // Remove all accounts
            for account in accounts {
                try msalApplication.remove(account)
            }

            // Clear stored tokens
            try? credentialManager.delete(forKey: .entraIDAccessToken)
            try? credentialManager.delete(forKey: .entraIDRefreshToken)

            await MainActor.run {
                self.currentUser = nil
                self.isAuthenticated = false
            }

            print("✅ EntraID sign out successful")

        } catch {
            print("❌ EntraID sign out failed: \(error)")
            throw EntraIDError.signOutFailed(error)
        }
        #else
        // Clear stored tokens even without MSAL
        try? credentialManager.delete(forKey: .entraIDAccessToken)
        try? credentialManager.delete(forKey: .entraIDRefreshToken)

        await MainActor.run {
            self.currentUser = nil
            self.isAuthenticated = false
        }
        #endif
    }

    // MARK: - Cached Account

    private func checkCachedAccount() async {
        #if canImport(MSAL)
        guard let msalApplication = msalApplication as? MSALPublicClientApplication else { return }

        do {
            let accounts = try msalApplication.allAccounts()

            if let account = accounts.first {
                print("✅ Found cached EntraID account: \(account.username ?? "unknown")")

                // Try to sign in silently
                try? await signInSilently()
            } else {
                print("ℹ️ No cached EntraID account found")
            }
        } catch {
            print("❌ Failed to check cached account: \(error)")
        }
        #endif
    }

    // MARK: - User Profile

    private func createUserFromAccount(_ account: Any) async throws -> EntraIDUser {
        #if canImport(MSAL)
        guard let msalAccount = account as? MSALAccount else {
            throw EntraIDError.noAccountFound
        }
        
        // Get access token for Graph API
        guard let accessToken = try? credentialManager.retrieve(forKey: .entraIDAccessToken) else {
            throw EntraIDError.noAccessToken
        }

        // Fetch user profile from Microsoft Graph
        let graphClient = MicrosoftGraphClient(accessToken: accessToken)
        let profile = try await graphClient.getUserProfile()

        return EntraIDUser(
            id: msalAccount.identifier ?? profile.id,
            displayName: profile.displayName ?? msalAccount.username ?? "Unknown",
            email: profile.mail ?? msalAccount.username ?? "",
            jobTitle: profile.jobTitle,
            department: profile.department,
            permissions: [], // Populated from groups/roles
            groups: [],
            tenantId: nil, // Could be extracted from account if needed
            userPrincipalName: profile.userPrincipalName
        )
        #else
        throw EntraIDError.notConfigured
        #endif
    }

    // MARK: - Token Management

    /// Get current access token (may trigger silent refresh)
    func getAccessToken() async throws -> String {
        // Try to get from cache first
        if let cachedToken = try? credentialManager.retrieve(forKey: .entraIDAccessToken) {
            return cachedToken
        }

        // Refresh token silently
        let user = try await signInSilently()
        guard let token = try? credentialManager.retrieve(forKey: .entraIDAccessToken) else {
            throw EntraIDError.noAccessToken
        }

        return token
    }
    
    // MARK: - EntraIDService Protocol Methods
    
    /// Refresh the current access token
    func refreshToken() async throws {
        guard isAuthenticated else {
            throw EntraIDError.noAccountFound
        }
        
        do {
            _ = try await signInSilently()
            print("✅ Token refreshed successfully")
        } catch {
            print("❌ Token refresh failed: \(error)")
            lastError = error
            throw EntraIDError.tokenRefreshFailed
        }
    }
    
    /// Get the current authenticated user
    func getCurrentUser() async throws -> EntraIDUser? {
        return currentUser
    }
    
    /// Check if user is currently authenticated
    func checkAuthenticationStatus() async -> Bool {
        return isAuthenticated && currentUser != nil
    }
}

// MARK: - Supporting Types

struct GraphApplication: Codable {
    let id: String
    let displayName: String?
    let appId: String?
    let signInAudience: String?
}

struct GraphGroup: Codable {
    let id: String
    let displayName: String?
    let description: String?
    let securityEnabled: Bool?
}

struct GraphDirectoryObject {
    let id: String
}

// MARK: - Errors

enum EntraIDError: Error, LocalizedError {
    case notConfigured
    case noViewController
    case authenticationFailed(Error)
    case signOutFailed(Error)
    case noAccountFound
    case noAccessToken
    case tokenRefreshFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "EntraID not configured. Please set tenant ID and client ID."
        case .noViewController:
            return "No view controller available for authentication."
        case .authenticationFailed(let error):
            return "Authentication failed: \(error.localizedDescription)"
        case .signOutFailed(let error):
            return "Sign out failed: \(error.localizedDescription)"
        case .noAccountFound:
            return "No cached account found. Please sign in."
        case .noAccessToken:
            return "No access token available."
        case .tokenRefreshFailed:
            return "Failed to refresh access token."
        }
    }
}
