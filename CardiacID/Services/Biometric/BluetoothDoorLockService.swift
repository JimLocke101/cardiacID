import Foundation
import CoreBluetooth
import Combine

/// Service for managing Bluetooth door locks and access control
class BluetoothDoorLockService: NSObject, ObservableObject {
    
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
    
    // MARK: - Heart Authentication
    private let authenticationService = HeartAuthenticationService.shared
    
    enum ConnectionStatus {
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
    
    // MARK: - Setup
    
    private func setupBluetoothManager() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
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
    
    func disconnectFromDevice(_ device: BluetoothDevice) {
        guard let peripheral = device.peripheral else { return }
        centralManager?.cancelPeripheralConnection(peripheral)
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
    
    private func performHeartAuthentication(_ heartData: Data) async throws -> Bool {
        // Simulate authentication process
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // In a real implementation, this would:
        // 1. Send heart pattern to door lock
        // 2. Door lock validates against stored patterns
        // 3. Returns success/failure
        
        return Bool.random() // Mock success/failure
    }
    
    private func unlockDoor() async throws {
        guard let peripheral = connectedPeripheral,
              let characteristic = lockCharacteristic else {
            throw BluetoothError.invalidDevice
        }
        
        // Send unlock command
        let unlockCommand = Data([0x01, 0x55, 0x4E, 0x4C, 0x4F, 0x43, 0x4B]) // "UNLOCK"
        peripheral.writeValue(unlockCommand, for: characteristic, type: .withResponse)
        
        print("🚪 Door unlock command sent")
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
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("✅ Bluetooth is powered on")
        case .poweredOff:
            errorMessage = "Bluetooth is powered off"
        case .resetting:
            errorMessage = "Bluetooth is resetting"
        case .unauthorized:
            errorMessage = "Bluetooth access denied"
        case .unsupported:
            errorMessage = "Bluetooth not supported"
        case .unknown:
            errorMessage = "Bluetooth state unknown"
        @unknown default:
            errorMessage = "Unknown Bluetooth state"
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        
        let device = BluetoothDevice(
            identifier: peripheral.identifier.uuidString,
            name: peripheral.name ?? "Unknown Device",
            peripheral: peripheral,
            rssi: RSSI.intValue,
            advertisementData: advertisementData
        )
        
        if !discoveredDevices.contains(where: { $0.identifier == device.identifier }) {
            discoveredDevices.append(device)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionStatus = .connected
        
        // Discover services
        peripheral.delegate = self
        peripheral.discoverServices([lockServiceUUID])
        
        // Add to connected devices
        let device = BluetoothDevice(
            identifier: peripheral.identifier.uuidString,
            name: peripheral.name ?? "Unknown Device",
            peripheral: peripheral,
            rssi: 0
        )
        
        if !connectedDevices.contains(where: { $0.identifier == device.identifier }) {
            connectedDevices.append(device)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionStatus = .failed(error?.localizedDescription ?? "Connection failed")
        errorMessage = "Failed to connect: \(error?.localizedDescription ?? "Unknown error")"
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionStatus = .disconnected
        connectedPeripheral = nil
        lockCharacteristic = nil
        
        // Remove from connected devices
        connectedDevices.removeAll { $0.identifier == peripheral.identifier.uuidString }
        
        if let error = error {
            errorMessage = "Disconnected with error: \(error.localizedDescription)"
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothDoorLockService: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            errorMessage = "Service discovery failed: \(error!.localizedDescription)"
            return
        }
        
        guard let services = peripheral.services else { return }
        
        for service in services {
            if service.uuid == lockServiceUUID {
                peripheral.discoverCharacteristics([unlockCharacteristicUUID], for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            errorMessage = "Characteristic discovery failed: \(error!.localizedDescription)"
            return
        }
        
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            if characteristic.uuid == unlockCharacteristicUUID {
                lockCharacteristic = characteristic
                print("🔓 Lock characteristic discovered")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            errorMessage = "Write failed: \(error.localizedDescription)"
        } else {
            print("✅ Successfully wrote to characteristic: \(characteristic.uuid)")
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

enum BluetoothError: Error, LocalizedError {
    case bluetoothUnavailable
    case notConnected
    case authenticationFailed
    case invalidDevice
    case transmissionFailed
    
    var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable:
            return "Bluetooth is not available on this device"
        case .notConnected:
            return "Not connected to any device"
        case .authenticationFailed:
            return "Heart pattern authentication failed"
        case .invalidDevice:
            return "Invalid or unsupported device"
        case .transmissionFailed:
            return "Failed to transmit data to device"
        }
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