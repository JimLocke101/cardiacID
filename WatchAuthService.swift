//
//  WatchAuthService.swift
//  CardiacID WatchKit Extension
//
//  Authentication service for watchOS that receives tokens from iOS
//  and provides Microsoft Graph API access
//

#if os(watchOS)
import Foundation
import WatchConnectivity
import Combine

@MainActor
class WatchAuthService: NSObject, ObservableObject {
    static let shared = WatchAuthService()
    
    @Published private(set) var isAuthenticated = false
    @Published private(set) var currentUser: WatchUser?
    @Published private(set) var isWaitingForAuth = false
    @Published private(set) var errorMessage: String?
    
    private let session = WCSession.default
    private let tokenManager = SharedAuthTokenManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    struct WatchUser {
        let id: String
        let displayName: String
        let email: String
        let initials: String
    }
    
    private override init() {
        super.init()
        setupWatchConnectivity()
        observeTokenManager()
    }
    
    private func setupWatchConnectivity() {
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }
        
        // Listen for authentication results
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAuthResult(_:)),
            name: .watchEntraIDAuthResult,
            object: nil
        )
    }
    
    private func observeTokenManager() {
        tokenManager.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isAuthenticated in
                self?.isAuthenticated = isAuthenticated
                if isAuthenticated, let token = self?.tokenManager.currentToken {
                    self?.currentUser = WatchUser(
                        id: token.userInfo.id,
                        displayName: token.userInfo.displayName,
                        email: token.userInfo.email,
                        initials: self?.createInitials(from: token.userInfo.displayName) ?? "?"
                    )
                } else {
                    self?.currentUser = nil
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Authentication Methods
    
    func requestAuthenticationFromiPhone() async -> Bool {
        guard session.isReachable else {
            errorMessage = "iPhone not reachable"
            return false
        }
        
        isWaitingForAuth = true
        errorMessage = nil
        
        let message: [String: Any] = [
            "type": "auth_request",
            "platform": "watchOS",
            "timestamp": Date().timeIntervalSince1970
        ]
        
        return await withCheckedContinuation { continuation in
            session.sendMessage(
                message,
                replyHandler: { reply in
                    Task { @MainActor in
                        if let success = reply["success"] as? Bool, success {
                            print("✅ Authentication request sent to iPhone")
                            continuation.resume(returning: true)
                        } else {
                            let error = reply["error"] as? String ?? "Unknown error"
                            self.errorMessage = error
                            self.isWaitingForAuth = false
                            continuation.resume(returning: false)
                        }
                    }
                },
                errorHandler: { error in
                    Task { @MainActor in
                        self.errorMessage = "Failed to contact iPhone: \(error.localizedDescription)"
                        self.isWaitingForAuth = false
                        continuation.resume(returning: false)
                    }
                }
            )
        }
    }
    
    @objc private func handleAuthResult(_ notification: Notification) {
        guard let result = notification.object as? WatchAuthenticationResult else {
            return
        }
        
        isWaitingForAuth = false
        
        if result.isSuccess, 
           let token = result.token,
           let expiresAt = result.expiresAt {
            
            // Create a user from the received token
            // Note: We would need additional user info from the iPhone
            let authToken = AuthToken(
                accessToken: token,
                refreshToken: result.refreshToken,
                expiresAt: expiresAt,
                scopes: ["User.Read"],
                userInfo: AuthToken.UserInfo(
                    id: "watch-user", // This should come from iPhone
                    displayName: "Watch User", // This should come from iPhone
                    email: "watch@example.com", // This should come from iPhone
                    tenantId: nil
                ),
                issuedAt: Date()
            )
            
            tokenManager.storeToken(authToken)
            errorMessage = nil
            
        } else {
            errorMessage = result.errorMessage ?? "Authentication failed"
        }
    }
    
    // MARK: - API Access
    
    func makeAuthenticatedRequest(to endpoint: String) async throws -> Data {
        let token = try await tokenManager.refreshTokenIfNeeded()
        
        guard let url = URL(string: "https://graph.microsoft.com/v1.0/\(endpoint)") else {
            throw WatchAuthError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WatchAuthError.apiRequestFailed
        }
        
        return data
    }
    
    func getUserProfile() async throws -> WatchUser {
        let data = try await makeAuthenticatedRequest(to: "me")
        let profile = try JSONDecoder().decode(GraphUserProfile.self, from: data)
        
        let user = WatchUser(
            id: profile.id,
            displayName: profile.displayName ?? "Unknown",
            email: profile.mail ?? profile.userPrincipalName,
            initials: createInitials(from: profile.displayName ?? "?")
        )
        
        currentUser = user
        return user
    }
    
    // MARK: - Utility
    
    private func createInitials(from name: String) -> String {
        let components = name.components(separatedBy: " ")
        let initials = components.compactMap { $0.first }.map { String($0) }
        return initials.prefix(2).joined()
    }
    
    func signOut() {
        tokenManager.signOut()
        currentUser = nil
        errorMessage = nil
        isWaitingForAuth = false
    }
}

// MARK: - WCSessionDelegate

extension WatchAuthService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("❌ Watch session activation error: \(error)")
            errorMessage = "Connection error: \(error.localizedDescription)"
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async {
            self.handleReceivedMessage(message)
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async {
            self.handleReceivedMessage(message)
            replyHandler(["received": true])
        }
    }
    
    private func handleReceivedMessage(_ message: [String: Any]) {
        print("⌚️ Received message from iPhone: \(message)")
        
        if let type = message["type"] as? String {
            switch type {
            case "auth_result":
                // Handle authentication result
                if let success = message["success"] as? Bool,
                   success,
                   let tokenData = message["token"] as? String,
                   let userInfo = message["user"] as? [String: Any] {
                    
                    let authToken = AuthToken(
                        accessToken: tokenData,
                        refreshToken: message["refresh_token"] as? String,
                        expiresAt: {
                            if let timestamp = message["expires_at"] as? TimeInterval {
                                return Date(timeIntervalSince1970: timestamp)
                            }
                            return Date().addingTimeInterval(3600) // Default 1 hour
                        }(),
                        scopes: message["scopes"] as? [String] ?? ["User.Read"],
                        userInfo: AuthToken.UserInfo(
                            id: userInfo["id"] as? String ?? "unknown",
                            displayName: userInfo["displayName"] as? String ?? "Unknown User",
                            email: userInfo["email"] as? String ?? "",
                            tenantId: userInfo["tenantId"] as? String
                        ),
                        issuedAt: Date()
                    )
                    
                    tokenManager.storeToken(authToken)
                } else {
                    errorMessage = message["error"] as? String ?? "Authentication failed"
                }
                
                isWaitingForAuth = false
                
            default:
                print("⚠️ Unknown message type: \(type)")
            }
        }
    }
}

// MARK: - Errors

enum WatchAuthError: LocalizedError {
    case sessionNotSupported
    case iPhoneNotReachable
    case authenticationTimeout
    case invalidURL
    case apiRequestFailed
    
    var errorDescription: String? {
        switch self {
        case .sessionNotSupported:
            return "Watch Connectivity not supported"
        case .iPhoneNotReachable:
            return "iPhone is not reachable"
        case .authenticationTimeout:
            return "Authentication request timed out"
        case .invalidURL:
            return "Invalid API endpoint URL"
        case .apiRequestFailed:
            return "API request failed"
        }
    }
}

#endif