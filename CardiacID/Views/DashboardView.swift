import SwiftUI
import HealthKit
import Combine

struct DashboardView: View {
    // Environment and state objects
    @EnvironmentObject private var authManager: AuthenticationManager
    @EnvironmentObject private var watchConnectivity: WatchConnectivityService
    @EnvironmentObject private var authViewModel: AuthViewModel
    
    // State variables
    @State private var authenticationStatus: AuthenticationStatus = .inactive
    @State private var lastHeartRate: Int = 0
    @State private var lastHeartRateTime: Date? = nil
    @State private var lastAuthEvent: AuthEvent? = nil
    @State private var showingAuthDetail = false
    @State private var recentEvents: [AuthEvent] = []
    @State private var connectedDevices: [Device] = []
    
    // Colors
    private let colors = HeartIDColors()
    
    // Subscriptions
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Status Card
                StatusCard(status: authenticationStatus)
                    .padding(.horizontal)
                    .onTapGesture {
                        if authenticationStatus == .inactive {
                            startAuthentication()
                        } else if authenticationStatus == .warning {
                            startAuthentication()
                        }
                    }
                
                // Heart Rate Monitor
                HeartRateCard(heartRate: lastHeartRate, timestamp: lastHeartRateTime)
                    .padding(.horizontal)
                
                // Device Status
                DeviceStatusCard(devices: connectedDevices, watchConnectivity: watchConnectivity)
                    .padding(.horizontal)
                
                // Recent Activity
                RecentActivityList(events: recentEvents)
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(colors.background)
        .navigationTitle("Dashboard")
        .onAppear {
            setupSubscriptions()
            updateAuthStatus()
            loadRecentEvents()
            loadConnectedDevices()
        }
        .onDisappear {
            cancellables.removeAll()
        }
        .sheet(isPresented: $showingAuthDetail) {
            if let event = lastAuthEvent {
                AuthenticationDetailView(event: event)
            }
        }
    }
    
    // MARK: - Setup
    
    private func setupSubscriptions() {
        // Watch heart rate updates
        watchConnectivity.heartRatePublisher
            .sink { heartRate, timestamp in
                lastHeartRate = heartRate
                lastHeartRateTime = timestamp
            }
            .store(in: &cancellables)
        
        // Auth manager status updates
        authManager.$authState
            .sink { state in
                updateAuthStatus(from: state)
            }
            .store(in: &cancellables)
        
        // Auth manager heart rate updates
        authManager.$currentHeartRate
            .sink { heartRate in
                if heartRate > 0 {
                    self.lastHeartRate = heartRate
                    self.lastHeartRateTime = Date()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Data Loading

    private func loadRecentEvents() {
        // Load recent auth events from Supabase using async/await
        Task {
            do {
                let events = try await SupabaseService.shared.getRecentAuthEvents(limit: 5)
                await MainActor.run {
                    self.recentEvents = events
                }
            } catch {
                print("Failed to load recent events: \(error)")
                await MainActor.run {
                    self.recentEvents = []
                }
            }
        }
    }

    private func loadConnectedDevices() {
        // Load connected devices from Supabase using async/await
        Task {
            do {
                let devices = try await SupabaseService.shared.getDevices()
                await MainActor.run {
                    self.connectedDevices = devices.filter { $0.status == .active }
                }
            } catch {
                print("Failed to load connected devices: \(error)")
                await MainActor.run {
                    self.connectedDevices = []
                }
            }
        }
    }
    
    // MARK: - Authentication
    
    private func updateAuthStatus(from authState: AuthState? = nil) {
        let state = authState ?? authManager.authState
        
        switch state {
        case .authenticated:
            self.authenticationStatus = .active
        case .authenticating:
            self.authenticationStatus = .warning
        case .idle:
            self.authenticationStatus = .inactive
        case .failed(_):
            self.authenticationStatus = .error
        case .warning:
            self.authenticationStatus = .warning
        }
    }
    
    private func startAuthentication() {
        if !authManager.isMonitoring {
            // Start heart monitoring on phone and watch
            authManager.startMonitoring()
            watchConnectivity.startMonitoring()
        }
        
        // Begin authentication
        authManager.authenticate()
    }
}

// MARK: - Status Card
struct StatusCard: View {
    let status: AuthenticationStatus
    private let colors = HeartIDColors()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: status.icon)
                    .foregroundColor(status.color)
                    .font(.system(size: 22))
                Text(status.title)
                    .font(.headline)
                Spacer()
                
                if status == .active {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(colors.success)
                        .font(.system(size: 20))
                }
            }
            
            Text(status.description)
                .font(.subheadline)
                .foregroundColor(colors.text.opacity(0.8))
            
            if status == .active {
                HStack {
                    Text("Last verified:")
                        .font(.caption)
                        .foregroundColor(colors.text.opacity(0.6))
                    Text("Just now")
                        .font(.caption)
                        .foregroundColor(colors.text.opacity(0.8))
                }
            }
        }
        .padding()
        .background(colors.surface)
        .cornerRadius(16)
    }
}

// MARK: - Heart Rate Card
struct HeartRateCard: View {
    let heartRate: Int
    let timestamp: Date?
    private let colors = HeartIDColors()
    
    var formattedTime: String {
        guard let timestamp = timestamp else { return "--" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("\(heartRate)")
                .font(.system(size: 64, weight: .bold))
                .foregroundColor(colors.accent)
            
            Text("BPM")
                .font(.subheadline)
                .foregroundColor(colors.text.opacity(0.8))
            
            // Animated heart rate wave
            HeartRateWaveView(active: heartRate > 0)
                .frame(height: 60)
            
            if let _ = timestamp {
                Text("Updated \(formattedTime)")
                    .font(.caption)
                    .foregroundColor(colors.text.opacity(0.6))
            }
        }
        .padding()
        .background(colors.surface)
        .cornerRadius(16)
    }
}

// MARK: - Device Status Card
struct DeviceStatusCard: View {
    let devices: [Device]
    let watchConnectivity: WatchConnectivityService
    private let colors = HeartIDColors()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Connected Devices")
                    .font(.headline)
                Spacer()
                
                NavigationLink {
                    DeviceManagementView()
                } label: {
                    Text("View All")
                        .font(.caption)
                        .foregroundColor(colors.accent)
                }
            }
            
            if devices.isEmpty {
                HStack {
                    Image(systemName: "applewatch")
                        .foregroundColor(colors.accent.opacity(0.7))
                    Text(watchConnectivity.isReachable ? "Apple Watch Connected" : "No devices connected")
                        .font(.subheadline)
                    Spacer()
                    
                    if watchConnectivity.isReachable {
                        Circle()
                            .fill(colors.success)
                            .frame(width: 8, height: 8)
                    }
                }
            } else {
                ForEach(devices.prefix(2)) { device in
                    HStack {
                        Image(systemName: deviceIcon(for: device.type))
                            .foregroundColor(colors.accent)
                        VStack(alignment: .leading) {
                            Text(device.name)
                                .font(.subheadline)
                            Text(device.status.rawValue.capitalized)
                                .font(.caption)
                                .foregroundColor(colors.success)
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding()
        .background(colors.surface)
        .cornerRadius(16)
    }
    
    func deviceIcon(for type: Device.DeviceType) -> String {
        return type.icon
    }
}

// MARK: - Recent Activity List
struct RecentActivityList: View {
    let events: [AuthEvent]
    private let colors = HeartIDColors()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Activity")
                    .font(.headline)
                Spacer()
                
                NavigationLink {
                    ActivityLogView()
                } label: {
                    Text("View All")
                        .font(.caption)
                        .foregroundColor(colors.accent)
                }
            }
            
            if events.isEmpty {
                Text("No recent activity")
                    .font(.subheadline)
                    .foregroundColor(colors.text.opacity(0.7))
                    .padding(.vertical, 8)
            } else {
                ForEach(events.prefix(3)) { event in
                    HStack {
                        Circle()
                            .fill(event.success ? colors.success : colors.error)
                            .frame(width: 8, height: 8)
                        Text(eventDescription(for: event))
                            .font(.subheadline)
                        Spacer()
                        Text(timeAgo(from: event.timestamp))
                            .font(.caption)
                            .foregroundColor(colors.text.opacity(0.6))
                    }
                }
            }
        }
        .padding()
        .background(colors.surface)
        .cornerRadius(16)
    }
    
    func eventDescription(for event: AuthEvent) -> String {
        let action: String
        switch event.eventType {
        case .biometricAuth, .passwordAuth:
            action = "Authentication"
        case .signIn:
            action = "Sign In"
        case .signOut:
            action = "Sign Out"
        case .failedAttempt:
            action = "Failed Attempt"
        case .accountLocked:
            action = "Account Locked"
        case .passwordReset:
            action = "Password Reset"
        case .tokenRefresh:
            action = "Token Refresh"
        }

        return "\(action) \(event.success ? "Successful" : "Failed")"
    }
    
    func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Heart Rate Wave View
struct HeartRateWaveView: View {
    @State private var phase: CGFloat = 0
    let active: Bool
    private let colors = HeartIDColors()
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let width = size.width
                let height = size.height
                let midHeight = height / 2
                
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: midHeight))
                        for x in stride(from: 0, through: width, by: 2) {
                            let angle = (x / width) * 2 * .pi + phase
                            let y = midHeight + sin(angle * 2) * (height / 4)
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    },
                    with: .color(active ? colors.accent : colors.text.opacity(0.3)),
                    lineWidth: 2
                )
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                phase = 2 * .pi
            }
        }
    }
}

// MARK: - Authentication Status
enum AuthenticationStatus {
    case active
    case inactive
    case warning
    case error
    
    var icon: String {
        switch self {
        case .active: return "checkmark.shield.fill"
        case .inactive: return "shield.fill"
        case .warning: return "exclamationmark.shield.fill"
        case .error: return "xmark.shield.fill"
        }
    }
    
    var color: Color {
        let colors = HeartIDColors()
        switch self {
        case .active: return colors.success
        case .inactive: return colors.text.opacity(0.5)
        case .warning: return colors.warning
        case .error: return colors.error
        }
    }
    
    var title: String {
        switch self {
        case .active: return "Protected"
        case .inactive: return "Not Protected"
        case .warning: return "Action Required"
        case .error: return "Authentication Failed"
        }
    }
    
    var description: String {
        switch self {
        case .active: return "Your identity is being continuously verified"
        case .inactive: return "Tap to start identity verification"
        case .warning: return "Please verify your identity"
        case .error: return "Unable to verify identity. Try again"
        }
    }
}

// MARK: - Authentication Detail View (Placeholder)
struct AuthenticationDetailView: View {
    let event: AuthEvent
    @Environment(\.dismiss) private var dismiss
    private let colors = HeartIDColors()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Authentication details will be implemented here
                    Text("Authentication Details")
                        .font(.title2)
                }
                .padding()
            }
            .background(colors.background)
            .navigationTitle("Authentication Details")
            .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
    }
}


#Preview {
    NavigationView {
        DashboardView()
            .environmentObject(AuthenticationManager())
            .environmentObject(WatchConnectivityService.shared)
            .environmentObject(AuthViewModel())
    }
}
