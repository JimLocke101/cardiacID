import Foundation

/// Represents a device in the system (IoT devices, phones, etc.)
struct Device: Codable, Identifiable {
    let id: UUID
    let name: String
    let type: DeviceType
    let status: DeviceStatus
    let lastSeen: Date?
    let macAddress: String?
    let ipAddress: String?
    let firmwareVersion: String?
    let batteryLevel: Double?
    let isOnline: Bool
    let capabilities: [DeviceCapability]
    let location: String?
    let userId: String?
    let metadata: [String: String]
    
    enum DeviceType: String, Codable, CaseIterable {
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
        
        var displayName: String {
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
        
        var icon: String {
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
    
    enum DeviceStatus: String, Codable, CaseIterable {
        case active = "active"
        case inactive = "inactive"
        case maintenance = "maintenance"
        case error = "error"
        case offline = "offline"
        case pending = "pending"
        
        var displayName: String {
            switch self {
            case .active: return "Active"
            case .inactive: return "Inactive"
            case .maintenance: return "Maintenance"
            case .error: return "Error"
            case .offline: return "Offline"
            case .pending: return "Pending"
            }
        }
        
        var color: String {
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
    
    enum DeviceCapability: String, Codable, CaseIterable {
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
        
        var displayName: String {
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
    
    init(
        name: String,
        type: DeviceType,
        status: DeviceStatus = .pending,
        lastSeen: Date? = nil,
        macAddress: String? = nil,
        ipAddress: String? = nil,
        firmwareVersion: String? = nil,
        batteryLevel: Double? = nil,
        isOnline: Bool = false,
        capabilities: [DeviceCapability] = [],
        location: String? = nil,
        userId: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.status = status
        self.lastSeen = lastSeen
        self.macAddress = macAddress
        self.ipAddress = ipAddress
        self.firmwareVersion = firmwareVersion
        self.batteryLevel = batteryLevel
        self.isOnline = isOnline
        self.capabilities = capabilities
        self.location = location
        self.userId = userId
        self.metadata = metadata
    }
    
    // MARK: - Computed Properties
    
    var isHealthy: Bool {
        return status == .active && isOnline
    }
    
    var needsAttention: Bool {
        return status == .error || status == .maintenance || !isOnline
    }
    
    var batteryStatus: String {
        guard let level = batteryLevel else { return "Unknown" }
        switch level {
        case 0.8...1.0: return "High"
        case 0.5...0.79: return "Medium" 
        case 0.2...0.49: return "Low"
        case 0.0...0.19: return "Critical"
        default: return "Unknown"
        }
    }
    
    var lastSeenText: String {
        guard let lastSeen = lastSeen else { return "Never" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: lastSeen)
    }
    
    // MARK: - Methods
    
    func hasCapability(_ capability: DeviceCapability) -> Bool {
        return capabilities.contains(capability)
    }
    
    mutating func updateStatus(_ newStatus: DeviceStatus) {
        status = newStatus
    }
    
    mutating func updateLastSeen() {
        lastSeen = Date()
    }
    
    mutating func updateBatteryLevel(_ level: Double) {
        batteryLevel = max(0, min(1, level)) // Clamp between 0 and 1
    }
}

// MARK: - Extensions

extension Device {
    /// Creates a sample iPhone device
    static func sampleiPhone() -> Device {
        return Device(
            name: "iPhone 15 Pro",
            type: .smartphone,
            status: .active,
            lastSeen: Date(),
            firmwareVersion: "iOS 17.1",
            batteryLevel: 0.85,
            isOnline: true,
            capabilities: [.heartRateMonitoring, .biometricAuth, .nfcReading, .cameraCapture, .locationServices],
            location: "Office Building A"
        )
    }
    
    /// Creates a sample Apple Watch device
    static func sampleAppleWatch() -> Device {
        return Device(
            name: "Apple Watch Series 9",
            type: .smartwatch,
            status: .active,
            lastSeen: Date(),
            firmwareVersion: "watchOS 10.1",
            batteryLevel: 0.65,
            isOnline: true,
            capabilities: [.heartRateMonitoring, .biometricAuth, .environmentalSensors],
            location: "Office Building A"
        )
    }
    
    /// Creates a sample door lock device
    static func sampleDoorLock() -> Device {
        return Device(
            name: "Smart Door Lock - Main Entrance",
            type: .doorLock,
            status: .active,
            lastSeen: Date().addingTimeInterval(-300), // 5 minutes ago
            firmwareVersion: "v2.1.4",
            batteryLevel: 0.45,
            isOnline: true,
            capabilities: [.nfcReading, .bluetoothComm, .remoteControl],
            location: "Main Entrance"
        )
    }
}