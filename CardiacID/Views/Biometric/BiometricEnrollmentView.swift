//
//  BiometricEnrollmentView.swift
//  CardiacID
//
//  Created for Phase 5 - iOS UI Implementation
//  Biometric enrollment flow with 3 ECG samples
//

import SwiftUI

struct BiometricEnrollmentView: View {
    @StateObject private var viewModel = BiometricEnrollmentViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color(hex: "1a1a2e"), Color(hex: "16213e")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    enrollmentHeader

                    // Content based on state
                    ScrollView {
                        VStack(spacing: 24) {
                            switch viewModel.enrollmentState {
                            case .welcome:
                                welcomeContent
                            case .instructions:
                                instructionsContent
                            case .capturingECG(let sampleNumber):
                                capturingECGContent(sampleNumber: sampleNumber)
                            case .processing:
                                processingContent
                            case .success:
                                successContent
                            case .error(let message):
                                errorContent(message: message)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 32)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            await viewModel.initialize()
        }
    }

    // MARK: - Header

    private var enrollmentHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 44, height: 44)
                }

                Spacer()

                if case .capturingECG = viewModel.enrollmentState {
                    Text("Sample \(viewModel.currentSampleNumber)/3")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Progress bar
            if viewModel.showProgress {
                ProgressView(value: viewModel.progress)
                    .tint(Color(hex: "e94560"))
                    .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Welcome

    private var welcomeContent: some View {
        VStack(spacing: 24) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color(hex: "e94560").opacity(0.2))
                    .frame(width: 120, height: 120)

                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(Color(hex: "e94560"))
            }
            .padding(.top, 40)

            // Title
            VStack(spacing: 12) {
                Text("HeartID Enrollment")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)

                Text("Set up your cardiac biometric authentication")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            // Features
            VStack(spacing: 20) {
                FeatureRow(
                    icon: "lock.shield.fill",
                    title: "96-99% Accuracy",
                    description: "ECG-based cardiac signature authentication"
                )

                FeatureRow(
                    icon: "applewatch",
                    title: "Apple Watch Required",
                    description: "Uses your watch's ECG sensor for enrollment"
                )

                FeatureRow(
                    icon: "clock.fill",
                    title: "2 Minutes Setup",
                    description: "3 quick ECG recordings to create your template"
                )
            }
            .padding(.vertical, 24)

            // Start button
            Button(action: { viewModel.startEnrollment() }) {
                HStack {
                    Text("Get Started")
                        .font(.system(size: 18, weight: .semibold))

                    Image(systemName: "arrow.right")
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color(hex: "e94560"))
                .cornerRadius(16)
            }
            .padding(.top, 16)

            Spacer()
        }
    }

    // MARK: - Instructions

    private var instructionsContent: some View {
        VStack(spacing: 24) {
            // Animation or illustration
            ZStack {
                Circle()
                    .fill(Color(hex: "0f3460").opacity(0.5))
                    .frame(width: 160, height: 160)

                Image(systemName: "applewatch.watchface")
                    .font(.system(size: 80))
                    .foregroundColor(Color(hex: "e94560"))
            }
            .padding(.top, 20)

            VStack(spacing: 16) {
                Text("How to Record ECG")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                Text("Follow these steps for best results:")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
            }

            VStack(spacing: 16) {
                InstructionStep(
                    number: 1,
                    title: "Open Health App",
                    description: "Open the Health app on your Apple Watch"
                )

                InstructionStep(
                    number: 2,
                    title: "Navigate to ECG",
                    description: "Find and open the Electrocardiogram (ECG) feature"
                )

                InstructionStep(
                    number: 3,
                    title: "Rest Your Arm",
                    description: "Place your arm on a flat surface for stability"
                )

                InstructionStep(
                    number: 4,
                    title: "Place Finger",
                    description: "Hold your finger on the Digital Crown for 30 seconds"
                )

                InstructionStep(
                    number: 5,
                    title: "Stay Still",
                    description: "Remain still and calm during the recording"
                )
            }
            .padding(.vertical, 16)

            Button(action: { viewModel.beginCapture() }) {
                Text("I'm Ready")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color(hex: "e94560"))
                    .cornerRadius(16)
            }

            Spacer()
        }
    }

    // MARK: - Capturing ECG

    private func capturingECGContent(sampleNumber: Int) -> some View {
        VStack(spacing: 32) {
            Spacer()

            // Animated pulse
            ZStack {
                ForEach(0..<3) { index in
                    Circle()
                        .stroke(Color(hex: "e94560").opacity(0.3), lineWidth: 2)
                        .frame(width: 140 + CGFloat(index * 40), height: 140 + CGFloat(index * 40))
                        .scaleEffect(viewModel.pulseAnimation ? 1.2 : 0.8)
                        .opacity(viewModel.pulseAnimation ? 0 : 1)
                        .animation(
                            Animation.easeInOut(duration: 1.5)
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 0.3),
                            value: viewModel.pulseAnimation
                        )
                }

                Circle()
                    .fill(Color(hex: "e94560"))
                    .frame(width: 140, height: 140)

                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 60))
                    .foregroundColor(.white)
            }

            VStack(spacing: 16) {
                Text("Recording ECG Sample \(sampleNumber)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                Text("Please record an ECG on your Apple Watch")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)

                if viewModel.isWaiting {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)

                        Text("Waiting for recording... (\(viewModel.timeoutRemaining)s)")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.top, 8)
                }
            }

            // Tips
            VStack(alignment: .leading, spacing: 12) {
                Text("Tips for Best Quality:")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                TipRow(icon: "hand.raised.fill", text: "Keep your arm still on a table")
                TipRow(icon: "applewatch", text: "Ensure watch fits snugly on wrist")
                TipRow(icon: "moon.zzz.fill", text: "Breathe calmly and relax")
            }
            .padding(20)
            .background(Color.white.opacity(0.05))
            .cornerRadius(16)

            Spacer()

            // Cancel button
            Button(action: { viewModel.cancelEnrollment() }) {
                Text("Cancel")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Processing

    private var processingContent: some View {
        VStack(spacing: 32) {
            Spacer()

            // Processing animation
            ZStack {
                Circle()
                    .stroke(Color(hex: "e94560").opacity(0.2), lineWidth: 4)
                    .frame(width: 140, height: 140)

                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Color(hex: "e94560"), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(viewModel.rotationAngle))
                    .animation(Animation.linear(duration: 1).repeatForever(autoreverses: false), value: viewModel.rotationAngle)

                Image(systemName: "brain.head.profile")
                    .font(.system(size: 60))
                    .foregroundColor(Color(hex: "e94560"))
            }

            VStack(spacing: 12) {
                Text("Creating Your Template")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                Text("Analyzing cardiac signatures from 3 ECG samples")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
    }

    // MARK: - Success

    private var successContent: some View {
        VStack(spacing: 32) {
            Spacer()

            // Success animation
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 140, height: 140)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
            }
            .scaleEffect(viewModel.successScale)
            .animation(.spring(response: 0.5, dampingFraction: 0.6), value: viewModel.successScale)

            VStack(spacing: 16) {
                Text("Enrollment Complete!")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                Text("Your cardiac biometric template has been created")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            // Stats
            HStack(spacing: 24) {
                StatCard(title: "Quality", value: "\(Int(viewModel.templateQuality * 100))%", icon: "star.fill")
                StatCard(title: "Samples", value: "3", icon: "waveform.path.ecg")
                StatCard(title: "Confidence", value: "\(Int(viewModel.initialConfidence * 100))%", icon: "shield.checkmark.fill")
            }
            .padding(.vertical, 24)

            Button(action: { dismiss() }) {
                Text("Continue")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.green)
                    .cornerRadius(16)
            }

            Spacer()
        }
    }

    // MARK: - Error

    private func errorContent(message: String) -> some View {
        VStack(spacing: 32) {
            Spacer()

            // Error icon
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 140, height: 140)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.red)
            }

            VStack(spacing: 16) {
                Text("Enrollment Failed")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                Text(message)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button(action: { viewModel.retryEnrollment() }) {
                    Text("Try Again")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color(hex: "e94560"))
                        .cornerRadius(16)
                }

                Button(action: { dismiss() }) {
                    Text("Cancel")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            Spacer()
        }
    }
}

// MARK: - Supporting Views

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(Color(hex: "e94560"))
                .frame(width: 44, height: 44)
                .background(Color(hex: "e94560").opacity(0.2))
                .cornerRadius(12)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)

                Text(description)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()
        }
    }
}

struct InstructionStep: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(hex: "e94560"))
                    .frame(width: 32, height: 32)

                Text("\(number)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)

                Text(description)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()
        }
    }
}

struct TipRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "e94560"))
                .frame(width: 24)

            Text(text)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.white.opacity(0.8))

            Spacer()
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(Color(hex: "e94560"))

            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - ViewModel

@MainActor
class BiometricEnrollmentViewModel: ObservableObject {
    @Published var enrollmentState: EnrollmentState = .welcome
    @Published var progress: Double = 0.0
    @Published var currentSampleNumber: Int = 0
    @Published var isWaiting: Bool = false
    @Published var timeoutRemaining: Int = 180
    @Published var pulseAnimation: Bool = false
    @Published var rotationAngle: Double = 0
    @Published var successScale: CGFloat = 0.5
    @Published var templateQuality: Double = 0.0
    @Published var initialConfidence: Double = 0.0

    private let heartIDService = HeartIDService()
    private let hybridStorage = HybridTemplateStorageService()
    private var timeoutTask: Task<Void, Never>?

    var showProgress: Bool {
        switch enrollmentState {
        case .capturingECG, .processing:
            return true
        default:
            return false
        }
    }

    enum EnrollmentState {
        case welcome
        case instructions
        case capturingECG(sampleNumber: Int)
        case processing
        case success
        case error(message: String)
    }

    func initialize() async {
        // Initialize HeartID service
        await heartIDService.initialize()
    }

    func startEnrollment() {
        withAnimation {
            enrollmentState = .instructions
        }
    }

    func beginCapture() {
        withAnimation {
            enrollmentState = .capturingECG(sampleNumber: 1)
            currentSampleNumber = 1
            progress = 0.0
        }

        startPulseAnimation()
        performEnrollment()
    }

    private func performEnrollment() {
        Task {
            do {
                isWaiting = true
                startTimeoutCountdown()

                // Perform enrollment (3 ECG samples)
                try await heartIDService.beginEnrollment(userId: "user@example.com") // TODO: Get real user ID

                // Enrollment successful
                timeoutTask?.cancel()
                isWaiting = false

                // Get template quality and confidence
                if let template = try? await hybridStorage.loadTemplate() {
                    templateQuality = template.qualityScore
                    initialConfidence = heartIDService.currentConfidence
                }

                withAnimation {
                    enrollmentState = .processing
                    rotationAngle = 360
                }

                // Simulate processing
                try? await Task.sleep(nanoseconds: 2_000_000_000)

                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    enrollmentState = .success
                    successScale = 1.0
                }

            } catch {
                timeoutTask?.cancel()
                isWaiting = false

                withAnimation {
                    enrollmentState = .error(message: error.localizedDescription)
                }
            }
        }
    }

    private func startPulseAnimation() {
        pulseAnimation = true
    }

    private func startTimeoutCountdown() {
        timeoutRemaining = 180
        timeoutTask = Task {
            while timeoutRemaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                timeoutRemaining -= 1
            }
        }
    }

    func cancelEnrollment() {
        timeoutTask?.cancel()
        // Reset state if needed
    }

    func retryEnrollment() {
        withAnimation {
            enrollmentState = .instructions
            progress = 0.0
            currentSampleNumber = 0
        }
    }
}

// MARK: - Color Extension

#Preview {
    BiometricEnrollmentView()
}
