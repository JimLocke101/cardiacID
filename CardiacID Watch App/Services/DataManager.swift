import Foundation
import Combine

/// Manages local data persistence and user preferences
class DataManager: ObservableObject {
    @Published var userProfile: UserProfile?
    @Published var userPreferences: UserPreferences
    
    private let userDefaults = UserDefaults.standard
    private let fileManager = FileManager.default
    
    init() {
        self.userPreferences = UserPreferences()
        loadUserProfile()
        loadUserPreferences()
    }
    
    // MARK: - User Profile Management
    
    func saveUserProfile(_ profile: UserProfile) {
        do {
            let data = try JSONEncoder().encode(profile)
            userDefaults.set(data, forKey: "userProfile")
            self.userProfile = profile
        } catch {
            print("Failed to save user profile: \(error)")
        }
    }
    
    private func loadUserProfile() {
        guard let data = userDefaults.data(forKey: "userProfile") else { return }
        
        do {
            let profile = try JSONDecoder().decode(UserProfile.self, from: data)
            self.userProfile = profile
        } catch {
            print("Failed to load user profile: \(error)")
        }
    }
    
    // MARK: - User Preferences Management
    
    func saveUserPreferences(_ preferences: UserPreferences) {
        do {
            let data = try JSONEncoder().encode(preferences)
            userDefaults.set(data, forKey: "userPreferences")
            self.userPreferences = preferences
        } catch {
            print("Failed to save user preferences: \(error)")
        }
    }
    
    private func loadUserPreferences() {
        guard let data = userDefaults.data(forKey: "userPreferences") else { return }
        
        do {
            let preferences = try JSONDecoder().decode(UserPreferences.self, from: data)
            self.userPreferences = preferences
        } catch {
            print("Failed to load user preferences: \(error)")
        }
    }
    
    // MARK: - Data Management
    
    func clearAllData() {
        userDefaults.removeObject(forKey: "userProfile")
        userDefaults.removeObject(forKey: "userPreferences")
        userProfile = nil
        userPreferences = UserPreferences()
        
        // Clear any cached files
        clearCacheDirectory()
    }
    
    private func clearCacheDirectory() {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: nil)
            for fileURL in contents {
                try fileManager.removeItem(at: fileURL)
            }
        } catch {
            print("Failed to clear cache directory: \(error)")
        }
    }
    
    // MARK: - File Management
    
    func saveToFile<T: Codable>(_ object: T, to fileName: String) -> Bool {
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(fileName)
        
        do {
            let data = try JSONEncoder().encode(object)
            try data.write(to: fileURL)
            return true
        } catch {
            print("Failed to save \(fileName): \(error)")
            return false
        }
    }
    
    func loadFromFile<T: Codable>(_ type: T.Type, from fileName: String) -> T? {
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(fileName)
        
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            print("Failed to load \(fileName): \(error)")
            return nil
        }
    }
    
    // MARK: - Statistics
    
    func getAppStatistics() -> AppStatistics {
        let launchCount = userDefaults.integer(forKey: "appLaunchCount")
        let firstLaunch = userDefaults.object(forKey: "firstLaunchDate") as? Date
        let lastAuthentication = userDefaults.object(forKey: "lastAuthentication") as? Date
        
        return AppStatistics(
            launchCount: launchCount,
            firstLaunchDate: firstLaunch,
            lastAuthenticationDate: lastAuthentication,
            isUserEnrolled: userProfile?.isEnrolled ?? false
        )
    }
    
    func incrementLaunchCount() {
        let currentCount = userDefaults.integer(forKey: "appLaunchCount")
        userDefaults.set(currentCount + 1, forKey: "appLaunchCount")
        
        if userDefaults.object(forKey: "firstLaunchDate") == nil {
            userDefaults.set(Date(), forKey: "firstLaunchDate")
        }
    }
    
    func updateLastAuthentication() {
        userDefaults.set(Date(), forKey: "lastAuthentication")
    }
}

