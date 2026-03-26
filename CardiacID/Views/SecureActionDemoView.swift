//
//  SecureActionDemoView.swift
//  CardiacID
//
//  "Secure Operations" — 5 HeartID-gated action buttons.
//  Each routes through HeartAuthPolicyEngine before executing.
//

import SwiftUI

struct SecureActionDemoView: View {
    @StateObject private var sessionTrust  = DefaultSessionTrustManager()
    @StateObject private var identityEngine = HeartIdentityEngine.shared
    @StateObject private var vault         = ProtectedFileVault.shared
    @StateObject private var hwService     = HardwareAuthorizationService.shared
    @StateObject private var passkeyCoord  = PasskeyCoordinator.shared

    @State private var activeAction: ActionItem?
    @State private var lastDecisions: [String: AuthPolicyDecision] = [:]
    @State private var statusMessages: [String: String] = [:]
    @State private var isProcessing = false

    private let colors = HeartIDColors()
    private let policyEngine: any HeartAuthPolicyEngineProtocol = DefaultHeartAuthPolicyEngine()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                sessionBanner
                ForEach(actions) { item in
                    actionCard(item)
                }
            }
            .padding()
        }
        .background(colors.background.ignoresSafeArea())
        .navigationTitle("Secure Operations")
        .navigationBarTitleDisplayMode(.large)
        .overlay { if isProcessing { processingOverlay } }
    }

    // MARK: - Action Definitions

    struct ActionItem: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let action: ProtectedAction
        let color: Color
    }

    private var actions: [ActionItem] {[
        ActionItem(id: "verify",   title: "Verify with HeartID",     subtitle: "Cardiac biometric identity check",
                   icon: "waveform.path.ecg",           action: .signInToApp,              color: colors.accent),
        ActionItem(id: "file",     title: "Unlock Protected File",   subtitle: "Decrypt vault-protected file",
                   icon: "lock.doc.fill",                action: .unlockProtectedFile,      color: Color(hex: "#2196F3")),
        ActionItem(id: "passkey",  title: "Begin Passkey Sign-In",   subtitle: "FIDO2 WebAuthn assertion",
                   icon: "person.badge.key.fill",        action: .beginPasskeyAssertion,    color: Color(hex: "#9C27B0")),
        ActionItem(id: "sensitive",title: "Authorize Sensitive Action",subtitle: "Elevated privilege operation",
                   icon: "checkmark.shield.fill",        action: .authorizeSensitiveAction,  color: colors.warning),
        ActionItem(id: "hardware", title: "Prepare Hardware Command", subtitle: "Sign command for device control",
                   icon: "cpu.fill",                     action: .authorizeHardwareCommand, color: colors.error),
    ]}

    // MARK: - Session Banner

    private var sessionBanner: some View {
        let trust = sessionTrust.state.currentState
        return HStack(spacing: 12) {
            Image(systemName: trust.systemImage)
                .font(.title3).foregroundColor(trustColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(trust.displayName)
                    .font(.subheadline).fontWeight(.semibold).foregroundColor(colors.text)
                Text(sessionTrust.state.lastVerifiedDescription)
                    .font(.caption).foregroundColor(colors.secondary)
            }
            Spacer()
        }
        .padding()
        .background(trustColor.opacity(0.10))
        .cornerRadius(12)
    }

    // MARK: - Action Card

    private func actionCard(_ item: ActionItem) -> some View {
        let trust = sessionTrust.state.currentState
        let disabled = trust == .denied || trust == .expired || isProcessing

        return Button(action: { execute(item) }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    Image(systemName: item.icon)
                        .font(.title3).foregroundColor(.white)
                        .frame(width: 42, height: 42)
                        .background(disabled ? colors.secondary : item.color)
                        .cornerRadius(10)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(disabled ? colors.secondary : colors.text)
                        Text(item.subtitle)
                            .font(.caption).foregroundColor(colors.secondary)
                    }
                    Spacer()

                    if activeAction?.id == item.id && isProcessing {
                        ProgressView().progressViewStyle(.circular).scaleEffect(0.8).tint(colors.accent)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundColor(colors.secondary)
                    }
                }

                // Inline decision result
                if let decision = lastDecisions[item.id] {
                    DecisionBadge(decision: decision, colors: colors)
                }

                if let msg = statusMessages[item.id] {
                    Text(msg).font(.caption2).foregroundColor(colors.secondary)
                        .lineLimit(2)
                }
            }
            .padding()
            .background(colors.card)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1.0)
    }

    // MARK: - Processing Overlay

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().progressViewStyle(.circular)
                    .scaleEffect(1.3).tint(.white)
                Text(activeAction?.title ?? "Processing…")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
        }
    }

    // MARK: - Execute

    private func execute(_ item: ActionItem) {
        activeAction = item
        isProcessing = true
        lastDecisions[item.id] = nil
        statusMessages[item.id] = nil

        Task {
            defer { isProcessing = false; activeAction = nil }

            // Step 1: HeartID verification
            let result = await identityEngine.verify()
            sessionTrust.recordVerification(result)

            // Step 2: Policy evaluation
            let decision = policyEngine.evaluate(result: result, for: item.action)
            lastDecisions[item.id] = decision

            guard decision.isAllowed else {
                statusMessages[item.id] = decision.rationale
                return
            }

            // Step 3: Execute the action
            await performAction(item)
        }
    }

    private func performAction(_ item: ActionItem) async {
        switch item.action {
        case .signInToApp:
            statusMessages[item.id] = "Session elevated: \(sessionTrust.state.currentState.displayName)"

        case .unlockProtectedFile:
            let ok = await vault.unlock()
            statusMessages[item.id] = ok ? "Vault unlocked." : (vault.errorMessage ?? "Failed.")

        case .beginPasskeyAssertion:
            do {
                try await passkeyCoord.initiateAssertion()
                statusMessages[item.id] = passkeyCoord.state.displayLabel
            } catch {
                statusMessages[item.id] = error.localizedDescription
            }

        case .authorizeSensitiveAction:
            statusMessages[item.id] = "Sensitive action authorized at \(sessionTrust.state.confidencePercentage)."

        case .authorizeHardwareCommand:
            _ = await hwService.authorizeCommand(.unlock)
            statusMessages[item.id] = hwService.lastSignedEnvelope != nil
                ? "Signed envelope created." : (hwService.errorMessage ?? "Failed.")

        default:
            statusMessages[item.id] = "Action completed."
        }
    }

    // MARK: - Helpers

    private var trustColor: Color {
        switch sessionTrust.state.currentState {
        case .unverified:       return colors.secondary
        case .recentlyVerified: return colors.success
        case .elevatedTrust:    return Color(hex: "#2196F3")
        case .expired:          return colors.warning
        case .denied:           return colors.error
        }
    }
}

// MARK: - Decision Badge

private struct DecisionBadge: View {
    let decision: AuthPolicyDecision
    let colors: HeartIDColors

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
            Text(decision.decision.rawValue.capitalized)
                .font(.caption2).fontWeight(.bold)
            Text("·")
            Text(String(format: "%.0f%%", decision.actualScore * 100))
                .font(.caption2)
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .cornerRadius(6)
    }

    private var icon: String {
        switch decision.decision {
        case .allow:        return "checkmark.circle.fill"
        case .deny:         return "xmark.circle.fill"
        case .requireStepUp: return "arrow.up.circle.fill"
        }
    }

    private var color: Color {
        switch decision.decision {
        case .allow:        return colors.success
        case .deny:         return colors.error
        case .requireStepUp: return colors.warning
        }
    }
}
