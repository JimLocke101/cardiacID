// PasskeyStepUpView.swift
// CardiacID
//
// Modal sheet for step-up verification of privileged actions.
// Presented with .medium detent over existing content.
// Requires 0.92 cardiac confidence — the highest assurance tier.

import SwiftUI

struct PasskeyStepUpView: View {
    @ObservedObject var flowManager: HeartIDPasskeyFlowManager
    @EnvironmentObject private var watchConnectivity: WatchConnectivityService
    @Environment(\.dismiss) private var dismiss

    let actionDescription: String
    let userID: UUID
    let credentialIDs: [Data]
    let onAuthorized: () -> Void

    private let colors = HeartIDColors()
    private let stepUpThreshold = PasskeyActionType.stepUpVerification.minimumCardiacConfidence
    private let authThreshold = PasskeyActionType.registration.minimumCardiacConfidence

    var body: some View {
        VStack(spacing: 0) {
            // Gold accent bar
            colors.accent
                .frame(height: 4)
                .frame(maxWidth: .infinity)

            VStack(spacing: 22) {
                header
                confidenceRing
                statusLine
                actionButtons
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .background(colors.background.ignoresSafeArea())
        .onChange(of: flowManager.flowState) { newState in
            if newState == .success {
                // Brief pause so the user sees the success state
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    onAuthorized()
                    dismiss()
                }
            }
        }
        .onDisappear {
            if flowManager.flowState != .success {
                flowManager.reset()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 28))
                .foregroundColor(colors.accent)

            Text("Step-Up Verification")
                .font(.headline).fontWeight(.bold)
                .foregroundColor(colors.text)

            Text("Authorizing: \(actionDescription)")
                .font(.subheadline)
                .foregroundColor(colors.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }

    // MARK: - Confidence Ring

    private var confidenceRing: some View {
        let confidence = watchConnectivity.liveBiometricConfidence

        return ZStack {
            // Track
            Circle()
                .stroke(colors.primary, lineWidth: 10)
                .frame(width: 110, height: 110)

            // Fill
            Circle()
                .trim(from: 0, to: confidence)
                .stroke(ringColor(for: confidence), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .frame(width: 110, height: 110)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.35), value: confidence)

            // Center label
            VStack(spacing: 2) {
                Text("\(Int(confidence * 100))")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(colors.text)
                Text("%")
                    .font(.caption2)
                    .foregroundColor(colors.secondary)
            }
        }
    }

    private func ringColor(for confidence: Double) -> Color {
        if confidence >= stepUpThreshold { return colors.success }
        if confidence >= authThreshold   { return colors.accent }
        return colors.error
    }

    // MARK: - Status Line

    private var statusLine: some View {
        let confidence = watchConnectivity.liveBiometricConfidence
        let meetsThreshold = confidence >= stepUpThreshold

        return Group {
            switch flowManager.flowState {
            case .idle:
                if meetsThreshold {
                    Label("Ready to authorize", systemImage: "checkmark.circle.fill")
                        .font(.subheadline).foregroundColor(colors.success)
                } else {
                    Text("Requires \(Int(stepUpThreshold * 100))% cardiac confidence")
                        .font(.subheadline).foregroundColor(colors.warning)
                }

            case .requestingChallenge:
                HStack(spacing: 8) {
                    ProgressView().progressViewStyle(.circular).scaleEffect(0.8).tint(colors.accent)
                    Text("Preparing challenge...").font(.subheadline).foregroundColor(colors.secondary)
                }

            case .awaitingCardiacConfirmation, .presentingPasskeyUI:
                HStack(spacing: 8) {
                    ProgressView().progressViewStyle(.circular).scaleEffect(0.8).tint(colors.accent)
                    Text("Verifying...").font(.subheadline).foregroundColor(colors.secondary)
                }

            case .verifyingAssertion:
                HStack(spacing: 8) {
                    ProgressView().progressViewStyle(.circular).scaleEffect(0.8).tint(colors.accent)
                    Text("Completing...").font(.subheadline).foregroundColor(colors.secondary)
                }

            case .success:
                Label("Authorized", systemImage: "checkmark.seal.fill")
                    .font(.subheadline).fontWeight(.semibold).foregroundColor(colors.success)

            case .failed:
                Text(flowManager.lastError?.localizedDescription ?? "Authorization failed")
                    .font(.caption).foregroundColor(colors.error)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Buttons

    private var actionButtons: some View {
        let confidence = watchConnectivity.liveBiometricConfidence
        let enabled = confidence >= stepUpThreshold
        let isProcessing = ![.idle, .success, .failed].contains(flowManager.flowState)

        return VStack(spacing: 12) {
            // Authorize button
            Button(action: authorize) {
                HStack(spacing: 8) {
                    if isProcessing {
                        ProgressView().progressViewStyle(.circular).scaleEffect(0.75).tint(colors.primary)
                    } else {
                        Image(systemName: "checkmark.shield.fill")
                    }
                    Text(isProcessing ? "Authorizing..." : "Authorize")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(enabled && !isProcessing ? colors.accent : colors.secondary.opacity(0.25))
                .foregroundColor(enabled && !isProcessing ? colors.primary : colors.secondary)
                .cornerRadius(11)
            }
            .disabled(!enabled || isProcessing)

            // Cancel / Try Again
            if flowManager.flowState == .failed {
                Button(action: { flowManager.reset() }) {
                    Text("Try Again")
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(colors.accent)
                }
            } else if !isProcessing && flowManager.flowState != .success {
                Button(action: { dismiss() }) {
                    Text("Cancel")
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(colors.secondary)
                }
            }
        }
    }

    // MARK: - Action

    private func authorize() {
        let confidence = watchConnectivity.liveBiometricConfidence
        Task {
            // UX: 0.5s minimum animation so the user sees the confirmation state
            // rather than an instantaneous jump through intermediate states.
            async let minDelay: Void = Task.sleep(nanoseconds: 500_000_000)
            async let flow: Void = flowManager.startStepUp(
                for: userID,
                credentialIDs: credentialIDs,
                cardiacConfidence: confidence,
                actionDescription: actionDescription
            )
            _ = try? await minDelay
            await flow
        }
    }
}

// MARK: - Preview

#if DEBUG
struct PasskeyStepUpView_Previews: PreviewProvider {
    static var previews: some View {
        Color.black
            .ignoresSafeArea()
            .sheet(isPresented: .constant(true)) {
                PasskeyStepUpView(
                    flowManager: HeartIDPasskeyFlowManager(),
                    actionDescription: "Export User Data",
                    userID: UUID(),
                    credentialIDs: [Data("preview-cred".utf8)],
                    onAuthorized: {}
                )
                .environmentObject(WatchConnectivityService.shared)
                .presentationDetents([.medium])
            }
    }
}
#endif
