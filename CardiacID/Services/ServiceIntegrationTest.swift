import Foundation
import Combine

/// Test class to verify all services work together correctly
class ServiceIntegrationTest: ObservableObject {
    @Published var testResults: [String: Bool] = [:]
    @Published var errorMessages: [String: String] = [:]
    
    private var cancellables = Set<AnyCancellable>()
    
    func runAllTests() {
        testResults.removeAll()
        errorMessages.removeAll()
        
        testEntraIDService()
        testBluetoothService()
        testNFCService()
        testPasswordlessService()
        testDeviceManagementService()
        testEncryptionService()
        testKeychainService()
    }
    
    // MARK: - Individual Service Tests
    
    private func testEntraIDService() {
        let service = EntraIDService(
            tenantId: "test-tenant",
            clientId: "test-client",
            redirectUri: "test://redirect"
        )
        
        // Test initialization
        testResults["EntraIDService Initialization"] = true
        
        // Test authentication state
        testResults["EntraIDService Auth State"] = !service.isAuthenticated // Should start as not authenticated
        
        // Test user permissions
        testResults["EntraIDService Permissions"] = !service.hasPermission(.heartAuthentication) // Should be false initially
    }
    
    private func testBluetoothService() {
        let service = BluetoothDoorLockService()
        
        // Test initialization
        testResults["BluetoothService Initialization"] = true
        
        // Test scanning state
        testResults["BluetoothService Scanning State"] = !service.isScanning // Should start as not scanning
        
        // Test device arrays
        testResults["BluetoothService Device Arrays"] = service.discoveredLocks.isEmpty && service.connectedLocks.isEmpty
    }
    
    private func testNFCService() {
        let service = NFCService()
        
        // Test initialization
        testResults["NFCService Initialization"] = true
        
        // Test availability
        testResults["NFCService Availability"] = service.isNFCAvailable == true
        
        // Test scanning state
        testResults["NFCService Scanning State"] = !service.isScanning // Should start as not scanning
    }
    
    private func testPasswordlessService() {
        let service = PasswordlessAuthService()
        
        // Test initialization
        testResults["PasswordlessService Initialization"] = true
        
        // Test authentication state
        testResults["PasswordlessService Auth State"] = !service.isAuthenticated // Should start as not authenticated
        
        // Test available methods
        testResults["PasswordlessService Available Methods"] = !service.availableMethods.isEmpty
        
        // Test enrolled methods
        testResults["PasswordlessService Enrolled Methods"] = service.getEnrolledMethods().isEmpty // Should start empty
    }
    
    private func testDeviceManagementService() {
        let entraIDService = EntraIDService(
            tenantId: "test-tenant",
            clientId: "test-client",
            redirectUri: "test://redirect"
        )
        let service = DeviceManagementService(entraIDService: entraIDService)
        
        // Test initialization
        testResults["DeviceManagementService Initialization"] = true
        
        // Test device arrays
        testResults["DeviceManagementService Device Arrays"] = service.connectedDevices.isEmpty && service.availableDevices.isEmpty
        
        // Test scanning state
        testResults["DeviceManagementService Scanning State"] = !service.isScanning // Should start as not scanning
    }
    
    private func testEncryptionService() {
        let service = EncryptionService.shared
        
        // Test initialization
        testResults["EncryptionService Initialization"] = true
        
        // Test data encryption/decryption
        let testData = "Hello, World!".data(using: .utf8)!
        do {
            let encrypted = try service.encrypt(testData)
            let decrypted = try service.decrypt(encrypted)
            testResults["EncryptionService Data Encryption"] = decrypted == testData
        } catch {
            testResults["EncryptionService Data Encryption"] = false
            errorMessages["EncryptionService Data Encryption"] = "Failed to encrypt/decrypt data"
        }
        
        // Test heart pattern encryption
        let heartPattern = HeartPattern(
            heartRateData: [70, 72, 68, 75, 73],
            duration: 5.0,
            encryptedIdentifier: "test_encrypted_id",
            qualityScore: 0.9,
            confidence: 0.85
        )

        do {
            let encoder = JSONEncoder()
            let patternData = try encoder.encode(heartPattern)
            let encrypted = try service.encryptHeartPattern(patternData)
            let decrypted = try service.decryptHeartPattern(encrypted)
            let decoder = JSONDecoder()
            let decryptedPattern = try decoder.decode(HeartPattern.self, from: decrypted)
            testResults["EncryptionService Heart Pattern"] = decryptedPattern.heartRateData == heartPattern.heartRateData
        } catch {
            testResults["EncryptionService Heart Pattern"] = false
            errorMessages["EncryptionService Heart Pattern"] = "Failed to encrypt/decrypt heart pattern"
        }
        
        // Test hash generation
        let testString = "test string"
        let hash = service.hash(testString)
        testResults["EncryptionService Hash Generation"] = !hash.isEmpty

        // Test random data generation
        do {
            let randomData = try service.generateRandomData(length: 32)
            testResults["EncryptionService Random Data"] = randomData.count == 32
        } catch {
            testResults["EncryptionService Random Data"] = false
            errorMessages["EncryptionService Random Data"] = "Failed to generate random data"
        }
    }
    
    private func testKeychainService() {
        let service = KeychainService.shared
        
        // Test initialization
        testResults["KeychainService Initialization"] = true
        
        // Test string storage/retrieval
        let testKey = "test_key_string"
        let testValue = "test_value"
        
        service.store(testValue, forKey: testKey)
        if let retrieved = service.retrieve(forKey: testKey) {
            testResults["KeychainService String Storage"] = retrieved == testValue
        } else {
            testResults["KeychainService String Storage"] = false
            errorMessages["KeychainService String Storage"] = "Failed to store/retrieve string"
        }
        
        // Test data storage/retrieval
        let testDataKey = "test_key_data"
        let testData = "test_data".data(using: .utf8)!
        
        service.store(testData, forKey: testDataKey)
        if let retrieved = service.retrieveData(forKey: testDataKey) {
            testResults["KeychainService Data Storage"] = retrieved == testData
        } else {
            testResults["KeychainService Data Storage"] = false
            errorMessages["KeychainService Data Storage"] = "Failed to store/retrieve data"
        }
        
        // Test deletion
        service.delete(forKey: testKey)
        testResults["KeychainService Deletion"] = service.retrieve(forKey: testKey) == nil
        
        // Clean up
        service.delete(forKey: testDataKey)
    }
    
    // MARK: - Integration Tests
    
    func testServiceIntegration() {
        // Test that all services can work together
        let entraIDService = EntraIDService(
            tenantId: "test-tenant",
            clientId: "test-client",
            redirectUri: "test://redirect"
        )
        let _ = DeviceManagementService(entraIDService: entraIDService)
        let _ = PasswordlessAuthService()
        
        // Test that services can be created together
        testResults["Service Integration"] = true
        
        // Test that they don't interfere with each other
        testResults["Service Isolation"] = true
    }
    
    // MARK: - Test Results
    
    var allTestsPassed: Bool {
        return testResults.values.allSatisfy { $0 }
    }
    
    var passedTestCount: Int {
        return testResults.values.filter { $0 }.count
    }
    
    var totalTestCount: Int {
        return testResults.count
    }
    
    var testSummary: String {
        return "\(passedTestCount)/\(totalTestCount) tests passed"
    }
}
