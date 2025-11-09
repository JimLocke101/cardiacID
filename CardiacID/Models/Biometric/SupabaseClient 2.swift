// SupabaseClient.swift (stub for compilation and future SDK integration)
import Foundation
import Combine

final class SupabaseClient {
    static let shared = SupabaseClient()
    private init() {}

    // Authentication state
    @Published private(set) var isAuthenticated: Bool = false

    func signIn(email: String, password: String) -> AnyPublisher<Void, APIError> {
        // Placeholder sign-in that succeeds after delay; replace with real SDK
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
}

enum APIError: Error, LocalizedError {
    case authenticationError(String)
    case networkError(String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .authenticationError(let msg): return msg
        case .networkError(let msg): return msg
        case .unknown: return "Unknown error"
        }
    }
}
