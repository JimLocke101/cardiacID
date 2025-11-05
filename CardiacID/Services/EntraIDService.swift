import Foundation
import Combine
import AuthenticationServices
import CryptoKit
import Security

/// Service for Entra ID (Azure Active Directory) integration
class EntraIDService: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: EntraIDUser?
    @Published var errorMessage: String?
    @Published var isEnterpriseConnected = false

    // Secure credential manager
    private let credentialManager = SecureCredentialManager.shared
    private let environmentConfig = EnvironmentConfig.current

    // Enterprise configuration (loaded securely)
    private var tenantId: String {
        return (try? credentialManager.retrieve(forKey: .entraIDTenantID)) ?? ""
    }

    private var clientId: String {
        return (try? credentialManager.retrieve(forKey: .entraIDClientID)) ?? ""
    }

    private var redirectUri: String {
        return environmentConfig.entraIDRedirectURI
    }

    private var accessToken: String? {
        get {
            return try? credentialManager.retrieve(forKey: .entraIDAccessToken)
        }
        set {
            if let token = newValue {
                try? credentialManager.store(token, forKey: .entraIDAccessToken, securityLevel: .biometricRequired)
            } else {
                try? credentialManager.delete(forKey: .entraIDAccessToken)
            }
        }
    }

    private var refreshToken: String? {
        get {
            return try? credentialManager.retrieve(forKey: .entraIDRefreshToken)
        }
        set {
            if let token = newValue {
                try? credentialManager.store(token, forKey: .entraIDRefreshToken, securityLevel: .biometricRequired)
            } else {
                try? credentialManager.delete(forKey: .entraIDRefreshToken)
            }
        }
    }

    // OAuth 2.0 configuration
    private var authorizationEndpoint: String {
        return environmentConfig.entraIDAuthority
    }

    private var tokenEndpoint: String {
        return environmentConfig.entraIDAuthority
    }

    private let graphEndpoint = "https://graph.microsoft.com/v1.0"

    // Security
    private let keychain = KeychainService.shared
    private let encryptionService = EncryptionService.shared

    // Publishers
    private let authStateSubject = PassthroughSubject<EntraIDAuthState, Never>()
    var authStatePublisher: AnyPublisher<EntraIDAuthState, Never> {
        authStateSubject.eraseToAnyPublisher()
    }

    override init() {
        super.init()
        loadStoredCredentials()

        // Validate credentials on init
        if tenantId.isEmpty || clientId.isEmpty {
            print("⚠️ WARNING: EntraID credentials not configured. Please set up tenant ID and client ID.")
        }
    }
    
    // MARK: - Authentication Flow
    
    /// Start Entra ID authentication flow
    func authenticate() {
        authStateSubject.send(.authenticating)
        
        // Create authorization URL
        guard let authURL = createAuthorizationURL() else {
            errorMessage = "Failed to create authorization URL"
            authStateSubject.send(.error("Failed to create authorization URL"))
            return
        }
        
        // Present authentication web view
        presentAuthenticationWebView(url: authURL)
    }
    
    /// Complete authentication with authorization code
    func completeAuthentication(with code: String) {
        Task {
            do {
                let tokenResponse = try await exchangeCodeForTokens(code: code)
                await MainActor.run {
                    self.handleTokenResponse(tokenResponse)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.authStateSubject.send(.error(error.localizedDescription))
                }
            }
        }
    }
    
    /// Sign out from Entra ID
    func signOut() {
        Task {
            do {
                try await revokeTokens()
                await MainActor.run {
                    self.clearSession()
                    self.authStateSubject.send(.signedOut)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    // MARK: - Enterprise Features
    
    /// Get user's enterprise groups and roles
    func getUserGroups() -> AnyPublisher<[EntraIDGroup], EntraIDError> {
        guard isAuthenticated, let token = accessToken else {
            return Fail(error: EntraIDError.notAuthenticated).eraseToAnyPublisher()
        }
        
        return Future<[EntraIDGroup], EntraIDError> { promise in
            Task {
                do {
                    let groups = try await self.fetchUserGroups(token: token)
                    promise(.success(groups))
                } catch {
                    promise(.failure(error as? EntraIDError ?? .networkError(error)))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// Get user's enterprise applications
    func getUserApplications() -> AnyPublisher<[EntraIDApplication], EntraIDError> {
        guard isAuthenticated, let token = accessToken else {
            return Fail(error: EntraIDError.notAuthenticated).eraseToAnyPublisher()
        }
        
        return Future<[EntraIDApplication], EntraIDError> { promise in
            Task {
                do {
                    let apps = try await self.fetchUserApplications(token: token)
                    promise(.success(apps))
                } catch {
                    promise(.failure(error as? EntraIDError ?? .networkError(error)))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// Check if user has specific enterprise permission
    func hasPermission(_ permission: EntraIDPermission) -> Bool {
        guard let user = currentUser else { return false }
        return user.permissions.contains(permission)
    }
    
    /// Get enterprise security policies
    func getSecurityPolicies() -> AnyPublisher<[EntraIDSecurityPolicy], EntraIDError> {
        guard isAuthenticated, let token = accessToken else {
            return Fail(error: EntraIDError.notAuthenticated).eraseToAnyPublisher()
        }
        
        return Future<[EntraIDSecurityPolicy], EntraIDError> { promise in
            Task {
                do {
                    let policies = try await self.fetchSecurityPolicies(token: token)
                    promise(.success(policies))
                } catch {
                    promise(.failure(error as? EntraIDError ?? .networkError(error)))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    // MARK: - Heart ID Integration
    
    /// Register heart pattern with Entra ID for enterprise authentication
    func registerHeartPattern(_ pattern: HeartPattern) -> AnyPublisher<Bool, EntraIDError> {
        guard isAuthenticated, let token = accessToken else {
            return Fail(error: EntraIDError.notAuthenticated).eraseToAnyPublisher()
        }
        
        return Future<Bool, EntraIDError> { promise in
            Task {
                do {
                    // Encrypt heart pattern
                    guard let encryptedPattern = self.encryptionService.encryptHeartPattern(pattern) else {
                        promise(.failure(.encryptionError))
                        return
                    }
                    
                    // Register with Entra ID
                    let success = try await self.registerBiometricWithEntraID(
                        pattern: encryptedPattern,
                        token: token
                    )
                    promise(.success(success))
                } catch {
                    promise(.failure(error as? EntraIDError ?? .networkError(error)))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// Authenticate using heart pattern with Entra ID
    func authenticateWithHeartPattern(_ pattern: HeartPattern) -> AnyPublisher<EntraIDAuthResult, EntraIDError> {
        guard isAuthenticated, let token = accessToken else {
            return Fail(error: EntraIDError.notAuthenticated).eraseToAnyPublisher()
        }
        
        return Future<EntraIDAuthResult, EntraIDError> { promise in
            Task {
                do {
                    // Encrypt heart pattern
                    guard let encryptedPattern = self.encryptionService.encryptHeartPattern(pattern) else {
                        promise(.failure(.encryptionError))
                        return
                    }
                    
                    // Authenticate with Entra ID
                    let result = try await self.authenticateBiometricWithEntraID(
                        pattern: encryptedPattern,
                        token: token
                    )
                    promise(.success(result))
                } catch {
                    promise(.failure(error as? EntraIDError ?? .networkError(error)))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func createAuthorizationURL() -> URL? {
        var components = URLComponents(string: "\(authorizationEndpoint)/\(tenantId)/oauth2/v2.0/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: "openid profile email User.Read Group.Read.All Application.Read.All"),
            URLQueryItem(name: "state", value: generateState()),
            URLQueryItem(name: "nonce", value: generateNonce())
        ]
        return components?.url
    }
    
    private func presentAuthenticationWebView(url: URL) {
        // In a real implementation, this would present a web view
        // For now, we'll simulate the authentication flow
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            // Simulate successful authentication
            self.completeAuthentication(with: "mock_auth_code")
        }
    }
    
    private func exchangeCodeForTokens(code: String) async throws -> TokenResponse {
        let url = URL(string: "\(tokenEndpoint)/\(tenantId)/oauth2/v2.0/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "client_id": clientId,
            "code": code,
            "redirect_uri": redirectUri,
            "grant_type": "authorization_code"
        ]
        
        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw EntraIDError.authenticationError
        }
        
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }
    
    private func handleTokenResponse(_ response: TokenResponse) {
        accessToken = response.accessToken
        refreshToken = response.refreshToken
        
        // Store tokens securely
        if let accessToken = accessToken {
            keychain.store(accessToken, forKey: "entra_access_token")
        }
        if let refreshToken = refreshToken {
            keychain.store(refreshToken, forKey: "entra_refresh_token")
        }
        
        // Fetch user profile
        Task {
            do {
                let user = try await fetchUserProfile(token: response.accessToken)
                await MainActor.run {
                    self.currentUser = user
                    self.isAuthenticated = true
                    self.isEnterpriseConnected = true
                    self.authStateSubject.send(.authenticated)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.authStateSubject.send(.error(error.localizedDescription))
                }
            }
        }
    }
    
    private func fetchUserProfile(token: String) async throws -> EntraIDUser {
        let url = URL(string: "\(graphEndpoint)/me")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw EntraIDError.networkError(NSError(domain: "EntraID", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch user profile"]))
        }
        
        let userResponse = try JSONDecoder().decode(EntraIDUserResponse.self, from: data)
        return EntraIDUser(from: userResponse)
    }
    
    private func fetchUserGroups(token: String) async throws -> [EntraIDGroup] {
        let url = URL(string: "\(graphEndpoint)/me/memberOf")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw EntraIDError.networkError(NSError(domain: "EntraID", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch user groups"]))
        }
        
        let groupsResponse = try JSONDecoder().decode(EntraIDGroupsResponse.self, from: data)
        return groupsResponse.value.map { group in
            EntraIDGroup(
                id: group.id ?? "",
                displayName: group.displayName ?? "",
                description: group.description,
                securityEnabled: group.securityEnabled ?? false
            )
        }
    }
    
    private func fetchUserApplications(token: String) async throws -> [EntraIDApplication] {
        let url = URL(string: "\(graphEndpoint)/me/ownedObjects")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw EntraIDError.networkError(NSError(domain: "EntraID", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch user applications"]))
        }
        
        let appsResponse = try JSONDecoder().decode(EntraIDApplicationsResponse.self, from: data)
        return appsResponse.value.map { app in
            EntraIDApplication(
                id: app.id ?? "",
                displayName: app.displayName ?? "",
                appId: app.appId ?? "",
                signInAudience: app.signInAudience ?? ""
            )
        }
    }
    
    private func fetchSecurityPolicies(token: String) async throws -> [EntraIDSecurityPolicy] {
        let url = URL(string: "\(graphEndpoint)/policies/authenticationMethodsPolicy")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw EntraIDError.networkError(NSError(domain: "EntraID", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch security policies"]))
        }
        
        let policiesResponse = try JSONDecoder().decode(EntraIDSecurityPoliciesResponse.self, from: data)
        return policiesResponse.value.map { policy in
            EntraIDSecurityPolicy(
                id: policy.id ?? "",
                displayName: policy.displayName ?? "",
                description: policy.description,
                policyType: policy.policyType ?? "",
                isEnabled: policy.isEnabled ?? false
            )
        }
    }
    
    private func registerBiometricWithEntraID(pattern: Data, token: String) async throws -> Bool {
        // In a real implementation, this would register the biometric with Entra ID
        // For now, we'll simulate success
        return true
    }
    
    private func authenticateBiometricWithEntraID(pattern: Data, token: String) async throws -> EntraIDAuthResult {
        // In a real implementation, this would authenticate the biometric with Entra ID
        // For now, we'll simulate success
        return EntraIDAuthResult(success: true, permissions: [.heartAuthentication, .doorAccess], message: "Authentication successful")
    }
    
    private func revokeTokens() async throws {
        guard let refreshToken = refreshToken else { return }
        
        let url = URL(string: "\(tokenEndpoint)/\(tenantId)/oauth2/v2.0/logout")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "client_id": clientId,
            "refresh_token": refreshToken
        ]
        
        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw EntraIDError.networkError(NSError(domain: "EntraID", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to revoke tokens"]))
        }
    }
    
    private func clearSession() {
        accessToken = nil
        refreshToken = nil
        currentUser = nil
        isAuthenticated = false
        isEnterpriseConnected = false
        
        // Clear stored tokens
        keychain.delete(forKey: "entra_access_token")
        keychain.delete(forKey: "entra_refresh_token")
    }
    
    private func loadStoredCredentials() {
        accessToken = keychain.retrieve(forKey: "entra_access_token")
        refreshToken = keychain.retrieve(forKey: "entra_refresh_token")
        
        if accessToken != nil {
            isAuthenticated = true
            isEnterpriseConnected = true
        }
    }
    
    private func generateState() -> String {
        return UUID().uuidString
    }
    
    private func generateNonce() -> String {
        return UUID().uuidString
    }
}

// MARK: - Supporting Types

enum EntraIDAuthState {
    case idle
    case authenticating
    case authenticated
    case signedOut
    case error(String)
}

enum EntraIDError: Error, LocalizedError {
    case notAuthenticated
    case authenticationError
    case networkError(Error)
    case encryptionError
    case invalidResponse
    case tokenExpired
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
        case .authenticationError:
            return "Authentication failed"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .encryptionError:
            return "Encryption failed"
        case .invalidResponse:
            return "Invalid response from server"
        case .tokenExpired:
            return "Access token has expired"
        }
    }
}

struct EntraIDUser {
    let id: String
    let displayName: String
    let email: String
    let jobTitle: String?
    let department: String?
    let permissions: [EntraIDPermission]
    let groups: [String]
    
    init(from response: EntraIDUserResponse) {
        self.id = response.id
        self.displayName = response.displayName
        self.email = response.mail ?? response.userPrincipalName
        self.jobTitle = response.jobTitle
        self.department = response.department
        self.permissions = [] // Would be populated from groups/roles
        self.groups = [] // Would be populated from group membership
    }
}

struct EntraIDGroup {
    let id: String
    let displayName: String
    let description: String?
    let securityEnabled: Bool
}

struct EntraIDApplication {
    let id: String
    let displayName: String
    let appId: String
    let signInAudience: String
}

struct EntraIDSecurityPolicy {
    let id: String
    let displayName: String
    let description: String
    let policyType: String
    let isEnabled: Bool
}

struct EntraIDAuthResult {
    let success: Bool
    let permissions: [EntraIDPermission]
    let message: String?
}

enum EntraIDPermission: String, CaseIterable {
    case heartAuthentication = "heart_authentication"
    case doorAccess = "door_access"
    case nfcAccess = "nfc_access"
    case bluetoothAccess = "bluetooth_access"
    case adminAccess = "admin_access"
    case userManagement = "user_management"
    case deviceManagement = "device_management"
}

// MARK: - API Response Models

struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let tokenType: String
    let scope: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case scope
    }
}

struct EntraIDUserResponse: Codable {
    let id: String
    let displayName: String
    let mail: String?
    let userPrincipalName: String
    let jobTitle: String?
    let department: String?
}

struct EntraIDGroupsResponse: Codable {
    let value: [EntraIDGroupResponse]
}

struct EntraIDGroupResponse: Codable {
    let id: String?
    let displayName: String?
    let description: String?
    let securityEnabled: Bool?
}

struct EntraIDApplicationsResponse: Codable {
    let value: [EntraIDApplicationResponse]
}

struct EntraIDApplicationResponse: Codable {
    let id: String?
    let displayName: String?
    let appId: String?
    let signInAudience: String?
}

struct EntraIDSecurityPoliciesResponse: Codable {
    let value: [EntraIDSecurityPolicyResponse]
}

struct EntraIDSecurityPolicyResponse: Codable {
    let id: String?
    let displayName: String?
    let description: String
    let policyType: String?
    let isEnabled: Bool?
}
