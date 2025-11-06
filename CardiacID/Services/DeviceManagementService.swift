import Foundation
import Combine
import CoreBluetooth
import CoreNFC

/// Comprehensive device management service for controlling all connected devices
class DeviceManagementService: NSObject, ObservableObject {
    @Published var connectedDevices: [ManagedDevice] = []
    @Published var availableDevices: [ManagedDevice] = []
    @Published var isScanning = false
    @Published var errorMessage: String?
    @Published var deviceStatus: [UUID: iPhoneDeviceStatus] = [:]
    
    // Services
    private let bluetoothService = BluetoothDoorLockService()
    private let nfcService = NFCService()
    private let entraIDService: MockEntraIDService
    private let passwordlessService = PasswordlessAuthService()
    private let encryptionService = EncryptionService.shared
    private let keychain = KeychainService.shared
    
    // Publishers
    private let deviceUpdateSubject = PassthroughSubject<DeviceUpdate, Never>()
    private let commandResultSubject = PassthroughSubject<DeviceCommandResult, Never>()
    
    var deviceUpdatePublisher: AnyPublisher<DeviceUpdate, Never> {
        deviceUpdateSubject.eraseToAnyPublisher()
    }
    
    var commandResultPublisher: AnyPublisher<DeviceCommandResult, Never> {
        commandResultSubject.eraseToAnyPublisher()
    }
    
    init(entraIDService: MockEntraIDService) {
        self.entraIDService = entraIDService
        super.init()
        setupServices()
        loadStoredDevices()
    }
    
    // MARK: - Service Setup
    
    // MARK: - Cancellables

    private var cancellables = Set<AnyCancellable>()

    private func setupServices() {
        // Setup Bluetooth service
        bluetoothService.$discoveredLocks
            .sink { [weak self] locks in
                self?.updateAvailableDevices()
            }
            .store(in: &cancellables)

        bluetoothService.$connectedLocks
            .sink { [weak self] locks in
                self?.updateConnectedDevices()
            }
            .store(in: &cancellables)

        // Setup NFC service
        nfcService.$lastScannedTag
            .sink { [weak self] tag in
                if let tag = tag {
                    self?.handleNFCTag(tag)
                }
            }
            .store(in: &cancellables)

        // Setup Entra ID service
        entraIDService.$isAuthenticated
            .sink { [weak self] (isAuthenticated: Bool) in
                if isAuthenticated {
                    self?.syncEnterpriseDevices()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Device Discovery
    
    /// Start scanning for all available devices
    func startScanning() {
        isScanning = true
        
        // Start Bluetooth scanning
        bluetoothService.startScanning()
        
        // Start NFC scanning
        nfcService.startScanning()
        
        // Update available devices
        updateAvailableDevices()
    }
    
    /// Stop scanning for devices
    func stopScanning() {
        isScanning = false
        
        bluetoothService.stopScanning()
        nfcService.stopScanning()
    }
    
    /// Refresh device list
    func refreshDevices() {
        updateAvailableDevices()
        updateConnectedDevices()
    }
    
    // MARK: - Device Management
    
    /// Connect to a device
    func connectToDevice(_ device: ManagedDevice) {
        Task {
            do {
                let result = try await performConnection(device)
                
                await MainActor.run {
                    if result.success {
                        self.deviceUpdateSubject.send(.connected(device))
                        self.commandResultSubject.send(result)
                    } else {
                        self.errorMessage = result.error ?? "Failed to connect to device"
                        self.commandResultSubject.send(result)
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.commandResultSubject.send(DeviceCommandResult(
                        success: false,
                        deviceId: device.id,
                        command: .connect,
                        error: error.localizedDescription
                    ))
                }
            }
        }
    }
    
    /// Disconnect from a device
    func disconnectFromDevice(_ device: ManagedDevice) {
        Task {
            do {
                let result = try await performDisconnection(device)
                
                await MainActor.run {
                    if result.success {
                        self.deviceUpdateSubject.send(.disconnected(device))
                        self.commandResultSubject.send(result)
                    } else {
                        self.errorMessage = result.error ?? "Failed to disconnect from device"
                        self.commandResultSubject.send(result)
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.commandResultSubject.send(DeviceCommandResult(
                        success: false,
                        deviceId: device.id,
                        command: .disconnect,
                        error: error.localizedDescription
                    ))
                }
            }
        }
    }
    
    /// Execute a command on a device
    func executeCommand(_ command: DeviceCommand, on device: ManagedDevice, with heartPattern: HeartPattern? = nil) {
        Task {
            do {
                let result = try await performCommand(command, on: device, with: heartPattern)
                
                await MainActor.run {
                    self.commandResultSubject.send(result)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.commandResultSubject.send(DeviceCommandResult(
                        success: false,
                        deviceId: device.id,
                        command: command,
                        error: error.localizedDescription
                    ))
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func performConnection(_ device: ManagedDevice) async throws -> DeviceCommandResult {
        switch device.type {
        case .bluetoothDoorLock:
            if let bluetoothLock = device.bluetoothLock {
                bluetoothService.connectToLock(bluetoothLock)
                return DeviceCommandResult(success: true, deviceId: device.id, command: .connect)
            }
        case .nfcTag:
            // NFC connection is handled automatically when scanning
            return DeviceCommandResult(success: true, deviceId: device.id, command: .connect)
        case .appleWatch:
            // Apple Watch connection is handled by WatchConnectivity
            return DeviceCommandResult(success: true, deviceId: device.id, command: .connect)
        case .enterpriseDevice:
            // Enterprise device connection requires Entra ID authentication
            guard entraIDService.isAuthenticated else {
                throw DeviceManagementError.notAuthenticated
            }
            return DeviceCommandResult(success: true, deviceId: device.id, command: .connect)
        }
        
        throw DeviceManagementError.unsupportedDevice
    }
    
    private func performDisconnection(_ device: ManagedDevice) async throws -> DeviceCommandResult {
        switch device.type {
        case .bluetoothDoorLock:
            if let bluetoothLock = device.bluetoothLock {
                bluetoothService.disconnectFromLock(bluetoothLock)
                return DeviceCommandResult(success: true, deviceId: device.id, command: .disconnect)
            }
        case .nfcTag:
            // NFC disconnection is handled automatically
            return DeviceCommandResult(success: true, deviceId: device.id, command: .disconnect)
        case .appleWatch:
            // Apple Watch disconnection is handled by WatchConnectivity
            return DeviceCommandResult(success: true, deviceId: device.id, command: .disconnect)
        case .enterpriseDevice:
            // Enterprise device disconnection
            return DeviceCommandResult(success: true, deviceId: device.id, command: .disconnect)
        }
        
        throw DeviceManagementError.unsupportedDevice
    }
    
    private func performCommand(_ command: DeviceCommand, on device: ManagedDevice, with heartPattern: HeartPattern?) async throws -> DeviceCommandResult {
        // Authenticate if required
        if command.requiresAuthentication {
            guard let pattern = heartPattern else {
                throw DeviceManagementError.authenticationRequired
            }
            
            let authResult = try await authenticateWithDevice(device, using: pattern)
            guard authResult.success else {
                throw DeviceManagementError.authenticationFailed
            }
        }
        
        // Execute command based on device type
        switch device.type {
        case .bluetoothDoorLock:
            return try await executeBluetoothCommand(command, on: device, with: heartPattern)
        case .nfcTag:
            return try await executeNFCCommand(command, on: device, with: heartPattern)
        case .appleWatch:
            return try await executeWatchCommand(command, on: device, with: heartPattern)
        case .enterpriseDevice:
            return try await executeEnterpriseCommand(command, on: device, with: heartPattern)
        }
    }
    
    private func executeBluetoothCommand(_ command: DeviceCommand, on device: ManagedDevice, with heartPattern: HeartPattern?) async throws -> DeviceCommandResult {
        guard let bluetoothLock = device.bluetoothLock else {
            throw DeviceManagementError.invalidDevice
        }
        
        switch command {
        case .unlock:
            if let pattern = heartPattern {
                bluetoothService.unlockDoor(bluetoothLock, with: pattern)
            }
            return DeviceCommandResult(success: true, deviceId: device.id, command: command)
        case .lock:
            bluetoothService.lockDoor(bluetoothLock)
            return DeviceCommandResult(success: true, deviceId: device.id, command: command)
        case .status:
            bluetoothService.checkLockStatus(bluetoothLock)
            return DeviceCommandResult(success: true, deviceId: device.id, command: command)
        default:
            throw DeviceManagementError.unsupportedCommand
        }
    }
    
    private func executeNFCCommand(_ command: DeviceCommand, on device: ManagedDevice, with heartPattern: HeartPattern?) async throws -> DeviceCommandResult {
        switch command {
        case .read:
            // Read NFC tag data
            return DeviceCommandResult(success: true, deviceId: device.id, command: command)
        case .write:
            // Write data to NFC tag
            return DeviceCommandResult(success: true, deviceId: device.id, command: command)
        case .authenticate:
            if let pattern = heartPattern {
                // Authenticate with NFC using heart pattern
                return DeviceCommandResult(success: true, deviceId: device.id, command: command)
            }
            throw DeviceManagementError.authenticationRequired
        default:
            throw DeviceManagementError.unsupportedCommand
        }
    }
    
    private func executeWatchCommand(_ command: DeviceCommand, on device: ManagedDevice, with heartPattern: HeartPattern?) async throws -> DeviceCommandResult {
        // Apple Watch commands are handled by WatchConnectivityService
        // For now, we'll simulate the command execution
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        return DeviceCommandResult(success: true, deviceId: device.id, command: command)
    }
    
    private func executeEnterpriseCommand(_ command: DeviceCommand, on device: ManagedDevice, with heartPattern: HeartPattern?) async throws -> DeviceCommandResult {
        // Enterprise device commands require Entra ID authentication
        guard entraIDService.isAuthenticated else {
            throw DeviceManagementError.notAuthenticated
        }
        
        // Execute enterprise-specific command
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        return DeviceCommandResult(success: true, deviceId: device.id, command: command)
    }
    
    private func authenticateWithDevice(_ device: ManagedDevice, using heartPattern: HeartPattern) async throws -> DeviceAuthResult {
        // Authenticate with device using heart pattern
        // This would involve sending the heart pattern to the device for verification

        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Simulate authentication success
        let success = heartPattern.confidence > 0.7

        return DeviceAuthResult(
            success: success,
            deviceId: device.id,
            token: success ? try encryptionService.generateRandomString(length: 32) : nil,
            expiresAt: success ? Date().addingTimeInterval(300) : nil
        )
    }
    
    // MARK: - Device Updates
    
    private func updateAvailableDevices() {
        var devices: [ManagedDevice] = []
        
        // Add Bluetooth door locks
        for lock in bluetoothService.discoveredLocks {
            devices.append(ManagedDevice(
                name: lock.name,
                type: DeviceType.bluetoothDoorLock,
                status: iPhoneDeviceStatus.discovered,
                bluetoothLock: lock
            ))
        }
        
        // Add NFC tags
        if let nfcTag = nfcService.lastScannedTag {
            devices.append(ManagedDevice(
                name: "NFC Tag",
                type: DeviceType.nfcTag,
                status: iPhoneDeviceStatus.discovered,
                nfcTag: nfcTag
            ))
        }
        
        // Add Apple Watch
        devices.append(ManagedDevice(
            name: "Apple Watch",
            type: DeviceType.appleWatch,
            status: iPhoneDeviceStatus.discovered
        ))
        
        // Add enterprise devices
        if entraIDService.isAuthenticated {
            devices.append(ManagedDevice(
                name: "Enterprise Device",
                type: DeviceType.enterpriseDevice,
                status: iPhoneDeviceStatus.discovered
            ))
        }
        
        availableDevices = devices
    }
    
    private func updateConnectedDevices() {
        var devices: [ManagedDevice] = []
        
        // Add connected Bluetooth door locks
        for lock in bluetoothService.connectedLocks {
            devices.append(ManagedDevice(
                name: lock.name,
                type: DeviceType.bluetoothDoorLock,
                status: iPhoneDeviceStatus.connected,
                bluetoothLock: lock
            ))
        }
        
        // Add other connected devices
        // This would include Apple Watch, enterprise devices, etc.
        
        connectedDevices = devices
    }
    
    private func handleNFCTag(_ tag: NFCTagData) {
        // Handle NFC tag discovery
        let device = ManagedDevice(
            name: "NFC Tag",
            type: DeviceType.nfcTag,
            status: iPhoneDeviceStatus.discovered,
            nfcTag: tag
        )
        
        if !availableDevices.contains(where: { $0.id == device.id }) {
            availableDevices.append(device)
        }
    }
    
    private func syncEnterpriseDevices() {
        // Sync enterprise devices from Entra ID
        // This would fetch devices from the enterprise directory
        updateAvailableDevices()
    }
    
    // MARK: - Data Persistence
    
    private func loadStoredDevices() {
        // Load previously connected devices from storage
        if let data = keychain.retrieveData(forKey: "stored_devices"),
           let devices = try? JSONDecoder().decode([ManagedDevice].self, from: data) {
            connectedDevices = devices
        }
    }
    
    private func saveStoredDevices() {
        // Save connected devices to storage
        if let data = try? JSONEncoder().encode(connectedDevices) {
            keychain.store(data, forKey: "stored_devices")
        }
    }
    
    // MARK: - Error Handling

    func clearError() {
        errorMessage = nil
    }
}

// MARK: - Supporting Types

struct ManagedDevice: Codable, Identifiable {
    let id: UUID
    let name: String
    let type: DeviceType
    let status: iPhoneDeviceStatus
    let bluetoothLock: BluetoothDoorLock?
    let nfcTag: NFCTagData?
    let lastSeen: Date?
    let capabilities: [DeviceCapability]
    
    enum CodingKeys: String, CodingKey {
        case id, name, type, status, lastSeen, capabilities
    }
    
    init(id: UUID = UUID(), name: String, type: DeviceType, status: iPhoneDeviceStatus, bluetoothLock: BluetoothDoorLock? = nil, nfcTag: NFCTagData? = nil, lastSeen: Date? = nil, capabilities: [DeviceCapability] = []) {
        self.id = id
        self.name = name
        self.type = type
        self.status = status
        self.bluetoothLock = bluetoothLock
        self.nfcTag = nfcTag
        self.lastSeen = lastSeen
        self.capabilities = capabilities
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(DeviceType.self, forKey: .type)
        status = try container.decode(iPhoneDeviceStatus.self, forKey: .status)
        lastSeen = try container.decodeIfPresent(Date.self, forKey: .lastSeen)
        capabilities = try container.decodeIfPresent([DeviceCapability].self, forKey: .capabilities) ?? []
        bluetoothLock = nil
        nfcTag = nil
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(lastSeen, forKey: .lastSeen)
        try container.encode(capabilities, forKey: .capabilities)
    }
}

enum DeviceType: String, Codable, CaseIterable {
    case bluetoothDoorLock = "bluetooth_door_lock"
    case nfcTag = "nfc_tag"
    case appleWatch = "apple_watch"
    case enterpriseDevice = "enterprise_device"
}

enum iPhoneDeviceStatus: String, Codable, CaseIterable {
    case discovered = "discovered"
    case connected = "connected"
    case disconnected = "disconnected"
    case error = "error"
}

enum DeviceCapability: String, Codable, CaseIterable {
    case unlock = "unlock"
    case lock = "lock"
    case read = "read"
    case write = "write"
    case authenticate = "authenticate"
    case status = "status"
    case battery = "battery"
}

enum DeviceCommand: String, Codable, CaseIterable {
    case connect = "connect"
    case disconnect = "disconnect"
    case unlock = "unlock"
    case lock = "lock"
    case read = "read"
    case write = "write"
    case authenticate = "authenticate"
    case status = "status"
    case battery = "battery"
    
    var requiresAuthentication: Bool {
        switch self {
        case .unlock, .write, .authenticate:
            return true
        default:
            return false
        }
    }
}

enum DeviceUpdate {
    case connected(ManagedDevice)
    case disconnected(ManagedDevice)
    case statusChanged(ManagedDevice, iPhoneDeviceStatus)
    case error(ManagedDevice, String)
}

struct DeviceCommandResult {
    let success: Bool
    let deviceId: UUID
    let command: DeviceCommand
    let error: String?
    let data: Data?
    
    init(success: Bool, deviceId: UUID, command: DeviceCommand, error: String? = nil, data: Data? = nil) {
        self.success = success
        self.deviceId = deviceId
        self.command = command
        self.error = error
        self.data = data
    }
}

struct DeviceAuthResult {
    let success: Bool
    let deviceId: UUID
    let token: String?
    let expiresAt: Date?
}

enum DeviceManagementError: Error, LocalizedError {
    case notAuthenticated
    case authenticationRequired
    case authenticationFailed
    case unsupportedDevice
    case unsupportedCommand
    case invalidDevice
    case connectionFailed
    case commandFailed
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated with enterprise"
        case .authenticationRequired:
            return "Authentication required for this command"
        case .authenticationFailed:
            return "Authentication failed"
        case .unsupportedDevice:
            return "Unsupported device type"
        case .unsupportedCommand:
            return "Unsupported command for this device"
        case .invalidDevice:
            return "Invalid device"
        case .connectionFailed:
            return "Failed to connect to device"
        case .commandFailed:
            return "Command failed to execute"
        case .unknown:
            return "Unknown error"
        }
    }
}
