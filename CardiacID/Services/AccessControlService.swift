//
//  AccessControlService.swift
//  CardiacID
//
//  Maps EntraID group memberships to door/resource access permissions
//  Caches permissions locally for offline operation
//  Integrates with BluetoothDoorLockService for BLE door access control
//

import Foundation
import Combine

/// Enterprise access control service that maps EntraID groups to physical/logical access permissions
/// Syncs from Microsoft Graph API and caches locally for offline door unlock authorization
@MainActor
class AccessControlService: ObservableObject {
    static let shared = AccessControlService()

    // MARK: - Published State

    @Published private(set) var doorPermissions: [DoorPermission] = []
    @Published private(set) var computerPermissions: [ComputerPermission] = []
    @Published private(set) var filePermissions: [FilePermission] = []
    @Published private(set) var lastSyncTime: Date?
    @Published private(set) var isSyncing: Bool = false
    @Published private(set) var syncError: String?

    // MARK: - Cache Keys

    private let doorCacheKey = "access_control_doors"
    private let computerCacheKey = "access_control_computers"
    private let fileCacheKey = "access_control_files"
    private let syncTimestampKey = "access_control_last_sync"

    // MARK: - Models

    struct DoorPermission: Codable, Identifiable, Equatable {
        let id: String
        let name: String
        let groupId: String
        let groupName: String
        let accessLevel: AccessLevel
        let location: String?
        let requiresHeartID: Bool
        let minimumConfidence: Double
    }

    struct ComputerPermission: Codable, Identifiable, Equatable {
        let id: String
        let resourceName: String
        let groupId: String
        let groupName: String
        let accessLevel: AccessLevel
        let requiresFIDO2: Bool
    }

    struct FilePermission: Codable, Identifiable, Equatable {
        let id: String
        let resourceName: String
        let groupId: String
        let groupName: String
        let accessLevel: AccessLevel
    }

    enum AccessLevel: String, Codable, Comparable {
        case none = "none"
        case viewer = "viewer"
        case user = "user"
        case admin = "admin"

        static func < (lhs: AccessLevel, rhs: AccessLevel) -> Bool {
            let order: [AccessLevel] = [.none, .viewer, .user, .admin]
            return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
        }
    }

    struct AccessDecision {
        let granted: Bool
        let permission: DoorPermission?
        let reason: String
        let requiresStepUp: Bool
    }

    // MARK: - Initialization

    private init() {
        loadCachedPermissions()
    }

    // MARK: - Permission Sync from EntraID

    /// Sync group memberships from Microsoft Graph API and map to access permissions.
    /// Uses the `access_control_config` Supabase table for group→resource mapping
    /// when available; falls back to keyword heuristics for unmatched groups.
    func syncPermissions() async throws {
        isSyncing = true
        syncError = nil

        defer { isSyncing = false }

        do {
            let token = try await EntraIDAuthClient.shared.getAccessToken()
            let graphClient = MicrosoftGraphClient(accessToken: token)
            let groups = try await graphClient.getUserGroups()

            // Attempt to load explicit mapping config from Supabase
            let configEntries = await loadPermissionConfig()

            if configEntries.isEmpty {
                // No config table data — fall back to keyword heuristics
                print("AccessControl: No Supabase config found, using keyword heuristics")
                doorPermissions     = mapGroupsToDoorPermissions(groups, config: [])
                computerPermissions = mapGroupsToComputerPermissions(groups, config: [])
                filePermissions     = mapGroupsToFilePermissions(groups, config: [])
            } else {
                doorPermissions     = mapGroupsToDoorPermissions(groups, config: configEntries)
                computerPermissions = mapGroupsToComputerPermissions(groups, config: configEntries)
                filePermissions     = mapGroupsToFilePermissions(groups, config: configEntries)
            }

            lastSyncTime = Date()
            cachePermissions()

            print("AccessControl: Synced \(doorPermissions.count) door, \(computerPermissions.count) computer, \(filePermissions.count) file permissions")
        } catch {
            syncError = error.localizedDescription
            print("AccessControl: Sync failed - \(error)")
            throw error
        }
    }

    // MARK: - Supabase Config Fetch

    /// Row shape from the access_control_config Supabase table
    private struct ACConfigEntry: Decodable {
        let groupId: String?
        let groupPrefix: String?
        let resourceType: String   // "door" | "computer" | "file"
        let resourceName: String
        let accessLevel: String
        let requiresHeartid: Bool
        let minimumConfidence: Double
        let location: String?
        let requiresFido2: Bool

        enum CodingKeys: String, CodingKey {
            case groupId = "group_id"
            case groupPrefix = "group_prefix"
            case resourceType = "resource_type"
            case resourceName = "resource_name"
            case accessLevel = "access_level"
            case requiresHeartid = "requires_heartid"
            case minimumConfidence = "minimum_confidence"
            case location
            case requiresFido2 = "requires_fido2"
        }
    }

    private func loadPermissionConfig() async -> [ACConfigEntry] {
        guard let urlString = try? SecureCredentialManager.shared.retrieve(forKey: .supabaseURL),
              let apiKey    = try? SecureCredentialManager.shared.retrieve(forKey: .supabaseAPIKey),
              let url       = URL(string: "\(urlString)/rest/v1/access_control_config?select=*") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey,             forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            return try JSONDecoder().decode([ACConfigEntry].self, from: data)
        } catch {
            print("AccessControl: Failed to load Supabase config: \(error)")
            return []
        }
    }

    // MARK: - Access Checks

    /// Check if user has access to a specific door/resource
    func hasAccess(to resourceId: String) -> Bool {
        return doorPermissions.contains { $0.id == resourceId && $0.accessLevel != .none }
    }

    /// Check access with HeartID confidence gating
    func checkDoorAccess(doorId: String, heartIDConfidence: Double) -> AccessDecision {
        guard let permission = doorPermissions.first(where: { $0.id == doorId }) else {
            return AccessDecision(granted: false, permission: nil,
                                  reason: "No permission for this door", requiresStepUp: false)
        }

        guard permission.accessLevel != .none else {
            return AccessDecision(granted: false, permission: permission,
                                  reason: "Access level is none", requiresStepUp: false)
        }

        if permission.requiresHeartID {
            guard heartIDConfidence >= permission.minimumConfidence else {
                return AccessDecision(granted: false, permission: permission,
                                      reason: "HeartID confidence \(Int(heartIDConfidence * 100))% below required \(Int(permission.minimumConfidence * 100))%",
                                      requiresStepUp: true)
            }
        }

        return AccessDecision(granted: true, permission: permission,
                              reason: "Access granted via group \(permission.groupName)",
                              requiresStepUp: false)
    }

    /// Check computer access permission
    func hasComputerAccess(to resourceId: String) -> Bool {
        return computerPermissions.contains { $0.id == resourceId && $0.accessLevel != .none }
    }

    /// Check file access permission
    func hasFileAccess(to resourceId: String) -> Bool {
        return filePermissions.contains { $0.id == resourceId && $0.accessLevel != .none }
    }

    /// Get the highest access level for a resource across all group memberships
    func highestAccessLevel(for resourceId: String) -> AccessLevel {
        let doorLevel = doorPermissions
            .filter { $0.id == resourceId }
            .map { $0.accessLevel }
            .max() ?? .none

        let computerLevel = computerPermissions
            .filter { $0.id == resourceId }
            .map { $0.accessLevel }
            .max() ?? .none

        let fileLevel = filePermissions
            .filter { $0.id == resourceId }
            .map { $0.accessLevel }
            .max() ?? .none

        return max(doorLevel, max(computerLevel, fileLevel))
    }

    // MARK: - Group-to-Permission Mapping

    /// Returns the best-matching config entry for a group: exact group_id match first,
    /// then group_prefix (display name starts-with), then nil (triggers heuristic fallback).
    private func configEntry(for group: GraphGroup, type: String, config: [ACConfigEntry]) -> ACConfigEntry? {
        let name = group.displayName?.lowercased() ?? ""
        // 1. Exact group ID match
        if let exact = config.first(where: { $0.groupId == group.id && $0.resourceType == type }) {
            return exact
        }
        // 2. Display-name prefix match (case-insensitive)
        return config.first(where: {
            $0.resourceType == type &&
            $0.groupPrefix != nil &&
            name.hasPrefix($0.groupPrefix!.lowercased())
        })
    }

    private func mapGroupsToDoorPermissions(_ groups: [GraphGroup], config: [ACConfigEntry]) -> [DoorPermission] {
        return groups.compactMap { group in
            let groupName = group.displayName?.lowercased() ?? ""

            if let entry = configEntry(for: group, type: "door", config: config) {
                // Config-driven mapping — precise and deployment-specific
                return DoorPermission(
                    id: group.id,
                    name: entry.resourceName,
                    groupId: group.id,
                    groupName: group.displayName ?? "Unknown",
                    accessLevel: AccessLevel(rawValue: entry.accessLevel) ?? .user,
                    location: entry.location,
                    requiresHeartID: entry.requiresHeartid,
                    minimumConfidence: entry.minimumConfidence
                )
            }

            // Keyword heuristic fallback (used when no Supabase config exists)
            guard groupName.contains("access") || groupName.contains("door") ||
                  groupName.contains("building") || groupName.contains("facility") else { return nil }
            let isHighSecurity = groupName.contains("secure") || groupName.contains("restricted")
            return DoorPermission(
                id: group.id,
                name: group.displayName ?? "Unknown",
                groupId: group.id,
                groupName: group.displayName ?? "Unknown",
                accessLevel: isHighSecurity ? .admin : .user,
                location: nil,
                requiresHeartID: isHighSecurity,
                minimumConfidence: isHighSecurity ? 0.85 : 0.70
            )
        }
    }

    private func mapGroupsToComputerPermissions(_ groups: [GraphGroup], config: [ACConfigEntry]) -> [ComputerPermission] {
        return groups.compactMap { group in
            let groupName = group.displayName?.lowercased() ?? ""

            if let entry = configEntry(for: group, type: "computer", config: config) {
                return ComputerPermission(
                    id: group.id,
                    resourceName: entry.resourceName,
                    groupId: group.id,
                    groupName: group.displayName ?? "Unknown",
                    accessLevel: AccessLevel(rawValue: entry.accessLevel) ?? .user,
                    requiresFIDO2: entry.requiresFido2
                )
            }

            guard groupName.contains("computer") || groupName.contains("workstation") ||
                  groupName.contains("device") || groupName.contains("desktop") else { return nil }
            return ComputerPermission(
                id: group.id,
                resourceName: group.displayName ?? "Unknown",
                groupId: group.id,
                groupName: group.displayName ?? "Unknown",
                accessLevel: .user,
                requiresFIDO2: groupName.contains("secure")
            )
        }
    }

    private func mapGroupsToFilePermissions(_ groups: [GraphGroup], config: [ACConfigEntry]) -> [FilePermission] {
        return groups.compactMap { group in
            let groupName = group.displayName?.lowercased() ?? ""

            if let entry = configEntry(for: group, type: "file", config: config) {
                return FilePermission(
                    id: group.id,
                    resourceName: entry.resourceName,
                    groupId: group.id,
                    groupName: group.displayName ?? "Unknown",
                    accessLevel: AccessLevel(rawValue: entry.accessLevel) ?? .user
                )
            }

            guard groupName.contains("file") || groupName.contains("share") ||
                  groupName.contains("document") || groupName.contains("data") else { return nil }
            return FilePermission(
                id: group.id,
                resourceName: group.displayName ?? "Unknown",
                groupId: group.id,
                groupName: group.displayName ?? "Unknown",
                accessLevel: .user
            )
        }
    }

    // MARK: - Caching

    private func cachePermissions() {
        if let encoded = try? JSONEncoder().encode(doorPermissions) {
            UserDefaults.standard.set(encoded, forKey: doorCacheKey)
        }
        if let encoded = try? JSONEncoder().encode(computerPermissions) {
            UserDefaults.standard.set(encoded, forKey: computerCacheKey)
        }
        if let encoded = try? JSONEncoder().encode(filePermissions) {
            UserDefaults.standard.set(encoded, forKey: fileCacheKey)
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: syncTimestampKey)
    }

    func loadCachedPermissions() {
        if let data = UserDefaults.standard.data(forKey: doorCacheKey),
           let decoded = try? JSONDecoder().decode([DoorPermission].self, from: data) {
            doorPermissions = decoded
        }
        if let data = UserDefaults.standard.data(forKey: computerCacheKey),
           let decoded = try? JSONDecoder().decode([ComputerPermission].self, from: data) {
            computerPermissions = decoded
        }
        if let data = UserDefaults.standard.data(forKey: fileCacheKey),
           let decoded = try? JSONDecoder().decode([FilePermission].self, from: data) {
            filePermissions = decoded
        }
        if let timestamp = UserDefaults.standard.object(forKey: syncTimestampKey) as? TimeInterval {
            lastSyncTime = Date(timeIntervalSince1970: timestamp)
        }
    }

    /// Check if cached permissions are stale (older than 1 hour)
    var isCacheStale: Bool {
        guard let lastSync = lastSyncTime else { return true }
        return Date().timeIntervalSince(lastSync) > 3600
    }

    /// Clear all cached permissions
    func clearCache() {
        doorPermissions = []
        computerPermissions = []
        filePermissions = []
        lastSyncTime = nil
        UserDefaults.standard.removeObject(forKey: doorCacheKey)
        UserDefaults.standard.removeObject(forKey: computerCacheKey)
        UserDefaults.standard.removeObject(forKey: fileCacheKey)
        UserDefaults.standard.removeObject(forKey: syncTimestampKey)
    }
}
