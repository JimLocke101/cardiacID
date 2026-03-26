//
//  SecurityDebugView.swift
//  CardiacID
//
//  PolicyDebugView — DEBUG builds only.
//  Editable thresholds, raw verification data, session timeline, simulation.
//  NOT accessible in Release builds.
//

import SwiftUI

// The entire view is wrapped in #if DEBUG.
// The NavigationLink in MenuView is also wrapped in #if DEBUG.

#if DEBUG

struct PolicyDebugView: View {
    @StateObject private var sessionTrust = DefaultSessionTrustManager()
    @StateObject private var identityEngine = HeartIdentityEngine.shared

    @State private var policyConfig = PolicyConfiguration.loadFromDefaults()
    @State private var simMatch: Double = 0.85
    @State private var simLiveness: Double = 0.90
    @State private var simResult: HeartVerificationResult?
    @State private var simDecisions: [AuthPolicyDecision] = []
    @State private var selectedTab: DebugTab = .thresholds

    private let colors = HeartIDColors()

    enum DebugTab: String, CaseIterable {
        case thresholds = "Thresholds"
        case session    = "Session"
        case simulate   = "Simulate"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Large red banner
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.white)
                Text("DEBUG — NOT FOR PRODUCTION")
                    .font(.caption).fontWeight(.heavy).foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal).padding(.vertical, 10)
            .background(Color.red)

            Picker("Section", selection: $selectedTab) {
                ForEach(DebugTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()

            switch selectedTab {
            case .thresholds: thresholdsTab
            case .session:    sessionTab
            case .simulate:   simulateTab
            }
        }
        .background(colors.background.ignoresSafeArea())
        .navigationTitle("Policy Debug")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Thresholds Tab

    private var thresholdsTab: some View {
        List {
            Section("Per-Action Thresholds (editable)") {
                ForEach(ProtectedAction.allCases) { action in
                    let binding = Binding<Double>(
                        get: { policyConfig.threshold(for: action) },
                        set: { newVal in
                            policyConfig.setThreshold(newVal, for: action)
                            policyConfig.saveToDefaults()
                        }
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: action.systemImage)
                                .foregroundColor(colors.accent).frame(width: 24)
                            Text(action.displayName).font(.subheadline).foregroundColor(colors.text)
                            Spacer()
                            Text(String(format: "%.0f%%", binding.wrappedValue * 100))
                                .font(.subheadline).fontWeight(.bold)
                                .foregroundColor(colors.warning)
                        }
                        Slider(value: binding, in: 0.50...1.00, step: 0.05)
                            .tint(colors.accent)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(colors.card)
                }
            }

            Section {
                Button("Reset to Production Defaults", role: .destructive) {
                    PolicyConfiguration.resetDefaults()
                    policyConfig = .production
                }
                .listRowBackground(colors.card)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Session Tab

    private var sessionTab: some View {
        List {
            Section("Current Session") {
                debugRow("Trust State", sessionTrust.state.currentState.displayName)
                debugRow("Last Verified", sessionTrust.state.lastVerifiedDescription)
                debugRow("Confidence", sessionTrust.state.confidencePercentage)
            }
            .listRowBackground(colors.card)

            if let result = identityEngine.lastResult {
                Section("Last HeartVerificationResult (raw)") {
                    debugRow("ID", result.id.uuidString.prefix(8) + "…")
                    debugRow("matchConfidence", String(format: "%.4f", result.matchConfidence))
                    debugRow("livenessConfidence", String(format: "%.4f", result.livenessConfidence))
                    debugRow("combinedScore", String(format: "%.4f", result.combinedScore))
                    debugRow("isAuthorized", result.isAuthorized ? "true" : "false")
                    debugRow("isLive", result.isLive ? "true" : "false")
                    debugRow("reasonCodes", result.reasonCodes.map(\.rawValue).joined(separator: ", "))
                    debugRow("timestamp", result.timestamp.formatted(.dateTime))
                }
                .listRowBackground(colors.card)
            }

            Section("Session Trust Timeline") {
                ForEach(TrustLevel.allCases, id: \.self) { level in
                    HStack(spacing: 10) {
                        Image(systemName: level.systemImage)
                            .foregroundColor(level == sessionTrust.state.currentState ? colors.accent : colors.secondary)
                            .frame(width: 24)
                        Text(level.displayName)
                            .font(.subheadline)
                            .foregroundColor(level == sessionTrust.state.currentState ? colors.text : colors.secondary)
                        Spacer()
                        if level == sessionTrust.state.currentState {
                            Text("CURRENT")
                                .font(.caption2).fontWeight(.bold)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(colors.accent)
                                .foregroundColor(colors.primary)
                                .cornerRadius(4)
                        }
                    }
                    .listRowBackground(colors.card)
                }
            }

            Section {
                Button("Reset Session", role: .destructive) {
                    sessionTrust.invalidate()
                }
                .listRowBackground(colors.card)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Simulate Tab

    private var simulateTab: some View {
        List {
            Section("Configurable Confidence") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Match Confidence: \(String(format: "%.0f%%", simMatch * 100))")
                        .font(.subheadline).foregroundColor(colors.text)
                    Slider(value: $simMatch, in: 0...1, step: 0.05)
                        .tint(colors.accent)
                }
                .listRowBackground(colors.card)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Liveness Confidence: \(String(format: "%.0f%%", simLiveness * 100))")
                        .font(.subheadline).foregroundColor(colors.text)
                    Slider(value: $simLiveness, in: 0...1, step: 0.05)
                        .tint(colors.accent)
                }
                .listRowBackground(colors.card)

                Button(action: runSimulation) {
                    Label("Simulate Verification", systemImage: "play.circle.fill")
                        .font(.headline).frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(colors.accent)
                .listRowBackground(colors.card)
            }

            if let result = simResult {
                Section("Simulated Result") {
                    debugRow("Combined", String(format: "%.2f%%", result.combinedScore * 100))
                    debugRow("Authorized", result.isAuthorized ? "YES" : "NO")
                    debugRow("Reasons", result.reasonCodes.map(\.rawValue).joined(separator: ", "))
                }
                .listRowBackground(colors.card)
            }

            if !simDecisions.isEmpty {
                Section("Per-Action Policy Decisions") {
                    ForEach(simDecisions) { decision in
                        HStack {
                            Image(systemName: decision.action.systemImage)
                                .foregroundColor(colors.accent).frame(width: 24)
                            Text(decision.action.displayName)
                                .font(.caption).foregroundColor(colors.text)
                            Spacer()
                            Text(decision.decision.rawValue.uppercased())
                                .font(.caption2).fontWeight(.bold)
                                .foregroundColor(decisionColor(decision.decision))
                        }
                        .listRowBackground(colors.card)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Helpers

    private func runSimulation() {
        let result = HeartVerificationResult.verified(
            match: simMatch, liveness: simLiveness
        )
        simResult = result
        sessionTrust.recordVerification(result)

        let engine = DefaultHeartAuthPolicyEngine(configuration: policyConfig)
        simDecisions = ProtectedAction.allCases.map { action in
            engine.evaluate(result: result, for: action)
        }
    }

    private func debugRow(_ label: String, _ value: some StringProtocol) -> some View {
        HStack {
            Text(label).font(.caption).foregroundColor(colors.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value).font(.caption).fontWeight(.medium).foregroundColor(colors.text)
            Spacer()
        }
    }

    private func decisionColor(_ d: PolicyDecision) -> Color {
        switch d {
        case .allow:       return colors.success
        case .deny:        return colors.error
        case .requireStepUp: return colors.warning
        }
    }
}

// Keep old name as typealias so existing MenuView reference compiles
typealias SecurityDebugView = PolicyDebugView

#else

// Release builds: SecurityDebugView is a no-op placeholder that should
// never be reachable (the NavigationLink is also gated by #if DEBUG).
struct SecurityDebugView: View {
    var body: some View {
        Text("Not available in Release builds.")
    }
}

#endif
