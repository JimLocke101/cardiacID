import SwiftUI
import Combine

/// View for managing passwordless authentication methods
struct PasswordlessAuthView: View {
    @StateObject private var passwordlessService = PasswordlessAuthService()
    @StateObject private var watchConnectivity = WatchConnectivityService.shared
    @State private var isEnrolling = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var selectedMethod: PasswordlessMethod?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "key.horizontal")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                    
                    Text("Passwordless Authentication")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Set up secure authentication without passwords")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                
                // Available Methods
                VStack(alignment: .leading, spacing: 12) {
                    Text("Available Methods")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    LazyVStack(spacing: 8) {
                        ForEach(passwordlessService.availableMethods) { method in
                            PasswordlessMethodRow(
                                method: method,
                                onEnroll: { enrollMethod(method) },
                                onRemove: { removeMethod(method) }
                            )
                        }
                    }
                }
                
                // Enrolled Methods
                if !passwordlessService.getEnrolledMethods().isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Enrolled Methods")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        LazyVStack(spacing: 8) {
                            ForEach(passwordlessService.getEnrolledMethods()) { method in
                                EnrolledMethodRow(method: method)
                            }
                        }
                    }
                }
                
                // Authentication Test
                if !passwordlessService.getEnrolledMethods().isEmpty {
                    VStack(spacing: 12) {
                        Text("Test Authentication")
                            .font(.headline)
                        
                        Button(action: testAuthentication) {
                            HStack {
                                Image(systemName: "person.badge.key")
                                Text("Test with Heart ID")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                Spacer()
            }
            .navigationTitle("Passwordless")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Authentication Result", isPresented: $showingAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
            .onReceive(passwordlessService.$errorMessage) { error in
                if let error = error {
                    alertMessage = error
                    showingAlert = true
                }
            }
            .onReceive(passwordlessService.enrollmentPublisher) { result in
                if result.success {
                    alertMessage = "Successfully enrolled in \(result.method.name)"
                } else {
                    alertMessage = "Failed to enroll in \(result.method.name): \(result.error ?? "Unknown error")"
                }
                showingAlert = true
            }
            .onReceive(passwordlessService.authResultPublisher) { result in
                if result.success {
                    alertMessage = "Authentication successful with \(result.method.name)"
                } else {
                    alertMessage = "Authentication failed with \(result.method.name): \(result.error ?? "Unknown error")"
                }
                showingAlert = true
            }
        }
    }
    
    // MARK: - Actions
    
    private func enrollMethod(_ method: PasswordlessMethod) {
        isEnrolling = true
        selectedMethod = method
        
        // Create a mock heart pattern for Heart ID enrollment
        let heartPattern = HeartPattern(
            heartRateData: [70, 72, 68, 75, 73, 71, 74, 69, 76, 72],
            duration: 10.0,
            encryptedIdentifier: "mock_encrypted_id",
            qualityScore: 0.9,
            confidence: 0.85
        )
        
        passwordlessService.enroll(method: method, with: heartPattern)
        
        // Send enrollment request to watch
        if let heartPatternData = try? JSONEncoder().encode(heartPattern) {
            Task {
                await watchConnectivity.sendPasswordlessAuthRequest(
                    method: method.type.rawValue,
                    heartPattern: heartPatternData
                )
            }
        }
        
        // Simulate enrollment delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isEnrolling = false
        }
    }
    
    private func removeMethod(_ method: PasswordlessMethod) {
        passwordlessService.removeEnrollment(method: method)
        alertMessage = "Removed \(method.name) from enrolled methods"
        showingAlert = true
    }
    
    private func testAuthentication() {
        guard let heartIDMethod = passwordlessService.getEnrolledMethods().first(where: { $0.type == .heartID }) else {
            alertMessage = "Heart ID is not enrolled"
            showingAlert = true
            return
        }
        
        // Create a mock heart pattern for authentication
        let heartPattern = HeartPattern(
            heartRateData: [70, 72, 68, 75, 73],
            duration: 5.0,
            encryptedIdentifier: "mock_encrypted_id",
            qualityScore: 0.9,
            confidence: 0.85
        )
        
        passwordlessService.authenticate(method: heartIDMethod, with: heartPattern)
        
        // Send authentication request to watch
        if let heartPatternData = try? JSONEncoder().encode(heartPattern) {
            Task {
                await watchConnectivity.sendPasswordlessAuthRequest(
                    method: heartIDMethod.type.rawValue,
                    heartPattern: heartPatternData
                )
            }
        }
    }
}

// MARK: - Passwordless Method Row

struct PasswordlessMethodRow: View {
    let method: PasswordlessMethod
    let onEnroll: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Method Icon
            Image(systemName: methodIcon)
                .font(.title2)
                .foregroundColor(methodColor)
                .frame(width: 30)
            
            // Method Info
            VStack(alignment: .leading, spacing: 4) {
                Text(method.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(methodDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Action Button
            if method.isEnrolled {
                Button(action: onRemove) {
                    Text("Remove")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            } else {
                Button(action: onEnroll) {
                    Text("Enroll")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(method.isAvailable ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(!method.isAvailable)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var methodIcon: String {
        switch method.type {
        case .biometric:
            return "faceid"
        case .fido2:
            return "key.horizontal"
        case .nfc:
            return "wave.3.right"
        case .bluetooth:
            return "antenna.radiowaves.left.and.right"
        case .heartID:
            return "heart.fill"
        }
    }
    
    private var methodColor: Color {
        if method.isEnrolled {
            return .green
        } else if method.isAvailable {
            return .blue
        } else {
            return .gray
        }
    }
    
    private var methodDescription: String {
        switch method.type {
        case .biometric:
            return "Use Face ID or Touch ID"
        case .fido2:
            return "FIDO2 / WebAuthn standard"
        case .nfc:
            return "Near Field Communication"
        case .bluetooth:
            return "Bluetooth device pairing"
        case .heartID:
            return "Heart pattern authentication"
        }
    }
}

// MARK: - Enrolled Method Row

struct EnrolledMethodRow: View {
    let method: PasswordlessMethod
    
    var body: some View {
        HStack(spacing: 12) {
            // Method Icon
            Image(systemName: methodIcon)
                .font(.title2)
                .foregroundColor(.green)
                .frame(width: 30)
            
            // Method Info
            VStack(alignment: .leading, spacing: 4) {
                Text(method.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Enrolled and ready to use")
                    .font(.subheadline)
                    .foregroundColor(.green)
            }
            
            Spacer()
            
            // Status Indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                
                Text("Active")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var methodIcon: String {
        switch method.type {
        case .biometric:
            return "faceid"
        case .fido2:
            return "key.horizontal"
        case .nfc:
            return "wave.3.right"
        case .bluetooth:
            return "antenna.radiowaves.left.and.right"
        case .heartID:
            return "heart.fill"
        }
    }
}

// MARK: - Preview

struct PasswordlessAuthView_Previews: PreviewProvider {
    static var previews: some View {
        PasswordlessAuthView()
    }
}
