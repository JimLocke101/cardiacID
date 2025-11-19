//
//  SettingsView.swift
//  CardiacID Watch App
//
//  Ported from HeartID_0_7 - Enterprise-Ready Configuration
//  Created by HeartID Team on 10/27/25.
//  Configurable settings: 88-99% accuracy thresholds, battery management, integration modes, factory reset
//

import SwiftUI

/// Comprehensive settings interface with confidence thresholds, battery management, and enterprise integration
struct SettingsView: View {
    @ObservedObject var heartIDService: HeartIDService
    @Environment(\.dismiss) private var dismiss

    @State private var minimumAccuracy: Double
    @State private var fullAccessThreshold: Double
    @State private var conditionalAccessThreshold: Double
    @State private var selectedIntegrationMode: IntegrationMode
    @State private var ppgUsageMultiplier: Double
    @State private var confidenceCheckIntervalMinutes: Double
    @State private var showingUnenrollConfirmation = false
    @State private var showingFactoryResetConfirmation = false
    @State private var showingDemoResetConfirmation = false

    init(heartIDService: HeartIDService) {
        self.heartIDService = heartIDService
        _minimumAccuracy = State(initialValue: heartIDService.thresholds.minimumAccuracy)
        _fullAccessThreshold = State(initialValue: heartIDService.thresholds.fullAccess)
        _conditionalAccessThreshold = State(initialValue: heartIDService.thresholds.conditionalAccess)
        _selectedIntegrationMode = State(initialValue: heartIDService.currentIntegrationMode)
        _ppgUsageMultiplier = State(initialValue: heartIDService.batterySettings.ppgUsageMultiplier)
        _confidenceCheckIntervalMinutes = State(initialValue: heartIDService.batterySettings.confidenceCheckIntervalMinutes)
    }

    var body: some View {
        NavigationStack {
            Form {
                accuracyThresholdsSection
                quickPresetsSection
                batteryManagementSection
                integrationModeSection
                deviceInfoSection
                dangerZoneSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveSettings()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .alert("Unenroll Device?", isPresented: $showingUnenrollConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                heartIDService.unenroll()
                dismiss()
            }
        } message: {
            Text("This will permanently delete your biometric template with secure AES-256 key wipe. You will need to enroll again to use CardiacID.")
        }
        .alert("Factory Reset?", isPresented: $showingFactoryResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset All", role: .destructive) {
                heartIDService.factoryReset()
                dismiss()
            }
        } message: {
            Text("This will delete ALL app data including template, settings, and thresholds with DOD-level secure wipe. Cannot be undone!")
        }
        .alert("Demo Reset?", isPresented: $showingDemoResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                heartIDService.demoReset()
                dismiss()
            }
        } message: {
            Text("This will delete your template but keep your settings (thresholds, integration mode). Use this for quick re-enrollment during demos.")
        }
    }
    
    // MARK: - View Components
    
    private var accuracyThresholdsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Minimum Accuracy")
                        .font(.caption)
                    Spacer()
                    Text("\(Int(minimumAccuracy * 100))%")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }

                Slider(value: $minimumAccuracy, in: 0.88...0.99, step: 0.01)

                Text("ECG authentication must meet this accuracy")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Full Access")
                        .font(.caption)
                    Spacer()
                    Text("\(Int(fullAccessThreshold * 100))%")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }

                Slider(value: $fullAccessThreshold, in: 0.70...0.95, step: 0.01)

                Text("Confidence for unrestricted access")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Conditional Access")
                        .font(.caption)
                    Spacer()
                    Text("\(Int(conditionalAccessThreshold * 100))%")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.yellow)
                }

                Slider(value: $conditionalAccessThreshold, in: 0.60...0.85, step: 0.01)

                Text("Limited access with step-up available")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        } header: {
            Label("Confidence Thresholds", systemImage: "slider.horizontal.3")
                .font(.caption)
        }
    }
    
    private var quickPresetsSection: some View {
        Section {
            Button("High Security (98%)") {
                applyPreset(.highSecurity)
            }
            .font(.caption)

            Button("Balanced (96%)") {
                applyPreset(.default)
            }
            .font(.caption)

            Button("Low Friction (88%)") {
                applyPreset(.lowFriction)
            }
            .font(.caption)
        } header: {
            Text("Quick Presets")
                .font(.caption)
        }
    }
    
    private var batteryManagementSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("PPG Usage")
                        .font(.caption)
                    Spacer()
                    Text("\(Int(ppgUsageMultiplier * 100))%")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(batteryColor(for: ppgUsageMultiplier))
                }

                Slider(value: $ppgUsageMultiplier, in: 0.2...1.0, step: 0.1)

                Text("Background PPG sensor usage (lower = better battery)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Check Interval")
                        .font(.caption)
                    Spacer()
                    Text("\(Int(confidenceCheckIntervalMinutes)) min")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }

                Slider(value: $confidenceCheckIntervalMinutes, in: 5...60, step: 5)

                Text("Time between confidence level updates")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Battery Presets
            HStack(spacing: 4) {
                Button("Max") {
                    applyBatteryPreset(.default)
                }
                .font(.caption2)
                .buttonStyle(.bordered)

                Button("Balanced") {
                    applyBatteryPreset(.balanced)
                }
                .font(.caption2)
                .buttonStyle(.bordered)

                Button("Saver") {
                    applyBatteryPreset(.powerSaver)
                }
                .font(.caption2)
                .buttonStyle(.bordered)
            }
        } header: {
            Label("Battery Management", systemImage: "battery.100")
                .font(.caption)
        } footer: {
            Text("Lower usage and longer intervals save battery but may reduce authentication accuracy.")
                .font(.caption2)
        }
    }
    
    private var integrationModeSection: some View {
        Section {
            Picker("Mode", selection: $selectedIntegrationMode) {
                ForEach(IntegrationMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue)
                        .tag(mode)
                }
            }
            .pickerStyle(.navigationLink)

            if selectedIntegrationMode.isDemo {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.orange)
                    Text("Demo mode - not connected")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Label("Enterprise Integration", systemImage: "link")
                .font(.caption)
        } footer: {
            Text("Templates are always stored locally on device with AES-256 encryption, regardless of integration mode.")
                .font(.caption2)
        }
    }
    
    private var deviceInfoSection: some View {
        Section {
            NavigationLink {
                SystemStatusView(heartIDService: heartIDService)
            } label: {
                HStack {
                    Label("System Status", systemImage: "chart.bar.doc.horizontal")
                        .font(.caption)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Text("Enrollment Status")
                    .font(.caption)
                Spacer()
                Text(enrollmentStatusText)
                    .font(.caption)
                    .foregroundColor(enrollmentStatusColor)
            }

            HStack {
                Text("Monitoring")
                    .font(.caption)
                Spacer()
                Text(heartIDService.isMonitoring ? "Active" : "Inactive")
                    .font(.caption)
                    .foregroundColor(heartIDService.isMonitoring ? .green : .secondary)
            }
        } header: {
            Text("Status")
                .font(.caption)
        }
    }
    
    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                showingUnenrollConfirmation = true
            } label: {
                Label("Unenroll & Delete Template", systemImage: "trash")
                    .font(.caption)
            }

            Button(role: .destructive) {
                showingFactoryResetConfirmation = true
            } label: {
                Label("Factory Reset (All Data)", systemImage: "arrow.counterclockwise")
                    .font(.caption)
            }

            Button {
                showingDemoResetConfirmation = true
            } label: {
                Label("Demo Reset (Keep Settings)", systemImage: "play.circle")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        } header: {
            Text("Danger Zone")
                .font(.caption)
        } footer: {
            Text("Factory Reset: Wipes all data with secure AES-256 key deletion. Demo Reset: Keeps thresholds/settings for quick re-enrollment.")
                .font(.caption2)
        }
    }

    // MARK: - Computed Properties

    private var enrollmentStatusText: String {
        switch heartIDService.enrollmentState {
        case .enrolled:
            return "Enrolled"
        case .enrolling:
            return "Enrolling..."
        case .notEnrolled:
            return "Not Enrolled"
        }
    }

    private var enrollmentStatusColor: Color {
        switch heartIDService.enrollmentState {
        case .enrolled:
            return .green
        case .enrolling:
            return .yellow
        case .notEnrolled:
            return .red
        }
    }

    // MARK: - Actions

    private func saveSettings() {
        let newThresholds = ConfidenceThresholds(
            fullAccess: fullAccessThreshold,
            conditionalAccess: conditionalAccessThreshold,
            requireStepUp: conditionalAccessThreshold,
            minimumAccuracy: minimumAccuracy
        )

        let newBatterySettings = BatteryManagementSettings(
            ppgUsageMultiplier: ppgUsageMultiplier,
            confidenceCheckIntervalMinutes: confidenceCheckIntervalMinutes
        )

        heartIDService.updateThresholds(newThresholds)
        heartIDService.setIntegrationMode(selectedIntegrationMode)

        Task {
            await heartIDService.updateBatterySettings(newBatterySettings)
        }

        print("✅ Settings saved - Min accuracy: \(Int(minimumAccuracy * 100))%, Mode: \(selectedIntegrationMode.rawValue)")
    }

    private func applyPreset(_ preset: ConfidenceThresholds) {
        minimumAccuracy = preset.minimumAccuracy
        fullAccessThreshold = preset.fullAccess
        conditionalAccessThreshold = preset.conditionalAccess
    }

    private func applyBatteryPreset(_ preset: BatteryManagementSettings) {
        ppgUsageMultiplier = preset.ppgUsageMultiplier
        confidenceCheckIntervalMinutes = preset.confidenceCheckIntervalMinutes
    }

    private func batteryColor(for usage: Double) -> Color {
        if usage >= 0.8 {
            return .red
        } else if usage >= 0.5 {
            return .orange
        } else {
            return .green
        }
    }
}

#Preview {
    SettingsView(heartIDService: HeartIDService())
}
