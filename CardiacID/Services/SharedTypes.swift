//
//  SharedTypes.swift
//  CardiacID
//
//  Shared type definitions used across multiple services
//  ONLY types that don't have a natural home in Models/ or a specific service
//

import Foundation

// MARK: - Device Management Types

struct ManagedDevice: Identifiable, Codable {
    let id: UUID
    let name: String
    let type: DeviceType
    var status: DeviceStatus
    var lastSeen: Date?
    let macAddress: String?
    var batteryLevel: Double?
    var isOnline: Bool
    let capabilities: [DeviceCapability]
    var nfcTagData: NFCTagData?

    // Non-codable properties for device references
    var bluetoothLock: BluetoothDoorLock?
    var nfcTag: NFCTagData?

    init(id: UUID = UUID(), name: String, type: DeviceType, status: DeviceStatus = .discovered, lastSeen: Date? = nil, macAddress: String? = nil, batteryLevel: Double? = nil, isOnline: Bool = false, capabilities: [DeviceCapability] = [], nfcTagData: NFCTagData? = nil, bluetoothLock: BluetoothDoorLock? = nil, nfcTag: NFCTagData? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.status = status
        self.lastSeen = lastSeen
        self.macAddress = macAddress
        self.batteryLevel = batteryLevel
        self.isOnline = isOnline
        self.capabilities = capabilities
        self.nfcTagData = nfcTagData
        self.bluetoothLock = bluetoothLock
        self.nfcTag = nfcTag
    }

    enum CodingKeys: String, CodingKey {
        case id, name, type, status, lastSeen, macAddress, batteryLevel, isOnline, capabilities, nfcTagData
    }
}

enum DeviceType: String, Codable {
    case bluetoothLock
    case bluetoothDoorLock  // Alias for bluetoothLock
    case nfcReader
    case nfcTag
    case heartIDDevice
    case smartphone
    case appleWatch
    case enterpriseDevice
    case other
}

enum DeviceStatus: String, Codable, CaseIterable {
    case active = "active"
    case inactive = "inactive"
    case connected = "connected"
    case disconnected = "disconnected"
    case discovered = "discovered"
    case error = "error"

    var displayName: String {
        switch self {
        case .active: return "Active"
        case .inactive: return "Inactive"
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        case .discovered: return "Discovered"
        case .error: return "Error"
        }
    }
}

enum DeviceCapability: String, Codable, CaseIterable {
    case heartRateMonitoring = "heart_rate_monitoring"
    case nfcReading = "nfc_reading"
    case bluetoothComm = "bluetooth_communication"
    case biometricAuth = "biometric_authentication"
    case doorLock = "door_lock"
    case authenticate = "authenticate"
    case unlock = "unlock"
    case lock = "lock"
    case status = "status"
    case battery = "battery"
    case read = "read"
    case write = "write"
}

enum DeviceCommand: String, Codable {
    case lock
    case unlock
    case authenticate
    case scan
    case pair
    case status
}

struct DeviceUpdate {
    let deviceAdded: ManagedDevice?
    let deviceUpdated: ManagedDevice?
    let deviceRemoved: ManagedDevice?
    let allDevices: [ManagedDevice]
}

struct DeviceCommandResult {
    let success: Bool
    let deviceId: UUID?
    let command: DeviceCommand
    let message: String?
    let error: String?

    init(success: Bool, deviceId: UUID? = nil, command: DeviceCommand, message: String? = nil, error: String? = nil) {
        self.success = success
        self.deviceId = deviceId
        self.command = command
        self.message = message
        self.error = error
    }
}

struct DeviceAuthResult {
    let success: Bool
    let deviceId: UUID
    let token: String?
    let expiresAt: Date?
}

extension DeviceUpdate {
    static func connected(_ device: ManagedDevice) -> DeviceUpdate {
        DeviceUpdate(deviceAdded: nil, deviceUpdated: device, deviceRemoved: nil, allDevices: [device])
    }

    static func disconnected(_ device: ManagedDevice) -> DeviceUpdate {
        DeviceUpdate(deviceAdded: nil, deviceUpdated: device, deviceRemoved: nil, allDevices: [])
    }
}

extension DeviceCommand {
    static let connect = DeviceCommand.pair
    static let disconnect = DeviceCommand.unlock // Placeholder
    static let read = DeviceCommand.scan
    static let write = DeviceCommand.unlock // Placeholder
    static let battery = DeviceCommand.scan // Placeholder

    var requiresAuthentication: Bool {
        switch self {
        case .unlock, .lock, .authenticate:
            return true
        case .scan, .pair, .status:
            return false
        }
    }
}

enum DeviceManagementError: Error, LocalizedError {
    case deviceNotFound
    case connectionFailed
    case authenticationRequired
    case authenticationFailed
    case notAuthenticated
    case invalidDevice
    case unsupportedCommand
    case unsupportedDevice
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .deviceNotFound: return "Device not found"
        case .connectionFailed: return "Connection failed"
        case .authenticationRequired: return "Authentication required"
        case .authenticationFailed: return "Authentication failed"
        case .notAuthenticated: return "Not authenticated"
        case .invalidDevice: return "Invalid device"
        case .unsupportedCommand: return "Unsupported command"
        case .unsupportedDevice: return "Unsupported device"
        case .commandFailed(let msg): return "Command failed: \(msg)"
        }
    }
}

// MARK: - NFC Types

struct NFCTagData: Codable, Identifiable {
    let id = UUID()
    let type: NFCTagType
    let data: Data
    let timestamp: Date
    let deviceId: String
}

enum NFCTagType: String, Codable {
    case heartID
    case ndef
    case iso14443
    case iso15693
}

struct NFCAuthResult {
    let success: Bool
    let token: String?
    let expiresAt: Date?
    let error: String?

    init(success: Bool, token: String? = nil, expiresAt: Date? = nil, error: String? = nil) {
        self.success = success
        self.token = token
        self.expiresAt = expiresAt
        self.error = error
    }
}

// MARK: - Technology Types

enum TechnologyType: String, CaseIterable, Codable {
    case bluetooth = "bluetooth"
    case nfc = "nfc"
    case entraID = "entraID"
    case heartID = "heartID"
    case fido2 = "fido2"
    case healthKit = "healthKit"

    var displayName: String {
        switch self {
        case .bluetooth: return "Bluetooth"
        case .nfc: return "NFC"
        case .entraID: return "EntraID"
        case .heartID: return "HeartID"
        case .fido2: return "FIDO2"
        case .healthKit: return "HealthKit"
        }
    }
}

// Device status for iPhone-specific device management
enum iPhoneDeviceStatus: String, Codable, CaseIterable {
    case connected = "connected"
    case disconnected = "disconnected"
    case discovered = "discovered"
    case error = "error"

    var displayName: String {
        switch self {
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        case .discovered: return "Discovered"
        case .error: return "Error"
        }
    }
}

// MARK: - Bluetooth Types

enum BluetoothError: Error, LocalizedError {
    case notAvailable
    case notConnected
    case connectionFailed
    case authenticationFailed
    case commandFailed
    case timeout
    case invalidDevice
    case encryptionFailed

    var errorDescription: String? {
        switch self {
        case .notAvailable: return "Bluetooth is not available"
        case .notConnected: return "Device is not connected"
        case .connectionFailed: return "Failed to connect"
        case .authenticationFailed: return "Authentication failed"
        case .commandFailed: return "Command failed"
        case .timeout: return "Operation timed out"
        case .invalidDevice: return "Invalid device"
        case .encryptionFailed: return "Failed to encrypt command"
        }
    }
}

// MARK: - Passwordless Auth Types

struct PasswordlessMethod: Identifiable, Codable {
    let id = UUID()
    let type: PasswordlessMethodType
    let name: String
    let isAvailable: Bool
    let isEnrolled: Bool
}

enum PasswordlessMethodType: String, Codable, CaseIterable {
    case biometric = "biometric"
    case fido2 = "fido2"
    case nfc = "nfc"
    case bluetooth = "bluetooth"
    case heartID = "heart_id"
}

struct PasswordlessAuthResult {
    let success: Bool
    let method: PasswordlessMethod
    let error: String?
}

struct PasswordlessEnrollmentResult {
    let success: Bool
    let method: PasswordlessMethod
    let error: String?
}

// MARK: - EntraID Types
// EntraIDUser defined in EntraIDAuthClient.swift (more complete version)

enum EntraIDPermission: String, CaseIterable {
    case userRead = "User.Read"
    case deviceRead = "Device.Read.All"
    case directoryRead = "Directory.Read.All"
}

// MARK: - Service State Management Types

/// Service state for external integrations
public enum ServiceState: String, CaseIterable {
    case available = "available"
    case connecting = "connecting"
    case connected = "connected"
    case hold = "hold"
    case unavailable = "unavailable"
    case error = "error"
    case missingCredentials = "missing_credentials"
    case configurationRequired = "configuration_required"
    case permissionsRequired = "permissions_required"
    case networkUnavailable = "network_unavailable"
}

/// Information about why a service is in hold state
public struct HoldStateInfo {
    public let reason: String
    public let suggestedAction: String
    public let canRetry: Bool
    public let estimatedResolution: TimeInterval?

    public init(reason: String, suggestedAction: String, canRetry: Bool, estimatedResolution: TimeInterval?) {
        self.reason = reason
        self.suggestedAction = suggestedAction
        self.canRetry = canRetry
        self.estimatedResolution = estimatedResolution
    }

    public static let missingCredentials = HoldStateInfo(
        reason: "Missing authentication credentials",
        suggestedAction: "Configure credentials in Settings",
        canRetry: true,
        estimatedResolution: nil
    )

    public static let networkUnavailable = HoldStateInfo(
        reason: "Network connection unavailable",
        suggestedAction: "Check internet connection",
        canRetry: true,
        estimatedResolution: 30
    )

    public static let configurationRequired = HoldStateInfo(
        reason: "Service configuration required",
        suggestedAction: "Complete setup in Settings",
        canRetry: true,
        estimatedResolution: nil
    )

    public static let permissionsRequired = HoldStateInfo(
        reason: "Required permissions not granted",
        suggestedAction: "Grant permissions in Settings",
        canRetry: true,
        estimatedResolution: nil
    )
}

/// Protocol for services that can be put on hold
public protocol HoldableService {
    var serviceState: ServiceState { get }
    var holdInfo: HoldStateInfo? { get }

    func putOnHold(reason: HoldStateInfo)
    func resumeFromHold() async throws
    func checkAvailability() async -> Bool
}

/// Service state manager
public class ServiceStateManager {
    public static let shared = ServiceStateManager()

    // Service identifiers
    public static let bluetoothService = "bluetooth"
    public static let nfcService = "nfc"
    public static let entraIDService = "entraID"
    public static let heartIDService = "heartID"
    public static let fido2Service = "fido2"
    public static let passwordlessService = "passwordless"
    public static let watchConnectivity = "watchConnectivity"

    private var serviceStates: [String: ServiceState] = [:]
    private var serviceHoldInfo: [String: HoldStateInfo] = [:]

    private init() {}

    public func registerService(_ serviceId: String, initialState: ServiceState = .available) {
        serviceStates[serviceId] = initialState
    }

    public func updateServiceState(_ serviceId: String, to state: ServiceState, holdInfo: HoldStateInfo? = nil) {
        serviceStates[serviceId] = state
        if let holdInfo = holdInfo {
            serviceHoldInfo[serviceId] = holdInfo
        } else {
            serviceHoldInfo.removeValue(forKey: serviceId)
        }
    }

    public func getServiceState(_ serviceId: String) -> ServiceState {
        return serviceStates[serviceId] ?? .unavailable
    }

    public func getHoldInfo(_ serviceId: String) -> HoldStateInfo? {
        return serviceHoldInfo[serviceId]
    }
}
