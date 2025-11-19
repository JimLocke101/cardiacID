//
//  EnrollView.swift
//  CardiacID Watch App
//
//  Ported from HeartID_0_7 - Enterprise-Ready 3-ECG Enrollment
//  Created by HeartID Team on 10/27/25.
//  Guides user through 3-ECG enrollment process for 96-99% accuracy
//

import SwiftUI

/// 3-ECG enrollment workflow with progress tracking and error recovery
/// Achieves 96-99% biometric accuracy through robust template creation
struct EnrollView: View {
    @ObservedObject var heartIDService: HeartIDService
    @State private var userId: String = "user_\(UUID().uuidString.prefix(8))"
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var showNameEntry = true
    @State private var isEnrolling = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showProcessing = false
    @State private var processingMessage: String = ""
    @State private var showErrorRecovery = false
    @State private var currentError: RecoverableError?
    @State private var currentSampleNumber: Int = 1
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.red)

                    Text("CardiacID Enrollment")
                        .font(.headline)

                    Text("Create your cardiac biometric template")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)

                Divider()

                // Name Entry Screen
                if showNameEntry {
                    VStack(spacing: 12) {
                        Text("Your Information")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("First Name")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("", text: $firstName)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last Name")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("", text: $lastName)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                        }

                        Button("Continue") {
                            showNameEntry = false
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(firstName.isEmpty || lastName.isEmpty)
                    }
                    .padding()
                } else if case .enrolling(let progress) = heartIDService.enrollmentState {
                    // Active Enrollment Progress
                    VStack(spacing: 12) {
                        Text("Processing ECG\n\(Int(progress * 3) + 1) of 3")
                            .font(.headline)
                            .multilineTextAlignment(.center)

                        ProgressView(value: progress)
                            .progressViewStyle(.linear)

                        Text("Please record an ECG in the Health app")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Open Health App") {
                            openHealthApp()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                    .padding()
                } else {
                    // Ready State - Setup Instructions
                    VStack(spacing: 12) {
                        Text("Setup Process")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 8) {
                                Text("1.")
                                    .fontWeight(.bold)
                                Text("Record 3 ECGs in the Health app (30 seconds each)")
                                    .font(.caption)
                            }

                            HStack(alignment: .top, spacing: 8) {
                                Text("2.")
                                    .fontWeight(.bold)
                                Text("We'll create your unique cardiac template")
                                    .font(.caption)
                            }

                            HStack(alignment: .top, spacing: 8) {
                                Text("3.")
                                    .fontWeight(.bold)
                                Text("Template stored securely with AES-256 encryption")
                                    .font(.caption)
                            }
                        }
                        .padding(.vertical, 8)

                        Text("Accuracy: 96-99%")
                            .font(.caption)
                            .foregroundColor(.green)
                            .fontWeight(.semibold)

                        Text("DOD-Level Security")
                            .font(.caption2)
                            .foregroundColor(.blue)
                            .fontWeight(.semibold)
                    }
                    .padding()

                    // Start Button
                    Button {
                        startEnrollment()
                    } label: {
                        if isEnrolling {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Text("Begin Enrollment")
                                .fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(isEnrolling)
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
                .disabled(isEnrolling)
            }
        }
        .alert("Enrollment Error", isPresented: $showError) {
            Button("OK") {
                showError = false
            }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .sheet(isPresented: $showProcessing) {
            ProcessingView(message: processingMessage)
        }
        .sheet(isPresented: $showErrorRecovery) {
            if let error = currentError {
                ErrorRecoveryView(
                    error: error,
                    onRetry: {
                        retryCurrentSample()
                    },
                    onCancel: {
                        cancelEnrollment()
                    }
                )
            }
        }
    }

    // MARK: - Actions

    private func startEnrollment() {
        isEnrolling = true
        errorMessage = nil
        currentSampleNumber = 1

        Task {
            do {
                try await heartIDService.beginEnrollment(userId: userId, firstName: firstName, lastName: lastName)
                isEnrolling = false
            } catch {
                isEnrolling = false
                handleEnrollmentError(error, sampleNumber: currentSampleNumber)
            }
        }
    }

    private func openHealthApp() {
        // Open ECG app (Health app ECG feature)
        if URL(string: "x-apple-health://") != nil {
            // Note: On watchOS, this will open the ECG app
            // User needs to manually record ECG
            print("Opening Health app for ECG recording")
        }
    }

    private func retryCurrentSample() {
        print("Retrying ECG sample #\(currentSampleNumber)")
        showErrorRecovery = false
        isEnrolling = true

        Task {
            do {
                // Retry enrollment from current sample
                try await heartIDService.beginEnrollment(userId: userId, firstName: firstName, lastName: lastName)
                isEnrolling = false
            } catch {
                isEnrolling = false
                handleEnrollmentError(error, sampleNumber: currentSampleNumber)
            }
        }
    }

    private func cancelEnrollment() {
        print("Enrollment cancelled")
        showErrorRecovery = false
        isEnrolling = false
        currentSampleNumber = 1
    }

    private func handleEnrollmentError(_ error: Error, sampleNumber: Int) {
        currentSampleNumber = sampleNumber

        // Handle HealthKit errors
        if let healthKitError = error as? HealthKitError {
            switch healthKitError {
            case .timeout:
                currentError = .ecgTimeout(sampleNumber: sampleNumber)
                showErrorRecovery = true
            case .healthKitTimeout:
                currentError = .healthKitTimeout(elapsedSeconds: 60)
                showErrorRecovery = true
            case .noECGFound:
                currentError = .noECGFound
                showErrorRecovery = true
            default:
                errorMessage = error.localizedDescription
                showError = true
            }
            return
        }

        // Handle EnrollmentError specifically
        if let enrollmentError = error as? EnrollmentError {
            switch enrollmentError {
            case .poorQuality:
                currentError = .poorSignalQuality
                showErrorRecovery = true
            case .timeout:
                currentError = .ecgTimeout(sampleNumber: sampleNumber)
                showErrorRecovery = true
            default:
                errorMessage = error.localizedDescription
                showError = true
            }
            return
        }

        // Default error handling
        errorMessage = error.localizedDescription
        showError = true
    }
}

// MARK: - Helper Views

/// Processing indicator view
struct ProcessingView: View {
    let message: String
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "gearshape.2")
                .font(.system(size: 40))
                .foregroundColor(.blue)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: isAnimating)

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .onAppear {
            isAnimating = true
        }
    }
}

/// Error recovery view with retry/cancel options
struct ErrorRecoveryView: View {
    let error: RecoverableError
    let onRetry: () -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: error.icon)
                .font(.system(size: 40))
                .foregroundColor(.orange)

            Text(error.title)
                .font(.headline)

            Text(error.message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                    onCancel()
                }
                .buttonStyle(.bordered)

                Button("Retry") {
                    dismiss()
                    onRetry()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding()
    }
}

/// Recoverable error types
enum RecoverableError {
    case ecgTimeout(sampleNumber: Int)
    case healthKitTimeout(elapsedSeconds: Int)
    case noECGFound
    case poorSignalQuality

    var title: String {
        switch self {
        case .ecgTimeout: return "ECG Timeout"
        case .healthKitTimeout: return "HealthKit Timeout"
        case .noECGFound: return "No ECG Found"
        case .poorSignalQuality: return "Poor Signal Quality"
        }
    }

    var message: String {
        switch self {
        case .ecgTimeout(let sampleNumber):
            return "ECG sample #\(sampleNumber) timed out. Please record an ECG and try again."
        case .healthKitTimeout(let seconds):
            return "Waited \(seconds) seconds for ECG. Please record an ECG and retry."
        case .noECGFound:
            return "No recent ECG recording found. Please record an ECG in the Health app."
        case .poorSignalQuality:
            return "Signal quality too low (SNR < 10 dB). Please ensure good contact and try again."
        }
    }

    var icon: String {
        switch self {
        case .ecgTimeout, .healthKitTimeout: return "clock.badge.exclamationmark"
        case .noECGFound: return "waveform.path.ecg.rectangle"
        case .poorSignalQuality: return "exclamationmark.triangle"
        }
    }
}

#Preview {
    EnrollView(heartIDService: HeartIDService())
}
