import Foundation
import LocalAuthentication

/// Mock Authentication Manager for missing dependency
@MainActor
class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isMonitoring = false
    @Published var currentUser: String?
    @Published var errorMessage: String?
    
    func authenticate() async throws {
        // Mock implementation
        isAuthenticated = true
        currentUser = "Mock User"
    }
    
    func signOut() {
        isAuthenticated = false
        currentUser = nil
    }
    
    func startMonitoring() {
        isMonitoring = true
    }
    
    func stopMonitoring() {
        isMonitoring = false
    }
}

/// Mock Auth View Model
@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var user: EntraIDUser?
    @Published var isLoading = false
    
    func signIn() async {
        isLoading = true
        // Mock delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        isAuthenticated = true
        isLoading = false
    }
    
    func signOut() {
        isAuthenticated = false
        user = nil
    }
}

/// Mock Watch Connectivity Service
class WatchConnectivityService: ObservableObject {
    static let shared = WatchConnectivityService()
    
    @Published var isReachable = false
    @Published var isConnected = false
    @Published var lastMessage: [String: Any]?
    
    private init() {
        // Mock connectivity
        isConnected = Bool.random()
    }
    
    func sendMessage(_ message: [String: Any]) {
        lastMessage = message
    }
}

/// Mock Supabase Service
class SupabaseService: ObservableObject {
    static let shared = SupabaseService()
    
    private init() {}
    
    func getRecentAuthEvents(limit: Int) async throws -> [AuthEvent] {
        // Mock events
        return [
            AuthEvent(
                eventType: .authentication,
                timestamp: Date().addingTimeInterval(-3600),
                success: true,
                device: "iPhone 15",
                location: "Office"
            ),
            AuthEvent(
                eventType: .enrollment,
                timestamp: Date().addingTimeInterval(-7200),
                success: true,
                device: "Apple Watch",
                location: "Home"
            ),
            AuthEvent(
                eventType: .authentication,
                timestamp: Date().addingTimeInterval(-10800),
                success: false,
                device: "iPad",
                location: "Unknown"
            )
        ]
    }
}