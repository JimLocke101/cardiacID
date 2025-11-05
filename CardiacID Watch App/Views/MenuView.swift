import SwiftUI

struct MenuView: View {
    @EnvironmentObject var authenticationService: AuthenticationService
    @EnvironmentObject var dataManager: DataManager
    @State private var showingEnroll = false
    @State private var showingAuthenticate = false
    @State private var showingSettings = false
    @State private var showingCalibrate = false
    @State private var showingSecurityLevel = false
    @State private var showingAlarmNotification = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.red)
                        
                        Text("HeartID")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Menu")
                            .font(.system(size: 12)) // Reduced from .title2 (22pt) by 30% to ~15pt, then further reduced
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        if authenticationService.isUserEnrolled {
                            Text("Enrolled")
                                .font(.caption)
                                .foregroundColor(.green)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(8)
                        } else {
                            Text("Not Enrolled")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.2))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.bottom, 20)
                    
                    // Menu Items
                    VStack(spacing: 12) {
                        MenuButton(
                            title: "Enroll",
                            icon: "person.badge.plus",
                            color: .blue,
                            isEnabled: !authenticationService.isUserEnrolled
                        ) {
                            showingEnroll = true
                        }
                        
                        MenuButton(
                            title: "Authenticate",
                            icon: "checkmark.shield",
                            color: .green,
                            isEnabled: authenticationService.isUserEnrolled
                        ) {
                            showingAuthenticate = true
                        }
                        
                        MenuButton(
                            title: "Calibrate",
                            icon: "tuningfork",
                            color: .purple,
                            isEnabled: authenticationService.isUserEnrolled
                        ) {
                            showingCalibrate = true
                        }
                        
                        MenuButton(
                            title: "Security Level",
                            icon: "lock.shield",
                            color: .orange,
                            isEnabled: true
                        ) {
                            showingSecurityLevel = true
                        }
                        
                        MenuButton(
                            title: "Alarm Notification",
                            icon: "bell",
                            color: .red,
                            isEnabled: true
                        ) {
                            showingAlarmNotification = true
                        }
                        
                        MenuButton(
                            title: "Settings",
                            icon: "gear",
                            color: .gray,
                            isEnabled: true
                        ) {
                            showingSettings = true
                        }
                    }
                    
                    Spacer()
                    
                    // Status Information
                    if authenticationService.isUserEnrolled {
                        VStack(spacing: 8) {
                            Text("Authentication Status")
                                .font(.headline)
                            
                            HStack {
                                Circle()
                                    .fill(authenticationService.isAuthenticated ? Color.green : Color.red)
                                    .frame(width: 12, height: 12)
                                
                                Text(authenticationService.isAuthenticated ? "Authenticated" : "Not Authenticated")
                                    .font(.caption)
                            }
                            
                            if let lastResult = authenticationService.lastAuthenticationResult {
                                Text("Last Result: \(lastResult.message)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showingEnroll) {
            EnrollView()
        }
        .sheet(isPresented: $showingAuthenticate) {
            AuthenticateView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingCalibrate) {
            CalibrateView()
        }
        .sheet(isPresented: $showingSecurityLevel) {
            SecurityLevelView()
        }
        .sheet(isPresented: $showingAlarmNotification) {
            AlarmNotificationView()
        }
    }
}

struct MenuButton: View {
    let title: String
    let icon: String
    let color: Color
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isEnabled ? color : .gray)
                    .frame(width: 30)
                
                Text(title)
                    .font(.headline)
                    .foregroundColor(isEnabled ? .primary : .gray)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isEnabled ? color.opacity(0.1) : Color.gray.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isEnabled ? color.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .disabled(!isEnabled)
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Supporting Views

struct CalibrateView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authenticationService: AuthenticationService
    @EnvironmentObject var healthKitService: HealthKitService
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Calibration")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Calibration helps improve authentication accuracy by analyzing your heart pattern in different conditions.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Start Calibration") {
                    // Start calibration process
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Calibrate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SecurityLevelView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedLevel: SecurityLevel
    
    init() {
        _selectedLevel = State(initialValue: .medium)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Security Level")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Choose your preferred security level. Higher levels provide more security but may require more precise heart pattern matching.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                
                VStack(spacing: 12) {
                    ForEach(SecurityLevel.allCases, id: \.self) { level in
                        SecurityLevelRow(
                            level: level,
                            isSelected: selectedLevel == level
                        ) {
                            selectedLevel = level
                        }
                    }
                }
                
                Spacer()
                
                Button("Save Security Level") {
                    var preferences = dataManager.userPreferences
                    preferences.securityLevel = selectedLevel
                    dataManager.saveUserPreferences(preferences)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedLevel == dataManager.userPreferences.securityLevel)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Security Level")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            selectedLevel = dataManager.userPreferences.securityLevel
        }
    }
}

struct SecurityLevelRow: View {
    let level: SecurityLevel
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(level.rawValue)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(level.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.gray)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct AlarmNotificationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    @State private var enableAlarms: Bool
    @State private var enableNotifications: Bool
    
    init() {
        _enableAlarms = State(initialValue: true)
        _enableNotifications = State(initialValue: true)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Alarm & Notifications")
                    .font(.title2)
                    .fontWeight(.bold)
                
                VStack(spacing: 16) {
                    Toggle("Enable Alarms", isOn: $enableAlarms)
                        .toggleStyle(SwitchToggleStyle())
                    
                    Toggle("Enable Notifications", isOn: $enableNotifications)
                        .toggleStyle(SwitchToggleStyle())
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                
                Spacer()
                
                Button("Save Settings") {
                    var preferences = dataManager.userPreferences
                    preferences.enableAlarms = enableAlarms
                    preferences.enableNotifications = enableNotifications
                    dataManager.saveUserPreferences(preferences)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Alarms & Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            enableAlarms = dataManager.userPreferences.enableAlarms
            enableNotifications = dataManager.userPreferences.enableNotifications
        }
    }
}

#Preview {
    MenuView()
        .environmentObject(AuthenticationService())
        .environmentObject(DataManager())
}


