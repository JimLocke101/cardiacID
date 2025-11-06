import Foundation

/// Service for storing biometric templates using hybrid cloud/local storage
class HybridTemplateStorageService {
    
    // MARK: - Dependencies
    private let supabaseClient: SupabaseClient
    private let keychain = KeychainService.shared
    private let encryptionService = EncryptionService.shared
    
    // MARK: - Configuration
    private let maxLocalTemplates = 5
    private let syncInterval: TimeInterval = 24 * 60 * 60 // 24 hours
    
    init(supabaseClient: SupabaseClient = SupabaseClient.shared) {
        self.supabaseClient = supabaseClient
        setupAutoSync()
    }
    
    // MARK: - Template Storage
    
    /// Store a biometric template with hybrid approach
    func storeTemplate(_ template: BiometricTemplate) async throws {
        // Always store locally first for immediate access
        try storeTemplateLocally(template)
        
        // Then sync to cloud if connected
        if supabaseClient.isAuthenticated {
            try await syncTemplateToCloud(template)
        }
    }
    
    /// Retrieve a biometric template
    func retrieveTemplate(for userId: String) async throws -> BiometricTemplate? {
        // Try local first (fastest)
        if let localTemplate = try retrieveTemplateLocally(for: userId) {
            return localTemplate
        }
        
        // Fall back to cloud if authenticated
        if supabaseClient.isAuthenticated {
            return try await retrieveTemplateFromCloud(for: userId)
        }
        
        return nil
    }
    
    /// Delete a biometric template
    func deleteTemplate(for userId: String) async throws {
        // Delete locally
        try deleteTemplateLocally(for: userId)
        
        // Delete from cloud if connected
        if supabaseClient.isAuthenticated {
            try await deleteTemplateFromCloud(for: userId)
        }
    }
    
    // MARK: - Local Storage
    
    private func storeTemplateLocally(_ template: BiometricTemplate) throws {
        let key = "biometric_template_\(template.userId)"
        let data = try JSONEncoder().encode(template)
        let encryptedData = try encryptionService.encrypt(data)
        keychain.store(encryptedData, forKey: key)
    }
    
    private func retrieveTemplateLocally(for userId: String) throws -> BiometricTemplate? {
        let key = "biometric_template_\(userId)"
        
        guard let encryptedData = keychain.retrieve(forKey: key) else {
            return nil
        }
        
        let data = try encryptionService.decrypt(encryptedData)
        return try JSONDecoder().decode(BiometricTemplate.self, from: data)
    }
    
    private func deleteTemplateLocally(for userId: String) throws {
        let key = "biometric_template_\(userId)"
        keychain.delete(forKey: key)
    }
    
    // MARK: - Cloud Storage
    
    private func syncTemplateToCloud(_ template: BiometricTemplate) async throws {
        try await supabaseClient.storeBiometricTemplate(
            template.templateData,
            qualityScore: template.qualityScore,
            sampleCount: template.sampleCount
        )
    }
    
    private func retrieveTemplateFromCloud(for userId: String) async throws -> BiometricTemplate? {
        // Implementation would depend on Supabase client methods
        // For now, return nil as fallback
        return nil
    }
    
    private func deleteTemplateFromCloud(for userId: String) async throws {
        try await supabaseClient.deleteBiometricTemplate()
    }
    
    // MARK: - Sync Management
    
    private func setupAutoSync() {
        // Setup periodic sync with cloud
        Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.performPeriodicSync()
            }
        }
    }
    
    private func performPeriodicSync() async {
        guard supabaseClient.isAuthenticated else { return }
        
        // Sync logic would go here
        // For now, just log that sync was attempted
        print("🔄 Performing periodic template sync")
    }
    
    /// Force a manual sync with cloud
    func forceSyncWithCloud() async throws {
        guard supabaseClient.isAuthenticated else {
            throw HybridStorageError.notAuthenticated
        }
        
        await performPeriodicSync()
    }
    
    /// Get storage statistics
    func getStorageStats() -> StorageStats {
        let localCount = getLocalTemplateCount()
        
        return StorageStats(
            localTemplates: localCount,
            cloudSyncEnabled: supabaseClient.isAuthenticated,
            lastSyncDate: getLastSyncDate()
        )
    }
    
    private func getLocalTemplateCount() -> Int {
        // Count local templates
        // This is a simplified implementation
        return 0
    }
    
    private func getLastSyncDate() -> Date? {
        return UserDefaults.standard.object(forKey: "last_template_sync") as? Date
    }
}

// MARK: - Supporting Types

struct BiometricTemplate: Codable {
    let id: String
    let userId: String
    let templateData: Data
    let qualityScore: Double
    let sampleCount: Int
    let createdAt: Date
    let updatedAt: Date
    
    init(userId: String, templateData: Data, qualityScore: Double, sampleCount: Int) {
        self.id = UUID().uuidString
        self.userId = userId
        self.templateData = templateData
        self.qualityScore = qualityScore
        self.sampleCount = sampleCount
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

struct StorageStats {
    let localTemplates: Int
    let cloudSyncEnabled: Bool
    let lastSyncDate: Date?
}

enum HybridStorageError: Error, LocalizedError {
    case notAuthenticated
    case encryptionFailed
    case syncFailed(String)
    case templateNotFound
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Cloud storage requires authentication"
        case .encryptionFailed:
            return "Failed to encrypt template data"
        case .syncFailed(let reason):
            return "Sync failed: \(reason)"
        case .templateNotFound:
            return "Biometric template not found"
        }
    }
}

// MARK: - Mock Services for Development

class KeychainService {
    static let shared = KeychainService()
    
    private var storage: [String: Data] = [:]
    
    func store(_ data: Data, forKey key: String) {
        storage[key] = data
    }
    
    func retrieve(forKey key: String) -> Data? {
        return storage[key]
    }
    
    func delete(forKey key: String) {
        storage.removeValue(forKey: key)
    }
}

class EncryptionService {
    static let shared = EncryptionService()
    
    func encrypt(_ data: Data) throws -> Data {
        // Mock encryption - in production this would use proper cryptography
        return data
    }
    
    func decrypt(_ data: Data) throws -> Data {
        // Mock decryption - in production this would use proper cryptography
        return data
    }
}