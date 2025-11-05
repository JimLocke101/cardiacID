//
//  HybridTemplateStorageService.swift
//  CardiacID
//
//  Created for Phase 4 - Biometric Engine Integration
//  Combines local Keychain storage with cloud Supabase sync
//

import Foundation

/// Hybrid storage service that stores templates locally AND syncs to cloud
/// Primary storage: Local Keychain (fast, always available, offline-first)
/// Secondary storage: Supabase cloud (backup, multi-device sync)
class HybridTemplateStorageService {
    private let localStorage = TemplateStorageService()
    private let cloudStorage = SupabaseClient.shared

    // MARK: - Storage Strategy

    /// Save template to both local Keychain and cloud Supabase
    /// Uses offline-first approach: local save always succeeds, cloud sync is async
    func saveTemplate(_ template: BiometricTemplate, syncToCloud: Bool = true) async throws {
        // 1. Save to local Keychain (primary storage, always first)
        try localStorage.saveTemplate(template)
        print("✅ Template saved to local Keychain")

        // 2. Optionally sync to cloud (secondary storage, best-effort)
        if syncToCloud {
            do {
                try await cloudStorage.syncBiometricTemplate(template)
                print("✅ Template synced to Supabase cloud")
            } catch {
                print("⚠️ Cloud sync failed (local save successful): \(error.localizedDescription)")
                // Don't throw - local storage is primary, cloud is secondary
                // User can still authenticate offline with local template
            }
        }
    }

    /// Load template with local-first strategy
    /// 1. Try local Keychain first (fast, offline)
    /// 2. If not found, try cloud Supabase (slower, requires network)
    /// 3. If cloud succeeds, cache locally for future offline use
    func loadTemplate() async throws -> BiometricTemplate {
        // Try local first (offline-first)
        if let localTemplate = try? localStorage.loadTemplate() {
            print("✅ Template loaded from local Keychain")
            return localTemplate
        }

        // Local not found, try cloud
        print("⏳ Local template not found, checking cloud...")
        do {
            let cloudTemplate = try await cloudStorage.loadBiometricTemplate()
            print("✅ Template loaded from Supabase cloud")

            // Cache locally for future offline use
            try? localStorage.saveTemplate(cloudTemplate)
            print("✅ Cloud template cached locally")

            return cloudTemplate
        } catch {
            print("❌ No template found in local or cloud storage")
            throw StorageError.notFound
        }
    }

    /// Delete template from both local and cloud
    func deleteTemplate() async {
        // Delete from local
        localStorage.deleteTemplate()
        print("🗑️ Template deleted from local Keychain")

        // Delete from cloud (best-effort)
        do {
            try await cloudStorage.deleteBiometricTemplate()
            print("🗑️ Template deleted from Supabase cloud")
        } catch {
            print("⚠️ Cloud deletion failed (local deletion successful): \(error.localizedDescription)")
        }
    }

    /// Check if template exists (local-first)
    func hasTemplate() -> Bool {
        return localStorage.hasTemplate()
    }

    /// Sync local template to cloud (manual backup)
    /// Useful for migrating existing local templates to cloud storage
    func syncLocalToCloud() async throws {
        guard let template = try? localStorage.loadTemplate() else {
            throw StorageError.notFound
        }

        try await cloudStorage.syncBiometricTemplate(template)
        print("✅ Local template manually synced to cloud")
    }

    /// Pull cloud template to local (manual restore)
    /// Useful for restoring from cloud on a new device
    func syncCloudToLocal() async throws {
        let cloudTemplate = try await cloudStorage.loadBiometricTemplate()
        try localStorage.saveTemplate(cloudTemplate)
        print("✅ Cloud template manually synced to local")
    }
}
