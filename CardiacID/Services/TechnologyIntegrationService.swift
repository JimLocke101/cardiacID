import Foundation
import Combine
import CoreBluetooth
import CoreNFC
import HealthKit
import SwiftUI

/// Comprehensive service for integrating and managing all Heart ID technologies
class TechnologyIntegrationService: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var isInitialized = false
    @Published var integrationStatus: IntegrationStatus = .disconnected
    @Published var availableTechnologies: Set<TechnologyType> = []
    @Published var connectedDevices: [IntegratedDevice] = []
    @Published var errorMessage: String?
    @Published var isScanning = false
    @Published var lastActivity: TechnologyActivityEvent?
    
    // MARK: - Services
    private let entraIDService: EntraIDService
    private let bluetoothService: BluetoothDoorLockService
    private let nfcService: NFCService
    private let deviceManagementService: DeviceManagementService
    private let passwordlessService: PasswordlessAuthService
    private let encryptionService = EncryptionService.shared
    private let keychain = KeychainService.shared
    
    // MARK: - State Management
    private var cancellables = Set<AnyCancellable>()
    private var heartPatternCache: [UUID: HeartPattern] = [:]
    private var deviceCapabilities: [UUID: Set<DeviceCapability>] = [:]
    
    // MARK: - Initialization
    init(entraIDService: EntraIDService) {
        self.entraIDService = entraIDService
        self.bluetoothService = BluetoothDoorLockService()
        self.nfcService = NFCService()
        self.deviceManagementService = DeviceManagementService(entraIDService: entraIDService)
        self.passwordlessService = PasswordlessAuthService()
        
        super.init()
        setupServices()
    }
    
    // MARK: - Service Setup
    private func setupServices() {
        // Setup error handling
        setupErrorHandling()
        
        // Setup device discovery
        setupDeviceDiscovery()
        
        // Setup authentication flows
        setupAuthenticationFlows()
        
        // Setup heart pattern management
        setupHeartPatternManagement()
        
        // Initialize available technologies
        checkAvailableTechnologies()
        
        isInitialized = true
    }
    
    private func setupErrorHandling() {
        // EntraID errors
        entraIDService.$errorMessage
            .compactMap { $0 }
            .sink { [weak self] error in
                self?.handleError(.entraID, error)
            }
            .store(in: &cancellables)
        
        // Bluetooth errors
        bluetoothService.$errorMessage
            .compactMap { $0 }
            .sink { [weak self] error in
                self?.handleError(.bluetooth, error)
            }
            .store(in: &cancellables)
        
        // NFC errors
        nfcService.$errorMessage
            .compactMap { $0 }
            .sink { [weak self] error in
                self?.handleError(.nfc, error)
            }
            .store(in: &cancellables)
    }
    
    private func setupDeviceDiscovery() {
        // Bluetooth device discovery
        bluetoothService.$discoveredLocks
            .sink { [weak self] locks in
                self?.updateConnectedDevices()
            }
            .store(in: &cancellables)
        
        bluetoothService.$connectedLocks
            .sink { [weak self] locks in
                self?.updateConnectedDevices()
            }
            .store(in: &cancellables)
        
        // NFC device discovery
        nfcService.$lastScannedTag
            .compactMap { $0 }
            .sink { [weak self] tag in
                self?.handleNFCTag(tag)
            }
            .store(in: &cancellables)
        
        // Device management updates
        deviceManagementService.$connectedDevices
            .sink { [weak self] devices in
                self?.updateConnectedDevices()
            }
            .store(in: &cancellables)
    }
    
    private func setupAuthenticationFlows() {
        // EntraID authentication
        entraIDService.$isAuthenticated
            .sink { [weak self] isAuthenticated in
                self?.updateIntegrationStatus()
                if isAuthenticated {
                    self?.syncEnterpriseDevices()
                }
            }
            .store(in: &cancellables)
        
        // Passwordless authentication - using a placeholder since the property doesn't exist yet
        // passwordlessService.$isPasswordlessEnabled
        //     .sink { [weak self] _ in
        //         self?.updateIntegrationStatus()
        //     }
        //     .store(in: &cancellables)
    }
    
    private func setupHeartPatternManagement() {
        // Heart pattern caching and management
        // This would integrate with HealthKit and the authentication manager
    }
    
    // MARK: - Public Methods
    
    /// Start scanning for all available devices
    func startScanning() {
        isScanning = true
        
        // Start Bluetooth scanning
        if availableTechnologies.contains(.bluetooth) {
            bluetoothService.startScanning()
        }
        
        // Start NFC scanning
        if availableTechnologies.contains(.nfc) {
            nfcService.startScanning()
        }
        
        // Start device management scanning
        deviceManagementService.startScanning()
        
        logActivity(.scanningStarted, "Started scanning for devices")
    }
    
    /// Stop scanning for devices
    func stopScanning() {
        isScanning = false
        
        bluetoothService.stopScanning()
        nfcService.stopScanning()
        deviceManagementService.stopScanning()
        
        logActivity(.scanningStopped, "Stopped scanning for devices")
    }
    
    /// Connect to a specific device
    func connectToDevice(_ device: IntegratedDevice) async throws {
        logActivity(.connectionAttempt, "Attempting to connect to \(device.name)")
        
        switch device.type {
        case .bluetoothDoorLock:
            if let bluetoothLock = device.bluetoothLock {
                bluetoothService.connectToLock(bluetoothLock)
            }
        case .nfcTag:
            // NFC connection is automatic when scanning
            break
        case .appleWatch:
            // Apple Watch connection is handled by WatchConnectivity
            break
        case .enterpriseDevice:
            // Enterprise device connection requires EntraID authentication
            guard entraIDService.isAuthenticated else {
                throw IntegrationError.notAuthenticated
            }
        }
        
        // Update device status
        updateConnectedDevices()
        logActivity(.deviceConnected, "Connected to \(device.name)")
    }
    
    /// Disconnect from a specific device
    func disconnectFromDevice(_ device: IntegratedDevice) async throws {
        logActivity(.disconnectionAttempt, "Attempting to disconnect from \(device.name)")
        
        switch device.type {
        case .bluetoothDoorLock:
            if let bluetoothLock = device.bluetoothLock {
                bluetoothService.disconnectFromLock(bluetoothLock)
            }
        case .nfcTag, .appleWatch, .enterpriseDevice:
            // These connections are handled automatically
            break
        }
        
        updateConnectedDevices()
        logActivity(.deviceDisconnected, "Disconnected from \(device.name)")
    }
    
    /// Execute a command on a device with heart pattern authentication
    func executeCommand(_ command: DeviceCommand, on device: IntegratedDevice, with heartPattern: HeartPattern? = nil) async throws {
        logActivity(.commandExecution, "Executing \(command.rawValue) on \(device.name)")
        
        // Authenticate if required
        if command.requiresAuthentication {
            guard let pattern = heartPattern else {
                throw IntegrationError.authenticationRequired
            }
            
            let authResult = try await authenticateWithDevice(device, using: pattern)
            guard authResult.success else {
                throw IntegrationError.authenticationFailed
            }
        }
        
        // Execute command based on device type
        switch device.type {
        case .bluetoothDoorLock:
            try await executeBluetoothCommand(command, on: device, with: heartPattern)
        case .nfcTag:
            try await executeNFCCommand(command, on: device, with: heartPattern)
        case .appleWatch:
            try await executeWatchCommand(command, on: device, with: heartPattern)
        case .enterpriseDevice:
            try await executeEnterpriseCommand(command, on: device, with: heartPattern)
        }
        
        logActivity(.commandCompleted, "Completed \(command.rawValue) on \(device.name)")
    }
    
    /// Register a heart pattern for a specific device
    func registerHeartPattern(_ pattern: HeartPattern, for device: IntegratedDevice) async throws {
        logActivity(.patternRegistration, "Registering heart pattern for \(device.name)")
        
        // Encrypt and store heart pattern
        guard let encryptedPattern = encryptionService.encryptHeartPattern(pattern) else {
            throw IntegrationError.encryptionFailed
        }
        
        // Store in keychain with device-specific key
        let key = "heart_pattern_\(device.id.uuidString)"
        keychain.store(encryptedPattern, forKey: key)
        
        // Cache the pattern
        heartPatternCache[device.id] = pattern
        
        logActivity(.patternRegistered, "Heart pattern registered for \(device.name)")
    }
    
    /// Get heart pattern for a specific device
    func getHeartPattern(for device: IntegratedDevice) -> HeartPattern? {
        return heartPatternCache[device.id]
    }
    
    /// Sync enterprise devices from EntraID
    func syncEnterpriseDevices() {
        guard entraIDService.isAuthenticated else { return }
        
        logActivity(.enterpriseSync, "Syncing enterprise devices")
        
        // This would fetch enterprise devices from EntraID
        // For now, we'll simulate it
        let enterpriseDevice = IntegratedDevice(
            id: UUID(),
            name: "Enterprise Device",
            type: .enterpriseDevice,
            status: .connected,
            capabilities: [.authenticate, .unlock, .status],
            lastSeen: Date()
        )
        
        if !connectedDevices.contains(where: { $0.id == enterpriseDevice.id }) {
            connectedDevices.append(enterpriseDevice)
        }
        
        logActivity(.enterpriseSynced, "Enterprise devices synced")
    }
    
    // MARK: - Private Methods
    
    private func checkAvailableTechnologies() {
        var technologies: Set<TechnologyType> = []
        
        // Check Bluetooth availability
        if bluetoothService.isBluetoothAvailable {
            technologies.insert(.bluetooth)
        }
        
        // Check NFC availability
        if nfcService.isNFCAvailable {
            technologies.insert(.nfc)
        }
        
        // Check EntraID availability - using a different approach since tenantId is private
        technologies.insert(.entraID)
        
        // Check HealthKit availability
        if HKHealthStore.isHealthDataAvailable() {
            technologies.insert(.healthKit)
        }
        
        availableTechnologies = technologies
        updateIntegrationStatus()
    }
    
    private func updateIntegrationStatus() {
        let hasEntraID = entraIDService.isAuthenticated
        let hasPasswordless = true // PasswordlessService doesn't have this property yet
        let hasDevices = !connectedDevices.isEmpty
        
        if hasEntraID && hasPasswordless && hasDevices {
            integrationStatus = .fullyIntegrated
        } else if hasEntraID || hasPasswordless || hasDevices {
            integrationStatus = .partiallyIntegrated
        } else {
            integrationStatus = .disconnected
        }
    }
    
    private func updateConnectedDevices() {
        var devices: [IntegratedDevice] = []
        
        // Add Bluetooth door locks
        for lock in bluetoothService.connectedLocks {
            let device = IntegratedDevice(
                id: lock.id,
                name: lock.name,
                type: .bluetoothDoorLock,
                status: lock.isConnected ? .connected : .disconnected,
                capabilities: [.unlock, .lock, .status, .battery],
                bluetoothLock: lock,
                lastSeen: Date()
            )
            devices.append(device)
        }
        
        // Add NFC tags
        if let nfcTag = nfcService.lastScannedTag {
            let device = IntegratedDevice(
                id: UUID(),
                name: "NFC Tag",
                type: .nfcTag,
                status: .connected,
                capabilities: [.read, .write, .authenticate],
                nfcTag: nfcTag,
                lastSeen: Date()
            )
            devices.append(device)
        }
        
        // Add Apple Watch
        let watchDevice = IntegratedDevice(
            id: UUID(),
            name: "Apple Watch",
            type: .appleWatch,
            status: .connected,
            capabilities: [.authenticate],
            lastSeen: Date()
        )
        devices.append(watchDevice)
        
        connectedDevices = devices
        updateIntegrationStatus()
    }
    
    private func handleNFCTag(_ tag: NFCTagData) {
        let device = IntegratedDevice(
            id: UUID(),
            name: "NFC Tag",
            type: .nfcTag,
            status: .discovered,
            capabilities: [.read, .write, .authenticate],
            nfcTag: tag,
            lastSeen: Date()
        )
        
        if !connectedDevices.contains(where: { $0.id == device.id }) {
            connectedDevices.append(device)
        }
        
        logActivity(.nfcTagDetected, "NFC tag detected: \(tag.type)")
    }
    
    private func authenticateWithDevice(_ device: IntegratedDevice, using heartPattern: HeartPattern) async throws -> DeviceAuthResult {
        // Get stored heart pattern for device
        let key = "heart_pattern_\(device.id.uuidString)"
        guard let encryptedPattern = keychain.retrieveData(forKey: key),
              let storedPattern = encryptionService.decryptHeartPattern(encryptedPattern) else {
            throw IntegrationError.patternNotFound
        }
        
        // Compare patterns (simplified comparison)
        let similarity = compareHeartPatterns(storedPattern, heartPattern)
        let success = similarity > 0.8 // 80% similarity threshold
        
        return DeviceAuthResult(
            success: success,
            deviceId: device.id,
            token: success ? encryptionService.generateRandomString(length: 32) : nil,
            expiresAt: success ? Date().addingTimeInterval(300) : nil
        )
    }
    
    private func compareHeartPatterns(_ pattern1: HeartPattern, _ pattern2: HeartPattern) -> Double {
        // Simplified heart pattern comparison
        // In a real implementation, this would use advanced signal processing
        let data1 = pattern1.heartRateData
        let data2 = pattern2.heartRateData
        
        guard data1.count == data2.count else { return 0.0 }
        
        let differences = zip(data1, data2).map { abs($0 - $1) }
        let averageDifference = differences.reduce(0, +) / Double(differences.count)
        let maxDifference = max(data1.max() ?? 0, data2.max() ?? 0)
        
        return max(0, 1.0 - (averageDifference / maxDifference))
    }
    
    private func executeBluetoothCommand(_ command: DeviceCommand, on device: IntegratedDevice, with heartPattern: HeartPattern?) async throws {
        guard let bluetoothLock = device.bluetoothLock else {
            throw IntegrationError.invalidDevice
        }
        
        switch command {
        case .unlock:
            if let pattern = heartPattern {
                bluetoothService.unlockDoor(bluetoothLock, with: pattern)
            }
        case .lock:
            bluetoothService.lockDoor(bluetoothLock)
        case .status:
            bluetoothService.checkLockStatus(bluetoothLock)
        case .battery:
            // Get battery level
            break
        default:
            throw IntegrationError.unsupportedCommand
        }
    }
    
    private func executeNFCCommand(_ command: DeviceCommand, on device: IntegratedDevice, with heartPattern: HeartPattern?) async throws {
        switch command {
        case .read:
            nfcService.readTagData()
        case .write:
            // Write data to NFC tag
            break
        case .authenticate:
            if let pattern = heartPattern {
                nfcService.authenticateWithHeartPattern(pattern, via: device.nfcTag!)
            }
        default:
            throw IntegrationError.unsupportedCommand
        }
    }
    
    private func executeWatchCommand(_ command: DeviceCommand, on device: IntegratedDevice, with heartPattern: HeartPattern?) async throws {
        // Apple Watch commands are handled by WatchConnectivityService
        // This would send commands to the watch app
    }
    
    private func executeEnterpriseCommand(_ command: DeviceCommand, on device: IntegratedDevice, with heartPattern: HeartPattern?) async throws {
        guard entraIDService.isAuthenticated else {
            throw IntegrationError.notAuthenticated
        }
        
        // Execute enterprise-specific command
        // This would integrate with EntraID for enterprise device control
    }
    
    private func handleError(_ technology: TechnologyType, _ error: String) {
        errorMessage = "\(technology.rawValue): \(error)"
        logActivity(.error, "Error in \(technology.rawValue): \(error)")
    }
    
    private func logActivity(_ type: ActivityType, _ message: String) {
        let activity = TechnologyActivityEvent(
            id: UUID(),
            type: type,
            message: message,
            timestamp: Date(),
            technology: .entraID
        )
        
        lastActivity = activity
        
        // Store activity in persistent storage
        // This would save to a database or local storage
    }
}

// MARK: - Supporting Types

enum IntegrationStatus {
    case disconnected
    case partiallyIntegrated
    case fullyIntegrated
    
    var description: String {
        switch self {
        case .disconnected: return "Not Connected"
        case .partiallyIntegrated: return "Partially Integrated"
        case .fullyIntegrated: return "Fully Integrated"
        }
    }
    
    var color: Color {
        let colors = HeartIDColors()
        switch self {
        case .disconnected: return colors.error
        case .partiallyIntegrated: return colors.warning
        case .fullyIntegrated: return colors.success
        }
    }
}

enum TechnologyType: String, CaseIterable, Codable {
    case bluetooth = "Bluetooth"
    case nfc = "NFC"
    case entraID = "EntraID"
    case healthKit = "HealthKit"
    case appleWatch = "Apple Watch"
    case enterprise = "Enterprise"
}

struct IntegratedDevice: Identifiable, Codable {
    let id: UUID
    let name: String
    let type: DeviceType
    let status: iPhoneDeviceStatus
    let capabilities: Set<DeviceCapability>
    let bluetoothLock: BluetoothDoorLock?
    let lastSeen: Date?
    
    // Non-codable properties
    var nfcTag: NFCTagData?
    
    init(id: UUID = UUID(), name: String, type: DeviceType, status: iPhoneDeviceStatus, capabilities: Set<DeviceCapability>, bluetoothLock: BluetoothDoorLock? = nil, nfcTag: NFCTagData? = nil, lastSeen: Date? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.status = status
        self.capabilities = capabilities
        self.bluetoothLock = bluetoothLock
        self.nfcTag = nfcTag
        self.lastSeen = lastSeen
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, type, status, capabilities, bluetoothLock, lastSeen
    }
}

enum ActivityType: String, CaseIterable, Codable {
    case scanningStarted
    case scanningStopped
    case connectionAttempt
    case deviceConnected
    case disconnectionAttempt
    case deviceDisconnected
    case commandExecution
    case commandCompleted
    case patternRegistration
    case patternRegistered
    case enterpriseSync
    case enterpriseSynced
    case nfcTagDetected
    case error
}

struct TechnologyActivityEvent: Identifiable, Codable {
    let id: UUID
    let type: ActivityType
    let message: String
    let timestamp: Date
    let technology: TechnologyType
}

enum IntegrationError: Error, LocalizedError {
    case notAuthenticated
    case authenticationRequired
    case authenticationFailed
    case patternNotFound
    case encryptionFailed
    case invalidDevice
    case unsupportedCommand
    case connectionFailed
    case commandFailed
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not authenticated with enterprise"
        case .authenticationRequired: return "Authentication required for this operation"
        case .authenticationFailed: return "Authentication failed"
        case .patternNotFound: return "Heart pattern not found for device"
        case .encryptionFailed: return "Encryption failed"
        case .invalidDevice: return "Invalid device"
        case .unsupportedCommand: return "Unsupported command for this device"
        case .connectionFailed: return "Failed to connect to device"
        case .commandFailed: return "Command failed to execute"
        }
    }
}
