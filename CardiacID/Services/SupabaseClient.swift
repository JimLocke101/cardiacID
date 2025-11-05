//
//  SupabaseClient.swift
//  HeartID Mobile
//
//  Production Supabase client using official Swift SDK
//  Replaces mock SuprabaseService with real database operations
//

import Foundation
import Supabase
import Auth
import PostgREST
import Combine

/// Production Supabase client with real database integration
class SupabaseClient: ObservableObject {
    // MARK: - Singleton
    static let shared = SupabaseClient()

    // MARK: - Dependencies
    private let credentialManager = SecureCredentialManager.shared
    private let environmentConfig = EnvironmentConfig.current

    // MARK: - Supabase Client
    private var client: SupabaseClient?

    // MARK: - Published State
    @Published private(set) var currentUser: User?
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isInitialized = false

    // MARK: - Initialization

    private init() {
        initializeClient()
    }

    private func initializeClient() {
        do {
            // Get API key from secure storage
            guard let apiKey = try? credentialManager.retrieve(forKey: .supabaseAPIKey) else {
                print("⚠️ Supabase API key not found in Keychain")
                print("💡 Please complete credential setup in CredentialSetupView")
                return
            }

            // Get Supabase URL from environment config
            let supabaseURL = URL(string: environmentConfig.supabaseURL)!

            // Initialize Supabase client
            self.client = SupabaseClient(
                supabaseURL: supabaseURL,
                supabaseKey: apiKey,
                options: SupabaseClientOptions(
                    db: DatabaseOptions(schema: "public"),
                    auth: AuthOptions(
                        autoRefreshToken: true,
                        persistSession: true,
                        detectSessionInURL: true,
                        flowType: .pkce
                    ),
                    global: GlobalOptions(
                        headers: [
                            "X-Client-Info": "heartid-ios/\(DebugConfig.appVersion)"
                        ]
                    )
                )
            )

            isInitialized = true
            print("✅ Supabase client initialized successfully")

            // Check for existing session
            Task {
                await checkExistingSession()
            }

        } catch {
            print("❌ Failed to initialize Supabase client: \(error)")
        }
    }

    // MARK: - Session Management

    private func checkExistingSession() async {
        guard let client = client else { return }

        do {
            let session = try await client.auth.session
            await MainActor.run {
                self.isAuthenticated = session.user != nil
                if let authUser = session.user {
                    print("✅ Restored existing session for user: \(authUser.email ?? "unknown")")
                    Task {
                        await self.loadUserProfile(authUser.id)
                    }
                }
            }
        } catch {
            print("ℹ️ No existing session found")
        }
    }

    // MARK: - Authentication

    /// Sign in with email and password
    func signIn(email: String, password: String) async throws -> User {
        guard let client = client else {
            throw SupabaseError.clientNotInitialized
        }

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
                userId: UUID().uuidString, // Unknown user
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
        guard let client = client else {
            throw SupabaseError.clientNotInitialized
        }

        do {
            // Create auth user
            let session = try await client.auth.signUp(email: email, password: password)

            guard let authUser = session.user else {
                throw SupabaseError.authenticationError(NSError(domain: "SupabaseClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user returned from signUp"]))
            }

            // Create user profile in database
            let user = User(
                id: authUser.id.uuidString,
                email: email,
                firstName: fullName ?? "",
                lastName: nil,
                profileImageUrl: nil,
                deviceIds: [],
                enrollmentStatus: .pending,
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
        guard let client = client else {
            throw SupabaseError.clientNotInitialized
        }

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

    // MARK: - User Profile

    private func loadUserProfile(_ userId: UUID) async throws -> User {
        guard let client = client else {
            throw SupabaseError.clientNotInitialized
        }

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
                enrollmentStatus: User.EnrollmentStatus(rawValue: response.enrollment_status) ?? .pending,
                createdAt: ISO8601DateFormatter().date(from: response.created_at) ?? Date()
            )

            return user

        } catch {
            print("❌ Failed to load user profile: \(error)")
            throw SupabaseError.dataError(error.localizedDescription)
        }
    }

    private func createUserProfile(_ user: User) async throws {
        guard let client = client else {
            throw SupabaseError.clientNotInitialized
        }

        struct UserInsert: Encodable {
            let id: UUID
            let email: String
            let full_name: String?
            let enrollment_status: String
        }

        let insert = UserInsert(
            id: UUID(uuidString: user.id)!,
            email: user.email,
            full_name: user.firstName.isEmpty ? nil : user.firstName,
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

    func updateUserProfile(fullName: String? = nil, enrollmentStatus: User.EnrollmentStatus? = nil) async throws {
        guard let client = client else {
            throw SupabaseError.clientNotInitialized
        }

        guard let userId = currentUser?.id else {
            throw SupabaseError.authenticationError(NSError(domain: "SupabaseClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No current user"]))
        }

        var updates: [String: Any] = [:]

        if let name = fullName {
            updates["full_name"] = name
        }

        if let status = enrollmentStatus {
            updates["enrollment_status"] = status.rawValue
            if status == .completed {
                updates["enrollment_completed_at"] = ISO8601DateFormatter().string(from: Date())
            }
        }

        guard !updates.isEmpty else { return }

        do {
            try await client.database
                .from("users")
                .update(updates)
                .eq("id", value: userId)
                .execute()

            // Reload user profile
            let updatedUser = try await loadUserProfile(UUID(uuidString: userId)!)

            await MainActor.run {
                self.currentUser = updatedUser
            }

            print("✅ User profile updated")

        } catch {
            print("❌ Failed to update user profile: \(error)")
            throw SupabaseError.dataError(error.localizedDescription)
        }
    }

    // MARK: - Device Management

    func getDevices() async throws -> [Device] {
        guard let client = client else {
            throw SupabaseError.clientNotInitialized
        }

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
                    id: row.id.uuidString,
                    userId: row.user_id.uuidString,
                    name: row.device_name,
                    type: Device.SupabaseDeviceType(rawValue: row.device_type) ?? .other,
                    status: Device.DeviceStatus(rawValue: row.status) ?? .inactive,
                    lastSyncDate: row.last_sync_date.flatMap { ISO8601DateFormatter().date(from: $0) }
                )
            }

            return devices

        } catch {
            print("❌ Failed to load devices: \(error)")
            throw SupabaseError.dataError(error.localizedDescription)
        }
    }

    func addDevice(name: String, type: Device.SupabaseDeviceType, deviceIdentifier: String) async throws -> Device {
        guard let client = client else {
            throw SupabaseError.clientNotInitialized
        }

        guard let userId = currentUser?.id else {
            throw SupabaseError.authenticationError(NSError(domain: "SupabaseClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No current user"]))
        }

        struct DeviceInsert: Encodable {
            let user_id: UUID
            let device_identifier: String
            let device_name: String
            let device_type: String
            let status: String
        }

        let insert = DeviceInsert(
            user_id: UUID(uuidString: userId)!,
            device_identifier: deviceIdentifier,
            device_name: name,
            device_type: type.rawValue,
            status: "pending"
        )

        do {
            struct DeviceRow: Decodable {
                let id: UUID
                let user_id: UUID
                let device_name: String
                let device_type: String
                let status: String
            }

            let response: DeviceRow = try await client.database
                .from("devices")
                .insert(insert)
                .select()
                .single()
                .execute()
                .value

            let device = Device(
                id: response.id.uuidString,
                userId: response.user_id.uuidString,
                name: response.device_name,
                type: Device.SupabaseDeviceType(rawValue: response.device_type) ?? .other,
                status: Device.DeviceStatus(rawValue: response.status) ?? .pending,
                lastSyncDate: nil
            )

            print("✅ Device added: \(name)")
            return device

        } catch {
            print("❌ Failed to add device: \(error)")
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
        guard let client = client else {
            throw SupabaseError.clientNotInitialized
        }

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
        guard let client = client else {
            throw SupabaseError.clientNotInitialized
        }

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
                    id: row.id.uuidString,
                    userId: row.user_id.uuidString,
                    deviceId: row.device_id?.uuidString ?? "unknown",
                    eventType: AuthEvent.EventType(rawValue: row.event_type) ?? .authentication,
                    success: row.success,
                    failureReason: row.failure_reason,
                    timestamp: ISO8601DateFormatter().date(from: row.timestamp) ?? Date(),
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
        guard let client = client else {
            throw SupabaseError.clientNotInitialized
        }

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

            // Update user enrollment status
            try await updateUserProfile(enrollmentStatus: .completed)

            print("✅ Biometric template saved securely")

        } catch {
            print("❌ Failed to save biometric template: \(error)")
            throw SupabaseError.dataError(error.localizedDescription)
        }
    }

    // MARK: - Biometric Template Cloud Storage Integration

    /// Save a complete BiometricTemplate to Supabase with client-side encryption
    /// Template is encrypted before being sent to the cloud
    func syncBiometricTemplate(_ template: BiometricTemplate) async throws {
        // Encode template to JSON
        let encoder = JSONEncoder()
        let templateData = try encoder.encode(template)

        // Encrypt template data (AES-256-GCM)
        let encryptionService = EncryptionService.shared
        let encryptedData = try encryptionService.encrypt(templateData)

        // Save to Supabase
        try await saveBiometricTemplate(
            encryptedData,
            qualityScore: template.qualityScore,
            sampleCount: template.sampleCount
        )

        print("✅ BiometricTemplate synced to Supabase cloud storage (encrypted)")
    }

    /// Load biometric template from Supabase cloud storage
    /// Returns decrypted template or throws if not found
    func loadBiometricTemplate() async throws -> BiometricTemplate {
        guard let client = client else {
            throw SupabaseError.clientNotInitialized
        }

        guard let userId = currentUser?.id else {
            throw SupabaseError.authenticationError(NSError(domain: "SupabaseClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No current user"]))
        }

        struct TemplateResponse: Decodable {
            let id: UUID
            let user_id: UUID
            let template_data: Data
            let quality_score: Double
            let created_at: Date
            let updated_at: Date
        }

        do {
            let response: [TemplateResponse] = try await client.database
                .from("biometric_templates")
                .select()
                .eq("user_id", value: userId)
                .is("deleted_at", value: "null")
                .limit(1)
                .execute()
                .value

            guard let templateRow = response.first else {
                throw SupabaseError.dataError("No biometric template found")
            }

            // Decrypt template data
            let encryptionService = EncryptionService.shared
            let decryptedData = try encryptionService.decrypt(templateRow.template_data)

            // Decode template
            let decoder = JSONDecoder()
            let template = try decoder.decode(BiometricTemplate.self, from: decryptedData)

            print("✅ BiometricTemplate loaded from Supabase cloud storage (decrypted)")
            return template

        } catch {
            print("❌ Failed to load biometric template: \(error)")
            throw SupabaseError.dataError(error.localizedDescription)
        }
    }

    /// Delete biometric template from cloud storage
    /// Soft deletes by setting deleted_at timestamp
    func deleteBiometricTemplate() async throws {
        guard let client = client else {
            throw SupabaseError.clientNotInitialized
        }

        guard let userId = currentUser?.id else {
            throw SupabaseError.authenticationError(NSError(domain: "SupabaseClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No current user"]))
        }

        do {
            // Soft delete by updating deleted_at timestamp
            try await client.database
                .from("biometric_templates")
                .update(["deleted_at": Date().ISO8601Format()])
                .eq("user_id", value: userId)
                .is("deleted_at", value: "null")
                .execute()

            // Update user enrollment status
            try await updateUserProfile(enrollmentStatus: .revoked)

            print("✅ Biometric template deleted from cloud storage")

        } catch {
            print("❌ Failed to delete biometric template: \(error)")
            throw SupabaseError.dataError(error.localizedDescription)
        }
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
