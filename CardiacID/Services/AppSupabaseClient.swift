// AppSupabaseClient.swift
// CardiacID
//
// Real Supabase integration for authentication and data persistence.
// Uses Supabase Auth REST API and PostgREST directly via URLSession,
// working alongside the Supabase Swift SDK modules already linked
// (Auth, PostgREST, Functions, Realtime, Storage).
//
// Connection details are sourced from SupabaseConfiguration.swift.
// All API keys used here are publishable/anon — safe for client-side use.
// The service role key never appears in this file.

import Foundation
import Combine
import UIKit

// MARK: - Private Supabase Response Models

private struct SupabaseSession: Decodable {
    let accessToken:  String
    let tokenType:    String
    let expiresIn:    Int
    let refreshToken: String
    let user:         SupabaseAuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case tokenType    = "token_type"
        case expiresIn    = "expires_in"
        case refreshToken = "refresh_token"
        case user
    }
}

private struct SupabaseAuthUser: Decodable {
    let id:           String
    let email:        String?
    let userMetadata: SupabaseUserMeta?

    struct SupabaseUserMeta: Decodable {
        let firstName: String?
        let lastName:  String?
        let fullName:  String?

        enum CodingKeys: String, CodingKey {
            case firstName = "first_name"
            case lastName  = "last_name"
            case fullName  = "full_name"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case userMetadata = "user_metadata"
    }
}

private struct DBAuthEventRow: Decodable {
    let id:                   String
    let userId:               String?
    let eventType:            String
    let authenticationMethod: String
    let success:              Bool
    let confidenceScore:      Double?
    let failureReason:        String?
    let createdAt:            String

    enum CodingKeys: String, CodingKey {
        case id
        case userId               = "user_id"
        case eventType            = "event_type"
        case authenticationMethod = "authentication_method"
        case success
        case confidenceScore      = "confidence_score"
        case failureReason        = "failure_reason"
        case createdAt            = "created_at"
    }
}

// MARK: - AppSupabaseClient

final class AppSupabaseClient: ObservableObject {
    static let shared = AppSupabaseClient()

    // MARK: - Published State

    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var currentUser: User? = nil

    // MARK: - Private Session State

    private var accessToken: String?
    private var refreshToken: String?

    // MARK: - Init

    private init() {
        // Ensure Supabase credentials are in Keychain before any call goes out
        SupabaseConfiguration.bootstrap()
    }

    // MARK: - URL / Header Helpers

    // Supabase REST/Auth endpoints require the JWT anon key as the `apikey` header.
    // The publishableKey (sb_publishable_*) is for the JS SDK only; raw HTTP calls must use the JWT.
    private var apiKey: String { SupabaseConfiguration.anonKey }

    private func authHeaders(useUserToken: Bool = true) -> [String: String] {
        var headers: [String: String] = [
            "apikey":       apiKey,
            "Content-Type": "application/json",
        ]
        if useUserToken, let token = accessToken {
            headers["Authorization"] = "Bearer \(token)"
        } else {
            headers["Authorization"] = "Bearer \(apiKey)"
        }
        return headers
    }

    private func postgrestURL(_ table: String, query: String = "") -> URL? {
        let base = "\(SupabaseConfiguration.restURL)/\(table)"
        return URL(string: query.isEmpty ? base : "\(base)?\(query)")
    }

    // MARK: - Sign In

    func signIn(email: String, password: String) -> AnyPublisher<Void, APIError> {
        Future<Void, APIError> { promise in
            Task {
                do {
                    guard let url = URL(string: "\(SupabaseConfiguration.authURL)/token?grant_type=password") else {
                        return promise(.failure(.invalidURL))
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue(self.apiKey,           forHTTPHeaderField: "apikey")
                    request.setValue("application/json",    forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: [
                        "email": email, "password": password
                    ])

                    let (data, response) = try await URLSession.shared.data(for: request)
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200...299).contains(statusCode) else {
                        let msg = Self.extractErrorMessage(from: data) ?? "Sign in failed"
                        return promise(.failure(.serverError(statusCode, msg)))
                    }

                    let session = try JSONDecoder().decode(SupabaseSession.self, from: data)
                    await MainActor.run { self.applySession(session, email: email) }
                    promise(.success(()))
                } catch let e as APIError { promise(.failure(e))
                } catch { promise(.failure(.networkError(error))) }
            }
        }.eraseToAnyPublisher()
    }

    // MARK: - Sign Up

    func signUp(email: String, password: String, name: String) -> AnyPublisher<User, APIError> {
        Future<User, APIError> { promise in
            Task {
                do {
                    let parts     = name.split(separator: " ", maxSplits: 1)
                    let firstName = parts.first.map(String.init)
                    let lastName  = parts.count > 1 ? String(parts[1]) : nil

                    guard let url = URL(string: "\(SupabaseConfiguration.authURL)/signup") else {
                        return promise(.failure(.invalidURL))
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue(self.apiKey,           forHTTPHeaderField: "apikey")
                    request.setValue("application/json",    forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: [
                        "email":    email,
                        "password": password,
                        "data": [
                            "first_name": firstName as Any,
                            "last_name":  lastName  as Any,
                            "full_name":  name
                        ]
                    ])

                    let (data, response) = try await URLSession.shared.data(for: request)
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200...299).contains(statusCode) else {
                        let msg = Self.extractErrorMessage(from: data) ?? "Sign up failed"
                        return promise(.failure(.serverError(statusCode, msg)))
                    }

                    let session = try JSONDecoder().decode(SupabaseSession.self, from: data)
                    let user = User(
                        id:        session.user.id,
                        email:     session.user.email ?? email,
                        firstName: firstName,
                        lastName:  lastName
                    )
                    await MainActor.run { self.applySession(session, email: email) }
                    promise(.success(user))
                } catch let e as APIError { promise(.failure(e))
                } catch { promise(.failure(.networkError(error))) }
            }
        }.eraseToAnyPublisher()
    }

    // Alias for backward compatibility
    func register(email: String, password: String, name: String) -> AnyPublisher<User, APIError> {
        signUp(email: email, password: password, name: name)
    }

    // MARK: - Sign Out

    func signOut() -> AnyPublisher<Void, APIError> {
        Future<Void, APIError> { promise in
            Task {
                if let token = self.accessToken,
                   let url = URL(string: "\(SupabaseConfiguration.authURL)/logout") {
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue(self.apiKey,     forHTTPHeaderField: "apikey")
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    _ = try? await URLSession.shared.data(for: request)
                }
                await MainActor.run {
                    self.accessToken   = nil
                    self.refreshToken  = nil
                    self.isAuthenticated = false
                    self.currentUser   = nil
                }
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    // MARK: - Profile Update

    func updateUserProfile(name: String, profileImage: UIImage?) -> AnyPublisher<Void, APIError> {
        Future<Void, APIError> { promise in
            Task {
                // Update in-memory user immediately for responsive UI
                let parts     = name.split(separator: " ", maxSplits: 1)
                let firstName = parts.first.map(String.init)
                let lastName  = parts.count > 1 ? String(parts[1]) : nil
                await MainActor.run {
                    if var u = self.currentUser {
                        u.firstName = firstName
                        u.lastName  = lastName
                        self.currentUser = u
                    }
                }

                // Persist to Supabase Auth user metadata
                if let token = self.accessToken,
                   let url = URL(string: "\(SupabaseConfiguration.authURL)/user") {
                    var request = URLRequest(url: url)
                    request.httpMethod = "PUT"
                    request.setValue(self.apiKey,        forHTTPHeaderField: "apikey")
                    request.setValue("Bearer \(token)",  forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try? JSONSerialization.data(withJSONObject: [
                        "data": ["first_name": firstName as Any, "last_name": lastName as Any, "full_name": name]
                    ])
                    _ = try? await URLSession.shared.data(for: request)
                }
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    // MARK: - Biometric Template (stub — real implementation via Storage module)

    func syncBiometricTemplate(_ template: BiometricTemplate) async throws {
        // TODO: Upload encrypted template blob to Supabase Storage
        // supabase.storage.from("biometric-templates").upload(...)
    }

    func loadBiometricTemplate() async throws -> BiometricTemplate {
        throw StorageError.notFound
    }

    func deleteBiometricTemplate() async throws {
        // TODO: Delete from Supabase Storage
    }

    // MARK: - Recent Auth Events

    /// Fetches the most recent auth events for the current user from the
    /// `auth_events` table via PostgREST.
    func getRecentAuthEvents(limit: Int = 10) async throws -> [AuthEvent] {
        guard let userId = currentUser?.id,
              let url = postgrestURL("auth_events",
                  query: "select=*&user_id=eq.\(userId)&order=created_at.desc&limit=\(limit)") else {
            return []
        }

        var request = URLRequest(url: url)
        for (k, v) in authHeaders() { request.setValue(v, forHTTPHeaderField: k) }

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(statusCode) else { return [] }

        let rows = try JSONDecoder().decode([DBAuthEventRow].self, from: data)
        return rows.compactMap { Self.mapDBRowToAuthEvent($0) }
    }

    // MARK: - Devices (stub — no Device model yet)

    func getDevices() async throws -> [Device] { [] }

    // MARK: - Auth Event Logging

    /// Logs an authentication event to the `auth_events` Supabase table.
    /// Uses the user's JWT for the Authorization header so RLS row-level
    /// ownership checks pass. Falls back to anon-level if not signed in.
    func logAuthEvent(
        eventType: String,
        method: String,
        success: Bool,
        confidence: Double?,
        failureReason: String?,
        metadata: [String: Any]?
    ) async throws {
        var body: [String: Any] = [
            "event_type":            eventType,
            "authentication_method": method,
            "success":               success,
            "created_at":            ISO8601DateFormatter().string(from: Date()),
        ]
        if let userId    = currentUser?.id    { body["user_id"]         = userId }
        if let conf      = confidence          { body["confidence_score"] = conf }
        if let reason    = failureReason       { body["failure_reason"]  = reason }
        if let meta      = metadata,
           let metaJSON  = try? JSONSerialization.data(withJSONObject: meta),
           let metaObj   = try? JSONSerialization.jsonObject(with: metaJSON) {
            body["metadata"] = metaObj
        }

        guard let url = postgrestURL("auth_events") else { return }

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        var request  = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody   = bodyData
        for (k, v) in authHeaders(useUserToken: true) { request.setValue(v, forHTTPHeaderField: k) }
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        let (_, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(statusCode) else {
            throw APIError.serverError(statusCode, "auth_events insert failed")
        }
        print("AuthEvent persisted: [\(eventType)] \(method) success:\(success)")
    }

    // MARK: - Private Helpers

    @MainActor
    private func applySession(_ session: SupabaseSession, email: String) {
        accessToken   = session.accessToken
        refreshToken  = session.refreshToken
        isAuthenticated = true
        currentUser = User(
            id:        session.user.id,
            email:     session.user.email ?? email,
            firstName: session.user.userMetadata?.firstName,
            lastName:  session.user.userMetadata?.lastName
        )
    }

    private static func mapDBRowToAuthEvent(_ row: DBAuthEventRow) -> AuthEvent? {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.date(from: row.createdAt) ?? Date()
        let eventType: AuthEvent.EventType = AuthEvent.EventType(rawValue: row.eventType)
                                          ?? .authentication
        return AuthEvent(
            id:        row.id,
            userId:    row.userId ?? "",
            eventType: eventType,
            timestamp: timestamp,
            success:   row.success
        )
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["msg"] as? String ?? json["message"] as? String ?? json["error_description"] as? String
    }
}

// MARK: - Type Aliases for Compatibility

typealias AppSupabaseClientLocal = AppSupabaseClient
typealias SupabaseService        = AppSupabaseClient
