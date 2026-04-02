import Foundation
import Combine
import SwiftUI

/// ViewModel to handle user authentication state and interact with backend.
/// Every authentication action is logged to both AuditLogger (local/OSLog)
/// and AppSupabaseClient (cloud auth_events table) for the Activity Log.
class AuthViewModel: ObservableObject {
    // Authentication state
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var authError: String?
    @Published var isLoading = false
    @Published var initialFlow: AuthFlow = .signIn
    @Published var shouldShowWatchSetup = false

    enum AuthFlow {
        case signIn
        case signUp
    }

    // References to services
    private let supabaseService = SupabaseService.shared
    private let auditLogger     = AuditLogger.shared
    private var cancellables    = Set<AnyCancellable>()

    init() {
        supabaseService.$isAuthenticated
            .assign(to: &$isAuthenticated)

        supabaseService.$currentUser
            .assign(to: &$currentUser)

        if supabaseService.currentUser != nil {
            isAuthenticated = true
        }
    }

    // MARK: - Sign In (real Supabase — never demo)

    func signIn(email: String, password: String) {
        debugLog.auth("Attempting sign in for email: \(email)")
        logEvent(type: "sign_in_attempt", method: "password", email: email)

        guard !email.isEmpty, !password.isEmpty else {
            debugLog.auth("Sign in failed - empty credentials")
            authError = "Email and password cannot be empty"
            logEvent(type: "sign_in_failed", method: "password", email: email, success: false, reason: "empty_credentials")
            return
        }

        isLoading = true
        authError = nil

        supabaseService.signIn(email: email, password: password)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] (completion: Subscribers.Completion<APIError>) in
                self?.isLoading = false

                if case .failure(let error) = completion {
                    debugLog.error("Sign in failed for user: \(email)", error: error)
                    self?.authError = error.localizedDescription
                    self?.logEvent(type: "sign_in_failed", method: "password", email: email,
                                   success: false, reason: error.localizedDescription)
                }
            }, receiveValue: { [weak self] _ in
                debugLog.auth("Sign in successful for user: \(email)")
                self?.logEvent(type: "sign_in_success", method: "password", email: email, success: true)
            })
            .store(in: &cancellables)
    }

    // MARK: - Register

    func register(name: String, email: String, password: String) {
        debugLog.auth("Attempting registration for email: \(email)")
        logEvent(type: "registration_attempt", method: "password", email: email)

        guard !name.isEmpty, !email.isEmpty, !password.isEmpty else {
            authError = "Name, email and password cannot be empty"
            logEvent(type: "registration_failed", method: "password", email: email,
                     success: false, reason: "empty_fields")
            return
        }

        isLoading = true
        authError = nil

        SupabaseService.shared.register(email: email, password: password, name: name)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                self?.isLoading = false
                if case .failure(let error) = completion {
                    self?.authError = error.localizedDescription
                    self?.logEvent(type: "registration_failed", method: "password", email: email,
                                   success: false, reason: error.localizedDescription)
                }
            }, receiveValue: { [weak self] user in
                self?.currentUser = user
                self?.isAuthenticated = true
                self?.shouldShowWatchSetup = true
                self?.logEvent(type: "registration_success", method: "password", email: email, success: true)
            })
            .store(in: &cancellables)
    }

    // MARK: - Demo Mode (isolated — only from Demo button)

    func signInDemo() {
        logEvent(type: "demo_mode_attempt", method: "demo", email: "john.doe@acme.com")
        #if DEBUG
        DemoModeManager.shared.evaluateCredentials(
            email: "john.doe@acme.com",
            password: "~password1234argos2020~"
        )
        if DemoModeManager.shared.isDemoEnabled {
            isLoading = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.isLoading = false
                self?.isAuthenticated = true
                self?.currentUser = User(
                    id: UUID().uuidString,
                    email: "john.doe@acme.com",
                    firstName: "John",
                    lastName: "Doe (Demo)"
                )
                self?.logEvent(type: "demo_mode_activated", method: "demo",
                               email: "john.doe@acme.com", success: true)
            }
            return
        }
        #endif
        authError = "Demo mode is not available in this build."
        logEvent(type: "demo_mode_unavailable", method: "demo", email: "", success: false,
                 reason: "Not available in this build configuration")
    }

    // MARK: - Sign Out

    func signOut() {
        let email = currentUser?.email ?? "unknown"
        logEvent(type: "sign_out", method: "manual", email: email, success: true)

        supabaseService.signOut()
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] (completion: Subscribers.Completion<APIError>) in
                if case .failure(let error) = completion {
                    self?.authError = error.localizedDescription
                    self?.logEvent(type: "sign_out_failed", method: "manual",
                                   email: email, success: false, reason: error.localizedDescription)
                }
            }, receiveValue: { [weak self] _ in
                self?.logEvent(type: "sign_out_complete", method: "manual", email: email, success: true)
            })
            .store(in: &cancellables)
    }

    // MARK: - Update Profile

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
            }, receiveValue: { [weak self] _ in
                self?.logEvent(type: "profile_updated", method: "manual",
                               email: self?.currentUser?.email ?? "", success: true)
            })
            .store(in: &cancellables)
    }

    func setInitialFlow(_ flow: AuthFlow) {
        self.initialFlow = flow
    }

    // MARK: - Audit Logging

    /// Logs to both AuditLogger (in-memory, instant for Activity Log) and
    /// AppSupabaseClient (cloud, persistent in auth_events table).
    private func logEvent(type: String, method: String, email: String,
                          success: Bool = true, reason: String? = nil) {
        // 1. Local audit log (immediate — shows in Activity Log instantly)
        auditLogger.logOperational(
            action: type,
            outcome: success ? "success" : "failed",
            reasonCode: reason ?? email
        )

        // 2. Cloud audit log (persistent — survives app restarts)
        Task {
            try? await AppSupabaseClientLocal.shared.logAuthEvent(
                eventType: type,
                method: method,
                success: success,
                confidence: nil,
                failureReason: reason,
                metadata: ["email": email, "source": "AuthViewModel"]
            )
        }
    }
}
