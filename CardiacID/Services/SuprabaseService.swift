import Foundation
import Combine

// MARK: - API Models

struct AuthEvent: Codable, Identifiable {
    let id: String
    let userId: String
    let deviceId: String
    let eventType: EventType
    let success: Bool
    let failureReason: String?
    let timestamp: Date
    let location: String?
    
    enum EventType: String, Codable {
        case enrollment = "enrollment"
        case authentication = "authentication"
        case revocation = "revocation"
    }
    
    // Full initializer
    init(id: String, userId: String, deviceId: String, eventType: EventType, success: Bool, failureReason: String?, timestamp: Date, location: String?) {
        self.id = id
        self.userId = userId
        self.deviceId = deviceId
        self.eventType = eventType
        self.success = success
        self.failureReason = failureReason
        self.timestamp = timestamp
        self.location = location
    }
    
    // Convenience initializer for local events
    init(timestamp: Date, success: Bool, details: String, heartRate: Int?) {
        self.id = UUID().uuidString
        self.userId = "local"
        self.deviceId = "local"
        self.eventType = .authentication
        self.success = success
        self.failureReason = success ? nil : details
        self.timestamp = timestamp
        self.location = nil
    }
}

struct Device: Codable, Identifiable {
    let id: String
    let userId: String
    let name: String
    let type: SupabaseDeviceType
    let status: DeviceStatus
    let lastSyncDate: Date?
    
    enum SupabaseDeviceType: String, Codable {
        case appleWatch = "apple_watch"
        case galaxyWatch = "galaxy_watch"
        case ouraRing = "oura_ring"
        case other = "other"
    }
    
    enum DeviceStatus: String, Codable {
        case active = "active"
        case inactive = "inactive"
        case pending = "pending"
        case revoked = "revoked"
    }
}

// MARK: - API Errors

enum SupabaseError: Error {
    case networkError(Error)
    case authenticationError
    case dataError(String)
    case encodingError
    case decodingError
    case unknownError
}

// MARK: - Suprabase Service

class SupabaseService {
    // Singleton instance
    static let shared = SupabaseService()

    // Secure credential manager
    private let credentialManager = SecureCredentialManager.shared
    private let environmentConfig = EnvironmentConfig.current

    // API Configuration (loaded securely from Keychain)
    private var baseUrl: String {
        return environmentConfig.supabaseURL
    }

    private var apiKey: String? {
        return try? credentialManager.retrieve(forKey: .supabaseAPIKey)
    }

    private var accessToken: String? {
        get {
            return try? credentialManager.retrieve(forKey: .userAuthToken)
        }
        set {
            if let token = newValue {
                try? credentialManager.store(token, forKey: .userAuthToken, securityLevel: .biometricRequired)
            } else {
                try? credentialManager.delete(forKey: .userAuthToken)
            }
        }
    }
    
    // Session state
    @Published private(set) var currentUser: User?
    @Published private(set) var isAuthenticated = false

    private init() {
        // Validate that API key is configured
        if apiKey == nil {
            print("⚠️ WARNING: Supabase API key not found in Keychain. Please configure credentials.")
        }
    }
    
    // MARK: - Authentication
    
    func signIn(email: String, password: String) -> AnyPublisher<User, SupabaseError> {
        // In a real app, this would make an actual API call to Supabase
        // For this demo, we'll simulate a successful sign-in
        
        let mockUser = User(
            id: UUID().uuidString,
            email: email,
            firstName: "John",
            lastName: "Doe",
            profileImageUrl: nil,
            deviceIds: ["apple-watch-1"],
            enrollmentStatus: User.EnrollmentStatus.completed,
            createdAt: Date()
        )
        
        return Just(mockUser)
            .delay(for: .seconds(1), scheduler: RunLoop.main)
            .handleEvents(receiveOutput: { [weak self] user in
                print("🔐 SupabaseService: Setting user and authentication state")
                self?.currentUser = user
                self?.isAuthenticated = true
                print("🔐 SupabaseService: isAuthenticated = \(self?.isAuthenticated ?? false)")
                // In a real app, would save token to keychain
                self?.accessToken = "mock-jwt-token"
            })
            .setFailureType(to: SupabaseError.self)
            .eraseToAnyPublisher()
    }
    
    func signOut() -> AnyPublisher<Void, SupabaseError> {
        // In a real app, this would make an API call to invalidate the token
        return Just(())
            .delay(for: .seconds(0.5), scheduler: RunLoop.main)
            .handleEvents(receiveOutput: { [weak self] _ in
                self?.currentUser = nil
                self?.isAuthenticated = false
                self?.accessToken = nil
            })
            .setFailureType(to: SupabaseError.self)
            .eraseToAnyPublisher()
    }
    
    // MARK: - User Management
    
    func updateUserProfile(name: String?, profileImage: Data?) -> AnyPublisher<User, SupabaseError> {
        guard var user = currentUser else {
            return Fail(error: SupabaseError.authenticationError).eraseToAnyPublisher()
        }
        
        if let name = name {
            // In a real app, this would make an API call to update user info
            var updatedUser = user
            updatedUser.firstName = name
            updatedUser.lastName = nil // Or handle parsing of name for first/last
            return Just(updatedUser)
                .delay(for: .seconds(0.5), scheduler: RunLoop.main)
                .handleEvents(receiveOutput: { [weak self] user in
                    self?.currentUser = user
                })
                .setFailureType(to: SupabaseError.self)
                .eraseToAnyPublisher()
        }
        
        return Just(user)
            .setFailureType(to: SupabaseError.self)
            .eraseToAnyPublisher()
    }
    
    // MARK: - Device Management
    
    func getDevices() -> AnyPublisher<[Device], SupabaseError> {
        guard isAuthenticated else {
            return Fail(error: SupabaseError.authenticationError).eraseToAnyPublisher()
        }
        
        // Mock devices for demo
        let mockDevices = [
            Device(
                id: "apple-watch-1",
                userId: currentUser?.id ?? "",
                name: "Apple Watch Series 9",
                type: .appleWatch,
                status: .active,
                lastSyncDate: Date()
            ),
            Device(
                id: "oura-ring-1",
                userId: currentUser?.id ?? "",
                name: "Oura Ring Gen3",
                type: .ouraRing,
                status: .active,
                lastSyncDate: Date().addingTimeInterval(-3600)
            )
        ]
        
        return Just(mockDevices)
            .delay(for: .seconds(0.5), scheduler: RunLoop.main)
            .setFailureType(to: SupabaseError.self)
            .eraseToAnyPublisher()
    }
    
    func addDevice(name: String, type: Device.SupabaseDeviceType) -> AnyPublisher<Device, SupabaseError> {
        guard isAuthenticated, let userId = currentUser?.id else {
            return Fail(error: SupabaseError.authenticationError).eraseToAnyPublisher()
        }
        
        let newDevice = Device(
            id: UUID().uuidString,
            userId: userId,
            name: name,
            type: type,
            status: .pending,
            lastSyncDate: nil
        )
        
        return Just(newDevice)
            .delay(for: .seconds(0.5), scheduler: RunLoop.main)
            .setFailureType(to: SupabaseError.self)
            .eraseToAnyPublisher()
    }
    
    // MARK: - Authentication Events
    
    func logAuthEvent(deviceId: String, eventType: AuthEvent.EventType, success: Bool, failureReason: String? = nil) -> AnyPublisher<AuthEvent, SupabaseError> {
        guard isAuthenticated, let userId = currentUser?.id else {
            return Fail(error: SupabaseError.authenticationError).eraseToAnyPublisher()
        }
        
        let event = AuthEvent(
            id: UUID().uuidString,
            userId: userId,
            deviceId: deviceId,
            eventType: eventType,
            success: success,
            failureReason: failureReason,
            timestamp: Date(),
            location: "Unknown" // In a real app, this would be the actual location if available
        )
        
        return Just(event)
            .delay(for: .seconds(0.2), scheduler: RunLoop.main)
            .setFailureType(to: SupabaseError.self)
            .eraseToAnyPublisher()
    }
    
    func getRecentAuthEvents(limit: Int = 10) -> AnyPublisher<[AuthEvent], SupabaseError> {
        guard isAuthenticated, let userId = currentUser?.id else {
            return Fail(error: SupabaseError.authenticationError).eraseToAnyPublisher()
        }
        
        // Mock auth events for demo
        var mockEvents: [AuthEvent] = []
        
        for i in 0..<min(limit, 20) {
            let success = i % 3 != 0 // Make some failures for demonstration
            let event = AuthEvent(
                id: UUID().uuidString,
                userId: userId,
                deviceId: i % 2 == 0 ? "apple-watch-1" : "oura-ring-1",
                eventType: .authentication,
                success: success,
                failureReason: success ? nil : "Pattern mismatch",
                timestamp: Date().addingTimeInterval(-Double(i * 3600)),
                location: "Home"
            )
            mockEvents.append(event)
        }
        
        return Just(mockEvents)
            .delay(for: .seconds(0.5), scheduler: RunLoop.main)
            .setFailureType(to: SupabaseError.self)
            .eraseToAnyPublisher()
    }
}
