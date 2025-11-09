// SupabaseService.swift
import Foundation
import Combine

final class SupabaseService: ObservableObject {
    static let shared = SupabaseService()
    private init() {}

    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var currentUser: User?

    private let client = AppSupabaseClientLocal.shared

    func signIn(email: String, password: String) -> AnyPublisher<Void, APIError> {
        // If demo-mode is enabled, we should not reach here (AuthViewModel short-circuits)
        return client.signIn(email: email, password: password)
            .handleEvents(receiveOutput: { [weak self] in
                self?.isAuthenticated = true
                self?.currentUser = User(id: UUID().uuidString, email: email, name: "User")
            })
            .eraseToAnyPublisher()
    }

    func signOut() -> AnyPublisher<Void, APIError> {
        return client.signOut()
            .handleEvents(receiveOutput: { [weak self] in
                self?.isAuthenticated = false
                self?.currentUser = nil
            })
            .eraseToAnyPublisher()
    }
    
    func register(email: String, password: String, name: String) -> AnyPublisher<User, APIError> {
        // If demo-mode is enabled, register a mock user
        if DemoModeManager.shared.isDemoEnabled {
            let user = User(id: UUID().uuidString, email: email, name: name)
            return Just(user).setFailureType(to: APIError.self)
                .handleEvents(receiveOutput: { [weak self] user in
                    self?.isAuthenticated = true
                    self?.currentUser = user
                })
                .eraseToAnyPublisher()
        }

        return client.signUp(email: email, password: password, name: name)
            .handleEvents(receiveOutput: { [weak self] user in
                self?.isAuthenticated = true
                self?.currentUser = user
            })
            .eraseToAnyPublisher()
    }

    func updateUserProfile(name: String, profileImage: UIImage?) -> AnyPublisher<Void, APIError> {
        let imageData = profileImage?.pngData()
        return client.updateUserProfile(name: name, profileImage: imageData)
            .handleEvents(receiveOutput: { [weak self] in
                if var user = self?.currentUser { user = User(id: user.id, email: user.email, name: name); self?.currentUser = user }
            })
            .eraseToAnyPublisher()
    }
}

struct User: Identifiable, Codable {
    let id: String
    let email: String
    let name: String
}
