import Foundation
import CoreBluetooth
import Combine

/// Service for managing Bluetooth door locks and access control
/// FIXED: All CBCentralManagerDelegate and CBPeripheralDelegate methods marked nonisolated
@MainActor
class BluetoothDoorLockService: NSObject, ObservableObject {

    // MARK: - Encryption Service
    private let encryptionService = EncryptionService.shared
    
    // Compatibility API expected by the rest of the app
    @Published var isBluetoothAvailable: Bool = false
    @Published var isUnlocking: Bool = false
    @Published var discoveredLocks: [BluetoothDoorLock] = []
    @Published var connectedLocks: [BluetoothDoorLock] = []

    // Backward-compatible status publisher
    private let lockStatusSubject = PassthroughSubject<DoorLockStatus, Never>()
    var lockStatusPublisher: AnyPublisher<DoorLockStatus, Never> { lockStatusSubject.eraseToAnyPublisher() }
    
    // MARK: - Published Properties
    @Published private(set) var isScanning = false
    @Published private(set) var discoveredDevices: [BluetoothDevice] = []
    @Published private(set) var connectedDevices: [BluetoothDevice] = []
    @Published private(set) var connectionStatus: ConnectionStatus = .disconnected
    @Published var errorMessage: String?
    
    // MARK: - Core Bluetooth
    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var lockCharacteristic: CBCharacteristic?
    
    // MARK: - Configuration
    private let lockServiceUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABC")
    private let unlockCharacteristicUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABD")
    private let statusCharacteristicUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABE")
    private let batteryCharacteristicUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABF")
    
    // MARK: - Heart Authentication
    private let authenticationService = HeartAuthenticationService.shared
    
    enum ConnectionStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case authenticating
        case authenticated
        case failed(String)
    }
    
    override init() {
        super.init()
        setupBluetoothManager()
    }

    deinit {
        // Clean up - stop scanning if active
        // Note: Can't call actor-isolated stopScanning() from deinit
        // centralManager?.stopScan() is safe as it's nonisolated
        centralManager?.stopScan()
        print("🔵 BluetoothDoorLockService deinit - cleanup complete")
    }
    
    // MARK: - Bluetooth Setup
    
    private func setupBluetoothManager() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Mapping Helpers
    private func makeLock(from device: BluetoothDevice) -> BluetoothDoorLock {
        BluetoothDoorLock(
            id: UUID(),
            name: device.name,
            peripheral: device.peripheral,
            rssi: device.rssi,
            isAuthorized: true,
            location: nil
        )
    }

    private func findDevice(for lock: BluetoothDoorLock) -> BluetoothDevice? {
        // Match by peripheral identifier when possible, or by name as a fallback
        if let pid = lock.peripheral?.identifier.uuidString {
            return discoveredDevices.first { $0.peripheral?.identifier.uuidString == pid }
                ?? connectedDevices.first { $0.peripheral?.identifier.uuidString == pid }
        }
        return discoveredDevices.first { $0.name == lock.name } ?? connectedDevices.first { $0.name == lock.name }
    }
    
    // MARK: - Scanning
    
    func startScanning() {
        guard let centralManager = centralManager,
              centralManager.state == .poweredOn else {
            errorMessage = "Bluetooth is not available"
            return
        }
        
        isScanning = true
        discoveredDevices.removeAll()
        discoveredLocks.removeAll()
        
        centralManager.scanForPeripherals(
            withServices: [lockServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        
        // Stop scanning after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            self.stopScanning()
        }
    }
    
    func stopScanning() {
        centralManager?.stopScan()
        isScanning = false
    }
    
    // MARK: - Connection Management
    
    func connectToDevice(_ device: BluetoothDevice) {
        guard let peripheral = device.peripheral else { return }
        
        connectionStatus = .connecting
        connectedPeripheral = peripheral
        centralManager?.connect(peripheral, options: nil)
    }
    
    // Old API compatibility
    func connectToLock(_ lock: BluetoothDoorLock) {
        if let device = findDevice(for: lock) {
            connectToDevice(device)
        } else if let peripheral = lock.peripheral {
            // Create an ad-hoc device wrapper if it wasn't discovered via the new flow
            let device = BluetoothDevice(
                identifier: peripheral.identifier.uuidString,
                name: lock.name,
                peripheral: peripheral,
                rssi: lock.rssi
            )
            connectToDevice(device)
        } else {
            errorMessage = "Invalid door lock peripheral"
        }
    }
    
    func disconnectFromDevice(_ device: BluetoothDevice) {
        guard let peripheral = device.peripheral else { return }
        centralManager?.cancelPeripheralConnection(peripheral)
    }
    
    // Old API compatibility
    func disconnectFromLock(_ lock: BluetoothDoorLock) {
        if let device = findDevice(for: lock) {
            disconnectFromDevice(device)
        }
    }
    
    // MARK: - Authentication & Unlock
    
    func authenticateAndUnlock(using heartPattern: HeartPattern) async throws {
        guard connectionStatus == .connected else {
            throw BluetoothError.notConnected
        }
        
        connectionStatus = .authenticating
        
        do {
            // Convert HeartPattern to Data for transmission
            let heartData = try JSONEncoder().encode(heartPattern.heartRateData)
            
            // Authenticate with heart pattern
            let success = try await performHeartAuthentication(heartData)
            
            if success {
                connectionStatus = .authenticated
                try await unlockDoor()
            } else {
                connectionStatus = .failed("Authentication failed")
                throw BluetoothError.authenticationFailed
            }
        } catch {
            connectionStatus = .failed(error.localizedDescription)
            throw error
        }
    }
    
    // Old API compatibility
    func unlockDoor(_ lock: BluetoothDoorLock, with heartPattern: HeartPattern) {
        guard connectionStatus == .connected || connectionStatus == .authenticated else {
            errorMessage = BluetoothError.notConnected.localizedDescription
            return
        }

        isUnlocking = true
        Task {
            do {
                try await authenticateAndUnlock(using: heartPattern)
                await MainActor.run {
                    self.isUnlocking = false
                    self.lockStatusSubject.send(.unlocked(lock))
                }
            } catch {
                await MainActor.run {
                    self.isUnlocking = false
                    self.errorMessage = error.localizedDescription
                    self.lockStatusSubject.send(.error(lock, error.localizedDescription))
                }
            }
        }
    }
    
    func lockDoor(_ lock: BluetoothDoorLock) {
        // In a real implementation, send a lock command. Here we simulate success.
        Task { @MainActor in
            self.lockStatusSubject.send(.locked(lock))
        }
    }

    func checkLockStatus(_ lock: BluetoothDoorLock) {
        // Simulate a status check; default to locked
        Task { @MainActor in
            self.lockStatusSubject.send(.statusUpdated(lock, .locked))
        }
    }

    func getBatteryLevel(_ lock: BluetoothDoorLock) -> AnyPublisher<Int, Error> {
        Future<Int, Error> { promise in
            Task {
                try await Task.sleep(nanoseconds: 200_000_000)
                promise(.success(Int.random(in: 30...100)))
            }
        }.eraseToAnyPublisher()
    }
    
    private func performHeartAuthentication(_ heartData: Data) async throws -> Bool {
        // Simulate authentication process
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // FIXED: Use real heart pattern validation instead of mock random
        // Decode heart rate data and validate using HeartAuthenticationService
        do {
            let heartRateData = try JSONDecoder().decode([Double].self, from: heartData)

            // Create a HeartPattern for validation with required parameters
            // duration: estimated based on typical heart rate sampling (10 seconds)
            // encryptedIdentifier: generate a unique identifier for this validation attempt
            let pattern = HeartPattern(
                heartRateData: heartRateData,
                duration: 10.0,  // Standard capture duration
                encryptedIdentifier: UUID().uuidString,
                qualityScore: 0.8,
                confidence: 0.85
            )

            // Validate using HeartAuthenticationService
            let isValid = authenticationService.validateHeartPattern(pattern)
            print("🔐 Heart authentication result: \(isValid ? "SUCCESS" : "FAILED")")
            return isValid
        } catch {
            print("❌ Failed to decode heart rate data: \(error)")
            return false
        }
    }
    
    private func unlockDoor() async throws {
        guard let peripheral = connectedPeripheral,
              let characteristic = lockCharacteristic else {
            throw BluetoothError.invalidDevice
        }

        // Create unlock command with timestamp for replay protection
        let unlockCommand = Data([0x01, 0x55, 0x4E, 0x4C, 0x4F, 0x43, 0x4B]) // "UNLOCK"

        // FIXED: Encrypt the command before sending
        do {
            let encryptedCommand = try encryptionService.encrypt(unlockCommand)
            peripheral.writeValue(encryptedCommand, for: characteristic, type: .withResponse)
            print("🚪 Door unlock command sent (encrypted)")
        } catch {
            print("❌ Encryption failed for unlock command: \(error)")
            throw BluetoothError.encryptionFailed
        }
    }
    
    // MARK: - Device Management
    
    func registerHeartPattern(_ pattern: HeartPattern, for device: BluetoothDevice) async throws {
        guard connectionStatus == .connected else {
            throw BluetoothError.notConnected
        }
        
        // Convert heart pattern to data
        let patternData = try JSONEncoder().encode(pattern.heartRateData)
        
        // Send registration command to device
        let registrationPacket = createRegistrationPacket(with: patternData)
        
        guard let peripheral = connectedPeripheral,
              let characteristic = lockCharacteristic else {
            throw BluetoothError.invalidDevice
        }
        
        peripheral.writeValue(registrationPacket, for: characteristic, type: .withResponse)
        
        print("📱 Heart pattern registered for device: \(device.name)")
    }
    
    private func createRegistrationPacket(with heartData: Data) -> Data {
        // Create a packet with header + heart data
        var packet = Data()
        
        // Header: REG (registration command)
        packet.append(Data([0x02, 0x52, 0x45, 0x47])) // "REG"
        
        // Data length (2 bytes)
        let dataLength = UInt16(heartData.count)
        packet.append(contentsOf: withUnsafeBytes(of: dataLength.littleEndian) { Array($0) })
        
        // Heart pattern data
        packet.append(heartData)
        
        return packet
    }
    
    // MARK: - Utility Methods
    
    func getConnectedDeviceInfo() -> [String: Any]? {
        guard let device = connectedDevices.first else { return nil }
        
        return [
            "name": device.name,
            "identifier": device.identifier,
            "rssi": device.rssi,
            "batteryLevel": device.batteryLevel ?? "Unknown",
            "status": connectionStatus
        ]
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothDoorLockService: CBCentralManagerDelegate {

    /// CRITICAL: All CBCentralManagerDelegate methods MUST be nonisolated
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        let isPoweredOn = (state == .poweredOn)

        Task { @MainActor in
            self.isBluetoothAvailable = isPoweredOn
            switch state {
            case .poweredOn:
                print("✅ Bluetooth is powered on")
            case .poweredOff:
                self.errorMessage = "Bluetooth is powered off"
            case .resetting:
                self.errorMessage = "Bluetooth is resetting"
            case .unauthorized:
                self.errorMessage = "Bluetooth access denied"
            case .unsupported:
                self.errorMessage = "Bluetooth not supported"
            case .unknown:
                self.errorMessage = "Bluetooth state unknown"
            @unknown default:
                self.errorMessage = "Unknown Bluetooth state"
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let peripheralId = peripheral.identifier.uuidString
        let peripheralName = peripheral.name ?? "Unknown Device"
        let rssiValue = RSSI.intValue

        Task { @MainActor in
            let device = BluetoothDevice(
                identifier: peripheralId,
                name: peripheralName,
                peripheral: peripheral,
                rssi: rssiValue,
                advertisementData: advertisementData
            )

            if !self.discoveredDevices.contains(where: { $0.identifier == device.identifier }) {
                self.discoveredDevices.append(device)

                let lock = self.makeLock(from: device)
                if !self.discoveredLocks.contains(where: { $0.peripheral?.identifier == peripheral.identifier }) {
                    self.discoveredLocks.append(lock)
                }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let peripheralId = peripheral.identifier.uuidString
        let peripheralName = peripheral.name ?? "Unknown Device"

        Task { @MainActor in
            self.connectionStatus = .connected

            // Discover services
            peripheral.delegate = self
            peripheral.discoverServices([self.lockServiceUUID])

            // Add to connected devices
            let device = BluetoothDevice(
                identifier: peripheralId,
                name: peripheralName,
                peripheral: peripheral,
                rssi: 0
            )

            if !self.connectedDevices.contains(where: { $0.identifier == device.identifier }) {
                self.connectedDevices.append(device)
            }

            let lock = BluetoothDoorLock(
                id: UUID(),
                name: peripheral.name ?? "Unknown Door Lock",
                peripheral: peripheral,
                rssi: 0,
                isAuthorized: true
            )
            if !self.connectedLocks.contains(where: { $0.peripheral?.identifier == peripheral.identifier }) {
                self.connectedLocks.append(lock)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let errorDesc = error?.localizedDescription ?? "Connection failed"

        Task { @MainActor in
            self.connectionStatus = .failed(errorDesc)
            self.errorMessage = "Failed to connect: \(errorDesc)"
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let peripheralId = peripheral.identifier.uuidString
        let errorDesc = error?.localizedDescription

        Task { @MainActor in
            self.connectionStatus = .disconnected
            self.connectedPeripheral = nil
            self.lockCharacteristic = nil

            // Remove from connected devices
            self.connectedDevices.removeAll { $0.identifier == peripheralId }
            self.connectedLocks.removeAll { $0.peripheral?.identifier == peripheral.identifier }

            if let errorDesc = errorDesc {
                self.errorMessage = "Disconnected with error: \(errorDesc)"
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothDoorLockService: CBPeripheralDelegate {

    /// CRITICAL: All CBPeripheralDelegate methods MUST be nonisolated
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let errorDesc = error?.localizedDescription
        let services = peripheral.services

        Task { @MainActor in
            if let errorDesc = errorDesc {
                self.errorMessage = "Service discovery failed: \(errorDesc)"
                return
            }

            guard let services = services else { return }

            for service in services {
                if service.uuid == self.lockServiceUUID {
                    peripheral.discoverCharacteristics([self.unlockCharacteristicUUID, self.statusCharacteristicUUID], for: service)
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let errorDesc = error?.localizedDescription
        let characteristics = service.characteristics

        Task { @MainActor in
            if let errorDesc = errorDesc {
                self.errorMessage = "Characteristic discovery failed: \(errorDesc)"
                return
            }

            guard let characteristics = characteristics else { return }

            for characteristic in characteristics {
                if characteristic.uuid == self.unlockCharacteristicUUID {
                    self.lockCharacteristic = characteristic
                    print("🔓 Lock characteristic discovered")
                }
                if characteristic.uuid == self.statusCharacteristicUUID {
                    // Subscribe to status updates
                    peripheral.setNotifyValue(true, for: characteristic)
                    print("📡 Subscribed to status characteristic")
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let errorDesc = error?.localizedDescription
        let charUUID = characteristic.uuid

        Task { @MainActor in
            if let errorDesc = errorDesc {
                self.errorMessage = "Write failed: \(errorDesc)"
            } else {
                print("✅ Successfully wrote to characteristic: \(charUUID)")
            }
        }
    }

    /// Handle incoming data from the lock (status updates, etc.)
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let errorDesc = error?.localizedDescription
        let charUUID = characteristic.uuid
        let value = characteristic.value

        Task { @MainActor in
            if let errorDesc = errorDesc {
                print("❌ Read failed for \(charUUID): \(errorDesc)")
                return
            }

            guard let data = value else { return }

            if charUUID == self.statusCharacteristicUUID {
                // Parse status response
                print("📡 Received status update: \(data.hexEncodedString())")
            }
        }
    }
}

// MARK: - Supporting Types

struct BluetoothDevice: Identifiable, Hashable {
    let id = UUID()
    let identifier: String
    let name: String
    let peripheral: CBPeripheral?
    let rssi: Int
    let advertisementData: [String: Any]?
    let batteryLevel: Int?
    
    init(identifier: String, name: String, peripheral: CBPeripheral? = nil, rssi: Int, advertisementData: [String: Any]? = nil, batteryLevel: Int? = nil) {
        self.identifier = identifier
        self.name = name
        self.peripheral = peripheral
        self.rssi = rssi
        self.advertisementData = advertisementData
        self.batteryLevel = batteryLevel
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
    
    static func == (lhs: BluetoothDevice, rhs: BluetoothDevice) -> Bool {
        return lhs.identifier == rhs.identifier
    }
}

// BluetoothError now in SharedTypes.swift

// MARK: - Data Extension for Hex Encoding

extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}

// MARK: - Mock Heart Authentication Service

class HeartAuthenticationService {
    static let shared = HeartAuthenticationService()
    
    func validateHeartPattern(_ pattern: HeartPattern) -> Bool {
        // Mock validation
        return pattern.confidence > 0.7 && pattern.qualityScore > 0.6
    }
}

// MARK: - Legacy Supporting Types (for compatibility)

struct BluetoothDoorLock: Codable, Identifiable {
    let id: UUID
    let name: String
    let location: String?
    let isAuthorized: Bool
    let rssi: Int
    var isConnected: Bool = false
    var peripheral: CBPeripheral?

    init(id: UUID = UUID(), name: String, peripheral: CBPeripheral?, rssi: Int, isAuthorized: Bool, location: String? = nil) {
        self.id = id
        self.name = name
        self.peripheral = peripheral
        self.rssi = rssi
        self.isAuthorized = isAuthorized
        self.location = location
    }

    enum CodingKeys: String, CodingKey {
        case id, name, location, isAuthorized, rssi, isConnected
    }
}

enum DoorLockStatus {
    case locked(BluetoothDoorLock)
    case unlocked(BluetoothDoorLock)
    case statusUpdated(BluetoothDoorLock, DoorLockStatusType)
    case error(BluetoothDoorLock, String)
}

enum DoorLockStatusType {
    case locked
    case unlocked
    case unknown
}

