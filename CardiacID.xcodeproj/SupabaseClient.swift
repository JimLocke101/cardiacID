//
//  SupabaseClient.swift
//  HeartID Mobile
//
//  Production Supabase client using official Swift SDK
//  Integrates with CardiacID authentication and data models
//

import Foundation
import UIKit
import Supabase
import Combine

/// Production Supabase service with CardiacID integration
class SupabaseService: ObservableObject {
    // MARK: - Singleton
    static let shared = SupabaseService()

    // MARK: - Dependencies
    private let credentialManager = SecureCredentialManager.shared
    private let environmentConfig = EnvironmentConfig.current

    // MARK: - Supabase Client
    private let client: SupabaseClient

    // MARK: - Published State
    @Published private(set) var currentUser: User?
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isInitialized = false

    // MARK: - Initialization

    private init() {
        // Initialize Supabase client with your credentials
        client = SupabaseClient(
            supabaseURL: URL(string: environmentConfig.supabaseURL)!,
            supabaseKey: environmentConfig.supabaseAnonKey
        )
        
        isInitialized = true
        print("✅ Supabase client initialized successfully")
        print("   URL: \(environmentConfig.supabaseURL)")
        print("   Project: \(environmentConfig.supabaseProjectID)")

        // Check for existing session
        Task {
            await checkExistingSession()
        }
    }

    // MARK: - Session Management

    private func checkExistingSession() async {
        do {
            let session = try await client.auth.session
            await MainActor.run {
                self.isAuthenticated = true
                let authUser = session.user
                print("✅ Restored existing session for user: \(authUser.email ?? "unknown")")
                Task {
                    try? await self.loadUserProfile(authUser.id)
                }
            }
        } catch {
            print("ℹ️ No existing session found")
        }
    }

    // MARK: - Authentication

    /// Sign in with email and password
    func signIn(email: String, password: String) async throws -> User {
        do {
            // Authenticate with Supabase Auth
            let session = try await client.auth.signIn(email: email, password: password)

            // Load user profile from database
            let user = try await loadUserProfile(session.user.id)

            await MainActor.run {
                self.currentUser = user
                self.isAuthenticated = true
            }

            // Log authentication event
            try await logAuthEvent(
                userId: user.id,
                eventType: .login,
                success: true,
                authMethod: .password
            )

            print("✅ User signed in successfully: \(email)")
            return user

        } catch {
            print("❌ Sign in failed: \(error)")

            // Log failed attempt
            try? await logAuthEvent(
                userId: UUID().uuidString,
                eventType: .login,
                success: false,
                authMethod: .password,
                failureReason: error.localizedDescription
            )

            throw SupabaseError.authenticationError(error)
        }
    }

    /// Sign up with email and password
    func signUp(email: String, password: String, fullName: String? = nil) async throws -> User {
        do {
            // Create auth user
            let session = try await client.auth.signUp(email: email, password: password)
            let authUser = session.user

            // Create user profile in database
            let user = User(
                id: authUser.id.uuidString,
                email: email,
                firstName: fullName ?? "",
                lastName: nil,
                profileImageUrl: nil,
                deviceIds: [],
                enrollmentStatus: .notStarted,
                createdAt: Date()
            )

            try await createUserProfile(user)

            await MainActor.run {
                self.currentUser = user
                self.isAuthenticated = true
            }

            print("✅ User signed up successfully: \(email)")
            return user

        } catch {
            print("❌ Sign up failed: \(error)")
            throw SupabaseError.authenticationError(error)
        }
    }

    /// Sign out current user
    func signOut() async throws {
        do {
            try await client.auth.signOut()

            await MainActor.run {
                self.currentUser = nil
                self.isAuthenticated = false
            }

            print("✅ User signed out successfully")

        } catch {
            print("❌ Sign out failed: \(error)")
            throw SupabaseError.authenticationError(error)
        }
    }

    // MARK: - User Profile Management

    private func loadUserProfile(_ userId: UUID) async throws -> User {
        struct UserRow: Decodable {
            let id: UUID
            let email: String
            let full_name: String?
            let avatar_url: String?
            let enrollment_status: String
            let created_at: String
        }

        do {
            let response: UserRow = try await client.database
                .from("users")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value

            let user = User(
                id: response.id.uuidString,
                email: response.email,
                firstName: response.full_name ?? "",
                lastName: nil,
                profileImageUrl: response.avatar_url,
                deviceIds: [],
                enrollmentStatus: User.EnrollmentStatus(rawValue: response.enrollment_status) ?? .notStarted,
                createdAt: ISO8601DateFormatter().date(from: response.created_at) ?? Date()
            )

            return user

        } catch {
            print("❌ Failed to load user profile: \(error)")
            throw SupabaseError.dataError(error.localizedDescription)
        }
    }

    private func createUserProfile(_ user: User) async throws {
        struct UserInsert: Encodable {
            let id: UUID
            let email: String
            let full_name: String?
            let enrollment_status: String
        }

        let insert = UserInsert(
            id: UUID(uuidString: user.id)!,
            email: user.email,
            full_name: (user.firstName?.isEmpty ?? true) ? nil : user.firstName,
            enrollment_status: user.enrollmentStatus.rawValue
        )

        do {
            try await client.database
                .from("users")
                .insert(insert)
                .execute()

            print("✅ User profile created in database")

        } catch {
            print("❌ Failed to create user profile: \(error)")
            throw SupabaseError.dataError(error.localizedDescription)
        }
    }

    // MARK: - Device Management

    func getDevices() async throws -> [Device] {
        guard let userId = currentUser?.id else {
            throw SupabaseError.authenticationError(NSError(domain: "SupabaseClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No current user"]))
        }

        struct DeviceRow: Decodable {
            let id: UUID
            let user_id: UUID
            let device_name: String
            let device_type: String
            let status: String
            let last_sync_date: String?
        }

        do {
            let response: [DeviceRow] = try await client.database
                .from("devices")
                .select()
                .eq("user_id", value: userId)
                .order("created_at", ascending: false)
                .execute()
                .value

            let devices = response.map { row in
                Device(
                    name: row.device_name,
                    type: Device.DeviceType(rawValue: row.device_type) ?? .other,
                    status: Device.DeviceStatus(rawValue: row.status) ?? .inactive,
                    lastSeen: row.last_sync_date.flatMap { ISO8601DateFormatter().date(from: $0) },
                    isOnline: row.status == "active",
                    userId: row.user_id.uuidString
                )
            }

            return devices

        } catch {
            print("❌ Failed to load devices: \(error)")
            throw SupabaseError.dataError(error.localizedDescription)
        }
    }

    // MARK: - Authentication Events

    func logAuthEvent(
        userId: String,
        eventType: AuthEventType,
        success: Bool,
        authMethod: AuthMethod,
        deviceId: String? = nil,
        confidenceScore: Double? = nil,
        failureReason: String? = nil
    ) async throws {
        struct AuthEventInsert: Encodable {
            let user_id: UUID
            let device_id: UUID?
            let event_type: String
            let authentication_method: String?
            let success: Bool
            let confidence_score: Double?
            let failure_reason: String?
        }

        let insert = AuthEventInsert(
            user_id: UUID(uuidString: userId)!,
            device_id: deviceId.flatMap { UUID(uuidString: $0) },
            event_type: eventType.rawValue,
            authentication_method: authMethod.rawValue,
            success: success,
            confidence_score: confidenceScore,
            failure_reason: failureReason
        )

        do {
            try await client.database
                .from("auth_events")
                .insert(insert)
                .execute()

            print("✅ Auth event logged: \(eventType.rawValue)")

        } catch {
            print("❌ Failed to log auth event: \(error)")
            // Don't throw - logging failures shouldn't block auth flow
        }
    }

    func getRecentAuthEvents(limit: Int = 50) async throws -> [AuthEvent] {
        guard let userId = currentUser?.id else {
            throw SupabaseError.authenticationError(NSError(domain: "SupabaseClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No current user"]))
        }

        struct AuthEventRow: Decodable {
            let id: UUID
            let user_id: UUID
            let device_id: UUID?
            let event_type: String
            let success: Bool
            let failure_reason: String?
            let timestamp: String
            let location_name: String?
        }

        do {
            let response: [AuthEventRow] = try await client.database
                .from("auth_events")
                .select()
                .eq("user_id", value: userId)
                .order("timestamp", ascending: false)
                .limit(limit)
                .execute()
                .value

            let events = response.map { row in
                AuthEvent(
                    timestamp: ISO8601DateFormatter().date(from: row.timestamp) ?? Date(),
                    success: row.success,
                    details: row.failure_reason ?? (row.success ? "Authentication successful" : "Authentication failed"),
                    userId: row.user_id.uuidString,
                    deviceId: row.device_id?.uuidString,
                    location: row.location_name
                )
            }

            return events

        } catch {
            print("❌ Failed to load auth events: \(error)")
            throw SupabaseError.dataError(error.localizedDescription)
        }
    }

    // MARK: - Biometric Templates

    func saveBiometricTemplate(_ encryptedTemplate: Data, qualityScore: Double, sampleCount: Int) async throws {
        guard let userId = currentUser?.id else {
            throw SupabaseError.authenticationError(NSError(domain: "SupabaseClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No current user"]))
        }

        struct TemplateInsert: Encodable {
            let user_id: UUID
            let template_data: Data
            let quality_score: Double
            let confidence_level: Double
            let sample_count: Int
            let device_model: String
            let device_os_version: String
        }

        let insert = TemplateInsert(
            user_id: UUID(uuidString: userId)!,
            template_data: encryptedTemplate,
            quality_score: qualityScore,
            confidence_level: min(qualityScore, 1.0),
            sample_count: sampleCount,
            device_model: UIDevice.current.model,
            device_os_version: UIDevice.current.systemVersion
        )

        do {
            try await client.database
                .from("biometric_templates")
                .insert(insert)
                .execute()

            print("✅ Biometric template saved securely")

        } catch {
            print("❌ Failed to save biometric template: \(error)")
            throw SupabaseError.dataError(error.localizedDescription)
        }
    }

    // MARK: - Direct Client Access
    
    /// Get direct access to the Supabase client for custom operations
    var supabaseClient: SupabaseClient {
        return client
    }
}

// MARK: - Supporting Types

enum AuthEventType: String {
    case enrollment
    case authentication
    case step_up_auth = "step_up_auth"
    case revocation
    case login
    case logout
}

enum AuthMethod: String {
    case ecg
    case ppg
    case hybrid
    case password
    case biometric
    case oauth
}

enum SupabaseError: Error, LocalizedError {
    case clientNotInitialized
    case authenticationError(Error)
    case dataError(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .clientNotInitialized:
            return "Supabase client not initialized. Please configure API credentials."
        case .authenticationError(let error):
            return "Authentication failed: \(error.localizedDescription)"
        case .dataError(let message):
            return "Data error: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Global Client Access

/// Global access to the configured Supabase client for convenience
let supabase = SupabaseService.shared.supabaseClient