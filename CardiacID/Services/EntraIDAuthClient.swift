//
//  EntraIDAuthClient.swift
//  HeartID Mobile
//
//  Production EntraID (Azure AD) authentication using Microsoft Authentication Library (MSAL)
//  Replaces mock EntraIDService with real OAuth 2.0 implementation
//

import Foundation
import UIKit
import MSAL
import Combine

/// Production EntraID authentication client using MSAL
@MainActor
class EntraIDAuthClient: NSObject, ObservableObject {
    // MARK: - Singleton
    static let shared = EntraIDAuthClient()

    // MARK: - Dependencies
    private let credentialManager = SecureCredentialManager.shared
    private let environmentConfig = EnvironmentConfig.current

    // MARK: - MSAL Configuration
    private var msalApplication: MSALPublicClientApplication?
    private var webViewParameters: MSALWebviewParameters?

    // MARK: - Published State
    @Published private(set) var isAuthenticated = false
    @Published private(set) var currentUser: EntraIDUser?
    @Published private(set) var errorMessage: String?

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

    private override init() {
        super.init()
        Task {
            await initializeMSAL()
        }
    }

    private func initializeMSAL() async {
        guard !tenantId.isEmpty && !clientId.isEmpty else {
            print("⚠️ EntraID credentials not configured")
            print("💡 Please configure tenant ID and client ID in CredentialSetupView")
            return
        }

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

            // Check for cached accounts
            await checkCachedAccount()

        } catch {
            print("❌ Failed to initialize MSAL: \(error)")
            errorMessage = "MSAL initialization failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Authentication

    /// Sign in with interactive authentication
    func signIn() async throws -> EntraIDUser {
        guard let msalApplication = msalApplication else {
            throw EntraIDError.notConfigured
        }

        // Get presenting view controller
        guard let windowScene = await UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let viewController = await windowScene.windows.first?.rootViewController else {
            throw EntraIDError.noViewController
        }

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
            throw EntraIDError.authenticationFailed(error)
        }
    }

    /// Sign in silently using cached account
    func signInSilently() async throws -> EntraIDUser {
        guard let msalApplication = msalApplication else {
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
    }

    /// Sign out current user
    func signOut() async throws {
        guard let msalApplication = msalApplication else {
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
    }

    // MARK: - Cached Account

    private func checkCachedAccount() async {
        guard let msalApplication = msalApplication else { return }

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
    }

    // MARK: - User Profile

    private func createUserFromAccount(_ account: MSALAccount) async throws -> EntraIDUser {
        // Get access token for Graph API
        guard let accessToken = try? credentialManager.retrieve(forKey: .entraIDAccessToken) else {
            throw EntraIDError.noAccessToken
        }

        // Fetch user profile from Microsoft Graph
        let graphClient = MicrosoftGraphClient(accessToken: accessToken)
        let profile = try await graphClient.getUserProfile()

        return EntraIDUser(
            id: account.identifier,
            displayName: profile.displayName ?? account.username ?? "Unknown",
            email: profile.mail ?? account.username ?? "",
            jobTitle: profile.jobTitle,
            department: profile.department,
            permissions: [], // Populated from groups/roles
            groups: []
        )
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
}

// MARK: - Microsoft Graph Client

/// Client for Microsoft Graph API
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

// MARK: - Supporting Types

struct EntraIDUser {
    let id: String
    let displayName: String
    let email: String
    let jobTitle: String?
    let department: String?
    let permissions: [String]
    let groups: [String]
}

struct GraphUserProfile: Codable {
    let id: String
    let displayName: String?
    let mail: String?
    let userPrincipalName: String
    let jobTitle: String?
    let department: String?
}

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

enum GraphAPIError: Error, LocalizedError {
    case requestFailed
    case invalidResponse
    case decodingError

    var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "Microsoft Graph API request failed."
        case .invalidResponse:
            return "Invalid response from Microsoft Graph API."
        case .decodingError:
            return "Failed to decode Microsoft Graph API response."
        }
    }
}
