import Foundation
import SwiftUI

// MARK: - Device Management Types

struct ManagedDevice: Identifiable {
    let id = UUID()
    let name: String
    let type: DeviceType
    let status: DeviceStatus
    let lastSeen: Date
    let batteryLevel: Int?
    let isConnected: Bool
    let capabilities: Set<DeviceCapability>
    
    init(name: String, type: DeviceType, status: DeviceStatus) {
        self.name = name
        self.type = type
        self.status = status
        self.lastSeen = Date()
        self.batteryLevel = Int.random(in: 20...100)
        self.isConnected = status == .connected
        self.capabilities = type.defaultCapabilities
    }
}

enum DeviceType: CaseIterable {
    case iPhone
    case appleWatch
    case bluetoothLock
    case nfcReader
    case enterpriseDevice
    
    var displayName: String {
        switch self {
        case .iPhone: return "iPhone"
        case .appleWatch: return "Apple Watch"
        case .bluetoothLock: return "Bluetooth Lock"
        case .nfcReader: return "NFC Reader"
        case .enterpriseDevice: return "Enterprise Device"
        }
    }
    
    var systemImage: String {
        switch self {
        case .iPhone: return "iphone"
        case .appleWatch: return "applewatch"
        case .bluetoothLock: return "lock.shield"
        case .nfcReader: return "wave.3.right"
        case .enterpriseDevice: return "building.2"
        }
    }
    
    var defaultCapabilities: Set<DeviceCapability> {
        switch self {
        case .iPhone:
            return [.heartAuthentication, .biometricAuth, .networkAuth]
        case .appleWatch:
            return [.heartAuthentication, .proximityAuth]
        case .bluetoothLock:
            return [.physicalAccess, .remoteControl]
        case .nfcReader:
            return [.nfcCommunication, .dataExchange]
        case .enterpriseDevice:
            return [.networkAuth, .dataSync, .remoteManagement]
        }
    }
}

enum DeviceStatus {
    case discovered
    case connecting
    case connected
    case disconnected
    case error
    
    var displayName: String {
        switch self {
        case .discovered: return "Discovered"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        case .error: return "Error"
        }
    }
    
    var color: Color {
        switch self {
        case .discovered: return .blue
        case .connecting: return .orange
        case .connected: return .green
        case .disconnected: return .gray
        case .error: return .red
        }
    }
}

enum DeviceCapability: CaseIterable {
    case heartAuthentication
    case biometricAuth
    case networkAuth
    case proximityAuth
    case physicalAccess
    case remoteControl
    case nfcCommunication
    case dataExchange
    case dataSync
    case remoteManagement
    
    var displayName: String {
        switch self {
        case .heartAuthentication: return "Heart Authentication"
        case .biometricAuth: return "Biometric Authentication"
        case .networkAuth: return "Network Authentication"
        case .proximityAuth: return "Proximity Authentication"
        case .physicalAccess: return "Physical Access"
        case .remoteControl: return "Remote Control"
        case .nfcCommunication: return "NFC Communication"
        case .dataExchange: return "Data Exchange"
        case .dataSync: return "Data Synchronization"
        case .remoteManagement: return "Remote Management"
        }
    }
}

enum DeviceCommand {
    case connect
    case disconnect
    case authenticate
    case lock
    case unlock
    case status
    case heartPattern
    
    var displayName: String {
        switch self {
        case .connect: return "Connect"
        case .disconnect: return "Disconnect"
        case .authenticate: return "Authenticate"
        case .lock: return "Lock"
        case .unlock: return "Unlock"
        case .status: return "Get Status"
        case .heartPattern: return "Heart Pattern"
        }
    }
}

struct DeviceCommandResult {
    let success: Bool
    let deviceId: UUID
    let command: DeviceCommand
    let message: String?
    let timestamp: Date
    
    init(success: Bool, deviceId: UUID, command: DeviceCommand, message: String? = nil) {
        self.success = success
        self.deviceId = deviceId
        self.command = command
        self.message = message
        self.timestamp = Date()
    }
}

// MARK: - NFC Types

struct NFCTagData: Identifiable {
    let id = UUID()
    let identifier: String
    let type: NFCTagType
    let data: Data
    let timestamp: Date
    let isEncrypted: Bool
    
    init(identifier: String, type: NFCTagType, data: Data, isEncrypted: Bool = false) {
        self.identifier = identifier
        self.type = type
        self.data = data
        self.timestamp = Date()
        self.isEncrypted = isEncrypted
    }
}

enum NFCTagType {
    case heartPattern
    case accessCard
    case credentials
    case generic
    
    var displayName: String {
        switch self {
        case .heartPattern: return "Heart Pattern"
        case .accessCard: return "Access Card"
        case .credentials: return "Credentials"
        case .generic: return "Generic Data"
        }
    }
}

struct NFCAuthResult {
    let success: Bool
    let user: EntraIDUser?
    let permissions: [NFCPermission]
    let expiresAt: Date?
    let error: String?
    
    init(success: Bool, user: EntraIDUser? = nil, permissions: [NFCPermission] = [], expiresAt: Date? = nil, error: String? = nil) {
        self.success = success
        self.user = user
        self.permissions = permissions
        self.expiresAt = expiresAt
        self.error = error
    }
}

// MARK: - Bluetooth Types

class BluetoothDoorLock: ObservableObject, Identifiable {
    let id = UUID()
    let name: String
    let identifier: String
    @Published var isConnected: Bool = false
    @Published var batteryLevel: Int?
    @Published var lockState: DoorLockState = .unknown
    @Published var rssi: Int = -50
    
    init(name: String, identifier: String) {
        self.name = name
        self.identifier = identifier
    }
}

// Add missing properties to existing services
extension BluetoothDoorLockService {
    var isBluetoothAvailable: Bool {
        return centralManager?.state == .poweredOn
    }
}

// MARK: - HeartID Colors

struct HeartIDColors {
    let primary = Color.blue
    let secondary = Color.gray
    let accent = Color.orange
    let success = Color.green
    let error = Color.red
    let warning = Color.yellow
    let text = Color.primary
    let background = Color(.systemBackground)
    let surface = Color(.systemGray6)
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.gray.opacity(0.2))
            .foregroundColor(.primary)
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}