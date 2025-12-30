//
//  SharedAuthTokenManager.swift
//  CardiacID
//
//  Cross-platform authentication token management
//  Supports both iOS (with MSAL) and watchOS (token-only)
//

import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif
import Combine

/// Shared authentication token that works across iOS and watchOS
struct AuthToken: Codable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
    let scopes: [String]
    let userInfo: UserInfo
    let issuedAt: Date
    
    struct UserInfo: Codable, Sendable {
        let id: String
        let displayName: String
        let email: String
        let tenantId: String?
    }
    
    var isExpired: Bool {
        return Date() >= expiresAt
    }
    
    var isExpiringSoon: Bool {
        return Date().addingTimeInterval(300) >= expiresAt // 5 minutes buffer
    }
}

/// Cross-platform authentication token manager
@MainActor
class SharedAuthTokenManager: ObservableObject {
    static let shared = SharedAuthTokenManager()
    
    @Published private(set) var currentToken: AuthToken?
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isRefreshing = false
    
    private let userDefaults = UserDefaults(suiteName: "group.com.argos.cardiacid")
    private let tokenKey = "shared_auth_token"
    
    #if os(iOS)
    private let watchConnectivity = WatchConnectivityService.shared
    #endif
    
    private init() {
        loadStoredToken()
        
        #if os(iOS)
        // Listen for authentication events
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAuthenticationSuccess),
            name: .authenticationSucceeded,
            object: nil
        )
        #endif
    }
    
    // MARK: - Token Storage
    
    private func loadStoredToken() {
        guard let tokenData = userDefaults?.data(forKey: tokenKey),
              let token = try? JSONDecoder().decode(AuthToken.self, from: tokenData) else {
            return
        }
        
        if !token.isExpired {
            currentToken = token
            isAuthenticated = true
        } else {
            // Token expired, clear it
            clearStoredToken()
        }
    }
    
    func storeToken(_ token: AuthToken) {
        do {
            let tokenData = try JSONEncoder().encode(token)
            userDefaults?.set(tokenData, forKey: tokenKey)
            
            currentToken = token
            isAuthenticated = true
            
            #if os(iOS)
            // Share token with watchOS
            Task {
                await shareTokenWithWatch(token)
            }
            #endif
            
            print("✅ Token stored and shared across platforms")
        } catch {
            print("❌ Failed to store token: \(error)")
        }
    }
    
    private func clearStoredToken() {
        userDefaults?.removeObject(forKey: tokenKey)
        currentToken = nil
        isAuthenticated = false
    }
    
    // MARK: - Cross-Platform Token Sharing
    
    #if os(iOS)
    private func shareTokenWithWatch(_ token: AuthToken) async {
        let authResult = WatchAuthenticationResult(
            isSuccess: true,
            token: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: token.expiresAt,
            errorMessage: nil,
            method: "entra_id"
        )
        
        let result = await watchConnectivity.sendEntraIDAuthResult(authResult)
        switch result {
        case .success:
            print("✅ Token shared with Watch successfully")
        case .failure(let error):
            print("⚠️ Failed to share token with Watch: \(error)")
        }
    }
    #endif
    
    // MARK: - Token Refresh
    
    func refreshTokenIfNeeded() async throws -> AuthToken {
        guard let currentToken = currentToken else {
            throw AuthTokenError.noToken
        }
        
        if !currentToken.isExpiringSoon {
            return currentToken
        }
        
        return try await refreshToken()
    }
    
    private func refreshToken() async throws -> AuthToken {
        isRefreshing = true
        defer { isRefreshing = false }
        
        #if os(iOS)
        // On iOS, use MSAL to refresh
        do {
            let user = try await EntraIDAuthClient.shared.signInSilently()
            guard let accessToken = try? SecureCredentialManager.shared.retrieve(forKey: .entraIDAccessToken) else {
                throw AuthTokenError.refreshFailed
            }
            
            let newToken = AuthToken(
                accessToken: accessToken,
                refreshToken: currentToken?.refreshToken,
                expiresAt: Date().addingTimeInterval(3600), // 1 hour
                scopes: ["User.Read", "Application.Read.All", "Group.Read.All"],
                userInfo: AuthToken.UserInfo(
                    id: user.id,
                    displayName: user.displayName,
                    email: user.email,
                    tenantId: user.tenantId
                ),
                issuedAt: Date()
            )
            
            storeToken(newToken)
            return newToken
            
        } catch {
            print("❌ Token refresh failed: \(error)")
            clearStoredToken()
            throw AuthTokenError.refreshFailed
        }
        #else
        // On watchOS, we can't refresh directly - need to request from iOS
        throw AuthTokenError.refreshNotSupported
        #endif
    }
    
    // MARK: - Authentication Status
    
    func signOut() {
        clearStoredToken()
        
        #if os(iOS)
        Task {
            try? await EntraIDAuthClient.shared.signOut()
        }
        #endif
    }
    
    @objc private func handleAuthenticationSuccess(_ notification: Notification) {
        #if os(iOS)
        if let user = notification.userInfo?["user"] as? EntraIDUser,
           let accessToken = try? SecureCredentialManager.shared.retrieve(forKey: .entraIDAccessToken) {
            
            let token = AuthToken(
                accessToken: accessToken,
                refreshToken: nil, // Will be populated by MSAL if available
                expiresAt: Date().addingTimeInterval(3600),
                scopes: ["User.Read", "Application.Read.All", "Group.Read.All"],
                userInfo: AuthToken.UserInfo(
                    id: user.id,
                    displayName: user.displayName,
                    email: user.email,
                    tenantId: user.tenantId
                ),
                issuedAt: Date()
            )
            
            storeToken(token)
        }
        #endif
    }
}

// MARK: - Errors

enum AuthTokenError: LocalizedError {
    case noToken
    case refreshFailed
    case refreshNotSupported
    
    var errorDescription: String? {
        switch self {
        case .noToken:
            return "No authentication token available"
        case .refreshFailed:
            return "Failed to refresh authentication token"
        case .refreshNotSupported:
            return "Token refresh not supported on this platform"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let authenticationSucceeded = Notification.Name("AuthenticationSucceeded")
    static let authenticationFailed = Notification.Name("AuthenticationFailed")
}