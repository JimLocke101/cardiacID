import SwiftUI
import Combine

/// View for managing enterprise authentication (Entra ID, Active Directory)
struct EnterpriseAuthView: View {
    @StateObject private var entraIDService: EntraIDService
    @StateObject private var watchConnectivity = WatchConnectivityService.shared
    @State private var isAuthenticating = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    init(entraIDService: EntraIDService) {
        self._entraIDService = StateObject(wrappedValue: entraIDService)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "building.2.crop.circle")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Enterprise Authentication")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Connect to your organization's identity system")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)
                
                // Authentication Status
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: entraIDService.isAuthenticated ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(entraIDService.isAuthenticated ? .green : .red)
                        
                        Text(entraIDService.isAuthenticated ? "Connected to Enterprise" : "Not Connected")
                            .fontWeight(.medium)
                    }
                    
                    if let user = entraIDService.currentUser {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Welcome, \(user.displayName)")
                                .font(.headline)
                            
                            Text(user.email)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            if let jobTitle = user.jobTitle {
                                Text(jobTitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                }
                
                // Authentication Actions
                VStack(spacing: 16) {
                    if entraIDService.isAuthenticated {
                        Button(action: signOut) {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                Text("Sign Out")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    } else {
                        Button(action: signIn) {
                            HStack {
                                if isAuthenticating {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "person.badge.key")
                                }
                                Text(isAuthenticating ? "Connecting..." : "Sign In with Entra ID")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(isAuthenticating)
                    }
                }
                
                // Enterprise Features
                if entraIDService.isAuthenticated {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Available Features")
                            .font(.headline)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            EnterpriseFeatureCard(
                                icon: "lock.shield",
                                title: "Door Access",
                                description: "Control office doors",
                                isEnabled: entraIDService.hasPermission(.doorAccess)
                            )
                            
                            EnterpriseFeatureCard(
                                icon: "wave.3.right",
                                title: "NFC Access",
                                description: "Contactless authentication",
                                isEnabled: entraIDService.hasPermission(.nfcAccess)
                            )
                            
                            EnterpriseFeatureCard(
                                icon: "antenna.radiowaves.left.and.right",
                                title: "Bluetooth Access",
                                description: "Wireless device control",
                                isEnabled: entraIDService.hasPermission(.bluetoothAccess)
                            )
                            
                            EnterpriseFeatureCard(
                                icon: "heart.fill",
                                title: "Heart ID",
                                description: "Biometric authentication",
                                isEnabled: entraIDService.hasPermission(.heartAuthentication)
                            )
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Enterprise")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Authentication Error", isPresented: $showingAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
            .onReceive(entraIDService.$errorMessage) { error in
                if let error = error {
                    alertMessage = error
                    showingAlert = true
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func signIn() {
        isAuthenticating = true
        entraIDService.authenticate()
        
        // Send authentication request to watch
        watchConnectivity.sendEntraIDAuthRequest()
    }
    
    private func signOut() {
        entraIDService.signOut()
        
        // Send sign out to watch
        watchConnectivity.sendEntraIDAuthResult(success: false, token: nil)
    }
}

// MARK: - Enterprise Feature Card

struct EnterpriseFeatureCard: View {
    let icon: String
    let title: String
    let description: String
    let isEnabled: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(isEnabled ? .blue : .gray)
            
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
            
            Text(description)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(isEnabled ? Color.blue.opacity(0.1) : Color(.systemGray5))
        .cornerRadius(8)
        .opacity(isEnabled ? 1.0 : 0.6)
    }
}

// MARK: - Preview

struct EnterpriseAuthView_Previews: PreviewProvider {
    static var previews: some View {
        EnterpriseAuthView(
            entraIDService: EntraIDService(
                tenantId: "test-tenant",
                clientId: "test-client",
                redirectUri: "test://redirect"
            )
        )
    }
}
