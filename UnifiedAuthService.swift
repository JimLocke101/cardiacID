//
//  UnifiedAuthService.swift
//  CardiacID
//
//  Unified authentication service that works across iOS and watchOS
//  Provides a single interface for authentication regardless of platform
//

import Foundation
import Combine

@MainActor
class UnifiedAuthService: ObservableObject {
    static let shared = UnifiedAuthService()
    
    @Published private(set) var isAuthenticated = false
    @Published private(set) var currentUser: UnifiedUser?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    
    private let tokenManager = SharedAuthTokenManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    #if os(iOS)
    private let iosAuthClient = EntraIDAuthClient.shared
    #elseif os(watchOS)
    private let watchAuthService = WatchAuthService.shared
    #endif
    
    struct UnifiedUser {
        let id: String
        let displayName: String
        let email: String
        let initials: String
        let platform: String
        
        #if os(iOS)
        init(from entraIDUser: EntraIDUser) {
            self.id = entraIDUser.id
            self.displayName = entraIDUser.displayName
            self.email = entraIDUser.email
            self.initials = entraIDUser.initials
            self.platform = "iOS"
        }
        #endif
        
        #if os(watchOS)
        init(from watchUser: WatchAuthService.WatchUser) {
            self.id = watchUser.id
            self.displayName = watchUser.displayName
            self.email = watchUser.email
            self.initials = watchUser.initials
            self.platform = "watchOS"
        }
        #endif
    }
    
    private init() {
        observeAuthenticationState()
    }
    
    private func observeAuthenticationState() {
        tokenManager.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isAuthenticated in
                self?.isAuthenticated = isAuthenticated
                
                if isAuthenticated, let token = self?.tokenManager.currentToken {
                    self?.currentUser = UnifiedUser(
                        id: token.userInfo.id,
                        displayName: token.userInfo.displayName,
                        email: token.userInfo.email,
                        initials: self?.createInitials(from: token.userInfo.displayName) ?? "?",
                        platform: self?.getCurrentPlatform() ?? "Unknown"
                    )
                } else {
                    self?.currentUser = nil
                }
            }
            .store(in: &cancellables)
        
        #if os(iOS)
        iosAuthClient.$errorMessage
            .receive(on: DispatchQueue.main)
            .assign(to: &$errorMessage)
            
        iosAuthClient.$serviceState
            .receive(on: DispatchQueue.main)
            .map { $0 == .connecting }
            .assign(to: &$isLoading)
        #endif
        
        #if os(watchOS)
        watchAuthService.$errorMessage
            .receive(on: DispatchQueue.main)
            .assign(to: &$errorMessage)
            
        watchAuthService.$isWaitingForAuth
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoading)
        #endif
    }
    
    // MARK: - Authentication Methods
    
    func signIn() async throws {
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        do {
            #if os(iOS)
            _ = try await iosAuthClient.signIn()
            #elseif os(watchOS)
            let success = await watchAuthService.requestAuthenticationFromiPhone()
            if !success {
                throw AuthenticationError.watchAuthFailed
            }
            #endif
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    func signInSilently() async throws {
        #if os(iOS)
        _ = try await iosAuthClient.signInSilently()
        #elseif os(watchOS)
        // On watchOS, silent sign-in means checking for existing tokens
        if !tokenManager.isAuthenticated {
            throw AuthenticationError.noStoredCredentials
        }
        #endif
    }
    
    func signOut() async {
        #if os(iOS)
        try? await iosAuthClient.signOut()
        #endif
        
        tokenManager.signOut()
        currentUser = nil
        errorMessage = nil
    }
    
    // MARK: - API Access
    
    func makeAuthenticatedAPICall<T: Codable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: Data? = nil,
        responseType: T.Type
    ) async throws -> T {
        let token = try await tokenManager.refreshTokenIfNeeded()
        
        guard let url = URL(string: "https://graph.microsoft.com/v1.0/\(endpoint)") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let body = body {
            request.httpBody = body
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard 200..<300 ~= httpResponse.statusCode else {
            throw APIError.serverError(httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(responseType.self, from: data)
    }
    
    // MARK: - User Profile
    
    func refreshUserProfile() async throws {
        let profile = try await makeAuthenticatedAPICall(
            endpoint: "me",
            responseType: GraphUserProfile.self
        )
        
        currentUser = UnifiedUser(
            id: profile.id,
            displayName: profile.displayName ?? "Unknown",
            email: profile.mail ?? profile.userPrincipalName,
            initials: createInitials(from: profile.displayName ?? "?"),
            platform: getCurrentPlatform()
        )
    }
    
    // MARK: - Utility
    
    private func createInitials(from name: String) -> String {
        let components = name.components(separatedBy: " ")
        let initials = components.compactMap { $0.first }.map { String($0) }
        return initials.prefix(2).joined()
    }
    
    private func getCurrentPlatform() -> String {
        #if os(iOS)
        return "iOS"
        #elseif os(watchOS)
        return "watchOS"
        #elseif os(macOS)
        return "macOS"
        #else
        return "Unknown"
        #endif
    }
}

// MARK: - Supporting Types

enum HTTPMethod: String {
    case GET = "GET"
    case POST = "POST"
    case PUT = "PUT"
    case DELETE = "DELETE"
    case PATCH = "PATCH"
}

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid API response"
        case .serverError(let code):
            return "Server error: \(code)"
        }
    }
}

enum AuthenticationError: LocalizedError {
    case watchAuthFailed
    case noStoredCredentials
    
    var errorDescription: String? {
        switch self {
        case .watchAuthFailed:
            return "Watch authentication failed"
        case .noStoredCredentials:
            return "No stored credentials available"
        }
    }
}