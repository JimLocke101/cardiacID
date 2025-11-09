// AppSupabaseClient.swift (renamed stub to avoid duplicate filename conflicts)
import Foundation
import Combine
import UIKit

final class AppSupabaseClient {
    static let shared = AppSupabaseClient()
    private init() {}

    // Authentication state
    @Published private(set) var isAuthenticated: Bool = false

    func signIn(email: String, password: String) -> AnyPublisher<Void, APIError> {
        return Future<Void, APIError> { promise in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
                self.isAuthenticated = true
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    func signOut() -> AnyPublisher<Void, APIError> {
        return Future<Void, APIError> { promise in
            self.isAuthenticated = false
            promise(.success(()))
        }.eraseToAnyPublisher()
    }

    func signUp(email: String, password: String, name: String) -> AnyPublisher<User, APIError> {
        return Future<User, APIError> { promise in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
                self.isAuthenticated = true
                let user = User(id: UUID().uuidString, email: email, name: name)
                promise(.success(user))
            }
        }.eraseToAnyPublisher()
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

    func updateUserProfile(name: String, profileImage: Data?) -> AnyPublisher<Void, APIError> {
        return Just(()).setFailureType(to: APIError.self).eraseToAnyPublisher()
    }
}
