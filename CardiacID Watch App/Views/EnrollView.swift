import SwiftUI

struct EnrollView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authenticationService: AuthenticationService
    @EnvironmentObject var healthKitService: HealthKitService
    @EnvironmentObject var dataManager: DataManager
    
    @State private var enrollmentState: EnrollmentState = .ready
    @State private var captureProgress: Double = 0
    @State private var currentHeartRate: Double = 0
    @State private var errorMessage: String?
    @State private var showingSuccess = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
                        
                        Text("Enroll in HeartID")
                            .font(.title3)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        Text("We'll capture your unique heart pattern for secure authentication")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                    }
                    .padding(.top, 10)
                    
                    // Status Display
                    VStack(spacing: 16) {
                        switch enrollmentState {
                        case .ready:
                            ReadyStateView()
                        case .capturing:
                            CapturingStateView(
                                progress: captureProgress,
                                heartRate: currentHeartRate
                            )
                        case .processing:
                            ProcessingStateView()
                        case .completed:
                            CompletedStateView()
                        case .error(let message):
                            ErrorStateView(message: message)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(16)
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        switch enrollmentState {
                        case .ready:
                            Button("Start Enrollment") {
                                startEnrollment()
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
                            
                        case .completed:
                            Button("Continue") {
                                showingSuccess = true
                            }
                            .buttonStyle(.borderedProminent)
                            
                        case .error:
                            Button("Try Again") {
                                resetEnrollment()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    
                    Spacer()
                    
                    // Instructions
                    if enrollmentState == .ready {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Instructions:")
                                .font(.caption)
                                .fontWeight(.semibold)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("• Sit comfortably and remain still")
                                Text("• Place your finger on the Digital Crown")
                                Text("• Keep your wrist stable during capture")
                                Text("• The process takes 9-16 seconds")
                            }
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
            .navigationTitle("Enroll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(enrollmentState == .capturing)
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
            if let error = error {
                enrollmentState = .error(error)
            }
        }
        .alert("Enrollment Successful", isPresented: $showingSuccess) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Your heart pattern has been successfully enrolled. You can now use HeartID for authentication.")
        }
    }
    
    // MARK: - Actions
    
    private func startEnrollment() {
        guard healthKitService.isAuthorized else {
            errorMessage = "HealthKit authorization required"
            return
        }
        
        enrollmentState = .capturing
        errorMessage = nil
        
        // Start heart rate capture
        healthKitService.startHeartRateCapture(duration: AppConfiguration.defaultCaptureDuration)
        
        // Listen for completion
        DispatchQueue.main.asyncAfter(deadline: .now() + AppConfiguration.defaultCaptureDuration + 1) {
            if enrollmentState == .capturing {
                completeEnrollment()
            }
        }
    }
    
    private func stopCapture() {
        healthKitService.stopHeartRateCapture()
        completeEnrollment()
    }
    
    private func completeEnrollment() {
        enrollmentState = .processing
        
        // Get captured heart rate data
        let heartRateData = healthKitService.heartRateSamples.map { $0.value }
        
        // Validate data
        guard healthKitService.validateHeartRateData(healthKitService.heartRateSamples) else {
            enrollmentState = .error("Invalid heart rate data. Please try again.")
            return
        }
        
        // Complete enrollment
        let success = authenticationService.completeEnrollment(with: heartRateData)
        
        if success {
            enrollmentState = .completed
        } else {
            enrollmentState = .error(authenticationService.errorMessage ?? "Enrollment failed")
        }
    }
    
    private func resetEnrollment() {
        enrollmentState = .ready
        captureProgress = 0
        currentHeartRate = 0
        errorMessage = nil
        healthKitService.clearError()
    }
}

// MARK: - State Views

enum EnrollmentState: Equatable {
    case ready
    case capturing
    case processing
    case completed
    case error(String)
}

struct ReadyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart")
                .font(.system(size: 40))
                .foregroundColor(.blue)
            
            Text("Ready to Enroll")
                .font(.headline)
            
            Text("Tap 'Start Enrollment' to begin capturing your heart pattern")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

struct CapturingStateView: View {
    let progress: Double
    let heartRate: Double
    
    var body: some View {
        VStack(spacing: 16) {
            // Progress Circle
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                    .frame(width: 80, height: 80)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: progress)
                
                Text("\(Int(progress * 100))%")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            
            VStack(spacing: 8) {
                Text("Capturing Heart Pattern")
                    .font(.headline)
                
                if heartRate > 0 {
                    Text("Heart Rate: \(Int(heartRate)) BPM")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Text("Please hold still...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct ProcessingStateView: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "gearshape.2")
                .font(.system(size: 40))
                .foregroundColor(.blue)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: isAnimating)
            
            Text("Processing Pattern")
                .font(.headline)
            
            Text("Analyzing your heart pattern and creating secure identifier...")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .onAppear {
            isAnimating = true
        }
    }
}

struct CompletedStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.green)
            
            Text("Enrollment Complete!")
                .font(.headline)
                .foregroundColor(.green)
            
            Text("Your heart pattern has been successfully enrolled and encrypted.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

struct ErrorStateView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.red)
            
            Text("Enrollment Failed")
                .font(.headline)
                .foregroundColor(.red)
            
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    EnrollView()
        .environmentObject(AuthenticationService())
        .environmentObject(HealthKitService())
        .environmentObject(DataManager())
}


