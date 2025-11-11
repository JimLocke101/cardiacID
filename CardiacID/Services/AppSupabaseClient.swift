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
}

// MARK: - Type Aliases for Compatibility
/// Alias for code that references AppSupabaseClientLocal
typealias AppSupabaseClientLocal = AppSupabaseClient

/// Alias for code that references SupabaseService
typealias SupabaseService = AppSupabaseClient
