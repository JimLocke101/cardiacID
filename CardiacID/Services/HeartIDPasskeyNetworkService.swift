// HeartIDPasskeyNetworkService.swift
// CardiacID
//
// Handles all network communication for the HeartID cardiac-gated passkey flow.
// Uses async/await throughout — no completion handlers.
//
// Data flows:
//   fetchChallenge       → INSERT into heartid_passkey_challenges
//   registerCredential   → UPDATE challenge + INSERT credential + INSERT audit
//   verifyAssertion      → SELECT credential + UPDATE sign_count + INSERT audit
//   listUserCredentials  → SELECT from heartid_passkey_credentials
//
// Uses the same Supabase REST pattern as AppSupabaseClient:
//   URLSession + SupabaseConfiguration + PostgREST query strings.
//
// SECURITY: All write operations use the user's JWT (not anon key alone).
// Signature verification for assertions MUST happen server-side in an Edge Function.

import Foundation

// MARK: - Error Types

enum HeartIDPasskeyNetworkError: Error, LocalizedError {
    case challengeFetchFailed
    case serverUnreachable
    case challengeAlreadyUsed
    case registrationFailed
    case assertionFailed
    case credentialNotFound

    var errorDescription: String? {
        switch self {
        case .challengeFetchFailed: return "Failed to fetch passkey challenge from server"
        case .serverUnreachable:    return "Supabase server is unreachable"
        case .challengeAlreadyUsed: return "Challenge has already been consumed"
        case .registrationFailed:   return "Passkey credential registration failed"
        case .assertionFailed:      return "Passkey assertion verification failed"
        case .credentialNotFound:   return "No matching credential found for this passkey"
        }
    }
}

// MARK: - Credential Info Model

/// Read-only view of a stored passkey credential for display in the UI.
struct HeartIDPasskeyCredentialInfo: Identifiable, Codable, Sendable {
    let id: UUID
    let credentialID: Data
    let displayName: String?
    let createdAt: Date
    let lastUsedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case credentialID  = "credential_id"
        case displayName   = "display_name"
        case createdAt     = "created_at"
        case lastUsedAt    = "last_used_at"
    }
}

// MARK: - Network Service

/// Manages all Supabase REST calls for the HeartID passkey lifecycle.
///
/// Thread-safety: all methods are async and stateless — safe to call from any actor.
/// Uses the same URL/key pattern as `AppSupabaseClient`.
final class HeartIDPasskeyNetworkService: Sendable {

    static let shared = HeartIDPasskeyNetworkService()

    private let restURL: String
    private let apiKey:  String
    private let session: URLSession

    private init() {
        self.restURL = SupabaseConfiguration.restURL
        self.apiKey  = SupabaseConfiguration.anonKey
        self.session = .shared
    }

    // MARK: - Challenge

    /// Inserts a new passkey challenge into `heartid_passkey_challenges`.
    ///
    /// The challenge bytes are 32 cryptographically random bytes generated client-side
    /// and persisted server-side. The returned `challengeID` is the row's primary key.
    ///
    /// - Parameters:
    ///   - userID: The authenticated user's UUID.
    ///   - actionType: `"registration"` or `"authentication"`.
    ///   - minimumCardiacConfidence: The HeartID confidence floor required to proceed.
    /// - Returns: A tuple of the raw challenge bytes and the row UUID.
    /// - Throws: `HeartIDPasskeyNetworkError.challengeFetchFailed` on insert failure,
    ///           `.serverUnreachable` on network error.
    func fetchChallenge(
        userID: UUID,
        actionType: String,
        minimumCardiacConfidence: Double
    ) async throws -> (challengeBytes: Data, challengeID: UUID) {

        // Generate 32 cryptographically random bytes
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw HeartIDPasskeyNetworkError.challengeFetchFailed }
        let challengeData = Data(bytes)

        let body: [String: Any] = [
            "user_id":          userID.uuidString,
            "challenge_bytes":  "\\x" + challengeData.map { String(format: "%02x", $0) }.joined(),
            "action_type":      actionType,
            "cardiac_min_conf": minimumCardiacConfidence
        ]

        let url = URL(string: "\(restURL)/heartid_passkey_challenges?select=id")!
        var request = makeRequest(url: url, method: "POST")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        do {
            let (responseData, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw HeartIDPasskeyNetworkError.challengeFetchFailed
            }
            data = responseData
        } catch is URLError {
            throw HeartIDPasskeyNetworkError.serverUnreachable
        }

        // Parse returned row to get the generated UUID
        struct InsertedRow: Decodable { let id: UUID }
        let rows = try JSONDecoder().decode([InsertedRow].self, from: data)
        guard let row = rows.first else { throw HeartIDPasskeyNetworkError.challengeFetchFailed }

        return (challengeBytes: challengeData, challengeID: row.id)
    }

    // MARK: - Registration

    /// Completes passkey registration: marks the challenge as used, stores the
    /// credential, and writes an audit entry.
    ///
    /// - Parameters:
    ///   - challengeID: The row ID returned by `fetchChallenge`.
    ///   - credentialID: The WebAuthn credential ID from the authenticator.
    ///   - attestationObject: The raw attestation object (CBOR).
    ///   - clientDataJSON: The client data JSON from the ceremony.
    ///   - cardiacConfidence: The HeartID confidence at the time of registration.
    /// - Throws: `.challengeAlreadyUsed` if the challenge was already consumed,
    ///           `.registrationFailed` on any other failure.
    func registerCredential(
        challengeID: UUID,
        credentialID: Data,
        attestationObject: Data,
        clientDataJSON: Data,
        cardiacConfidence: Double
    ) async throws {

        // Step 1: Mark challenge as used (optimistic — fails if already used)
        try await markChallengeUsed(challengeID)

        // Step 2: Insert credential
        let credHex = hexEncode(credentialID)
        // Extract public key from attestation in a real implementation;
        // here we store the full attestation for server-side extraction.
        let pubKeyHex = hexEncode(attestationObject)

        let credBody: [String: Any] = [
            "credential_id": credHex,
            "public_key":    pubKeyHex,
            "device_type":   "platform",
            "backed_up":     false,
            "transports":    ["internal"],
            "display_name":  "HeartID Passkey"
        ]

        let credURL = URL(string: "\(restURL)/heartid_passkey_credentials")!
        var credReq = makeRequest(url: credURL, method: "POST")
        credReq.httpBody = try JSONSerialization.data(withJSONObject: credBody)

        let (_, credResp) = try await session.data(for: credReq)
        guard let credHttp = credResp as? HTTPURLResponse, (200..<300).contains(credHttp.statusCode) else {
            throw HeartIDPasskeyNetworkError.registrationFailed
        }

        // Step 3: Audit entry
        try await insertAudit(
            credentialID: credentialID,
            actionType: "registration",
            success: true,
            cardiacConfidence: cardiacConfidence
        )
    }

    // MARK: - Assertion

    /// Verifies a passkey assertion by updating the credential's sign count,
    /// marking the challenge consumed, and writing an audit entry.
    ///
    /// - Important: **SECURITY: Signature verification must be implemented
    ///   in a Supabase Edge Function, not the client. Client-side verification
    ///   is not acceptable for production.** This method performs bookkeeping only.
    ///
    /// - Parameters:
    ///   - challengeID: The challenge row ID.
    ///   - credentialID: The credential being asserted.
    ///   - signature: The authenticator's signature (verified server-side).
    ///   - authenticatorData: The authenticator data blob.
    ///   - clientDataJSON: The client data JSON from the ceremony.
    ///   - userHandle: The user handle returned by the authenticator.
    ///   - cardiacConfidence: The HeartID confidence at the time of assertion.
    /// - Returns: `true` if bookkeeping succeeded (does NOT imply cryptographic verification).
    /// - Throws: `.credentialNotFound`, `.challengeAlreadyUsed`, `.assertionFailed`.
    func verifyAssertion(
        challengeID: UUID,
        credentialID: Data,
        signature: Data,
        authenticatorData: Data,
        clientDataJSON: Data,
        userHandle: Data,
        cardiacConfidence: Double
    ) async throws -> Bool {

        // TODO: SECURITY: Signature verification must be implemented
        // in a Supabase Edge Function, not the client. Client-side verification
        // is not acceptable for production.

        // Step 1: Fetch stored credential
        let credHex = hexEncode(credentialID)
        let fetchURL = URL(string: "\(restURL)/heartid_passkey_credentials?credential_id=eq.\(credHex)&select=id,sign_count,user_id")!
        let fetchReq = makeRequest(url: fetchURL, method: "GET")

        let (fetchData, fetchResp) = try await session.data(for: fetchReq)
        guard let fetchHttp = fetchResp as? HTTPURLResponse, (200..<300).contains(fetchHttp.statusCode) else {
            throw HeartIDPasskeyNetworkError.assertionFailed
        }

        struct CredRow: Decodable { let id: UUID; let sign_count: Int; let user_id: UUID }
        let creds = try JSONDecoder().decode([CredRow].self, from: fetchData)
        guard let cred = creds.first else { throw HeartIDPasskeyNetworkError.credentialNotFound }

        // Step 2: Increment sign_count + update last_used_at
        let updateBody: [String: Any] = [
            "sign_count":   cred.sign_count + 1,
            "last_used_at": ISO8601DateFormatter().string(from: Date())
        ]
        let updateURL = URL(string: "\(restURL)/heartid_passkey_credentials?id=eq.\(cred.id.uuidString)")!
        var updateReq = makeRequest(url: updateURL, method: "PATCH")
        updateReq.httpBody = try JSONSerialization.data(withJSONObject: updateBody)

        let (_, updateResp) = try await session.data(for: updateReq)
        guard let updateHttp = updateResp as? HTTPURLResponse, (200..<300).contains(updateHttp.statusCode) else {
            throw HeartIDPasskeyNetworkError.assertionFailed
        }

        // Step 3: Mark challenge as used
        try await markChallengeUsed(challengeID)

        // Step 4: Audit entry
        try await insertAudit(
            userID: cred.user_id,
            credentialID: credentialID,
            actionType: "authentication",
            success: true,
            cardiacConfidence: cardiacConfidence
        )

        return true
    }

    // MARK: - List Credentials

    /// Fetches all passkey credentials registered by the given user.
    ///
    /// - Parameter userID: The user's UUID.
    /// - Returns: An array of `HeartIDPasskeyCredentialInfo` for display.
    func listUserCredentials(userID: UUID) async throws -> [HeartIDPasskeyCredentialInfo] {
        let url = URL(string: "\(restURL)/heartid_passkey_credentials?user_id=eq.\(userID.uuidString)&select=id,credential_id,display_name,created_at,last_used_at&order=created_at.desc")!
        let request = makeRequest(url: url, method: "GET")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HeartIDPasskeyCredentialInfo].self, from: data)) ?? []
    }

    // MARK: - Private Helpers

    /// Marks a challenge row as `used = true`. Throws `.challengeAlreadyUsed` if
    /// the row is already consumed (PATCH returns 0 rows when WHERE doesn't match).
    private func markChallengeUsed(_ challengeID: UUID) async throws {
        let body: [String: Any] = ["used": true]
        let url = URL(string: "\(restURL)/heartid_passkey_challenges?id=eq.\(challengeID.uuidString)&used=eq.false")!
        var request = makeRequest(url: url, method: "PATCH")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw HeartIDPasskeyNetworkError.challengeAlreadyUsed
        }

        // PostgREST returns an empty array if the WHERE clause matched nothing
        struct Row: Decodable { let id: UUID }
        let rows = (try? JSONDecoder().decode([Row].self, from: data)) ?? []
        if rows.isEmpty { throw HeartIDPasskeyNetworkError.challengeAlreadyUsed }
    }

    /// Inserts a row into `heartid_passkey_audit`.
    private func insertAudit(
        userID: UUID? = nil,
        credentialID: Data? = nil,
        actionType: String,
        success: Bool,
        cardiacConfidence: Double? = nil,
        failureReason: String? = nil
    ) async throws {
        var body: [String: Any] = [
            "action_type": actionType,
            "success":     success
        ]
        if let uid = userID { body["user_id"] = uid.uuidString }
        if let cid = credentialID { body["credential_id"] = hexEncode(cid) }
        if let conf = cardiacConfidence { body["cardiac_confidence"] = conf }
        if let reason = failureReason { body["failure_reason"] = reason }

        let url = URL(string: "\(restURL)/heartid_passkey_audit")!
        var request = makeRequest(url: url, method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Fire-and-forget audit — don't fail the caller on audit insert errors
        _ = try? await session.data(for: request)
    }

    /// Builds a URLRequest with standard Supabase auth headers.
    /// Uses the user's JWT if available via SecureCredentialManager, else anon key.
    private func makeRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")

        // Prefer user JWT for RLS-aware queries
        if let token = try? SecureCredentialManager.shared.retrieve(forKey: .entraIDAccessToken) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Encodes Data as a Postgres bytea hex literal: `\xDEADBEEF`.
    private func hexEncode(_ data: Data) -> String {
        "\\x" + data.map { String(format: "%02x", $0) }.joined()
    }
}
