// AppSupabaseClient.swift (renamed stub to avoid duplicate filename conflicts)
import Foundation
import Combine
import UIKit

final class AppSupabaseClient: ObservableObject {
    static let shared = AppSupabaseClient()
    private init() {}

    // Authentication state
    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var currentUser: User? = nil

    func signIn(email: String, password: String) -> AnyPublisher<Void, APIError> {
        return Future<Void, APIError> { promise in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
                self.isAuthenticated = true
                self.currentUser = User(
                    id: UUID().uuidString,
                    email: email,
                    firstName: "Mock",
                    lastName: "User"
                )
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    func signOut() -> AnyPublisher<Void, APIError> {
        return Future<Void, APIError> { promise in
            self.isAuthenticated = false
            self.currentUser = nil
            promise(.success(()))
        }.eraseToAnyPublisher()
    }

    func signUp(email: String, password: String, name: String) -> AnyPublisher<User, APIError> {
        return Future<User, APIError> { promise in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
                self.isAuthenticated = true
                let nameParts = name.split(separator: " ", maxSplits: 1)
                let user = User(
                    id: UUID().uuidString,
                    email: email,
                    firstName: nameParts.first.map(String.init),
                    lastName: nameParts.count > 1 ? String(nameParts[1]) : nil
                )
                self.currentUser = user
                promise(.success(user))
            }
        }.eraseToAnyPublisher()
    }

    // Alias for backward compatibility with code calling 'register'
    func register(email: String, password: String, name: String) -> AnyPublisher<User, APIError> {
        return signUp(email: email, password: password, name: name)
    }

    // Biometric template operations used by HybridTemplateStorageService
    func syncBiometricTemplate(_ template: BiometricTemplate) async throws {
        // Replace with real upload
    }

    func loadBiometricTemplate() async throws -> BiometricTemplate {
        // Replace with real download
        throw StorageError.notFound
    }

    func deleteBiometricTemplate() async throws {
        // Replace with real deletion
    }

    func updateUserProfile(name: String, profileImage: UIImage?) -> AnyPublisher<Void, APIError> {
        return Future<Void, APIError> { promise in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                // Update current user's name
                if var user = self.currentUser {
                    let nameParts = name.split(separator: " ", maxSplits: 1)
                    var updatedUser = user
                    updatedUser.firstName = nameParts.first.map(String.init)
                    updatedUser.lastName = nameParts.count > 1 ? String(nameParts[1]) : nil
                    self.currentUser = updatedUser
                }
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    // MARK: - Dashboard/Activity Methods
    func getRecentAuthEvents(limit: Int = 10) async throws -> [AuthEvent] {
        // TODO: Implement real Supabase query
        return []
    }

    func getDevices() async throws -> [Device] {
        // TODO: Implement real Supabase query
        return []
    }

    // MARK: - Auth Event Logging

    /// Log an authentication event to the Supabase auth_events table
    /// Used by BiometricFallbackChainService, AccessControlService, and other auth flows
    func logAuthEvent(
        eventType: String,
        method: String,
        success: Bool,
        confidence: Double?,
        failureReason: String?,
        metadata: [String: Any]?
    ) async throws {
        // Build the event payload matching the auth_events schema
        var body: [String: Any] = [
            "event_type": eventType,
            "authentication_method": method,
            "success": success,
            "created_at": ISO8601DateFormatter().string(from: Date())
        ]

        if let userId = currentUser?.id {
            body["user_id"] = userId
        }
        if let confidence = confidence {
            body["confidence_score"] = confidence
        }
        if let reason = failureReason {
            body["failure_reason"] = reason
        }
        if let meta = metadata,
           let metaData = try? JSONSerialization.data(withJSONObject: meta),
           let metaString = String(data: metaData, encoding: .utf8) {
            body["metadata"] = metaString
        }

        // TODO: Replace with real Supabase PostgREST call when connected
        // Example:
        // let url = URL(string: "\(supabaseURL)/rest/v1/auth_events")!
        // var request = URLRequest(url: url)
        // request.httpMethod = "POST"
        // request.setValue("Bearer \(supabaseKey)", forHTTPHeaderField: "Authorization")
        // request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        // request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // request.httpBody = try JSONSerialization.data(withJSONObject: body)
        // let (_, _) = try await URLSession.shared.data(for: request)

        print("AuthEvent logged: [\(eventType)] \(method) - success: \(success)")
    }
}

// MARK: - Type Aliases for Compatibility
/// Alias for code that references AppSupabaseClientLocal
typealias AppSupabaseClientLocal = AppSupabaseClient

/// Alias for code that references SupabaseService
typealias SupabaseService = AppSupabaseClient
