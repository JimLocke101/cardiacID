import Foundation
import CoreBluetooth
import Combine
import SwiftUI

@MainActor
class BluetoothDoorLockService: NSObject, ObservableObject, HoldableService {
    @Published var discoveredLocks: [BluetoothLock] = []
    @Published var connectedLocks: [BluetoothLock] = []
    @Published var isScanning = false
    @Published var errorMessage: String?
    @Published var serviceState: ServiceState = .available
    @Published var holdInfo: HoldStateInfo?
    @Published var lastError: Error?
    
    private var centralManager: CBCentralManager?
    private let serviceStateManager = ServiceStateManager.shared
    private var scanTimer: Timer?
    
    override init() {
        super.init()
        setupBluetooth()
        serviceStateManager.registerService(ServiceStateManager.bluetoothService, initialState: .available)
    }
    
    private func setupBluetooth() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        guard serviceState != .hold else {
            errorMessage = "Bluetooth service is on hold"
            return
        }
        
        guard let centralManager = centralManager, centralManager.state == .poweredOn else {
            putOnHold(reason: .permissionsRequired)
            return
        }
        
        isScanning = true
        updateServiceState(.connecting)
        
        // Start scanning for door lock services
        centralManager.scanForPeripherals(withServices: [BluetoothLock.serviceUUID], options: nil)
        
        // Stop scanning after 30 seconds
        scanTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            self?.stopScanning()
        }
    }
    
    func stopScanning() {
        centralManager?.stopScan()
        isScanning = false
        scanTimer?.invalidate()
        updateServiceState(.available)
    }
    
    func connect(to lock: BluetoothLock) async throws {
        guard serviceState != .hold else {
            throw BluetoothError.serviceOnHold
        }
        
        guard let centralManager = centralManager else {
            throw BluetoothError.notInitialized
        }
        
        updateServiceState(.connecting)
        
        // Simulate connection process
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        if Bool.random() { // Simulate success/failure
            lock.connectionState = .connected
            if !connectedLocks.contains(where: { $0.id == lock.id }) {
                connectedLocks.append(lock)
            }
            updateServiceState(.connected)
        } else {
            throw BluetoothError.connectionFailed
        }
    }
    
    func disconnect(from lock: BluetoothLock) async {
        lock.connectionState = .disconnected
        connectedLocks.removeAll { $0.id == lock.id }
        
        if connectedLocks.isEmpty {
            updateServiceState(.available)
        }
    }
    
    func sendCommand(_ command: DoorLockCommand, to lock: BluetoothLock) async throws -> Bool {
        guard lock.connectionState == .connected else {
            throw BluetoothError.notConnected
        }
        
        guard serviceState != .hold else {
            throw BluetoothError.serviceOnHold
        }
        
        // Simulate command execution
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        return Bool.random() // Simulate success/failure
    }
    
    // MARK: - HoldableService Implementation
    
    func putOnHold(reason: HoldStateInfo) {
        holdInfo = reason
        updateServiceState(.hold)
        errorMessage = reason.reason
        
        // Stop scanning and disconnect all devices
        stopScanning()
        
        Task {
            for lock in connectedLocks {
                await disconnect(from: lock)
            }
        }
    }
    
    func resumeFromHold() async throws {
        guard serviceState == .hold else { return }
        
        holdInfo = nil
        errorMessage = nil
        lastError = nil
        
        // Check if we can resume
        guard let centralManager = centralManager else {
            setupBluetooth()
            return
        }
        
        if centralManager.state == .poweredOn {
            updateServiceState(.available)
            print("✅ Bluetooth service resumed from hold")
        } else {
            updateServiceState(.unavailable)
        }
    }
    
    func checkAvailability() async -> Bool {
        return centralManager?.state == .poweredOn
    }
    
    private func updateServiceState(_ state: ServiceState) {
        serviceState = state
        serviceStateManager.updateServiceState(
            ServiceStateManager.bluetoothService,
            to: state,
            holdInfo: holdInfo
        )
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothDoorLockService: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                updateServiceState(.available)
            case .poweredOff:
                putOnHold(reason: HoldStateInfo(
                    reason: "Bluetooth is turned off",
                    suggestedAction: "Turn on Bluetooth in Settings",
                    canRetry: true,
                    estimatedResolution: nil
                ))
            case .unauthorized:
                putOnHold(reason: .permissionsRequired)
            case .unsupported:
                updateServiceState(.unavailable)
            case .resetting:
                updateServiceState(.connecting)
            case .unknown:
                updateServiceState(.unavailable)
            @unknown default:
                updateServiceState(.unavailable)
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            let lock = BluetoothLock(peripheral: peripheral, rssi: RSSI.intValue)
            
            if !discoveredLocks.contains(where: { $0.id == lock.id }) {
                discoveredLocks.append(lock)
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            if let lock = discoveredLocks.first(where: { $0.peripheral.identifier == peripheral.identifier }) {
                lock.connectionState = .connected
                if !connectedLocks.contains(where: { $0.id == lock.id }) {
                    connectedLocks.append(lock)
                }
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            if let lock = connectedLocks.first(where: { $0.peripheral.identifier == peripheral.identifier }) {
                await disconnect(from: lock)
            }
            
            if let error = error {
                lastError = error
                errorMessage = "Device disconnected: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Supporting Types

class BluetoothLock: ObservableObject, Identifiable {
    let id = UUID()
    let peripheral: CBPeripheral
    let name: String
    let rssi: Int
    @Published var connectionState: ConnectionState = .disconnected
    @Published var batteryLevel: Int?
    @Published var lockState: DoorLockState = .unknown
    
    static let serviceUUID = CBUUID(string: "180F") // Battery service as example
    
    init(peripheral: CBPeripheral, rssi: Int) {
        self.peripheral = peripheral
        self.name = peripheral.name ?? "Unknown Lock"
        self.rssi = rssi
    }
}

enum ConnectionState {
    case disconnected
    case connecting
    case connected
}

enum DoorLockState {
    case locked
    case unlocked
    case jammed
    case unknown
}

enum DoorLockCommand {
    case lock
    case unlock
    case status
}

enum BluetoothError: LocalizedError {
    case notInitialized
    case notConnected
    case connectionFailed
    case serviceOnHold
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Bluetooth service not initialized"
        case .notConnected:
            return "Device not connected"
        case .connectionFailed:
            return "Failed to connect to device"
        case .serviceOnHold:
            return "Bluetooth service is on hold"
        case .permissionDenied:
            return "Bluetooth permission denied"
        }
    }
}