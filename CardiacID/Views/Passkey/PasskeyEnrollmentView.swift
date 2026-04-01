// PasskeyEnrollmentView.swift
// CardiacID
//
// Guides the user through registering a passkey gated by HeartID cardiac verification.
// Observes HeartIDPasskeyFlowManager for state transitions and live confidence.

import SwiftUI

struct PasskeyEnrollmentView: View {
    @ObservedObject var flowManager: HeartIDPasskeyFlowManager
    @EnvironmentObject private var watchConnectivity: WatchConnectivityService

    let userID: UUID
    let userName: String

    private let colors = HeartIDColors()
    private let registrationThreshold = PasskeyActionType.registration.minimumCardiacConfidence

    var body: some View {
        ZStack {
            colors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    headerSection
                    explanationCard
                    confidenceCard
                    actionSection
                }
                .padding()
            }
        }
        .navigationTitle("Register Passkey")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(colors.accent.opacity(0.12))
                    .frame(width: 88, height: 88)

                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 38))
                    .foregroundColor(colors.accent)
            }

            Text("Cardiac Passkey")
                .font(.title2).fontWeight(.bold)
                .foregroundColor(colors.text)

            Text("Your heartbeat becomes your password")
                .font(.subheadline)
                .foregroundColor(colors.secondary)
        }
        .padding(.top, 8)
    }

    // MARK: - Explanation Card

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("How it works", systemImage: "info.circle.fill")
                .font(.subheadline).fontWeight(.semibold)
                .foregroundColor(colors.accent)

            Text("Your cardiac signature will authorize your passkey — a secure credential stored on this device that replaces passwords for HeartID sign-in.")
                .font(.subheadline)
                .foregroundColor(colors.text.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            Divider().background(colors.secondary.opacity(0.2))

            HStack(spacing: 16) {
                benefitItem(icon: "lock.shield.fill", text: "Phishing-resistant")
                benefitItem(icon: "heart.fill", text: "Cardiac-gated")
                benefitItem(icon: "iphone", text: "On-device only")
            }
        }
        .padding()
        .background(colors.card)
        .cornerRadius(14)
    }

    private func benefitItem(icon: String, text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(colors.accent)
            Text(text)
                .font(.caption2).fontWeight(.medium)
                .foregroundColor(colors.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Confidence Card

    private var confidenceCard: some View {
        let confidence = watchConnectivity.liveBiometricConfidence
        let meetsThreshold = confidence >= registrationThreshold

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Cardiac Confidence", systemImage: "waveform.path.ecg")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(colors.text)
                Spacer()
                Text(String(format: "%.0f%%", confidence * 100))
                    .font(.title3).fontWeight(.bold)
                    .foregroundColor(meetsThreshold ? colors.accent : colors.error)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 5)
                        .fill(colors.primary)
                        .frame(height: 10)

                    // Fill
                    RoundedRectangle(cornerRadius: 5)
                        .fill(meetsThreshold ? colors.accent : colors.error)
                        .frame(width: geo.size.width * confidence, height: 10)
                        .animation(.easeInOut(duration: 0.4), value: confidence)

                    // Threshold marker
                    RoundedRectangle(cornerRadius: 1)
                        .fill(colors.text.opacity(0.5))
                        .frame(width: 2, height: 16)
                        .offset(x: geo.size.width * registrationThreshold - 1)
                }
            }
            .frame(height: 16)

            HStack {
                Text("Required: \(String(format: "%.0f%%", registrationThreshold * 100))")
                    .font(.caption).foregroundColor(colors.secondary)
                Spacer()
                if meetsThreshold {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundColor(colors.success)
                } else {
                    Label("Below threshold", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundColor(colors.warning)
                }
            }
        }
        .padding()
        .background(colors.card)
        .cornerRadius(14)
    }

    // MARK: - Action Section

    @ViewBuilder
    private var actionSection: some View {
        switch flowManager.flowState {
        case .idle:
            registerButton

        case .requestingChallenge:
            statusView(
                icon: nil,
                message: "Preparing secure challenge...",
                showSpinner: true
            )

        case .awaitingCardiacConfirmation:
            statusView(
                icon: "heart.fill",
                message: "Verifying cardiac signature...",
                showSpinner: true
            )

        case .presentingPasskeyUI:
            statusView(
                icon: "person.badge.key.fill",
                message: "Awaiting device confirmation...",
                showSpinner: true
            )

        case .verifyingAssertion:
            statusView(
                icon: nil,
                message: "Securing your credential...",
                showSpinner: true
            )

        case .success:
            successView

        case .failed:
            failedView
        }
    }

    private var registerButton: some View {
        let confidence = watchConnectivity.liveBiometricConfidence
        let enabled = confidence >= registrationThreshold

        return Button(action: {
            Task {
                await flowManager.startRegistration(
                    for: userID,
                    userName: userName,
                    cardiacConfidence: confidence
                )
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: "person.badge.key.fill")
                Text("Register Passkey")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(enabled ? colors.accent : colors.secondary.opacity(0.3))
            .foregroundColor(enabled ? colors.primary : colors.secondary)
            .cornerRadius(12)
        }
        .disabled(!enabled)
        .padding(.horizontal, 4)

    }

    // MARK: - Status Views

    private func statusView(icon: String?, message: String, showSpinner: Bool) -> some View {
        VStack(spacing: 16) {
            if showSpinner {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.2)
                    .tint(colors.accent)
            }
            if let icon {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(colors.accent)
            }
            Text(message)
                .font(.subheadline).fontWeight(.medium)
                .foregroundColor(colors.text)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(colors.card)
        .cornerRadius(14)
    }

    private var successView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundColor(colors.success)

            Text("Passkey Registered")
                .font(.headline).fontWeight(.bold)
                .foregroundColor(colors.text)

            Text("Your cardiac signature is your key.")
                .font(.subheadline)
                .foregroundColor(colors.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(colors.card)
        .cornerRadius(14)
    }

    private var failedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 38))
                .foregroundColor(colors.error)

            Text(flowManager.lastError?.localizedDescription ?? "Registration failed")
                .font(.subheadline)
                .foregroundColor(colors.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: { flowManager.reset() }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Try Again")
                        .fontWeight(.semibold)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 28)
                .background(colors.accent)
                .foregroundColor(colors.primary)
                .cornerRadius(10)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(colors.card)
        .cornerRadius(14)
    }
}

// MARK: - Preview

#if DEBUG
struct PasskeyEnrollmentView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PasskeyEnrollmentView(
                flowManager: HeartIDPasskeyFlowManager(),
                userID: UUID(),
                userName: "john.doe@acme.com"
            )
            .environmentObject(WatchConnectivityService.shared)
        }
        .preferredColorScheme(.dark)
    }
}
#endif
