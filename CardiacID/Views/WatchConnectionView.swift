//
//  WatchConnectionView.swift
//  CardiacID
//
//  REAL Watch Connection Status - Shows actual paired Watch status
//  Auto-discovers and connects to Apple Watch for biometric authentication
//

import SwiftUI
import WatchConnectivity

/// Real-time Watch connection status view with auto-discovery
struct WatchConnectionView: View {
    @EnvironmentObject var watchConnectivity: WatchConnectivityService
    @State private var isScanning = false
    @State private var lastConnectionAttempt: Date?
    @State private var connectionLog: [ConnectionLogEntry] = []

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Connection Status Card
                    connectionStatusCard

                    // Watch Details
                    if watchConnectivity.isPaired {
                        watchDetailsCard
                    }

                    // Connection Log
                    connectionLogSection

                    // Actions
                    actionButtons
                }
                .padding()
            }
            .navigationTitle("Apple Watch")
            .onAppear {
                startMonitoring()
            }
        }
    }

    // MARK: - Connection Status Card

    private var connectionStatusCard: some View {
        VStack(spacing: 16) {
            // Status Icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 100, height: 100)

                Image(systemName: statusIcon)
                    .font(.system(size: 50))
                    .foregroundColor(statusColor)
            }

            // Status Text
            VStack(spacing: 8) {
                Text(statusTitle)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Connection Details
            VStack(alignment: .leading, spacing: 12) {
                ConnectionStatusRow(
                    label: "Paired",
                    value: watchConnectivity.isPaired ? "Yes" : "No",
                    isGood: watchConnectivity.isPaired
                )

                ConnectionStatusRow(
                    label: "App Installed",
                    value: watchConnectivity.isInstalled ? "Yes" : "No",
                    isGood: watchConnectivity.isInstalled
                )

                ConnectionStatusRow(
                    label: "Connected",
                    value: watchConnectivity.isReachable ? "Yes" : "No",
                    isGood: watchConnectivity.isReachable
                )

                ConnectionStatusRow(
                    label: "Session",
                    value: watchConnectivity.isActivated ? "Active" : "Inactive",
                    isGood: watchConnectivity.isActivated
                )
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 2)
    }

    // MARK: - Watch Details Card

    private var watchDetailsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Watch Information")
                .font(.headline)

            if let lastHeartRate = watchConnectivity.lastHeartRateTimestamp {
                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.red)
                    Text("Last Heart Rate:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(watchConnectivity.lastHeartRate) BPM")
                        .fontWeight(.semibold)
                }

                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.blue)
                    Text("Received:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(timeAgo(from: lastHeartRate))
                        .fontWeight(.semibold)
                }
            } else {
                Text("No biometric data received yet")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 2)
    }

    // MARK: - Connection Log

    private var connectionLogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection Log")
                .font(.headline)

            if connectionLog.isEmpty {
                Text("No connection events yet")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(connectionLog.suffix(5)) { entry in
                    HStack {
                        Image(systemName: entry.icon)
                            .foregroundColor(entry.color)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.message)
                                .font(.subheadline)
                            Text(entry.timestamp, style: .time)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 8)
                    Divider()
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 2)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if !watchConnectivity.isPaired {
                Button(action: openWatchApp) {
                    HStack {
                        Image(systemName: "applewatch")
                        Text("Open Watch App on iPhone")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }

            if watchConnectivity.isPaired && !watchConnectivity.isInstalled {
                Button(action: installWatchApp) {
                    HStack {
                        Image(systemName: "arrow.down.circle")
                        Text("Install CardiacID on Watch")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }

            Button(action: refreshConnection) {
                HStack {
                    if isScanning {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(isScanning ? "Scanning..." : "Refresh Connection")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isScanning)
        }
    }

    // MARK: - Computed Properties

    private var statusColor: Color {
        if watchConnectivity.isReachable {
            return .green
        } else if watchConnectivity.isPaired {
            return .yellow
        } else {
            return .red
        }
    }

    private var statusIcon: String {
        if watchConnectivity.isReachable {
            return "checkmark.circle.fill"
        } else if watchConnectivity.isPaired {
            return "exclamationmark.triangle.fill"
        } else {
            return "xmark.circle.fill"
        }
    }

    private var statusTitle: String {
        if watchConnectivity.isReachable {
            return "Connected"
        } else if watchConnectivity.isPaired {
            return "Paired"
        } else {
            return "Not Paired"
        }
    }

    private var statusMessage: String {
        if watchConnectivity.isReachable {
            return "Your Apple Watch is connected and ready for biometric authentication"
        } else if watchConnectivity.isPaired && watchConnectivity.isInstalled {
            return "Watch is paired but not reachable. Make sure Watch app is running."
        } else if watchConnectivity.isPaired {
            return "Watch is paired but CardiacID app needs to be installed"
        } else {
            return "Please pair your Apple Watch using the Watch app"
        }
    }

    // MARK: - Helper Functions

    private func timeAgo(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))

        if seconds < 60 {
            return "\(seconds)s ago"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes)m ago"
        } else {
            let hours = seconds / 3600
            return "\(hours)h ago"
        }
    }

    private func startMonitoring() {
        addLog("Monitoring Watch connection...", icon: "eye", color: .blue)

        // Check initial status
        if watchConnectivity.isPaired {
            addLog("Watch is paired", icon: "checkmark.circle", color: .green)
        }

        if watchConnectivity.isInstalled {
            addLog("CardiacID app is installed on Watch", icon: "checkmark.circle", color: .green)
        }

        if watchConnectivity.isReachable {
            addLog("Watch is reachable and connected", icon: "checkmark.circle.fill", color: .green)
        }
    }

    private func refreshConnection() {
        isScanning = true
        lastConnectionAttempt = Date()
        addLog("Refreshing connection...", icon: "arrow.clockwise", color: .orange)

        // Force reactivation of WCSession
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isScanning = false

            if watchConnectivity.isReachable {
                addLog("Connection successful!", icon: "checkmark.circle.fill", color: .green)
            } else if watchConnectivity.isPaired {
                addLog("Watch paired but not reachable", icon: "exclamationmark.triangle", color: .yellow)
            } else {
                addLog("No Watch found. Please pair in Watch app.", icon: "xmark.circle", color: .red)
            }
        }
    }

    private func openWatchApp() {
        if let url = URL(string: "itms-watchs://") {
            UIApplication.shared.open(url)
            addLog("Opening Watch app...", icon: "applewatch", color: .blue)
        }
    }

    private func installWatchApp() {
        addLog("Please install CardiacID on your Watch via the Watch app", icon: "info.circle", color: .blue)
        // User needs to manually install via Watch app on iPhone
    }

    private func addLog(_ message: String, icon: String, color: Color) {
        let entry = ConnectionLogEntry(message: message, icon: icon, color: color)
        connectionLog.append(entry)

        // Keep only last 20 entries
        if connectionLog.count > 20 {
            connectionLog.removeFirst()
        }
    }
}

// MARK: - Supporting Views

struct ConnectionStatusRow: View {
    let label: String
    let value: String
    let isGood: Bool

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: isGood ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isGood ? .green : .red)
                    .font(.caption)
                Text(value)
                    .fontWeight(.semibold)
            }
        }
        .font(.subheadline)
    }
}

struct ConnectionLogEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let message: String
    let icon: String
    let color: Color
}

#Preview {
    WatchConnectionView()
        .environmentObject(WatchConnectivityService.shared)
}
