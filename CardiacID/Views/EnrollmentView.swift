import SwiftUI
import HealthKit

struct EnrollmentView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var currentStep = 0
    @State private var progress: CGFloat = 0.0
    private let colors = HeartIDColors()
    
    let steps = [
        EnrollmentStep(
            title: "Welcome to HeartID",
            description: "Secure your digital identity with your unique cardiac signature",
            icon: "heart.circle.fill"
        ),
        EnrollmentStep(
            title: "Connect Your Device",
            description: "Pair your Apple Watch or other supported wearable",
            icon: "applewatch"
        ),
        EnrollmentStep(
            title: "Baseline Capture",
            description: "We'll record your cardiac pattern for 2-3 minutes",
            icon: "waveform.path"
        ),
        EnrollmentStep(
            title: "Verification",
            description: "Quick test to ensure everything works perfectly",
            icon: "checkmark.shield.fill"
        )
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // Progress Bar
                ProgressBar(progress: progress)
                    .frame(height: 6)
                    .padding(.horizontal)
                
                // Step Content
                if currentStep < steps.count {
                    StepContent(step: steps[currentStep])
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                
                Spacer()
                
                // Navigation Buttons
                if currentStep == steps.count - 1 {
                    Button(action: completeEnrollment) {
                        Text("Complete Setup")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(colors.accent)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                } else {
                    Button(action: nextStep) {
                        Text("Continue")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(colors.accent)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
                
                if currentStep > 0 {
                    Button(action: previousStep) {
                        Text("Back")
                            .foregroundColor(colors.text)
                    }
                    .padding(.bottom)
                }
            }
            .padding(.vertical)
            .background(colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Skip") {
                completeEnrollment()
            })
        }
    }
    
    private func nextStep() {
        withAnimation {
            currentStep += 1
            progress = CGFloat(currentStep) / CGFloat(steps.count - 1)
        }
    }
    
    private func previousStep() {
        withAnimation {
            currentStep -= 1
            progress = CGFloat(currentStep) / CGFloat(steps.count - 1)
        }
    }
    
    private func completeEnrollment() {
        // Update AuthenticationManager enrollment status
        authManager.setEnrolled(true)
        
        // Start monitoring if not already started
        if !authManager.isMonitoring {
            authManager.startMonitoring()
        }
        
        dismiss()
    }
}

struct EnrollmentStep {
    let title: String
    let description: String
    let icon: String
}

struct StepContent: View {
    let step: EnrollmentStep
    private let colors = HeartIDColors()
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: step.icon)
                .font(.system(size: 60))
                .foregroundColor(colors.accent)
            
            VStack(spacing: 12) {
                Text(step.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text(step.description)
                    .font(.body)
                    .foregroundColor(colors.text.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
    }
}

struct ProgressBar: View {
    let progress: CGFloat
    private let colors = HeartIDColors()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(colors.surface)
                
                Rectangle()
                    .fill(colors.accent)
                    .frame(width: geometry.size.width * progress)
            }
            .cornerRadius(3)
        }
    }
}

#Preview {
    EnrollmentView()
}
