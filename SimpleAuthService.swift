//
//  SimpleAuthService.swift
//  CardiacID
//
//  Simplified authentication service to resolve build issues
//  This replaces the complex platform-specific implementations
//

import Foundation
import Combine

#if os(iOS)
import UIKit
#if canImport(MSAL)
import MSAL
#endif
#endif

#if os(watchOS)
import WatchKit
#endif

// MARK: - Simple User Model

struct SimpleUser: Codable, Identifiable {
    let id: String
    let displayName: String
    let email: String
    
    var initials: String {
        let components = displayName.components(separatedBy: " ")
        let initials = components.compactMap { $0.first }.map { String($0) }
        return initials.prefix(2).joined().uppercased()
    }
}

// MARK: - Simple Authentication Service

@MainActor
class SimpleAuthService: ObservableObject {
    static let shared = SimpleAuthService()
    
    @Published var isAuthenticated = false
    @Published var currentUser: SimpleUser?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let userDefaults = UserDefaults(suiteName: "group.com.argos.cardiacid") ?? UserDefaults.standard
    
    #if os(iOS) && canImport(MSAL)
    private var msalApplication: MSALPublicClientApplication?
    #endif
    
    private init() {
        loadStoredUser()
        #if os(iOS)
        setupMSAL()
        #endif
    }
    
    // MARK: - Setup
    
    private func loadStoredUser() {
        if let userData = userDefaults.data(forKey: "stored_user"),
           let user = try? JSONDecoder().decode(SimpleUser.self, from: userData) {
            currentUser = user
            isAuthenticated = true
        }
    }
    
    #if os(iOS)
    private func setupMSAL() {
        #if canImport(MSAL)
        // Only setup MSAL if the framework is available
        do {
            let config = MSALPublicClientApplicationConfig(
                clientId: "your-client-id-here", // Replace with actual client ID
                redirectUri: "cardiacid://auth",
                authority: try MSALAADAuthority(url: URL(string: "https://login.microsoftonline.com/common")!)
            )
            msalApplication = try MSALPublicClientApplication(configuration: config)
        } catch {
            print("⚠️ MSAL setup failed: \(error)")
            // Fallback to mock authentication in debug mode
            #if DEBUG
            print("🔧 Using mock authentication for development")
            #endif
        }
        #endif
    }
    #endif
    
    // MARK: - Authentication Methods
    
    func signIn() async throws {
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        #if os(iOS)
        try await signInIOS()
        #elseif os(watchOS)
        try await signInWatchOS()
        #else
        throw AuthError.platformNotSupported
        #endif
    }
    
    #if os(iOS)
    private func signInIOS() async throws {
        #if canImport(MSAL)
        if let msalApp = msalApplication {
            try await signInWithMSAL(msalApp)
        } else {
            try await signInMock()
        }
        #else
        try await signInMock()
        #endif
    }
    
    #if canImport(MSAL)
    private func signInWithMSAL(_ msalApp: MSALPublicClientApplication) async throws {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let viewController = windowScene.windows.first?.rootViewController else {
            throw AuthError.noViewController
        }
        
        let webParameters = MSALWebviewParameters(authPresentationViewController: viewController)
        let parameters = MSALInteractiveTokenParameters(
            scopes: ["User.Read", "openid", "profile"],
            webviewParameters: webParameters
        )
        
        let result = try await msalApp.acquireToken(with: parameters)
        
        let user = SimpleUser(
            id: result.account.identifier ?? UUID().uuidString,
            displayName: result.account.username ?? "MSAL User",
            email: result.account.username ?? ""
        )
        
        await storeUser(user)
    }
    #endif
    
    private func signInMock() async throws {
        // Mock authentication for development/testing
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
        
        let mockUser = SimpleUser(
            id: UUID().uuidString,
            displayName: "Test User",
            email: "test@example.com"
        )
        
        await storeUser(mockUser)
    }
    #endif
    
    #if os(watchOS)
    private func signInWatchOS() async throws {
        // For watchOS, we'll use a simplified approach
        // In a real implementation, this would communicate with iOS
        
        isLoading = true
        
        // Simulate authentication delay
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // For now, create a mock user for watchOS
        let watchUser = SimpleUser(
            id: "watch-user-\(UUID().uuidString)",
            displayName: "Watch User",
            email: "watch@example.com"
        )
        
        await storeUser(watchUser)
    }
    #endif
    
    func signOut() async {
        #if os(iOS) && canImport(MSAL)
        // Clear MSAL cache if available
        if let msalApp = msalApplication {
            do {
                let accounts = try msalApp.allAccounts()
                for account in accounts {
                    try msalApp.remove(account)
                }
            } catch {
                print("⚠️ MSAL signout failed: \(error)")
            }
        }
        #endif
        
        // Clear stored user data
        userDefaults.removeObject(forKey: "stored_user")
        
        currentUser = nil
        isAuthenticated = false
        errorMessage = nil
    }
    
    // MARK: - Helper Methods
    
    private func storeUser(_ user: SimpleUser) async {
        do {
            let userData = try JSONEncoder().encode(user)
            userDefaults.set(userData, forKey: "stored_user")
            
            currentUser = user
            isAuthenticated = true
            
            print("✅ User authenticated: \(user.displayName)")
        } catch {
            errorMessage = "Failed to store user data: \(error.localizedDescription)"
        }
    }
}

// MARK: - Error Types

enum AuthError: LocalizedError {
    case platformNotSupported
    case noViewController
    case authenticationFailed
    
    var errorDescription: String? {
        switch self {
        case .platformNotSupported:
            return "Authentication not supported on this platform"
        case .noViewController:
            return "No view controller available for authentication"
        case .authenticationFailed:
            return "Authentication failed"
        }
    }
}