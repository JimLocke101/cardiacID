//
//  PlatformAuthService.swift
//  CardiacID
//
//  Platform-conditional authentication service
//  Uses MSAL on iOS, token-based auth on watchOS
//

import Foundation
import Combine

#if os(iOS)
import UIKit
// MSAL is conditionally imported only for iOS
#if canImport(MSAL)
import MSAL
#endif
#endif

#if os(watchOS)
import WatchKit
import WatchConnectivity
#endif

// MARK: - Unified Authentication Protocol

protocol AuthenticationServiceProtocol: ObservableObject {
    var isAuthenticated: Bool { get }
    var currentUser: AuthUser? { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get }
    
    func signIn() async throws
    func signOut() async throws
    func refreshToken() async throws
}

// MARK: - Common User Model

struct AuthUser: Codable, Identifiable {
    let id: String
    let displayName: String
    let email: String
    let jobTitle: String?
    let department: String?
    let tenantId: String?
    
    var initials: String {
        let components = displayName.components(separatedBy: " ")
        let initials = components.compactMap { $0.first }.map { String($0) }
        return initials.prefix(2).joined().uppercased()
    }
}

// MARK: - iOS Implementation

#if os(iOS)
@MainActor
class iOSAuthService: ObservableObject, AuthenticationServiceProtocol {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var currentUser: AuthUser?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    
    private var msalApplication: MSALPublicClientApplication?
    private let watchConnectivity = WatchConnectivityService.shared
    private let configuration = MSALConfiguration.shared
    
    init() {
        initializeMSAL()
    }
    
    private func initializeMSAL() {
        #if canImport(MSAL)
        do {
            self.msalApplication = try configuration.createMSALApplication()
            print("✅ MSAL initialized successfully")
        } catch {
            print("❌ Failed to initialize MSAL: \(error)")
            errorMessage = "Failed to initialize authentication: \(error.localizedDescription)"
        }
        #else
        errorMessage = "MSAL framework not available"
        #endif
    }
    
    func signIn() async throws {
        #if canImport(MSAL)
        guard let msalApp = msalApplication else {
            throw AuthError.notInitialized
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let viewController = windowScene.windows.first?.rootViewController else {
                throw AuthError.noViewController
            }
            
            let webParameters = MSALWebviewParameters(authPresentationViewController: viewController)
            let parameters = MSALInteractiveTokenParameters(
                scopes: configuration.scopes,
                webviewParameters: webParameters
            )
            
            let result = try await msalApp.acquireToken(with: parameters)
            
            let user = AuthUser(
                id: result.account.identifier ?? UUID().uuidString,
                displayName: result.account.username ?? "Unknown User",
                email: result.account.username ?? "",
                jobTitle: nil,
                department: nil,
                tenantId: result.tenantId?.identifier
            )
            
            self.currentUser = user
            self.isAuthenticated = true
            
            // Share authentication with Watch
            await shareAuthWithWatch(token: result.accessToken, user: user)
            
        } catch {
            errorMessage = error.localizedDescription
            throw AuthError.signInFailed(error.localizedDescription)
        }
        
        isLoading = false
        #else
        throw AuthError.notSupported
        #endif
    }
    
    func signOut() async throws {
        #if canImport(MSAL)
        guard let msalApp = msalApplication else {
            throw AuthError.notInitialized
        }
        
        do {
            let accounts = try msalApp.allAccounts()
            for account in accounts {
                try msalApp.remove(account)
            }
            
            self.currentUser = nil
            self.isAuthenticated = false
            self.errorMessage = nil
            
            // Notify watch of sign out
            await notifyWatchSignOut()
            
        } catch {
            throw AuthError.signOutFailed(error.localizedDescription)
        }
        #else
        throw AuthError.notSupported
        #endif
    }
    
    func refreshToken() async throws {
        #if canImport(MSAL)
        guard let msalApp = msalApplication else {
            throw AuthError.notInitialized
        }
        
        do {
            let accounts = try msalApp.allAccounts()
            guard let account = accounts.first else {
                throw AuthError.noAccount
            }
            
            let parameters = MSALSilentTokenParameters(
                scopes: configuration.scopes,
                account: account
            )
            
            let result = try await msalApp.acquireTokenSilent(with: parameters)
            
            // Update watch with new token
            if let user = currentUser {
                await shareAuthWithWatch(token: result.accessToken, user: user)
            }
            
        } catch {
            throw AuthError.tokenRefreshFailed(error.localizedDescription)
        }
        #else
        throw AuthError.notSupported
        #endif
    }
    
    private func shareAuthWithWatch(token: String, user: AuthUser) async {
        let authResult = WatchAuthenticationResult(
            isSuccess: true,
            token: token,
            refreshToken: nil,
            expiresAt: Date().addingTimeInterval(3600),
            errorMessage: nil,
            method: "entra_id"
        )
        
        let result = await watchConnectivity.sendEntraIDAuthResult(authResult)
        if case .failure(let error) = result {
            print("⚠️ Failed to share auth with watch: \(error)")
        }
    }
    
    private func notifyWatchSignOut() async {
        let authResult = WatchAuthenticationResult(
            isSuccess: false,
            token: nil,
            refreshToken: nil,
            expiresAt: nil,
            errorMessage: "signed_out",
            method: "sign_out"
        )
        
        _ = await watchConnectivity.sendEntraIDAuthResult(authResult)
    }
}
#endif

// MARK: - watchOS Implementation

#if os(watchOS)
@MainActor
class WatchOSAuthService: ObservableObject, AuthenticationServiceProtocol {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var currentUser: AuthUser?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    
    private let session = WCSession.default
    
    init() {
        setupWatchConnectivity()
    }
    
    private func setupWatchConnectivity() {
        if WCSession.isSupported() {
            session.delegate = WatchSessionDelegate(authService: self)
            session.activate()
        }
    }
    
    func signIn() async throws {
        guard session.isReachable else {
            throw AuthError.watchNotReachable
        }
        
        isLoading = true
        errorMessage = nil
        
        let message: [String: Any] = [
            "type": "auth_request",
            "platform": "watchOS",
            "timestamp": Date().timeIntervalSince1970
        ]
        
        let success = await withCheckedContinuation { continuation in
            session.sendMessage(
                message,
                replyHandler: { reply in
                    if let success = reply["success"] as? Bool {
                        continuation.resume(returning: success)
                    } else {
                        continuation.resume(returning: false)
                    }
                },
                errorHandler: { error in
                    Task { @MainActor in
                        self.errorMessage = error.localizedDescription
                    }
                    continuation.resume(returning: false)
                }
            )
        }
        
        if !success {
            isLoading = false
            throw AuthError.watchAuthFailed
        }
        
        // Authentication will complete when we receive response from iOS
    }
    
    func signOut() async throws {
        currentUser = nil
        isAuthenticated = false
        errorMessage = nil
        isLoading = false
    }
    
    func refreshToken() async throws {
        // On watchOS, we can't refresh directly - need to request from iOS
        throw AuthError.refreshNotSupported
    }
    
    func handleAuthResult(_ result: WatchAuthenticationResult) {
        isLoading = false
        
        if result.isSuccess, let token = result.token {
            // Create user from token (would normally parse JWT or get from additional data)
            let user = AuthUser(
                id: "watch-user",
                displayName: "Watch User",
                email: "watch@example.com",
                jobTitle: nil,
                department: nil,
                tenantId: nil
            )
            
            self.currentUser = user
            self.isAuthenticated = true
            self.errorMessage = nil
        } else {
            self.errorMessage = result.errorMessage ?? "Authentication failed"
        }
    }
}

private class WatchSessionDelegate: NSObject, WCSessionDelegate {
    private weak var authService: WatchOSAuthService?
    
    init(authService: WatchOSAuthService) {
        self.authService = authService
        super.init()
    }
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            Task { @MainActor in
                self.authService?.errorMessage = error.localizedDescription
            }
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async {
            self.handleMessage(message)
        }
    }
    
    private func handleMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        
        switch type {
        case "auth_result":
            let result = WatchAuthenticationResult(
                isSuccess: message["success"] as? Bool ?? false,
                token: message["token"] as? String,
                refreshToken: message["refresh_token"] as? String,
                expiresAt: {
                    if let timestamp = message["expires_at"] as? TimeInterval {
                        return Date(timeIntervalSince1970: timestamp)
                    }
                    return nil
                }(),
                errorMessage: message["error"] as? String,
                method: "entra_id"
            )
            
            authService?.handleAuthResult(result)
            
        default:
            break
        }
    }
}
#endif

// MARK: - Unified Service Factory

class AuthServiceFactory {
    @MainActor
    static func createAuthService() -> any AuthenticationServiceProtocol {
        #if os(iOS)
        return iOSAuthService()
        #elseif os(watchOS)
        return WatchOSAuthService()
        #else
        fatalError("Unsupported platform")
        #endif
    }
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case notInitialized
    case noViewController
    case signInFailed(String)
    case signOutFailed(String)
    case tokenRefreshFailed(String)
    case noAccount
    case watchNotReachable
    case watchAuthFailed
    case refreshNotSupported
    case notSupported
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Authentication service not initialized"
        case .noViewController:
            return "No view controller available for authentication"
        case .signInFailed(let message):
            return "Sign in failed: \(message)"
        case .signOutFailed(let message):
            return "Sign out failed: \(message)"
        case .tokenRefreshFailed(let message):
            return "Token refresh failed: \(message)"
        case .noAccount:
            return "No account found"
        case .watchNotReachable:
            return "iPhone not reachable"
        case .watchAuthFailed:
            return "Watch authentication failed"
        case .refreshNotSupported:
            return "Token refresh not supported on this platform"
        case .notSupported:
            return "Authentication not supported on this platform"
        }
    }
}