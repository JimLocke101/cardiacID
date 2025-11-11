import SwiftUI
import Combine

// MARK: - Supporting Types

struct AuthEvent {
    let eventType: EventType
    let timestamp: Date
    let success: Bool
    let device: String?
    let location: String?
    
    enum EventType {
        case authentication
        case enrollment
        case revocation
    }
}

struct SecuritySettingsView: View {
    // Environment objects
    @EnvironmentObject private var authManager: AuthenticationManager
    @EnvironmentObject private var watchConnectivity: WatchConnectivityService
    @EnvironmentObject private var authViewModel: AuthViewModel
    
    // State properties
    @State private var continuousAuth = true
    @State private var enhancedSecurity = false
    @State private var backupAuth = true
    @State private var selectedSensitivity = 1
    @State private var recentEvents: [AuthEvent] = []
    @State private var isLoading = false
    @State private var showActivityLog = false
    
    // Private properties
    private let colors = HeartIDColors()
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Authentication Settings
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Authentication")
                            .font(.headline)
                        Spacer()
                        
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: colors.accent))
                                .scaleEffect(0.7)
                        }
                    }
                    
                    Toggle(isOn: $continuousAuth) {
                        VStack(alignment: .leading) {
                            Text("Continuous Authentication")
                                .font(.subheadline)
                            Text("Verify identity in real-time")
                                .font(.caption)
                                .foregroundColor(colors.text.opacity(0.6))
                        }
                    }
                    .onChange(of: continuousAuth) { newValue in
                        if newValue {
                            authManager.startMonitoring()
                            watchConnectivity.startMonitoring()
                        } else {
                            authManager.stopMonitoring()
                            watchConnectivity.stopMonitoring()
                        }
                    }
                    
                    Divider().background(colors.text.opacity(0.1))
                    
                    Toggle(isOn: $enhancedSecurity) {
                        VStack(alignment: .leading) {
                            Text("Enhanced Security")
                                .font(.subheadline)
                            Text("Additional verification for sensitive actions")
                                .font(.caption)
                                .foregroundColor(colors.text.opacity(0.6))
                        }
                    }
                    
                    Divider().background(colors.text.opacity(0.1))
                    
                    Toggle(isOn: $backupAuth) {
                        VStack(alignment: .leading) {
                            Text("Backup Authentication")
                                .font(.subheadline)
                            Text("Use Face ID/Touch ID as fallback")
                                .font(.caption)
                                .foregroundColor(colors.text.opacity(0.6))
                        }
                    }
                }
                .padding()
                .background(colors.surface)
                .cornerRadius(16)
                .padding(.horizontal)
                
                // Sensitivity Settings
                VStack(alignment: .leading, spacing: 16) {
                    Text("Sensitivity")
                        .font(.headline)
                    
                    Picker("Sensitivity Level", selection: $selectedSensitivity) {
                        Text("Low").tag(0)
                        Text("Medium").tag(1)
                        Text("High").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedSensitivity) { newValue in
                        authManager.setSensitivityLevel(newValue)
                    }
                    
                    Text("Higher sensitivity may require more frequent verifications")
                        .font(.caption)
                        .foregroundColor(colors.text.opacity(0.6))
                }
                .padding()
                .background(colors.surface)
                .cornerRadius(16)
                .padding(.horizontal)
                
                // Security Log
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Security Log")
                            .font(.headline)
                        Spacer()
                        
                        Button(action: { showActivityLog = true }) {
                            Text("View All")
                                .font(.caption)
                                .foregroundColor(colors.accent)
                        }
                    }
                    
                    if recentEvents.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 10) {
                                Text("No recent activity")
                                    .font(.subheadline)
                                    .foregroundColor(colors.text.opacity(0.7))
                                    .padding(.top, 10)
                            }
                            Spacer()
                        }
                    } else {
                        ForEach(recentEvents.prefix(3)) { event in
                            SecurityLogItem(event: event)
                        }
                    }
                }
                .padding()
                .background(colors.surface)
                .cornerRadius(16)
                .padding(.horizontal)
                
                // Emergency Options
                VStack(alignment: .leading, spacing: 16) {
                    Text("Emergency Options")
                        .font(.headline)
                    
                    Button(action: {
                        // Implement emergency revocation
                        isLoading = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            isLoading = false
                        }
                    }) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(colors.error)
                            Text("Revoke All Authentications")
                                .foregroundColor(colors.error)
                            Spacer()
                        }
                    }
                    
                    Text("Use in case of emergency only. This will immediately revoke all active authentications across all devices.")
                        .font(.caption)
                        .foregroundColor(colors.text.opacity(0.6))
                }
                .padding()
                .background(colors.surface)
                .cornerRadius(16)
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(colors.background)
        .navigationTitle("Security")
        .onAppear {
            loadSecurityData()
        }
        .onDisappear {
            cancellables.removeAll()
        }
        .sheet(isPresented: $showActivityLog) {
            ActivityLogView()
        }
    }
    
    private func loadSecurityData() {
        isLoading = true
        
        // Load sensitivity setting
        selectedSensitivity = UserDefaults.standard.integer(forKey: "sensitivityLevel")

        // Load authentication state
        continuousAuth = authManager.isMonitoring

        // Load recent events using async/await
        Task {
            do {
                let events = try await SupabaseService.shared.getRecentAuthEvents(limit: 3)
                await MainActor.run {
                    self.recentEvents = events
                    self.isLoading = false
                }
            } catch {
                print("Failed to load recent events: \(error)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

struct SecurityLogItem: View {
    let event: AuthEvent
    private let colors = HeartIDColors()
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: event.timestamp, relativeTo: Date())
    }
    
    var body: some View {
        HStack {
            Circle()
                .fill(event.success ? colors.success : colors.error)
                .frame(width: 8, height: 8)
            Text(eventDescription)
                .font(.subheadline)
            Spacer()
            Text(timeAgo)
                .font(.caption)
                .foregroundColor(colors.text.opacity(0.6))
        }
    }
    
    var eventDescription: String {
        let action: String
        switch event.eventType {
        case .authentication: action = "Authentication"
        case .enrollment: action = "Enrollment"
        case .revocation: action = "Revocation"
        }
        
        return "\(action) \(event.success ? "successful" : "failed")"
    }
}

#Preview {
    NavigationView {
        SecuritySettingsView()
            .environmentObject(AuthenticationManager())
            .environmentObject(WatchConnectivityService.shared)
            .environmentObject(AuthViewModel())
    }
}
