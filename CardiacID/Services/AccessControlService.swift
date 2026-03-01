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

    /// Sync group memberships from Microsoft Graph API and map to access permissions
    func syncPermissions() async throws {
        isSyncing = true
        syncError = nil

        defer { isSyncing = false }

        do {
            let token = try await EntraIDAuthClient.shared.getAccessToken()
            let graphClient = MicrosoftGraphClient(accessToken: token)
            let groups = try await graphClient.getUserGroups()

            // Map groups to permission types
            doorPermissions = mapGroupsToDoorPermissions(groups)
            computerPermissions = mapGroupsToComputerPermissions(groups)
            filePermissions = mapGroupsToFilePermissions(groups)
            lastSyncTime = Date()

            // Cache for offline use
            cachePermissions()

            print("AccessControl: Synced \(doorPermissions.count) door, \(computerPermissions.count) computer, \(filePermissions.count) file permissions")
        } catch {
            syncError = error.localizedDescription
            print("AccessControl: Sync failed - \(error)")
            throw error
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

    private func mapGroupsToDoorPermissions(_ groups: [GraphGroup]) -> [DoorPermission] {
        return groups.compactMap { group in
            guard let groupName = group.displayName?.lowercased() else { return nil }

            // Map groups containing access-related keywords to door permissions
            // In production, this mapping would come from a configuration endpoint or Supabase table
            if groupName.contains("access") || groupName.contains("door") ||
               groupName.contains("building") || groupName.contains("facility") {
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
            return nil
        }
    }

    private func mapGroupsToComputerPermissions(_ groups: [GraphGroup]) -> [ComputerPermission] {
        return groups.compactMap { group in
            guard let groupName = group.displayName?.lowercased() else { return nil }

            if groupName.contains("computer") || groupName.contains("workstation") ||
               groupName.contains("device") || groupName.contains("desktop") {
                return ComputerPermission(
                    id: group.id,
                    resourceName: group.displayName ?? "Unknown",
                    groupId: group.id,
                    groupName: group.displayName ?? "Unknown",
                    accessLevel: .user,
                    requiresFIDO2: groupName.contains("secure")
                )
            }
            return nil
        }
    }

    private func mapGroupsToFilePermissions(_ groups: [GraphGroup]) -> [FilePermission] {
        return groups.compactMap { group in
            guard let groupName = group.displayName?.lowercased() else { return nil }

            if groupName.contains("file") || groupName.contains("share") ||
               groupName.contains("document") || groupName.contains("data") {
                return FilePermission(
                    id: group.id,
                    resourceName: group.displayName ?? "Unknown",
                    groupId: group.id,
                    groupName: group.displayName ?? "Unknown",
                    accessLevel: .user
                )
            }
            return nil
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
