import SwiftUI

struct AuthenticateView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authenticationService: AuthenticationService
    @EnvironmentObject var healthKitService: HealthKitService
    
    @State private var authenticationState: AuthenticationViewState = .ready
    @State private var captureProgress: Double = 0
    @State private var currentHeartRate: Double = 0
    @State private var retryCount = 0
    @State private var showingResult = false
    @State private var lastResult: AuthenticationResult?
    
    private let maxRetries = 3
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 50))
                            .foregroundColor(.green)
                        
                        Text("Authenticate")
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        Text("Verify your identity using your heart pattern")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)
                    
                    // Status Display
                    VStack(spacing: 16) {
                        switch authenticationState {
                        case .ready:
                            ReadyStateView()
                        case .capturing:
                            CapturingStateView(
                                progress: captureProgress,
                                heartRate: currentHeartRate
                            )
                        case .processing:
                            ProcessingStateView()
                        case .result(let result):
                            ResultStateView(result: result, retryCount: retryCount)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(16)
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        switch authenticationState {
                        case .ready:
                            Button("Start Authentication") {
                                startAuthentication()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!healthKitService.isAuthorized)
                            
                            if !healthKitService.isAuthorized {
                                Button("Authorize HealthKit") {
                                    healthKitService.requestAuthorization()
                                }
                                .buttonStyle(.bordered)
                            }
                            
                        case .capturing:
                            Button("Stop Capture") {
                                stopCapture()
                            }
                            .buttonStyle(.bordered)
                            
                        case .processing:
                            // Processing state - no action buttons
                            EmptyView()
                            
                        case .result(let result):
                            if result.requiresRetry && retryCount < maxRetries {
                                Button("Try Again") {
                                    retryAuthentication()
                                }
                                .buttonStyle(.borderedProminent)
                            } else if result.isSuccessful {
                                Button("Continue") {
                                    showingResult = true
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                Button("Start Over") {
                                    resetAuthentication()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Instructions
                    if authenticationState == .ready {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Instructions:")
                                .font(.headline)
                            
                            Text("• Place your finger on the Digital Crown")
                            Text("• Keep your wrist stable")
                            Text("• Remain still during capture")
                            Text("• The process takes 9-16 seconds")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    // Retry Information
                    if retryCount > 0 && retryCount < maxRetries {
                        Text("Attempt \(retryCount) of \(maxRetries)")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
            .navigationTitle("Authenticate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(authenticationState == .capturing)
                }
            }
        }
        .onReceive(healthKitService.$captureProgress) { progress in
            captureProgress = progress
        }
        .onReceive(healthKitService.$currentHeartRate) { heartRate in
            currentHeartRate = heartRate
        }
        .onReceive(healthKitService.$errorMessage) { error in
            if error != nil {
                authenticationState = .result(.failed)
            }
        }
        .alert("Authentication Result", isPresented: $showingResult) {
            Button("OK") {
                dismiss()
            }
        } message: {
            if let result = lastResult {
                Text(result.message)
            }
        }
    }
    
    // MARK: - Actions
    
    private func startAuthentication() {
        guard healthKitService.isAuthorized else {
            return
        }
        
        authenticationState = .capturing
        retryCount = 0
        
        // Start heart rate capture
        healthKitService.startHeartRateCapture(duration: AppConfiguration.defaultCaptureDuration)
        
        // Listen for completion
        DispatchQueue.main.asyncAfter(deadline: .now() + AppConfiguration.defaultCaptureDuration + 1) {
            if authenticationState == .capturing {
                completeAuthentication()
            }
        }
    }
    
    private func stopCapture() {
        healthKitService.stopHeartRateCapture()
        completeAuthentication()
    }
    
    private func completeAuthentication() {
        authenticationState = .processing
        
        // Get captured heart rate data
        let heartRateData = healthKitService.heartRateSamples.map { $0.value }
        
        // Validate data
        guard healthKitService.validateHeartRateData(healthKitService.heartRateSamples) else {
            authenticationState = .result(.failed)
            return
        }
        
        // Perform authentication
        let result = authenticationService.completeAuthentication(with: heartRateData)
        lastResult = result
        
        // Update retry count if needed
        if result.requiresRetry {
            retryCount += 1
        }
        
        authenticationState = .result(result)
    }
    
    private func retryAuthentication() {
        authenticationState = .ready
        startAuthentication()
    }
    
    private func resetAuthentication() {
        authenticationState = .ready
        retryCount = 0
        lastResult = nil
        healthKitService.clearError()
    }
}

// MARK: - State Views

enum AuthenticationViewState: Equatable {
    case ready
    case capturing
    case processing
    case result(AuthenticationResult)
}

struct ResultStateView: View {
    let result: AuthenticationResult
    let retryCount: Int
    
    var body: some View {
        VStack(spacing: 16) {
            // Result Icon
            Image(systemName: resultIcon)
                .font(.system(size: 50))
                .foregroundColor(resultColor)
            
            // Result Text
            Text(resultTitle)
                .font(.headline)
                .foregroundColor(resultColor)
            
            Text(result.message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            // Additional Info
            if result.requiresRetry && retryCount < 3 {
                Text("Please try again for better accuracy")
                    .font(.caption2)
                    .foregroundColor(.orange)
            } else if result == .systemUnavailable {
                Text("Please try again later")
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
    }
    
    private var resultIcon: String {
        switch result {
        case .success, .approved:
            return "checkmark.circle.fill"
        case .retryRequired:
            return "exclamationmark.triangle.fill"
        case .failure, .failed:
            return "xmark.circle.fill"
        case .pending:
            return "clock.fill"
        case .cancelled:
            return "xmark.circle"
        case .systemUnavailable:
            return "wifi.slash"
        }
    }
    
    private var resultColor: Color {
        switch result {
        case .success, .approved:
            return .green
        case .retryRequired:
            return .orange
        case .failure, .failed, .systemUnavailable:
            return .red
        case .pending:
            return .blue
        case .cancelled:
            return .gray
        }
    }
    
    private var resultTitle: String {
        switch result {
        case .success, .approved:
            return "Authentication Successful!"
        case .retryRequired:
            return "Please Try Again"
        case .failure, .failed:
            return "Authentication Failed"
        case .pending:
            return "Authentication Pending"
        case .cancelled:
            return "Authentication Cancelled"
        case .systemUnavailable:
            return "System Unavailable"
        }
    }
}

#Preview {
    AuthenticateView()
        .environmentObject(AuthenticationService())
        .environmentObject(HealthKitService())
}


