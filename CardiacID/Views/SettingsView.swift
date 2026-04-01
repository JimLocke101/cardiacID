import SwiftUI
import Combine

struct SettingsView: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    @EnvironmentObject private var watchConnectivity: WatchConnectivityService
    @EnvironmentObject private var authViewModel: AuthViewModel
    
    @AppStorage("setting_continuousAuth") private var continuousAuth = true
    @AppStorage("setting_enhancedSecurity") private var enhancedSecurity = false
    @AppStorage("setting_backupAuth") private var backupAuth = true
    @AppStorage("setting_sensitivity") private var selectedSensitivity = 1
    @AppStorage("setting_dataRetentionDays") private var dataRetentionDays = 30
    @State private var showingConfirmLogout = false
    @State private var showingMenu = false
    @State private var isProcessing = false
    @State private var showClearConfirm = false
    @State private var clearResult: String?

    private let colors = HeartIDColors()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Security Settings Section
                settingsSection(title: "Security") {
                    // Continuous Authentication
                    Toggle(isOn: $continuousAuth) {
                        settingRow(
                            title: "Continuous Authentication",
                            description: "Continuously verify your identity",
                            icon: "checkmark.shield.fill"
                        )
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
                    
                    // Enhanced Security
                    Toggle(isOn: $enhancedSecurity) {
                        settingRow(
                            title: "Enhanced Security",
                            description: "Additional verification for sensitive actions",
                            icon: "lock.shield.fill"
                        )
                    }
                    
                    Divider().background(colors.text.opacity(0.1))
                    
                    // Backup Authentication
                    Toggle(isOn: $backupAuth) {
                        settingRow(
                            title: "Backup Authentication",
                            description: "Use Face ID/Touch ID as fallback",
                            icon: "faceid"
                        )
                    }
                }
                
                // Sensitivity Settings Section
                settingsSection(title: "Sensitivity") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Authentication Sensitivity")
                            .font(.subheadline)
                            .foregroundColor(colors.text)
                        
                        Text("Adjust how closely your cardiac pattern must match for authentication")
                            .font(.caption)
                            .foregroundColor(colors.text.opacity(0.7))
                        
                        Picker("Sensitivity Level", selection: $selectedSensitivity) {
                            Text("Low").tag(0)
                            Text("Medium").tag(1)
                            Text("High").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .padding(.top, 5)
                        .onChange(of: selectedSensitivity) { newValue in
                            authManager.setSensitivityLevel(newValue)
                        }
                        
                        if selectedSensitivity == 2 {
                            Text("Note: High sensitivity may require more frequent verifications")
                                .font(.caption)
                                .foregroundColor(colors.warning)
                                .padding(.top, 5)
                        }
                    }
                }
                
                // Privacy Settings Section
                settingsSection(title: "Privacy & Data") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Data Retention")
                            .font(.subheadline)
                            .foregroundColor(colors.text)
                        
                        Text("Choose how long to keep authentication history")
                            .font(.caption)
                            .foregroundColor(colors.text.opacity(0.7))
                        
                        Picker("Data Retention", selection: $dataRetentionDays) {
                            Text("7 days").tag(7)
                            Text("30 days").tag(30)
                            Text("90 days").tag(90)
                            Text("1 year").tag(365)
                        }
                        .pickerStyle(.segmented)
                        .padding(.top, 5)
                    }
                    
                    Divider().background(colors.text.opacity(0.1))
                    
                    Button(action: { showClearConfirm = true }) {
                        HStack {
                            if isProcessing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: colors.error))
                            } else {
                                Image(systemName: "trash")
                                    .foregroundColor(colors.error)
                            }
                            Text("Clear Authentication History")
                                .foregroundColor(colors.error)
                            Spacer()
                        }
                    }
                    .disabled(isProcessing)

                    if let result = clearResult {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(colors.success)
                    }
                    
                    Divider().background(colors.text.opacity(0.1))
                    
                    NavigationLink(destination: PrivacyPolicyView()) {
                        settingRow(
                            title: "Privacy Policy",
                            description: "Review how your data is protected",
                            icon: "hand.raised.fill"
                        )
                    }
                }
                
                #if DEBUG
                // Debug Section (only in debug builds)
                settingsSection(title: "Debug") {
                    DebugPanelView()
                }
                #endif
                
                // About Section
                settingsSection(title: "About") {
                    // Version info
                    HStack {
                        Text("Version")
                            .foregroundColor(colors.text)
                        Spacer()
                        Text("1.0.0 (25)")
                            .foregroundColor(colors.text.opacity(0.7))
                    }
                    
                    Divider().background(colors.text.opacity(0.1))
                    
                    // Terms of Service
                    NavigationLink(destination: TermsOfServiceView()) {
                        settingRow(
                            title: "Terms of Service",
                            description: "Review legal terms",
                            icon: "doc.text.fill"
                        )
                    }
                }
                
                // Account Actions
                settingsSection(title: "Account") {
                    Button(action: { showingConfirmLogout = true }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(colors.error)
                            Text("Sign Out")
                                .foregroundColor(colors.error)
                            Spacer()
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .background(colors.background)
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                HamburgerMenuButton(showMenu: $showingMenu)
            }
        }
        .sheet(isPresented: $showingMenu) {
            MenuView(isPresented: $showingMenu)
                .environmentObject(authViewModel)
                .environmentObject(authManager)
        }
        .alert("Sign Out", isPresented: $showingConfirmLogout) {
            Button("Sign Out", role: .destructive) { authViewModel.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert("Clear History", isPresented: $showClearConfirm) {
            Button("Clear All", role: .destructive) { performClearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will clear your local audit log. Cloud events are retained per your data retention policy.")
        }
    }
    
    // MARK: - Actions

    private func performClearHistory() {
        isProcessing = true
        AuditLogger.shared.clear()
        clearResult = "Local audit log cleared."
        isProcessing = false
    }

    // MARK: - Helper Views

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
                .foregroundColor(colors.text)
            
            VStack(spacing: 12) {
                content()
            }
            .padding()
            .background(colors.surface)
            .cornerRadius(16)
        }
        .padding(.horizontal)
    }
    
    private func settingRow(title: String, description: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(colors.accent)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(colors.text)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(colors.text.opacity(0.7))
            }
            
            Spacer()
        }
    }
}

// MARK: - Privacy Policy View
struct PrivacyPolicyView: View {
    private let colors = HeartIDColors()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy Policy")
                    .font(.title)
                    .fontWeight(.bold)
                
                Group {
                    sectionTitle("Introduction")
                    
                    Text("HeartID is committed to protecting your privacy and securing your biometric data. This policy explains how we collect, use, and protect your information.")
                        .padding(.bottom, 10)
                    
                    sectionTitle("Data Collection")
                    
                    Text("HeartID collects the following data to provide biometric authentication services:")
                        .padding(.bottom, 5)
                    
                    bulletPoint("Cardiac rhythm patterns for authentication")
                    bulletPoint("Device information for secure connections")
                    bulletPoint("Authentication events for security monitoring")
                    bulletPoint("User account information for profile management")
                    
                    sectionTitle("Zero-Knowledge Architecture")
                    
                    Text("HeartID uses a zero-knowledge architecture, meaning your raw biometric data never leaves your device. Only encrypted templates derived from your cardiac patterns are used for authentication.")
                        .padding(.bottom, 10)
                    
                    sectionTitle("Data Security")
                    
                    Text("We implement industry-leading security measures including:")
                        .padding(.bottom, 5)
                    
                    bulletPoint("End-to-end encryption for all data transfers")
                    bulletPoint("Secure enclave storage for biometric templates")
                    bulletPoint("NIST and ISO/IEC standards compliance")
                    bulletPoint("Regular security audits and penetration testing")
                }
                
                Group {
                    sectionTitle("Data Retention")
                    
                    Text("You control how long your authentication history is retained. By default, this is set to 30 days, but you can adjust this in Settings.")
                        .padding(.bottom, 10)
                    
                    sectionTitle("Your Rights")
                    
                    Text("You have the right to:")
                        .padding(.bottom, 5)
                    
                    bulletPoint("Access your personal data")
                    bulletPoint("Correct inaccurate information")
                    bulletPoint("Delete your data and history")
                    bulletPoint("Export your information")
                    bulletPoint("Withdraw consent at any time")
                    
                    sectionTitle("Compliance")
                    
                    Text("HeartID complies with applicable data protection regulations including HIPAA, GDPR, and CCPA.")
                        .padding(.bottom, 10)
                    
                    sectionTitle("Contact Us")
                    
                    Text("If you have questions about our privacy practices, please contact us at privacy@heartid.com.")
                        .padding(.bottom, 20)
                }
            }
            .padding()
        }
        .background(colors.background)
        .navigationTitle("Privacy Policy")
        .foregroundColor(colors.text)
    }
    
    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.vertical, 5)
    }
    
    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("•")
                .foregroundColor(HeartIDColors().accent)
            Text(text)
                .foregroundColor(HeartIDColors().text.opacity(0.9))
        }
        .padding(.bottom, 5)
    }
}

// MARK: - Terms of Service View
struct TermsOfServiceView: View {
    private let colors = HeartIDColors()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Terms of Service")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Last Updated: May 28, 2025")
                    .font(.subheadline)
                    .foregroundColor(colors.text.opacity(0.7))
                    .padding(.bottom, 20)
                
                Text("These Terms of Service (\"Terms\") govern your access to and use of the HeartID application. By using HeartID, you agree to these Terms and our Privacy Policy.")
                    .padding(.bottom, 10)
                
                // Terms content would be extensive here
                Text("The full terms of service would be displayed here, covering usage rights, limitations of liability, warranty disclaimers, termination conditions, and other legal provisions.")
                    .foregroundColor(colors.text.opacity(0.8))
                    .padding(.bottom, 20)
            }
            .padding()
        }
        .background(colors.background)
        .navigationTitle("Terms of Service")
        .foregroundColor(colors.text)
    }
}

#Preview {
    NavigationView {
        SettingsView()
            .environmentObject(AuthenticationManager())
            .environmentObject(WatchConnectivityService.shared)
            .environmentObject(AuthViewModel())
    }
}
