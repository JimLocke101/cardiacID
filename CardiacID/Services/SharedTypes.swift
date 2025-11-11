//
//  SharedTypes.swift
//  HeartID Mobile
//
//  Consolidated type definitions to resolve ambiguous type lookup errors
//

import Foundation

// MARK: - Device Types (Consolidated)

public enum DeviceType: String, Codable, CaseIterable {
    case smartphone = "smartphone"
    case smartwatch = "smartwatch"
    case nfcReader = "nfc_reader"
    case bluetoothBeacon = "bluetooth_beacon"
    case doorLock = "door_lock"
    case accessPoint = "access_point"
    case sensor = "sensor"
    case camera = "camera"
    case tablet = "tablet"
    case laptop = "laptop"
    case desktop = "desktop"
    case other = "other"
    
    public var displayName: String {
        switch self {
        case .smartphone: return "Smartphone"
        case .smartwatch: return "Smart Watch"
        case .nfcReader: return "NFC Reader"
        case .bluetoothBeacon: return "Bluetooth Beacon"
        case .doorLock: return "Smart Door Lock"
        case .accessPoint: return "Access Point"
        case .sensor: return "Sensor"
        case .camera: return "Camera"
        case .tablet: return "Tablet"
        case .laptop: return "Laptop"
        case .desktop: return "Desktop"
        case .other: return "Other"
        }
    }
    
    public var icon: String {
        switch self {
        case .smartphone: return "iphone"
        case .smartwatch: return "applewatch"
        case .nfcReader: return "wave.3.right"
        case .bluetoothBeacon: return "bluetooth"
        case .doorLock: return "lock.fill"
        case .accessPoint: return "wifi"
        case .sensor: return "sensor.tag.radiowaves.forward.fill"
        case .camera: return "camera.fill"
        case .tablet: return "ipad"
        case .laptop: return "laptopcomputer"
        case .desktop: return "desktopcomputer"
        case .other: return "questionmark.circle"
        }
    }
}

public enum DeviceStatus: String, Codable, CaseIterable {
    case active = "active"
    case inactive = "inactive"
    case maintenance = "maintenance"
    case error = "error"
    case offline = "offline"
    case pending = "pending"
    
    public var displayName: String {
        switch self {
        case .active: return "Active"
        case .inactive: return "Inactive"
        case .maintenance: return "Maintenance"
        case .error: return "Error"
        case .offline: return "Offline"
        case .pending: return "Pending"
        }
    }
    
    public var color: String {
        switch self {
        case .active: return "green"
        case .inactive: return "gray"
        case .maintenance: return "orange"
        case .error: return "red"
        case .offline: return "red"
        case .pending: return "yellow"
        }
    }
}

public enum DeviceCapability: String, Codable, CaseIterable {
    case heartRateMonitoring = "heart_rate_monitoring"
    case nfcReading = "nfc_reading"
    case bluetoothComm = "bluetooth_communication"
    case biometricAuth = "biometric_authentication"
    case locationServices = "location_services"
    case cameraCapture = "camera_capture"
    case audioRecording = "audio_recording"
    case environmentalSensors = "environmental_sensors"
    case wirelessCharging = "wireless_charging"
    case remoteControl = "remote_control"
    
    public var displayName: String {
        switch self {
        case .heartRateMonitoring: return "Heart Rate Monitoring"
        case .nfcReading: return "NFC Reading"
        case .bluetoothComm: return "Bluetooth Communication"
        case .biometricAuth: return "Biometric Authentication"
        case .locationServices: return "Location Services"
        case .cameraCapture: return "Camera Capture"
        case .audioRecording: return "Audio Recording"
        case .environmentalSensors: return "Environmental Sensors"
        case .wirelessCharging: return "Wireless Charging"
        case .remoteControl: return "Remote Control"
        }
    }
}

// MARK: - Technology Types (Consolidated)

public enum TechnologyType: String, Codable, CaseIterable {
    case heartID = "heartID"
    case entraID = "entraID"
    case bluetooth = "bluetooth"
    case nfc = "nfc"
    case biometric = "biometric"
    case fido2 = "fido2"
    case webauthn = "webauthn"
    case healthKit = "healthKit"
    case appleWatch = "appleWatch"
    
    public var displayName: String {
        switch self {
        case .heartID: return "HeartID Authentication"
        case .entraID: return "EntraID (Azure AD)"
        case .bluetooth: return "Bluetooth"
        case .nfc: return "NFC"
        case .biometric: return "Biometric"
        case .fido2: return "FIDO2"
        case .webauthn: return "WebAuthn"
        case .healthKit: return "HealthKit"
        case .appleWatch: return "Apple Watch"
        }
    }
    
    public var icon: String {
        switch self {
        case .heartID: return "heart.fill"
        case .entraID: return "person.badge.shield.checkmark"
        case .bluetooth: return "bluetooth"
        case .nfc: return "wave.3.right"
        case .biometric: return "touchid"
        case .fido2: return "key.fill"
        case .webauthn: return "network"
        case .healthKit: return "heart.text.square"
        case .appleWatch: return "applewatch"
        }
    }
}

// MARK: - Passwordless Authentication Types (Consolidated)

public enum PasswordlessMethodType: String, Codable, CaseIterable {
    case biometric = "biometric"
    case heartPattern = "heartPattern"
    case nfc = "nfc"
    case fido2 = "fido2"
    case webauthn = "webauthn"
    
    public var displayName: String {
        switch self {
        case .biometric: return "Biometric Authentication"
        case .heartPattern: return "Heart Pattern"
        case .nfc: return "NFC Token"
        case .fido2: return "FIDO2 Security Key"
        case .webauthn: return "WebAuthn"
        }
    }
}

public struct PasswordlessMethod: Codable, Identifiable {
    public let id = UUID()
    public let type: PasswordlessMethodType
    public let name: String
    public let isAvailable: Bool
    public let isEnrolled: Bool
    
    public init(type: PasswordlessMethodType, name: String, isAvailable: Bool = true, isEnrolled: Bool = false) {
        self.type = type
        self.name = name
        self.isAvailable = isAvailable
        self.isEnrolled = isEnrolled
    }
}

public struct PasswordlessAuthResult: Codable {
    public let success: Bool
    public let method: PasswordlessMethodType
    public let token: String?
    public let expiresAt: Date?
    public let error: String?
    
    public init(success: Bool, method: PasswordlessMethodType, token: String? = nil, expiresAt: Date? = nil, error: String? = nil) {
        self.success = success
        self.method = method
        self.token = token
        self.expiresAt = expiresAt
        self.error = error
    }
}

public struct PasswordlessEnrollmentResult: Codable {
    public let success: Bool
    public let method: PasswordlessMethodType
    public let publicKey: String?
    public let credentialId: String?
    public let error: String?
    
    public init(success: Bool, method: PasswordlessMethodType, publicKey: String? = nil, credentialId: String? = nil, error: String? = nil) {
        self.success = success
        self.method = method
        self.publicKey = publicKey
        self.credentialId = credentialId
        self.error = error
    }
}

// MARK: - Heart Pattern Types (Consolidated)

public struct HeartPattern: Codable, Identifiable {
    public let id: UUID
    public let data: Data
    public let timestamp: Date
    public let userId: String
    
    public init(data: Data, userId: String) {
        self.id = UUID()
        self.data = data
        self.timestamp = Date()
        self.userId = userId
    }
}

// MARK: - Device Command Types (Consolidated)

public enum DeviceCommand: String, Codable, CaseIterable {
    case unlock = "unlock"
    case lock = "lock"
    case status = "status"
    case battery = "battery"
    case authenticate = "authenticate"
    case read = "read"
    case write = "write"
    case connect = "connect"
    case disconnect = "disconnect"
    case reset = "reset"
    
    public var displayName: String {
        switch self {
        case .unlock: return "Unlock"
        case .lock: return "Lock"
        case .status: return "Check Status"
        case .battery: return "Battery Level"
        case .authenticate: return "Authenticate"
        case .read: return "Read Data"
        case .write: return "Write Data"
        case .connect: return "Connect"
        case .disconnect: return "Disconnect"
        case .reset: return "Reset"
        }
    }
}

public struct DeviceCommandResult: Codable {
    public let command: DeviceCommand
    public let success: Bool
    public let data: Data?
    public let error: String?
    public let timestamp: Date
    
    public init(command: DeviceCommand, success: Bool, data: Data? = nil, error: String? = nil) {
        self.command = command
        self.success = success
        self.data = data
        self.error = error
        self.timestamp = Date()
    }
}

// MARK: - Integration Types (Consolidated)

public enum IntegrationStatus: String, Codable, CaseIterable {
    case notIntegrated = "not_integrated"
    case partiallyIntegrated = "partially_integrated"
    case fullyIntegrated = "fully_integrated"
    case integrationFailed = "integration_failed"
    
    public var displayName: String {
        switch self {
        case .notIntegrated: return "Not Integrated"
        case .partiallyIntegrated: return "Partially Integrated"
        case .fullyIntegrated: return "Fully Integrated"
        case .integrationFailed: return "Integration Failed"
        }
    }
    
    public var color: String {
        switch self {
        case .notIntegrated: return "gray"
        case .partiallyIntegrated: return "orange"
        case .fullyIntegrated: return "green"
        case .integrationFailed: return "red"
        }
    }
}

public struct IntegratedDevice: Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let type: DeviceType
    public let integrationStatus: IntegrationStatus
    public let capabilities: [DeviceCapability]
    public let lastSeen: Date?
    public let metadata: [String: String]
    
    public init(name: String, type: DeviceType, integrationStatus: IntegrationStatus = .notIntegrated, capabilities: [DeviceCapability] = [], lastSeen: Date? = nil, metadata: [String: String] = [:]) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.integrationStatus = integrationStatus
        self.capabilities = capabilities
        self.lastSeen = lastSeen
        self.metadata = metadata
    }
}

// MARK: - Managed Device (Consolidated)

public struct ManagedDevice: Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let type: DeviceType
    public let status: DeviceStatus
    public let bluetoothIdentifier: String?
    public let nfcIdentifier: String?
    public let lastSeen: Date?
    public let capabilities: [DeviceCapability]
    public let metadata: [String: String]
    
    public init(name: String, type: DeviceType, status: DeviceStatus = .pending, bluetoothIdentifier: String? = nil, nfcIdentifier: String? = nil, lastSeen: Date? = nil, capabilities: [DeviceCapability] = [], metadata: [String: String] = [:]) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.status = status
        self.bluetoothIdentifier = bluetoothIdentifier
        self.nfcIdentifier = nfcIdentifier
        self.lastSeen = lastSeen
        self.capabilities = capabilities
        self.metadata = metadata
    }
}

// MARK: - Error Types (Consolidated)

public enum DeviceManagementError: LocalizedError {
    case deviceNotFound
    case authenticationRequired
    case connectionFailed
    case commandFailed(String)
    case unsupportedCommand
    case unsupportedDevice
    case networkError
    case authenticationFailed
    case invalidDevice
    
    public var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "Device not found"
        case .authenticationRequired:
            return "Authentication required"
        case .connectionFailed:
            return "Failed to connect to device"
        case .commandFailed(let message):
            return "Command failed: \(message)"
        case .unsupportedCommand:
            return "Command not supported by device"
        case .unsupportedDevice:
            return "Device not supported"
        case .networkError:
            return "Network error"
        case .authenticationFailed:
            return "Authentication failed"
        case .invalidDevice:
            return "Invalid device"
        }
    }
}

public enum BluetoothError: LocalizedError {
    case notSupported
    case unauthorized
    case poweredOff
    case connectionFailed
    case authenticationFailed
    case invalidDevice
    
    public var errorDescription: String? {
        switch self {
        case .notSupported:
            return "Bluetooth not supported"
        case .unauthorized:
            return "Bluetooth access not authorized"
        case .poweredOff:
            return "Bluetooth is powered off"
        case .connectionFailed:
            return "Failed to connect via Bluetooth"
        case .authenticationFailed:
            return "Bluetooth authentication failed"
        case .invalidDevice:
            return "Invalid Bluetooth device"
        }
    }
}

// MARK: - Auth Event Types (Consolidated)

public struct AuthEvent: Codable, Identifiable {
    public let id: UUID
    public let type: TechnologyType
    public let timestamp: Date
    public let success: Bool
    public let userId: String?
    public let deviceId: String?
    public let metadata: [String: String]
    
    public init(type: TechnologyType, success: Bool, userId: String? = nil, deviceId: String? = nil, metadata: [String: String] = [:]) {
        self.id = UUID()
        self.type = type
        self.timestamp = Date()
        self.success = success
        self.userId = userId
        self.deviceId = deviceId
        self.metadata = metadata
    }
}

public struct TechnologyActivityEvent: Codable, Identifiable {
    public let id: UUID
    public let technology: TechnologyType
    public let action: String
    public let timestamp: Date
    public let success: Bool
    public let details: [String: String]
    
    public init(technology: TechnologyType, action: String, success: Bool, details: [String: String] = [:]) {
        self.id = UUID()
        self.technology = technology
        self.action = action
        self.timestamp = Date()
        self.success = success
        self.details = details
    }
}

// MARK: - Device Update Types

public struct DeviceUpdate: Codable {
    public let deviceId: UUID
    public let updateType: UpdateType
    public let timestamp: Date
    public let data: [String: String]
    
    public enum UpdateType: String, Codable {
        case connected = "connected"
        case disconnected = "disconnected"
        case statusChanged = "status_changed"
        case batteryLevelChanged = "battery_level_changed"
        case capabilityAdded = "capability_added"
        case capabilityRemoved = "capability_removed"
    }
    
    public init(deviceId: UUID, updateType: UpdateType, data: [String: String] = [:]) {
        self.deviceId = deviceId
        self.updateType = updateType
        self.timestamp = Date()
        self.data = data
    }
}