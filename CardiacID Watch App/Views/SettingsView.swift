import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authenticationService: AuthenticationService
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var backgroundTaskService: BackgroundTaskService
    // @EnvironmentObject var watchConnectivityService: WatchConnectivityService  // Temporarily disabled
    
    @State private var showingClearDataAlert = false
    @State private var showingAbout = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "gear")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        
                        Text("Settings")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    .padding(.top, 20)
                    
                    // Settings Sections
                    VStack(spacing: 16) {
                        // Enrollment Section
                        SettingsSection(title: "Enrollment") {
                            VStack(spacing: 12) {
                                if authenticationService.isUserEnrolled {
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        Text("Enrolled")
                                        Spacer()
                                        Text("✓")
                                            .foregroundColor(.green)
                                    }
                                    
                                    Button("Re-enroll") {
                                        // Handle re-enrollment
                                    }
                                    .buttonStyle(.bordered)
                                } else {
                                    HStack {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .foregroundColor(.orange)
                                        Text("Not Enrolled")
                                        Spacer()
                                        Text("⚠")
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                        }
                        
                        // ECG/PPG Settings
                        SettingsSection(title: "Sensors") {
                            VStack(spacing: 12) {
                                SettingsRow(
                                    title: "ECG",
                                    icon: "waveform.path.ecg",
                                    isEnabled: true
                                ) {
                                    // Handle ECG settings
                                }
                                
                                SettingsRow(
                                    title: "PPG",
                                    icon: "heart.fill",
                                    isEnabled: true
                                ) {
                                    // Handle PPG settings
                                }
                            }
                        }
                        
                        // Collaboration Settings
                        SettingsSection(title: "Collaboration") {
                            VStack(spacing: 12) {
                                // iOS App Connection Status (Temporarily disabled)
                                HStack {
                                    Image(systemName: "iphone")
                                        .font(.title3)
                                        .foregroundColor(.gray)
                                        .frame(width: 24)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("iOS App")
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        
                                        Text("Not Connected")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Circle()
                                        .fill(Color.gray)
                                        .frame(width: 12, height: 12)
                                }
                                .padding(.vertical, 4)
                                
                                SettingsRow(
                                    title: "Bluetooth",
                                    icon: "bluetooth",
                                    isEnabled: dataManager.userPreferences.enableBluetooth
                                ) {
                                    toggleBluetooth()
                                }
                                
                                SettingsRow(
                                    title: "NFC",
                                    icon: "wave.3.right",
                                    isEnabled: dataManager.userPreferences.enableNFC
                                ) {
                                    toggleNFC()
                                }
                            }
                        }
                        
                        // Alarms & Notifications
                        SettingsSection(title: "Alarms & Notifications") {
                            VStack(spacing: 12) {
                                Toggle("Enable Alarms", isOn: Binding(
                                    get: { dataManager.userPreferences.enableAlarms },
                                    set: { updateAlarms($0) }
                                ))
                                
                                Toggle("Enable Notifications", isOn: Binding(
                                    get: { dataManager.userPreferences.enableNotifications },
                                    set: { updateNotifications($0) }
                                ))
                            }
                        }
                        
                        // Security Level
                        SettingsSection(title: "Security") {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Security Level")
                                    Spacer()
                                    Text(dataManager.userPreferences.securityLevel.rawValue)
                                        .foregroundColor(.secondary)
                                }
                                
                                Button("Change Security Level") {
                                    // Handle security level change
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        
                        // Health Integration
                        SettingsSection(title: "Health") {
                            VStack(spacing: 12) {
                                SettingsRow(
                                    title: "HealthKit Integration",
                                    icon: "heart.text.square",
                                    isEnabled: true
                                ) {
                                    // Handle HealthKit settings
                                }
                                
                                SettingsRow(
                                    title: "Health Data Export",
                                    icon: "square.and.arrow.up",
                                    isEnabled: false
                                ) {
                                    // Handle health data export
                                }
                            }
                        }
                        
                        // App Support
                        SettingsSection(title: "Support") {
                            VStack(spacing: 12) {
                                SettingsRow(
                                    title: "About HeartID",
                                    icon: "info.circle",
                                    isEnabled: true
                                ) {
                                    showingAbout = true
                                }
                                
                                SettingsRow(
                                    title: "Help & Support",
                                    icon: "questionmark.circle",
                                    isEnabled: true
                                ) {
                                    // Handle help
                                }
                                
                                SettingsRow(
                                    title: "Privacy Policy",
                                    icon: "hand.raised",
                                    isEnabled: true
                                ) {
                                    // Handle privacy policy
                                }
                            }
                        }
                        
                        // Account Management
                        SettingsSection(title: "Account") {
                            VStack(spacing: 12) {
                                Button("Logout") {
                                    logout()
                                }
                                .buttonStyle(.bordered)
                                .foregroundColor(.blue)
                                
                                Text("Return to login screen")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        
                        // Danger Zone
                        SettingsSection(title: "Data Management") {
                            VStack(spacing: 12) {
                                Button("Clear All Data") {
                                    showingClearDataAlert = true
                                }
                                .buttonStyle(.bordered)
                                .foregroundColor(.red)
                                
                                Text("This will delete all stored heart patterns and settings")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Clear All Data", isPresented: $showingClearDataAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All Data", role: .destructive) {
                clearAllData()
            }
        } message: {
            Text("This action cannot be undone. All your heart patterns and settings will be permanently deleted.")
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
    }
    
    // MARK: - Actions
    
    private func toggleBluetooth() {
        var preferences = dataManager.userPreferences
        preferences.enableBluetooth.toggle()
        dataManager.saveUserPreferences(preferences)
    }
    
    private func toggleNFC() {
        var preferences = dataManager.userPreferences
        preferences.enableNFC.toggle()
        dataManager.saveUserPreferences(preferences)
    }
    
    private func updateAlarms(_ enabled: Bool) {
        var preferences = dataManager.userPreferences
        preferences.enableAlarms = enabled
        dataManager.saveUserPreferences(preferences)
    }
    
    private func updateNotifications(_ enabled: Bool) {
        var preferences = dataManager.userPreferences
        preferences.enableNotifications = enabled
        dataManager.saveUserPreferences(preferences)
    }
    
    private func logout() {
        authenticationService.logout()
        dismiss()
    }
    
    private func clearAllData() {
        authenticationService.clearAllData()
        dismiss()
    }
}

// MARK: - Supporting Views

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            content
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

struct SettingsRow: View {
    let title: String
    let icon: String
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(isEnabled ? .blue : .gray)
                    .frame(width: 24)
                
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if isEnabled {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // App Icon and Name
                    VStack(spacing: 12) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.red)
                        
                        Text("HeartID")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Version 1.0.0")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)
                    
                    // Description
                    VStack(alignment: .leading, spacing: 12) {
                        Text("About HeartID")
                            .font(.headline)
                        
                        Text("HeartID is a revolutionary biometric authentication system that uses your unique heart pattern for secure identity verification. Our proprietary XenonX algorithm analyzes your heart's rhythm, variability, and morphological characteristics to create a secure, encrypted identifier that stays private on your Apple Watch.")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Features
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Key Features")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            FeatureRow(icon: "shield.checkered", text: "Secure biometric authentication")
                            FeatureRow(icon: "lock.shield", text: "End-to-end encryption")
                            FeatureRow(icon: "heart.fill", text: "PPG sensor integration")
                            FeatureRow(icon: "waveform.path.ecg", text: "ECG pattern analysis")
                            FeatureRow(icon: "bell", text: "Background monitoring")
                            FeatureRow(icon: "hand.raised", text: "Privacy-first design")
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Privacy Notice
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Privacy & Security")
                            .font(.headline)
                        
                        Text("Your heart pattern data is encrypted and stored securely on your Apple Watch. No biometric data is transmitted to external servers or shared with third parties. All processing happens locally on your device.")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("About")
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

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(text)
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthenticationService())
        .environmentObject(DataManager())
        .environmentObject(BackgroundTaskService())
        // .environmentObject(WatchConnectivityService())  // Temporarily disabled
}


