//
//  SecureDashboardView.swift
//  CardiacID
//
//  HeartID session trust dashboard.
//  Shows trust state, confidence gauge, verification timer, and verify button.
//

import SwiftUI

struct SecureDashboardView: View {
    @StateObject private var sessionTrust = DefaultSessionTrustManager()
    @StateObject private var identityEngine = HeartIdentityEngine.shared
    @StateObject private var vault = ProtectedFileVault.shared

    @State private var isVerifying = false
    @State private var timerTick = Date()

    private let colors = HeartIDColors()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                trustStateCard
                confidenceGauge
                sessionTimerCard
                vaultSummaryCard
            }
            .padding()
        }
        .background(colors.background.ignoresSafeArea())
        .navigationTitle("Secure Dashboard")
        .navigationBarTitleDisplayMode(.large)
        .onReceive(timer) { timerTick = $0 }
    }

    // MARK: - Trust State Card

    private var trustStateCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: trustIcon)
                    .font(.system(size: 40))
                    .foregroundColor(trustColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(sessionTrust.state.currentState.displayName)
                        .font(.title2).fontWeight(.bold)
                        .foregroundColor(trustColor)
                    Text("Last verified: \(sessionTrust.state.lastVerifiedDescription)")
                        .font(.caption).foregroundColor(colors.secondary)
                }
                Spacer()
            }

            Divider().background(colors.secondary.opacity(0.3))

            Button(action: verify) {
                HStack(spacing: 8) {
                    if isVerifying {
                        ProgressView().progressViewStyle(.circular)
                            .scaleEffect(0.8).tint(.white)
                    } else {
                        Image(systemName: "waveform.path.ecg")
                    }
                    Text(isVerifying ? "Verifying…" : "Verify Now")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(colors.accent)
                .foregroundColor(colors.primary)
                .cornerRadius(10)
            }
            .disabled(isVerifying)
        }
        .padding()
        .background(colors.card)
        .cornerRadius(14)
    }

    // MARK: - Circular Confidence Gauge

    private var confidenceGauge: some View {
        VStack(spacing: 12) {
            Text("Combined Confidence")
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(colors.secondary)

            ZStack {
                // Track
                Circle()
                    .stroke(colors.secondary.opacity(0.2), lineWidth: 12)
                    .frame(width: 140, height: 140)

                // Progress
                Circle()
                    .trim(from: 0, to: sessionTrust.state.lastConfidenceScore)
                    .stroke(trustColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: sessionTrust.state.lastConfidenceScore)

                // Percentage label
                VStack(spacing: 2) {
                    Text("\(Int(sessionTrust.state.lastConfidenceScore * 100))")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(colors.text)
                    Text("%")
                        .font(.caption).foregroundColor(colors.secondary)
                }
            }

            if let last = identityEngine.lastResult {
                HStack(spacing: 12) {
                    Label(
                        "Match: \(Int(last.matchConfidence * 100))%",
                        systemImage: "heart.fill"
                    )
                    Label(
                        "Live: \(Int(last.livenessConfidence * 100))%",
                        systemImage: "person.wave.2"
                    )
                }
                .font(.caption).foregroundColor(colors.secondary)
            }
        }
        .padding()
        .background(colors.card)
        .cornerRadius(14)
    }

    // MARK: - Session Timer Card

    private var sessionTimerCard: some View {
        let state = sessionTrust.state
        let showTimer = state.currentState == .recentlyVerified || state.currentState == .elevatedTrust

        return VStack(alignment: .leading, spacing: 10) {
            Label("Session Timer", systemImage: "timer")
                .font(.headline).foregroundColor(colors.text)

            if showTimer, let verified = state.lastVerified {
                let window = state.currentState == .elevatedTrust
                    ? SessionTrustState.elevatedWindow
                    : SessionTrustState.recentWindow
                let remaining = max(0, window - timerTick.timeIntervalSince(verified))
                let minutes = Int(remaining) / 60
                let seconds = Int(remaining) % 60

                HStack {
                    Text(String(format: "Expires in %d:%02d", minutes, seconds))
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(remaining < 60 ? colors.warning : colors.success)
                    Spacer()
                    Text(state.currentState.displayName)
                        .font(.caption)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(trustColor.opacity(0.2))
                        .foregroundColor(trustColor)
                        .cornerRadius(8)
                }
            } else {
                Text("No active session")
                    .font(.body).foregroundColor(colors.secondary)
            }
        }
        .padding()
        .background(colors.card)
        .cornerRadius(14)
    }

    // MARK: - Vault Summary

    private var vaultSummaryCard: some View {
        HStack(spacing: 16) {
            MetricBox(label: "Vault", value: vault.isLocked ? "Locked" : "Open",
                      icon: vault.isLocked ? "lock.fill" : "lock.open.fill",
                      color: vault.isLocked ? colors.warning : colors.success)
            MetricBox(label: "Files", value: "\(vault.items.count)",
                      icon: "doc.fill", color: colors.accent)
            MetricBox(label: "Trust", value: sessionTrust.state.currentState.displayName,
                      icon: trustIcon, color: trustColor)
        }
        .padding()
        .background(colors.card)
        .cornerRadius(14)
    }

    // MARK: - Helpers

    private var trustIcon: String { sessionTrust.state.currentState.systemImage }

    private var trustColor: Color {
        switch sessionTrust.state.currentState {
        case .unverified:       return colors.secondary
        case .recentlyVerified: return colors.success
        case .elevatedTrust:    return Color(hex: "#2196F3")
        case .expired:          return colors.warning
        case .denied:           return colors.error
        }
    }

    private func verify() {
        isVerifying = true
        Task {
            let result = await identityEngine.verify()
            sessionTrust.recordVerification(result)
            isVerifying = false
        }
    }
}

private struct MetricBox: View {
    let label: String; let value: String; let icon: String; let color: Color
    private let colors = HeartIDColors()
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).foregroundColor(color).font(.title2)
            Text(value).font(.caption).fontWeight(.semibold).foregroundColor(colors.text)
            Text(label).font(.caption2).foregroundColor(colors.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.10))
        .cornerRadius(10)
    }
}

// Keep the old name as a typealias so MenuView's existing reference compiles
typealias SecureAccessDashboardView = SecureDashboardView
