import Foundation
import Combine
import SwiftUI

/// ViewModel to handle user authentication state and interact with backend
class AuthViewModel: ObservableObject {
    // Authentication state
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var authError: String?
    @Published var isLoading = false
    
    // References to services
    private let supabaseService = SupabaseService.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Subscribe to the published properties from SupabaseService
        supabaseService.$isAuthenticated
            .assign(to: &$isAuthenticated)
        
        supabaseService.$currentUser
            .assign(to: &$currentUser)
        
        // If we already have a user, immediately set as authenticated
        if supabaseService.currentUser != nil {
            isAuthenticated = true
        }
    }
    
    /// Sign in a user with email and password
    func signIn(email: String, password: String) {
        debugLog.auth("Attempting sign in for email: \(email)")
        
        // Check for demo-mode credentials
        DemoModeManager.shared.evaluateCredentials(email: email, password: password)
        
        guard !email.isEmpty, !password.isEmpty else {
            debugLog.auth("Sign in failed - empty credentials")
            authError = "Email and password cannot be empty"
            return
        }
        
        isLoading = true
        authError = nil
        
        if DemoModeManager.shared.isDemoEnabled {
            // In demo mode, bypass real Supabase and set a mock user
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                self.isLoading = false
                self.isAuthenticated = true
                self.currentUser = User(id: UUID().uuidString, email: email, name: "John Doe (Demo)")
            }
            return
        }
        
        supabaseService.signIn(email: email, password: password)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] (completion: Subscribers.Completion<APIError>) in
                self?.isLoading = false

                if case .failure(let error) = completion {
                    debugLog.error("Sign in failed for user: \(email)", error: error)
                    self?.authError = error.localizedDescription
                }
            }, receiveValue: { _ in
                debugLog.auth("Sign in successful for user: \(email)")
                // The currentUser and isAuthenticated will be updated via the publishers
            })
            .store(in: &cancellables)
    }
    
    /// Register a new user and create their profile
    func register(name: String, email: String, password: String) {
        debugLog.auth("Attempting registration for email: \(email)")

        guard !name.isEmpty, !email.isEmpty, !password.isEmpty else {
            authError = "Name, email and password cannot be empty"
            return
        }

        isLoading = true
        authError = nil

        // Evaluate demo-mode against provided credentials
        DemoModeManager.shared.evaluateCredentials(email: email, password: password)

        SupabaseService.shared.register(email: email, password: password, name: name)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                self?.isLoading = false
                if case .failure(let error) = completion {
                    self?.authError = error.localizedDescription
                }
            }, receiveValue: { [weak self] user in
                self?.currentUser = user
                self?.isAuthenticated = true
            })
            .store(in: &cancellables)
    }
    
    /// Sign out the current user
    func signOut() {
        supabaseService.signOut()
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] (completion: Subscribers.Completion<APIError>) in
                if case .failure(let error) = completion {
                    self?.authError = error.localizedDescription
                }
            }, receiveValue: { _ in
                // The currentUser and isAuthenticated will be updated via the publishers
            })
            .store(in: &cancellables)
    }
    
    /// Update the user's profile
    func updateUserProfile(name: String) {
        guard currentUser != nil else {
            authError = "Not signed in"
            return
        }

        isLoading = true
        authError = nil

        supabaseService.updateUserProfile(name: name, profileImage: nil as UIImage?)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] (completion: Subscribers.Completion<APIError>) in
                self?.isLoading = false

                if case .failure(let error) = completion {
                    self?.authError = error.localizedDescription
                }
            }, receiveValue: { _ in
                // The currentUser will be updated via the publisher
            })
            .store(in: &cancellables)
    }
}
