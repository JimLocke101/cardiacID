import Foundation

// Minimal stub for SupabaseClient to satisfy HybridTemplateStorageService dependency
public class SupabaseClient {
    public let storage: StorageClient

    public init() {
        self.storage = StorageClient()
    }
}

public class StorageClient {
    public let from: (String) -> StorageBucket

    public init() {
        self.from = { bucketName in
            return StorageBucket(bucketName: bucketName)
        }
    }
}

public class StorageBucket {
    let bucketName: String

    public init(bucketName: String) {
        self.bucketName = bucketName
    }

    public func download(path: String, completion: @escaping (Result<Data, Error>) -> Void) {
        // Stub method: call completion with failure or empty data
        completion(.failure(NSError(domain: "Stub", code: 0, userInfo: [NSLocalizedDescriptionKey: "download not implemented in stub"])))
    }

    public func upload(path: String, data: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        // Stub method: call completion with failure
        completion(.failure(NSError(domain: "Stub", code: 0, userInfo: [NSLocalizedDescriptionKey: "upload not implemented in stub"])))
    }
}

extension SupabaseClient {
    func signOut() {
        // existing signOut implementation
    }

    func signUp(email: String, password: String, name: String) -> AnyPublisher<User, APIError> {
        // Placeholder sign-up flow; replace with real Supabase SDK signUp
        return Future<User, APIError> { promise in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
                self.isAuthenticated = true
                let user = User(id: UUID().uuidString, email: email, name: name)
                promise(.success(user))
            }
        }.eraseToAnyPublisher()
    }
}

extension SupabaseClient {
    // biometric methods section

    func updateUserProfile(name: String, profileImage: Data?) -> AnyPublisher<Void, APIError> {
        return Just(()).setFailureType(to: APIError.self).eraseToAnyPublisher()
    }
}
