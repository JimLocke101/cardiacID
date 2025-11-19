//
//  SystemStatusView.swift
//  CardiacID Watch App
//
//  Ported from HeartID_0_7 - Enterprise-Ready System Status Dashboard
//  Created by HeartID Team on 10/30/25.
//  Real-time monitoring dashboard with DOD-level security status
//

import SwiftUI

/// Comprehensive system status and diagnostics display
/// Shows real-time authentication state, ECG/PPG confidence, wrist detection, and configuration
struct SystemStatusView: View {
    @ObservedObject var heartIDService: HeartIDService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // User Information Section
                if let userName = heartIDService.enrolledUserName {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enrolled User")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(userName)
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                    } header: {
                        Label("User Information", systemImage: "person.circle.fill")
                            .font(.caption)
                    }
                }

                // HealthKit Status Section
                Section {
                    StatusRow(
                        label: "Authorization",
                        value: heartIDService.healthKitAuthorizationStatus,
                        statusColor: heartIDService.healthKitAuthorizationStatus == "Authorized" ? .green : .red
                    )

                    StatusRow(
                        label: "Connection",
                        value: heartIDService.healthKitConnectionStatus,
                        statusColor: heartIDService.healthKitConnectionStatus == "Connected" ? .green : .yellow
                    )
                } header: {
                    Label("HealthKit Status", systemImage: "heart.text.square.fill")
                        .font(.caption)
                }

                // ECG Status Section
                Section {
                    if let ecgTime = heartIDService.mostRecentECGTime {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Most Recent ECG")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(ecgTime)
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    } else {
                        StatusRow(
                            label: "Most Recent ECG",
                            value: "No ECG recorded",
                            statusColor: .secondary
                        )
                    }

                    if let ecgConfidence = heartIDService.mostRecentECGConfidence {
                        StatusRow(
                            label: "ECG Confidence",
                            value: "\(Int(ecgConfidence * 100))%",
                            statusColor: confidenceColor(ecgConfidence)
                        )
                    } else {
                        StatusRow(
                            label: "ECG Confidence",
                            value: "N/A",
                            statusColor: .secondary
                        )
                    }

                    if let peakECG = heartIDService.peakECGInInterval {
                        StatusRow(
                            label: "Peak ECG (Interval)",
                            value: "\(Int(peakECG * 100))%",
                            statusColor: confidenceColor(peakECG)
                        )
                    }
                } header: {
                    Label("ECG Status", systemImage: "waveform.path.ecg")
                        .font(.caption)
                }

                // PPG Status Section
                Section {
                    StatusRow(
                        label: "Sensor Monitoring",
                        value: heartIDService.ppgMonitoringStatus,
                        statusColor: heartIDService.ppgMonitoringStatus == "Active" ? .green : .secondary
                    )

                    StatusRow(
                        label: "Current Heart Rate",
                        value: heartIDService.currentHeartRate > 0 ? "\(Int(heartIDService.currentHeartRate)) BPM" : "N/A",
                        statusColor: heartIDService.currentHeartRate > 0 ? .green : .secondary
                    )

                    StatusRow(
                        label: "PPG Confidence",
                        value: heartIDService.currentPPGConfidenceValue > 0 ? "\(Int(heartIDService.currentPPGConfidenceValue * 100))%" : "N/A",
                        statusColor: confidenceColor(heartIDService.currentPPGConfidenceValue)
                    )

                    if let peakPPG = heartIDService.peakPPGInInterval {
                        StatusRow(
                            label: "Peak PPG (Interval)",
                            value: "\(Int(peakPPG * 100))%",
                            statusColor: confidenceColor(peakPPG)
                        )
                    }
                } header: {
                    Label("PPG Status", systemImage: "waveform.path")
                        .font(.caption)
                }

                // Overall Confidence Section
                Section {
                    StatusRow(
                        label: "Current Confidence",
                        value: "\(Int(heartIDService.currentConfidence * 100))%",
                        statusColor: confidenceColor(heartIDService.currentConfidence)
                    )

                    StatusRow(
                        label: "Authentication State",
                        value: heartIDService.authenticationStateText,
                        statusColor: heartIDService.authenticationStateColor
                    )

                    StatusRow(
                        label: "Access Level",
                        value: heartIDService.accessLevelText,
                        statusColor: heartIDService.accessLevelColor
                    )
                } header: {
                    Label("Overall Status", systemImage: "shield.checkered")
                        .font(.caption)
                }

                // Wrist Detection Section (DOD Security Feature)
                Section {
                    StatusRow(
                        label: "Watch on Wrist",
                        value: heartIDService.isWatchOnWrist ? "Yes" : "No",
                        statusColor: heartIDService.isWatchOnWrist ? .green : .red
                    )
                } header: {
                    Label("Wrist Detection", systemImage: "applewatch.watchface")
                        .font(.caption)
                } footer: {
                    Text("Watch removal invalidates authentication for security.")
                        .font(.caption2)
                }

                // System Configuration Section
                Section {
                    StatusRow(
                        label: "Check Interval",
                        value: "\(Int(heartIDService.batterySettings.confidenceCheckIntervalMinutes)) min",
                        statusColor: .blue
                    )

                    StatusRow(
                        label: "PPG Usage",
                        value: "\(Int(heartIDService.batterySettings.ppgUsageMultiplier * 100))%",
                        statusColor: .blue
                    )

                    StatusRow(
                        label: "Integration Mode",
                        value: heartIDService.currentIntegrationMode.rawValue,
                        statusColor: .blue
                    )
                } header: {
                    Label("Configuration", systemImage: "gearshape.2")
                        .font(.caption)
                }

                // Interval Tracking Section (Confidence Ceiling System)
                Section {
                    if let lastReset = heartIDService.lastIntervalResetTimeFormatted {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last Interval Reset")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(lastReset)
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    }

                    if let nextReset = heartIDService.nextIntervalResetTimeFormatted {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Next Interval Reset")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(nextReset)
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    }
                } header: {
                    Label("Interval Tracking", systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                } footer: {
                    Text("Peak confidence values reset at each interval.")
                        .font(.caption2)
                }
            }
            .navigationTitle("System Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.caption)
                            Text("Back")
                                .font(.caption)
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.caption)
                }
            }
        }
    }

    // MARK: - Helper Functions

    /// Color coding for confidence levels
    /// Green (≥90%), Yellow (≥70%), Orange (>0%), Secondary (0%)
    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.90 {
            return .green
        } else if confidence >= 0.70 {
            return .yellow
        } else if confidence > 0 {
            return .orange
        } else {
            return .secondary
        }
    }
}

// MARK: - Status Row Component

/// Reusable status row with label, value, and color-coded status
struct StatusRow: View {
    let label: String
    let value: String
    let statusColor: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(statusColor)
        }
    }
}

#Preview {
    SystemStatusView(heartIDService: HeartIDService())
}
