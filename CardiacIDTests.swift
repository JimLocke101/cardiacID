//
//  CardiacIDTests.swift
//  CardiacID Tests
//
//  Comprehensive test suite using Swift Testing framework
//

import Testing
import Foundation
@testable import CardiacID

@Suite("CardiacID Authentication Tests")
struct AuthenticationTests {
    
    @Test("Build Configuration Validation")
    func testBuildConfiguration() async throws {
        let config = BuildConfiguration.shared
        
        // Test platform detection
        #expect(config.currentPlatform != .unknown, "Platform should be detected")
        
        // Test bundle identifier
        #expect(!config.bundleIdentifier.isEmpty, "Bundle identifier should not be empty")
        
        // Test version information
        #expect(!config.appVersion.isEmpty, "App version should not be empty")
        #expect(!config.buildNumber.isEmpty, "Build number should not be empty")
        
        // Validate configuration
        let issues = config.validateConfiguration()
        #expect(issues.isEmpty, "Configuration should have no issues: \(issues)")
    }
    
    @Test("Credential Manager Basic Operations")
    func testCredentialManager() async throws {
        let manager = SecureCredentialManager.shared
        let testKey = CredentialKey.userProfile
        let testValue = "test_credential_value"
        
        // Test storage
        try manager.store(testValue, forKey: testKey)
        
        // Test existence check
        #expect(manager.exists(forKey: testKey), "Credential should exist after storage")
        
        // Test retrieval
        let retrievedValue = try manager.retrieve(forKey: testKey)
        #expect(retrievedValue == testValue, "Retrieved value should match stored value")
        
        // Test deletion
        try manager.delete(forKey: testKey)
        #expect(!manager.exists(forKey: testKey), "Credential should not exist after deletion")
        
        // Test retrieval of non-existent key
        #expect(throws: CredentialError.self) {
            _ = try manager.retrieve(forKey: testKey)
        }
    }
    
    #if os(iOS)
    @Test("MSAL Configuration")
    func testMSALConfiguration() async throws {
        let config = MSALConfiguration.shared
        
        // Test configuration setup
        try config.setupConfiguration(
            tenantId: "test-tenant-id",
            clientId: "test-client-id"
        )
        
        #expect(config.isConfigured, "Configuration should be marked as configured")
        #expect(!config.tenantId.isEmpty, "Tenant ID should not be empty")
        #expect(!config.clientId.isEmpty, "Client ID should not be empty")
        #expect(!config.scopes.isEmpty, "Scopes should not be empty")
        
        // Test cleanup
        try config.clearConfiguration()
        #expect(!config.isConfigured, "Configuration should be cleared")
    }
    #endif
    
    @Test("Watch Connectivity Service Initialization")
    func testWatchConnectivityService() async throws {
        let service = WatchConnectivityService.shared
        
        // Test that service initializes without crashing
        #expect(service != nil, "Watch connectivity service should initialize")
        
        // Test publishers are available
        let heartRatePublisher = service.heartRatePublisher
        let errorPublisher = service.errorPublisher
        
        #expect(heartRatePublisher != nil, "Heart rate publisher should be available")
        #expect(errorPublisher != nil, "Error publisher should be available")
    }
    
    @Test("Platform Detection and Feature Flags")
    func testPlatformDetection() async throws {
        let config = BuildConfiguration.shared
        let platform = config.currentPlatform
        
        // Test platform-specific features
        switch platform {
        case .iOS:
            #expect(config.enableMSAL, "MSAL should be enabled on iOS")
            #expect(config.enableWatchConnectivity, "Watch Connectivity should be enabled on iOS")
            #expect(config.enableHealthKit, "HealthKit should be enabled on iOS")
            
        case .watchOS:
            #expect(!config.enableMSAL, "MSAL should be disabled on watchOS")
            #expect(config.enableWatchConnectivity, "Watch Connectivity should be enabled on watchOS")
            #expect(config.enableHealthKit, "HealthKit should be enabled on watchOS")
            
        case .macOS:
            #expect(config.enableMSAL, "MSAL should be enabled on macOS")
            #expect(!config.enableWatchConnectivity, "Watch Connectivity should be disabled on macOS")
            #expect(!config.enableHealthKit, "HealthKit should be disabled on macOS")
            
        default:
            #expect(Bool(false), "Unsupported platform: \(platform)")
        }
    }
}

@Suite("Authentication Service Tests")
struct AuthServiceTests {
    
    @Test("Auth Service Factory")
    func testAuthServiceFactory() async throws {
        let authService = AuthServiceFactory.createAuthService()
        
        #expect(authService != nil, "Auth service should be created")
        #expect(!authService.isAuthenticated, "Auth service should start unauthenticated")
        #expect(authService.currentUser == nil, "Current user should be nil initially")
    }
    
    @Test("Auth User Model")
    func testAuthUserModel() async throws {
        let user = AuthUser(
            id: "test-id",
            displayName: "Test User",
            email: "test@example.com",
            jobTitle: "Developer",
            department: "Engineering",
            tenantId: "test-tenant"
        )
        
        #expect(user.id == "test-id", "User ID should match")
        #expect(user.displayName == "Test User", "Display name should match")
        #expect(user.email == "test@example.com", "Email should match")
        #expect(user.initials == "TU", "Initials should be generated correctly")
    }
    
    @Test("Authentication Error Handling")
    func testAuthErrorHandling() async throws {
        let errors: [AuthError] = [
            .notInitialized,
            .noViewController,
            .signInFailed("Test error"),
            .signOutFailed("Test error"),
            .tokenRefreshFailed("Test error"),
            .noAccount,
            .watchNotReachable,
            .watchAuthFailed,
            .refreshNotSupported,
            .notSupported
        ]
        
        for error in errors {
            #expect(error.errorDescription != nil, "Error should have description: \(error)")
            #expect(!error.errorDescription!.isEmpty, "Error description should not be empty")
        }
    }
}

@Suite("Security and Encryption Tests")
struct SecurityTests {
    
    @Test("Credential Encryption on watchOS", .enabled(if: BuildConfiguration.shared.currentPlatform == .watchOS))
    func testCredentialEncryption() async throws {
        #if os(watchOS)
        let manager = SecureCredentialManager.shared
        let testValue = "sensitive_test_data"
        let testKey = CredentialKey.entraIDAccessToken
        
        // Store encrypted credential
        try manager.store(testValue, forKey: testKey)
        
        // Verify it exists
        #expect(manager.exists(forKey: testKey), "Encrypted credential should exist")
        
        // Retrieve and verify
        let retrieved = try manager.retrieve(forKey: testKey)
        #expect(retrieved == testValue, "Decrypted value should match original")
        
        // Clean up
        try manager.delete(forKey: testKey)
        #endif
    }
    
    @Test("Keychain Access on iOS", .enabled(if: BuildConfiguration.shared.currentPlatform == .iOS))
    func testKeychainAccess() async throws {
        #if os(iOS)
        let manager = SecureCredentialManager.shared
        let testValue = "keychain_test_data"
        let testKey = CredentialKey.entraIDClientID
        
        // Store in keychain
        try manager.store(testValue, forKey: testKey, securityLevel: .standard)
        
        // Verify existence
        #expect(manager.exists(forKey: testKey), "Keychain item should exist")
        
        // Retrieve from keychain
        let retrieved = try manager.retrieve(forKey: testKey)
        #expect(retrieved == testValue, "Retrieved value should match stored value")
        
        // Clean up
        try manager.delete(forKey: testKey)
        #endif
    }
}

@Suite("Integration Tests")
struct IntegrationTests {
    
    @Test("End-to-End Configuration Setup")
    func testEndToEndConfiguration() async throws {
        let config = BuildConfiguration.shared
        
        // Print configuration for debugging
        config.printConfiguration()
        
        // Validate all components can initialize
        let credentialManager = SecureCredentialManager.shared
        #expect(credentialManager != nil, "Credential manager should initialize")
        
        let watchService = WatchConnectivityService.shared
        #expect(watchService != nil, "Watch connectivity service should initialize")
        
        #if os(iOS)
        // Test MSAL configuration setup
        let msalConfig = MSALConfiguration.shared
        try msalConfig.setupConfiguration(
            tenantId: "integration-test-tenant",
            clientId: "integration-test-client"
        )
        
        #expect(msalConfig.isConfigured, "MSAL should be configured")
        
        // Clean up
        try msalConfig.clearConfiguration()
        #endif
    }
    
    @Test("Authentication Flow Simulation")
    func testAuthenticationFlowSimulation() async throws {
        // This test simulates the authentication flow without actual network calls
        
        let authUser = AuthUser(
            id: UUID().uuidString,
            displayName: "Integration Test User",
            email: "integration@test.com",
            jobTitle: "Test Engineer",
            department: "QA",
            tenantId: "test-tenant"
        )
        
        // Simulate storing authentication data
        let credentialManager = SecureCredentialManager.shared
        try credentialManager.store(authUser.id, forKey: .userProfile)
        
        // Verify storage
        let storedId = try credentialManager.retrieve(forKey: .userProfile)
        #expect(storedId == authUser.id, "Stored user ID should match")
        
        // Simulate token storage
        let mockToken = "mock_access_token_\(UUID().uuidString)"
        try credentialManager.store(mockToken, forKey: .entraIDAccessToken)
        
        let retrievedToken = try credentialManager.retrieve(forKey: .entraIDAccessToken)
        #expect(retrievedToken == mockToken, "Retrieved token should match stored token")
        
        // Clean up
        try credentialManager.delete(forKey: .userProfile)
        try credentialManager.delete(forKey: .entraIDAccessToken)
    }
}

// MARK: - Test Utilities

struct TestUtilities {
    static func createMockUser() -> AuthUser {
        return AuthUser(
            id: "mock-user-id",
            displayName: "Mock User",
            email: "mock@test.com",
            jobTitle: "Tester",
            department: "QA",
            tenantId: "mock-tenant"
        )
    }
    
    static func createMockAuthResult(success: Bool = true) -> WatchAuthenticationResult {
        return WatchAuthenticationResult(
            isSuccess: success,
            token: success ? "mock_token" : nil,
            refreshToken: success ? "mock_refresh_token" : nil,
            expiresAt: success ? Date().addingTimeInterval(3600) : nil,
            errorMessage: success ? nil : "Mock error",
            method: "mock"
        )
    }
}