import SwiftUI
import Combine
import CoreBluetooth
import CoreNFC
import LocalAuthentication

/// Comprehensive technology management screen for EntraID, Active Directory, NFC, Bluetooth, and door locks
struct TechnologyManagementView: View {
    // Services (credentials now loaded securely from Keychain)
    @StateObject private var entraIDService = EntraIDService()
    @StateObject private var bluetoothService = BluetoothDoorLockService()
    @StateObject private var nfcService = NFCService()
    @StateObject private var passwordlessService = PasswordlessAuthService()
    
    // Computed property for device management service 
    private var deviceManagementService: DeviceManagementService {
        DeviceManagementService(entraIDService: entraIDService)
    }
    
    // State
    @State private var selectedTab: TechnologyTab = .entraID
    @State private var showingSettings = false
    @State private var showingDeviceDetails = false
    @State private var showingMenu = false
    @State private var selectedDevice: ManagedDevice?
    @State private var isScanning = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingApplicationsList = false

    // Colors
    private let colors = HeartIDColors()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HeaderView()
                
                // Technology Tabs
                TechnologyTabView(selectedTab: $selectedTab)
                
                // Content
                TabContentView(
                    selectedTab: selectedTab,
                    entraIDService: entraIDService,
                    bluetoothService: bluetoothService,
                    nfcService: nfcService,
                    deviceManagementService: deviceManagementService,
                    passwordlessService: passwordlessService,
                    onDeviceSelected: { device in
                        selectedDevice = device
                        showingDeviceDetails = true
                    },
                    showingApplicationsList: $showingApplicationsList
                )
            }
            .background(colors.background)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HamburgerMenuButton(showMenu: $showingMenu)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(colors.accent)
                    }
                }
            }
            .sheet(isPresented: $showingMenu) {
                MenuView(isPresented: $showingMenu)
                    .environmentObject(AuthViewModel())
                    .environmentObject(AuthenticationManager())
            }
            .sheet(isPresented: $showingSettings) {
                TechnologySettingsView(
                    entraIDService: entraIDService,
                    bluetoothService: bluetoothService,
                    nfcService: nfcService
                )
            }
            .sheet(isPresented: $showingDeviceDetails) {
                if let device = selectedDevice {
                    DeviceDetailView(device: device)
                }
            }
            .sheet(isPresented: $showingApplicationsList) {
                ApplicationsListView()
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
            .onAppear {
                setupServices()
            }
        }
    }
    
    private func setupServices() {
        // Setup error handling
        entraIDService.$errorMessage
            .compactMap { $0 }
            .sink { error in
                errorMessage = error
                showingError = true
            }
            .store(in: &cancellables)
        
        bluetoothService.$errorMessage
            .compactMap { $0 }
            .sink { error in
                errorMessage = error
                showingError = true
            }
            .store(in: &cancellables)
        
        nfcService.$errorMessage
            .compactMap { $0 }
            .sink { error in
                errorMessage = error
                showingError = true
            }
            .store(in: &cancellables)
    }
    
    @State private var cancellables = Set<AnyCancellable>()
}

// MARK: - Header View
struct HeaderView: View {
    private let colors = HeartIDColors()
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Technology Management")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Manage enterprise, device, and security integrations")
                        .font(.subheadline)
                        .foregroundColor(colors.text.opacity(0.7))
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top)
        }
        .background(colors.surface)
    }
}

// MARK: - Technology Tab View
struct TechnologyTabView: View {
    @Binding var selectedTab: TechnologyTab
    private let colors = HeartIDColors()
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(TechnologyTab.allCases, id: \.self) { tab in
                    TechnologyTabButton(
                        tab: tab,
                        isSelected: selectedTab == tab
                    ) {
                        selectedTab = tab
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(colors.surface)
    }
}

struct TechnologyTabButton: View {
    let tab: TechnologyTab
    let isSelected: Bool
    let action: () -> Void
    private let colors = HeartIDColors()
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16, weight: .medium))
                Text(tab.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(isSelected ? colors.accent : colors.text.opacity(0.7))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? colors.accent.opacity(0.1) : Color.clear)
            )
        }
    }
}

// MARK: - Tab Content View
struct TabContentView: View {
    let selectedTab: TechnologyTab
    let entraIDService: EntraIDService
    let bluetoothService: BluetoothDoorLockService
    let nfcService: NFCService
    let deviceManagementService: DeviceManagementService
    let passwordlessService: PasswordlessAuthService
    let onDeviceSelected: (ManagedDevice) -> Void
    @Binding var showingApplicationsList: Bool
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                switch selectedTab {
                case .entraID:
                    EntraIDManagementView(service: entraIDService, showingApplicationsList: $showingApplicationsList)
                case .bluetooth:
                    BluetoothManagementView(
                        service: bluetoothService,
                        onDeviceSelected: onDeviceSelected
                    )
                case .nfc:
                    NFCManagementView(
                        service: nfcService,
                        onDeviceSelected: onDeviceSelected
                    )
                case .doorLocks:
                    DoorLockManagementView(
                        bluetoothService: bluetoothService,
                        onDeviceSelected: onDeviceSelected
                    )
                case .devices:
                    DeviceManagementOverviewView(
                        service: deviceManagementService,
                        onDeviceSelected: onDeviceSelected
                    )
                case .security:
                    SecurityManagementView(
                        passwordlessService: passwordlessService,
                        entraIDService: entraIDService,
                        bluetoothService: bluetoothService
                    )
                }
            }
            .padding()
        }
    }
}

// MARK: - Technology Tabs
enum TechnologyTab: String, CaseIterable {
    case entraID = "EntraID"
    case bluetooth = "Bluetooth"
    case nfc = "NFC"
    case doorLocks = "Door Locks"
    case devices = "Devices"
    case security = "Security"
    
    var icon: String {
        switch self {
        case .entraID: return "building.2.crop.circle"
        case .bluetooth: return "bluetooth"
        case .nfc: return "wave.3.right"
        case .doorLocks: return "lock.shield"
        case .devices: return "iphone"
        case .security: return "shield.lefthalf.filled"
        }
    }
    
    var title: String {
        return rawValue
    }
}

// MARK: - EntraID Management View
struct EntraIDManagementView: View {
    @ObservedObject var service: EntraIDService
    @Binding var showingApplicationsList: Bool
    private let colors = HeartIDColors()

    var body: some View {
        VStack(spacing: 20) {
            // Connection Status
            ConnectionStatusCard(
                title: "EntraID Connection",
                isConnected: service.isAuthenticated,
                statusText: service.isAuthenticated ? "Connected" : "Not Connected",
                userInfo: service.currentUser.map { $0.displayName }
            )
            
            // Authentication Actions
            VStack(spacing: 12) {
                if service.isAuthenticated {
                    Button("Sign Out") {
                        service.signOut()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    
                    Button("Refresh User Info") {
                        // Refresh user information
                    }
                    .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button("Connect to EntraID") {
                        service.authenticate()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            
            // User Information
            if let user = service.currentUser {
                UserInfoCard(user: user)
            }
            
            // Enterprise Features
            if service.isAuthenticated {
                EnterpriseFeaturesCard(
                    service: service,
                    showingApplicationsList: $showingApplicationsList
                )
            }
        }
    }
}

// MARK: - Bluetooth Management View
struct BluetoothManagementView: View {
    @ObservedObject var service: BluetoothDoorLockService
    let onDeviceSelected: (ManagedDevice) -> Void
    private let colors = HeartIDColors()

    var body: some View {
        VStack(spacing: 16) {
            // Bluetooth Status Card
            HStack(spacing: 12) {
                Image(systemName: "bluetooth")
                    .font(.title2)
                    .foregroundColor(service.isBluetoothAvailable ? colors.accent : colors.error)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bluetooth")
                        .font(.headline).foregroundColor(colors.text)
                    Text(service.isBluetoothAvailable ? "Available" : "Bluetooth is off or unavailable")
                        .font(.caption).foregroundColor(colors.secondary)
                }
                Spacer()
                Circle()
                    .fill(service.isBluetoothAvailable ? colors.success : colors.error)
                    .frame(width: 10, height: 10)
            }
            .padding()
            .background(colors.surface)
            .cornerRadius(12)

            // Scan Controls
            HStack(spacing: 12) {
                Button(action: {
                    if service.isScanning { service.stopScanning() }
                    else { service.startScanning() }
                }) {
                    HStack(spacing: 8) {
                        if service.isScanning {
                            ProgressView().progressViewStyle(.circular).scaleEffect(0.7).tint(.white)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                        Text(service.isScanning ? "Scanning..." : "Scan for Devices")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(service.isScanning ? colors.warning : colors.accent)
                    .foregroundColor(service.isScanning ? colors.primary : .white)
                    .cornerRadius(10)
                }
                .disabled(!service.isBluetoothAvailable)

                if service.isScanning {
                    Button(action: { service.stopScanning() }) {
                        Image(systemName: "stop.fill")
                            .padding(12)
                            .background(colors.error)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
            }

            // Device count summary
            if service.isScanning || !service.discoveredLocks.isEmpty || !service.connectedLocks.isEmpty {
                HStack {
                    Label("\(service.discoveredLocks.count) found", systemImage: "magnifyingglass")
                        .font(.caption).foregroundColor(colors.secondary)
                    Spacer()
                    Label("\(service.connectedLocks.count) connected", systemImage: "link")
                        .font(.caption).foregroundColor(service.connectedLocks.isEmpty ? colors.secondary : colors.success)
                }
                .padding(.horizontal, 4)
            }

            // Connected Devices (shown first — priority)
            if !service.connectedLocks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .font(.subheadline).fontWeight(.semibold).foregroundColor(colors.success)

                    ForEach(service.connectedLocks) { device in
                        BluetoothDeviceRow(device: device, colors: colors, isConnected: true) {
                            let managed = ManagedDevice(name: device.name, type: .bluetoothDoorLock,
                                                        status: .connected, bluetoothLock: device)
                            onDeviceSelected(managed)
                        }
                    }
                }
                .padding()
                .background(colors.surface)
                .cornerRadius(12)
            }

            // Discovered Devices
            if !service.discoveredLocks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Discovered Devices", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.subheadline).fontWeight(.semibold).foregroundColor(colors.text)

                    ForEach(service.discoveredLocks) { device in
                        BluetoothDeviceRow(device: device, colors: colors, isConnected: false) {
                            let managed = ManagedDevice(name: device.name, type: .bluetoothDoorLock,
                                                        status: .discovered, bluetoothLock: device)
                            onDeviceSelected(managed)
                        }
                    }
                }
                .padding()
                .background(colors.surface)
                .cornerRadius(12)
            }

            // Empty state when not scanning and no devices
            if !service.isScanning && service.discoveredLocks.isEmpty && service.connectedLocks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bluetooth")
                        .font(.system(size: 40))
                        .foregroundColor(colors.secondary)
                    Text("No devices found")
                        .font(.subheadline).foregroundColor(colors.secondary)
                    Text("Tap \"Scan for Devices\" to discover nearby Bluetooth devices.")
                        .font(.caption).foregroundColor(colors.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            }
        }
    }
}

// MARK: - Bluetooth Device Row

private struct BluetoothDeviceRow: View {
    let device: BluetoothDoorLock
    let colors: HeartIDColors
    let isConnected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Bluetooth icon with signal indicator
                ZStack {
                    Image(systemName: "bluetooth")
                        .font(.title3)
                        .foregroundColor(isConnected ? colors.success : colors.accent)
                }
                .frame(width: 36, height: 36)
                .background((isConnected ? colors.success : colors.accent).opacity(0.15))
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name)
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(colors.text)
                    HStack(spacing: 8) {
                        // Signal strength
                        signalBars(rssi: device.rssi)
                        Text(signalLabel(rssi: device.rssi))
                            .font(.caption2).foregroundColor(colors.secondary)
                        if isConnected {
                            Text("Connected")
                                .font(.caption2).fontWeight(.semibold)
                                .foregroundColor(colors.success)
                        }
                    }
                }

                Spacer()

                // Signal strength indicator
                Text("\(device.rssi) dBm")
                    .font(.caption2)
                    .foregroundColor(colors.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption).foregroundColor(colors.secondary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func signalBars(rssi: Int) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<4, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1)
                    .fill(bar < signalLevel(rssi: rssi) ? colors.accent : colors.secondary.opacity(0.3))
                    .frame(width: 3, height: CGFloat(4 + bar * 3))
            }
        }
    }

    private func signalLevel(rssi: Int) -> Int {
        switch rssi {
        case -50...0:    return 4  // Excellent
        case -65...(-51): return 3  // Good
        case -80...(-66): return 2  // Fair
        case -95...(-81): return 1  // Weak
        default:          return 0  // No signal
        }
    }

    private func signalLabel(rssi: Int) -> String {
        switch rssi {
        case -50...0:    return "Strong"
        case -65...(-51): return "Good"
        case -80...(-66): return "Fair"
        default:          return "Weak"
        }
    }

    private func batteryIcon(level: Int) -> String {
        switch level {
        case 76...100: return "battery.100"
        case 51...75:  return "battery.75"
        case 26...50:  return "battery.50"
        case 1...25:   return "battery.25"
        default:       return "battery.0"
        }
    }
}

// MARK: - NFC Management View
struct NFCManagementView: View {
    @ObservedObject var service: NFCService
    let onDeviceSelected: (ManagedDevice) -> Void
    private let colors = HeartIDColors()
    
    var body: some View {
        VStack(spacing: 20) {
            // NFC Status
            ConnectionStatusCard(
                title: "NFC",
                isConnected: service.isNFCAvailable,
                statusText: service.isNFCAvailable ? "Available" : "Not Available",
                userInfo: nil
            )
            
            // NFC Actions
            VStack(spacing: 12) {
                if service.isScanning {
                    Button("Stop Scanning") {
                        service.stopScanning()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button("Start Scanning") {
                        service.startScanning()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                
                Button("Read Tag") {
                    service.readTagData()
                }
                .buttonStyle(SecondaryButtonStyle())
                
                Button("Write Tag") {
                    // Implement write functionality
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            
            // Last Scanned Tag
            if let tag = service.lastScannedTag {
                LastScannedTagCard(tag: tag)
            }
        }
    }
}

// MARK: - Door Lock Management View
struct DoorLockManagementView: View {
    @ObservedObject var bluetoothService: BluetoothDoorLockService
    let onDeviceSelected: (ManagedDevice) -> Void
    private let colors = HeartIDColors()
    
    var body: some View {
        VStack(spacing: 20) {
            // Door Lock Status
            ConnectionStatusCard(
                title: "Door Locks",
                isConnected: !bluetoothService.connectedLocks.isEmpty,
                statusText: "\(bluetoothService.connectedLocks.count) Connected",
                userInfo: nil
            )
            
            // Door Lock Actions
            VStack(spacing: 12) {
                Button("Discover Door Locks") {
                    bluetoothService.startScanning()
                }
                .buttonStyle(PrimaryButtonStyle())
                
                if !bluetoothService.connectedLocks.isEmpty {
                    Button("Refresh Status") {
                        // Refresh door lock status
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            
            // Connected Door Locks
            if !bluetoothService.connectedLocks.isEmpty {
                DoorLockList(
                    locks: bluetoothService.connectedLocks,
                    onLockSelected: onDeviceSelected
                )
            }
        }
    }
}

// MARK: - Device Management Overview View
struct DeviceManagementOverviewView: View {
    @ObservedObject var service: DeviceManagementService
    let onDeviceSelected: (ManagedDevice) -> Void
    private let colors = HeartIDColors()
    
    var body: some View {
        VStack(spacing: 20) {
            // Device Summary
            DeviceSummaryCard(
                connectedDevices: service.connectedDevices.count,
                availableDevices: service.availableDevices.count
            )
            
            // Device Actions
            VStack(spacing: 12) {
                if service.isScanning {
                    Button("Stop Scanning") {
                        service.stopScanning()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button("Start Scanning") {
                        service.startScanning()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                
                Button("Refresh Devices") {
                    service.refreshDevices()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            
            // Connected Devices
            if !service.connectedDevices.isEmpty {
                ConnectedDevicesList(
                    devices: service.connectedDevices,
                    onDeviceSelected: onDeviceSelected
                )
            }
            
            // Available Devices
            if !service.availableDevices.isEmpty {
                AvailableDevicesList(
                    devices: service.availableDevices,
                    onDeviceSelected: onDeviceSelected
                )
            }
        }
    }
}

// MARK: - Security Management View
struct SecurityManagementView: View {
    @ObservedObject var passwordlessService: PasswordlessAuthService
    @ObservedObject var entraIDService: EntraIDService
    @ObservedObject var bluetoothService: BluetoothDoorLockService
    private let colors = HeartIDColors()
    
    var body: some View {
        VStack(spacing: 20) {
            // Security Status
        SecurityStatusCard(
            passwordlessEnabled: true, // Placeholder since property doesn't exist yet
            entraIDConnected: entraIDService.isAuthenticated
        )
            
            // Security Actions
            VStack(spacing: 12) {
                Button("Configure Passwordless Auth") {
                    // Navigate to passwordless configuration
                }
                .buttonStyle(PrimaryButtonStyle())
                
                Button("Manage Biometrics") {
                    // Navigate to biometric management
                }
                .buttonStyle(SecondaryButtonStyle())
                
                Button("Security Settings") {
                    // Navigate to security settings
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            
            // Security Features
            SecurityFeaturesList(
                passwordlessService: passwordlessService,
                entraIDService: entraIDService,
                bluetoothService: bluetoothService
            )
        }
    }
}

// MARK: - Supporting Views

struct ConnectionStatusCard: View {
    let title: String
    let isConnected: Bool
    let statusText: String
    let userInfo: String?
    private let colors = HeartIDColors()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(isConnected ? colors.success : colors.error)
                    .frame(width: 12, height: 12)
                Text(title)
                    .font(.headline)
                Spacer()
                Text(statusText)
                    .font(.subheadline)
                    .foregroundColor(colors.text.opacity(0.7))
            }
            
            if let userInfo = userInfo {
                Text("User: \(userInfo)")
                    .font(.subheadline)
                    .foregroundColor(colors.text.opacity(0.8))
            }
        }
        .padding()
        .background(colors.surface)
        .cornerRadius(12)
    }
}

struct UserInfoCard: View {
    let user: EntraIDUserModel
    private let colors = HeartIDColors()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("User Information")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Name", value: user.displayName)
                InfoRow(label: "Email", value: user.email)
                if let jobTitle = user.jobTitle {
                    InfoRow(label: "Job Title", value: jobTitle)
                }
                if let department = user.department {
                    InfoRow(label: "Department", value: department)
                }
            }
        }
        .padding()
        .background(colors.surface)
        .cornerRadius(12)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    private let colors = HeartIDColors()
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(colors.text.opacity(0.7))
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(colors.text)
        }
    }
}

struct EnterpriseFeaturesCard: View {
    @ObservedObject var service: EntraIDService
    @Binding var showingApplicationsList: Bool
    private let colors = HeartIDColors()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enterprise Features")
                .font(.headline)

            VStack(spacing: 8) {
                FeatureButton(
                    title: "View Groups",
                    icon: "person.3.fill",
                    action: {
                        // Load and display groups
                    }
                )

                FeatureButton(
                    title: "View Applications",
                    icon: "app.fill",
                    action: {
                        showingApplicationsList = true
                    }
                )

                FeatureButton(
                    title: "Security Policies",
                    icon: "shield.fill",
                    action: {
                        // Load and display security policies
                    }
                )
            }
        }
        .padding()
        .background(colors.surface)
        .cornerRadius(12)
    }
}

struct FeatureButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    private let colors = HeartIDColors()
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(colors.accent)
                Text(title)
                    .foregroundColor(colors.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(colors.text.opacity(0.5))
                    .font(.caption)
            }
            .padding(.vertical, 8)
        }
    }
}

struct DiscoveredDevicesList: View {
    let devices: [BluetoothDoorLock]
    let onDeviceSelected: (ManagedDevice) -> Void
    private let colors = HeartIDColors()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Discovered Devices")
                .font(.headline)
            
            ForEach(devices) { device in
                DeviceRow(
                    name: device.name,
                    type: "Bluetooth Door Lock",
                    status: device.isConnected ? "Connected" : "Discovered",
                    rssi: device.rssi
                ) {
                    // Convert to ManagedDevice and call onDeviceSelected
                    let managedDevice = ManagedDevice(
                        name: device.name,
                        type: .bluetoothDoorLock,
                        status: device.isConnected ? .connected : .discovered,
                        bluetoothLock: device
                    )
                    onDeviceSelected(managedDevice)
                }
            }
        }
        .padding()
        .background(colors.surface)
        .cornerRadius(12)
    }
}

struct ConnectedDevicesList: View {
    let devices: [ManagedDevice]
    let onDeviceSelected: (ManagedDevice) -> Void
    private let colors = HeartIDColors()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connected Devices")
                .font(.headline)
            
            ForEach(devices) { device in
                DeviceRow(
                    name: device.name,
                    type: device.type.rawValue,
                    status: device.status.rawValue,
                    rssi: nil
                ) {
                    onDeviceSelected(device)
                }
            }
        }
        .padding()
        .background(colors.surface)
        .cornerRadius(12)
    }
}

struct AvailableDevicesList: View {
    let devices: [ManagedDevice]
    let onDeviceSelected: (ManagedDevice) -> Void
    private let colors = HeartIDColors()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Available Devices")
                .font(.headline)
            
            ForEach(devices) { device in
                DeviceRow(
                    name: device.name,
                    type: device.type.rawValue,
                    status: device.status.rawValue,
                    rssi: nil
                ) {
                    onDeviceSelected(device)
                }
            }
        }
        .padding()
        .background(colors.surface)
        .cornerRadius(12)
    }
}

struct DeviceRow: View {
    let name: String
    let type: String
    let status: String
    let rssi: Int?
    let action: () -> Void
    private let colors = HeartIDColors()
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.subheadline)
                        .foregroundColor(colors.text)
                    Text(type)
                        .font(.caption)
                        .foregroundColor(colors.text.opacity(0.7))
                }
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(status.capitalized)
                        .font(.caption)
                        .foregroundColor(colors.success)
                    if let rssi = rssi {
                        Text("\(rssi) dBm")
                            .font(.caption2)
                            .foregroundColor(colors.text.opacity(0.5))
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

struct LastScannedTagCard: View {
    let tag: NFCTagData
    private let colors = HeartIDColors()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last Scanned Tag")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Type", value: "\(tag.type)")
                InfoRow(label: "Timestamp", value: DateFormatter.localizedString(from: tag.timestamp, dateStyle: .short, timeStyle: .short))
                InfoRow(label: "Device ID", value: tag.deviceId)
            }
        }
        .padding()
        .background(colors.surface)
        .cornerRadius(12)
    }
}

struct DoorLockList: View {
    let locks: [BluetoothDoorLock]
    let onLockSelected: (ManagedDevice) -> Void
    private let colors = HeartIDColors()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connected Door Locks")
                .font(.headline)
            
            ForEach(locks) { lock in
                DoorLockRow(lock: lock) {
                    let managedDevice = ManagedDevice(
                        name: lock.name,
                        type: .bluetoothDoorLock,
                        status: .connected,
                        bluetoothLock: lock
                    )
                    onLockSelected(managedDevice)
                }
            }
        }
        .padding()
        .background(colors.surface)
        .cornerRadius(12)
    }
}

struct DoorLockRow: View {
    let lock: BluetoothDoorLock
    let action: () -> Void
    private let colors = HeartIDColors()
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "lock.shield")
                    .foregroundColor(colors.accent)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(lock.name)
                        .font(.subheadline)
                        .foregroundColor(colors.text)
                    if let location = lock.location {
                        Text(location)
                            .font(.caption)
                            .foregroundColor(colors.text.opacity(0.7))
                    }
                }
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Circle()
                        .fill(lock.isConnected ? colors.success : colors.error)
                        .frame(width: 8, height: 8)
                    Text(lock.isConnected ? "Connected" : "Disconnected")
                        .font(.caption)
                        .foregroundColor(colors.text.opacity(0.7))
                }
            }
            .padding(.vertical, 8)
        }
    }
}

struct DeviceSummaryCard: View {
    let connectedDevices: Int
    let availableDevices: Int
    private let colors = HeartIDColors()
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("\(connectedDevices)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(colors.accent)
                    Text("Connected")
                        .font(.subheadline)
                        .foregroundColor(colors.text.opacity(0.7))
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(availableDevices)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(colors.warning)
                    Text("Available")
                        .font(.subheadline)
                        .foregroundColor(colors.text.opacity(0.7))
                }
            }
        }
        .padding()
        .background(colors.surface)
        .cornerRadius(12)
    }
}

struct SecurityStatusCard: View {
    let passwordlessEnabled: Bool
    let entraIDConnected: Bool
    private let colors = HeartIDColors()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Security Status")
                .font(.headline)
            
            HStack {
                SecurityStatusItem(
                    title: "Passwordless Auth",
                    isEnabled: passwordlessEnabled
                )
                Spacer()
                SecurityStatusItem(
                    title: "EntraID",
                    isEnabled: entraIDConnected
                )
            }
        }
        .padding()
        .background(colors.surface)
        .cornerRadius(12)
    }
}

struct SecurityStatusItem: View {
    let title: String
    let isEnabled: Bool
    private let colors = HeartIDColors()
    
    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(isEnabled ? colors.success : colors.error)
                .frame(width: 12, height: 12)
            Text(title)
                .font(.caption)
                .foregroundColor(colors.text.opacity(0.7))
        }
    }
}

struct SecurityFeaturesList: View {
    @ObservedObject var passwordlessService: PasswordlessAuthService
    @ObservedObject var entraIDService: EntraIDService
    @ObservedObject var bluetoothService: BluetoothDoorLockService
    @StateObject private var watchConnectivity = WatchConnectivityService.shared
    private let colors = HeartIDColors()

    /// Checkmarks indicate whether each security feature is CURRENTLY ACTIVE:
    ///   - Green checkmark = available and operational right now
    ///   - Red X = unavailable, not configured, or not connected
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Security Features")
                    .font(.headline).foregroundColor(colors.text)
                Spacer()
                Text("Active Status")
                    .font(.caption2).foregroundColor(colors.secondary)
            }

            VStack(spacing: 8) {
                SecurityFeatureRow(
                    title: "Face ID / Touch ID",
                    isEnabled: isBiometricAvailable(),
                    icon: "faceid",
                    detail: isBiometricAvailable() ? "Device biometric ready" : "Not available"
                )

                SecurityFeatureRow(
                    title: "Heart Pattern Auth",
                    isEnabled: watchConnectivity.liveBiometricConfidence > 0,
                    icon: "heart.fill",
                    detail: watchConnectivity.liveBiometricConfidence > 0
                        ? "\(Int(watchConnectivity.liveBiometricConfidence * 100))% confidence"
                        : "Watch not connected"
                )

                SecurityFeatureRow(
                    title: "NFC Authentication",
                    isEnabled: NFCNDEFReaderSession.readingAvailable,
                    icon: "wave.3.right",
                    detail: NFCNDEFReaderSession.readingAvailable ? "Ready" : "Not available on this device"
                )

                SecurityFeatureRow(
                    title: "Bluetooth Security",
                    isEnabled: bluetoothService.isBluetoothAvailable,
                    icon: "bluetooth",
                    detail: bluetoothService.isBluetoothAvailable
                        ? "\(bluetoothService.connectedLocks.count) device(s) connected"
                        : "Bluetooth off or unavailable"
                )

                SecurityFeatureRow(
                    title: "Entra ID SSO",
                    isEnabled: entraIDService.isAuthenticated,
                    icon: "building.2.crop.circle",
                    detail: entraIDService.isAuthenticated
                        ? (entraIDService.currentUser?.displayName ?? "Connected")
                        : "Not signed in"
                )
            }
        }
        .padding()
        .background(colors.surface)
        .cornerRadius(12)
    }

    private func isBiometricAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
}

struct SecurityFeatureRow: View {
    let title: String
    let isEnabled: Bool
    let icon: String
    var detail: String = ""
    private let colors = HeartIDColors()

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(isEnabled ? colors.accent : colors.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(colors.text)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(colors.secondary)
                }
            }

            Spacer()

            Image(systemName: isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isEnabled ? colors.success : colors.error)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Button Styles
struct PrimaryButtonStyle: ButtonStyle {
    private let colors = HeartIDColors()
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(colors.accent)
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    private let colors = HeartIDColors()
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(colors.accent)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(colors.accent.opacity(0.1))
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

// MARK: - Device Detail View
struct DeviceDetailView: View {
    let device: ManagedDevice
    @Environment(\.dismiss) private var dismiss
    private let colors = HeartIDColors()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Device Header
                    VStack(spacing: 12) {
                        Image(systemName: deviceIcon(for: device.type))
                            .font(.system(size: 60))
                            .foregroundColor(colors.accent)
                        
                        Text(device.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(device.type.rawValue.capitalized)
                            .font(.subheadline)
                            .foregroundColor(colors.text.opacity(0.7))
                    }
                    .padding()
                    .background(colors.surface)
                    .cornerRadius(16)
                    
                    // Device Information
                    DeviceInfoSection(device: device)
                    
                    // Device Actions
                    DeviceActionsSection(device: device)
                    
                    // Device Status
                    DeviceStatusSection(device: device)
                }
                .padding()
            }
            .background(colors.background)
            .navigationTitle("Device Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func deviceIcon(for type: DeviceType) -> String {
        switch type {
        case .bluetoothDoorLock, .bluetoothLock: return "lock.shield"
        case .nfcTag: return "wave.3.right"
        case .appleWatch: return "applewatch"
        case .enterpriseDevice: return "building.2.crop.circle"
        case .nfcReader: return "wave.3.forward"
        case .heartIDDevice: return "heart.fill"
        case .smartphone: return "iphone"
        case .other: return "cube"
        }
    }
}

struct DeviceInfoSection: View {
    let device: ManagedDevice
    private let colors = HeartIDColors()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Device Information")
                .font(.headline)
            
            VStack(spacing: 8) {
                InfoRow(label: "ID", value: device.id.uuidString)
                InfoRow(label: "Type", value: device.type.rawValue)
                InfoRow(label: "Status", value: device.status.rawValue)
                if let lastSeen = device.lastSeen {
                    InfoRow(label: "Last Seen", value: DateFormatter.localizedString(from: lastSeen, dateStyle: .short, timeStyle: .short))
                }
            }
        }
        .padding()
        .background(colors.surface)
        .cornerRadius(12)
    }
}

struct DeviceActionsSection: View {
    let device: ManagedDevice
    private let colors = HeartIDColors()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.headline)
            
            VStack(spacing: 8) {
                Button("Connect") {
                    // Connect to device
                }
                .buttonStyle(PrimaryButtonStyle())
                
                Button("Disconnect") {
                    // Disconnect from device
                }
                .buttonStyle(SecondaryButtonStyle())
                
                Button("Refresh Status") {
                    // Refresh device status
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding()
        .background(colors.surface)
        .cornerRadius(12)
    }
}

struct DeviceStatusSection: View {
    let device: ManagedDevice
    private let colors = HeartIDColors()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Status")
                .font(.headline)
            
            HStack {
                Circle()
                    .fill(statusColor(for: device.status))
                    .frame(width: 12, height: 12)
                Text(device.status.rawValue.capitalized)
                    .font(.subheadline)
                Spacer()
            }
        }
        .padding()
        .background(colors.surface)
        .cornerRadius(12)
    }
    
    private func statusColor(for status: DeviceStatus) -> Color {
        let colors = HeartIDColors()
        switch status {
        case .active, .connected: return colors.success
        case .discovered: return colors.warning
        case .inactive, .disconnected: return colors.error
        case .error: return colors.error
        }
    }
}

// MARK: - Technology Settings View
struct TechnologySettingsView: View {
    @ObservedObject var entraIDService: EntraIDService
    @ObservedObject var bluetoothService: BluetoothDoorLockService
    @ObservedObject var nfcService: NFCService
    @Environment(\.dismiss) private var dismiss
    private let colors = HeartIDColors()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // EntraID Settings
                    SettingsSection(
                        title: "EntraID Configuration",
                        icon: "building.2.crop.circle"
                    ) {
                        EntraIDSettingsView(service: entraIDService)
                    }
                    
                    // Bluetooth Settings
                    SettingsSection(
                        title: "Bluetooth Configuration",
                        icon: "bluetooth"
                    ) {
                        BluetoothSettingsView(service: bluetoothService)
                    }
                    
                    // NFC Settings
                    SettingsSection(
                        title: "NFC Configuration",
                        icon: "wave.3.right"
                    ) {
                        NFCSettingsView(service: nfcService)
                    }
                }
                .padding()
            }
            .background(colors.background)
            .navigationTitle("Technology Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    private let colors = HeartIDColors()
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(colors.accent)
                Text(title)
                    .font(.headline)
            }
            
            content
        }
        .padding()
        .background(colors.surface)
        .cornerRadius(12)
    }
}

struct EntraIDSettingsView: View {
    @ObservedObject var service: EntraIDService
    private let colors = HeartIDColors()
    
    var body: some View {
        VStack(spacing: 12) {
            InfoRow(label: "Tenant ID", value: "your-tenant-id")
            InfoRow(label: "Client ID", value: "your-client-id")
            InfoRow(label: "Status", value: service.isAuthenticated ? "Connected" : "Not Connected")
        }
    }
}

struct BluetoothSettingsView: View {
    @ObservedObject var service: BluetoothDoorLockService
    private let colors = HeartIDColors()
    
    var body: some View {
        VStack(spacing: 12) {
            InfoRow(label: "Available", value: service.isBluetoothAvailable ? "Yes" : "No")
            InfoRow(label: "Scanning", value: service.isScanning ? "Yes" : "No")
            InfoRow(label: "Connected Devices", value: "\(service.connectedLocks.count)")
        }
    }
}

struct NFCSettingsView: View {
    @ObservedObject var service: NFCService
    private let colors = HeartIDColors()
    
    var body: some View {
        VStack(spacing: 12) {
            InfoRow(label: "Available", value: service.isNFCAvailable ? "Yes" : "No")
            InfoRow(label: "Scanning", value: service.isScanning ? "Yes" : "No")
            InfoRow(label: "Last Tag", value: service.lastScannedTag != nil ? "Scanned" : "None")
        }
    }
}

#Preview {
    TechnologyManagementView()
        .environmentObject(AuthenticationManager())
        .environmentObject(WatchConnectivityService.shared)
        .environmentObject(AuthViewModel())
}
