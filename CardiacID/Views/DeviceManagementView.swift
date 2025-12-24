//
//  DeviceManagementView.swift
//  CardiacID
//
//  REAL Watch Connection Management - Auto-discovers and connects to Apple Watch
//  Production-ready biometric device management
//

import SwiftUI
import WatchConnectivity

struct DeviceManagementView: View {
    @EnvironmentObject var watchConnectivity: WatchConnectivityService
    @State private var showingMenu = false
    @State private var isScanning = false
    @State private var lastScanTime: Date?
    @State private var connectionLog: [String] = []
    private let colors = HeartIDColors()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Apple Watch Connection Status
                watchConnectionCard

                // Real-time Biometric Data
                if watchConnectivity.isReachable {
                    biometricDataCard
                }

                // Connection Actions
                actionButtonsCard

                // Connection Log
                if !connectionLog.isEmpty {
                    connectionLogCard
                }
            }
            .padding(.vertical)
        }
        .background(colors.background)
        .navigationTitle("Apple Watch")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                HamburgerMenuButton(showMenu: $showingMenu)
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { refreshConnection() }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(isScanning ? .gray : .blue)
                }
                .disabled(isScanning)
            }
        }
        .sheet(isPresented: $showingMenu) {
            MenuView(isPresented: $showingMenu)
                .environmentObject(AuthViewModel())
                .environmentObject(AuthenticationManager())
        }
        .onAppear {
            startMonitoring()
        }
    }

    // MARK: - Watch Connection Card

    private var watchConnectionCard: some View {
        VStack(spacing: 16) {
            // Status Icon & Title
            HStack {
                Image(systemName: watchIcon)
                    .font(.system(size: 50))
                    .foregroundColor(statusColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(watchStatusTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(colors.text)

                    Text(watchStatusMessage)
                        .font(.subheadline)
                        .foregroundColor(colors.text.opacity(0.7))
                }

                Spacer()
            }

            Divider()

            // Connection Details
            VStack(spacing: 12) {
                StatusRow(label: "Paired", value: watchConnectivity.isPaired ? "Yes" : "No", isGood: watchConnectivity.isPaired, colors: colors)
                StatusRow(label: "App Installed", value: watchConnectivity.isInstalled ? "Yes" : "No", isGood: watchConnectivity.isInstalled, colors: colors)
                StatusRow(label: "Connected", value: watchConnectivity.isReachable ? "Yes" : "No", isGood: watchConnectivity.isReachable, colors: colors)
                StatusRow(label: "Session Active", value: watchConnectivity.isActivated ? "Yes" : "No", isGood: watchConnectivity.isActivated, colors: colors)
            }
        }
        .padding()
        .background(colors.surface)
        .cornerRadius(16)
        .padding(.horizontal)
    }

    // MARK: - Biometric Data Card

    private var biometricDataCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Live Biometric Data", systemImage: "waveform.path.ecg")
                .font(.headline)
                .foregroundColor(colors.text)

            if let lastHR = watchConnectivity.lastHeartRateTimestamp {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Heart Rate")
                            .font(.caption)
                            .foregroundColor(colors.text.opacity(0.7))
                        Text("\(watchConnectivity.lastHeartRate) BPM")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                    }

                    Spacer()

                    VStack(alignment: .trailing) {
                        Text("Received")
                            .font(.caption)
                            .foregroundColor(colors.text.opacity(0.7))
                        Text(timeAgo(from: lastHR))
                            .font(.subheadline)
                            .foregroundColor(colors.text)
                    }
                }

                if Date().timeIntervalSince(lastHR) < 30 {
                    HStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Real-time monitoring active")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            } else {
                Text("No biometric data received yet. Start monitoring on your Apple Watch.")
                    .font(.subheadline)
                    .foregroundColor(colors.text.opacity(0.6))
            }
        }
        .padding()
        .background(colors.surface)
        .cornerRadius(16)
        .padding(.horizontal)
    }

    // MARK: - Action Buttons Card

    private var actionButtonsCard: some View {
        VStack(spacing: 12) {
            if !watchConnectivity.isPaired {
                ActionButton(
                    title: "Pair Apple Watch",
                    icon: "applewatch",
                    color: .blue,
                    action: openWatchApp
                )
            }

            if watchConnectivity.isPaired && !watchConnectivity.isInstalled {
                ActionButton(
                    title: "Install CardiacID on Watch",
                    icon: "arrow.down.circle",
                    color: .green,
                    action: installWatchApp
                )
            }

            if watchConnectivity.isReachable {
                ActionButton(
                    title: "Start Watch Monitoring",
                    icon: "play.circle.fill",
                    color: .green,
                    action: startWatchMonitoring
                )
            }

            ActionButton(
                title: isScanning ? "Scanning..." : "Refresh Connection",
                icon: "arrow.clockwise",
                color: .orange,
                action: refreshConnection,
                disabled: isScanning
            )
        }
        .padding(.horizontal)
    }

    // MARK: - Connection Log Card

    private var connectionLogCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection Log")
                .font(.headline)
                .foregroundColor(colors.text)

            ForEach(connectionLog.suffix(10).reversed(), id: \.self) { log in
                HStack {
                    Circle()
                        .fill(Color.blue.opacity(0.3))
                        .frame(width: 6, height: 6)

                    Text(log)
                        .font(.caption)
                        .foregroundColor(colors.text.opacity(0.8))

                    Spacer()
                }
            }
        }
        .padding()
        .background(colors.surface)
        .cornerRadius(16)
        .padding(.horizontal)
    }

    // MARK: - Computed Properties

    private var watchIcon: String {
        if watchConnectivity.isReachable {
            return "applewatch.radiowaves.left.and.right"
        } else if watchConnectivity.isPaired {
            return "applewatch"
        } else {
            return "applewatch.slash"
        }
    }

    private var statusColor: Color {
        if watchConnectivity.isReachable {
            return .green
        } else if watchConnectivity.isPaired {
            return .yellow
        } else {
            return .red
        }
    }

    private var watchStatusTitle: String {
        if watchConnectivity.isReachable {
            return "Connected"
        } else if watchConnectivity.isPaired {
            return "Paired"
        } else {
            return "Not Paired"
        }
    }

    private var watchStatusMessage: String {
        if watchConnectivity.isReachable {
            return "Watch is connected and ready for biometric authentication"
        } else if watchConnectivity.isPaired && watchConnectivity.isInstalled {
            return "Watch paired but not reachable. Open CardiacID on Watch."
        } else if watchConnectivity.isPaired {
            return "Watch paired. Install CardiacID app on Watch."
        } else {
            return "Pair your Apple Watch to enable biometric authentication"
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
        addLog("🔍 Monitoring Watch connection...")

        if watchConnectivity.isPaired {
            addLog("✅ Watch is paired")
        }

        if watchConnectivity.isInstalled {
            addLog("✅ CardiacID app installed on Watch")
        }

        if watchConnectivity.isReachable {
            addLog("✅ Watch is reachable and connected")
        }

        if !watchConnectivity.isPaired {
            addLog("⚠️ No Watch paired. Please pair in Watch app.")
        }
    }

    private func refreshConnection() {
        isScanning = true
        lastScanTime = Date()
        addLog("🔄 Refreshing connection...")

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isScanning = false

            if watchConnectivity.isReachable {
                addLog("✅ Connection successful! Watch is connected.")
            } else if watchConnectivity.isPaired {
                addLog("⚠️ Watch paired but not reachable. Open CardiacID on Watch.")
            } else {
                addLog("❌ No Watch found. Please pair in Watch app.")
            }
        }
    }

    private func openWatchApp() {
        addLog("📱 Opening Watch app...")
        if let url = URL(string: "itms-watchs://") {
            UIApplication.shared.open(url)
        }
    }

    private func installWatchApp() {
        addLog("ℹ️ Install CardiacID on Watch via the Watch app on iPhone")
    }

    private func startWatchMonitoring() {
        addLog("▶️ Starting biometric monitoring on Watch...")
        watchConnectivity.startMonitoring()
    }

    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        connectionLog.append("[\(timestamp)] \(message)")

        // Keep only last 50 entries
        if connectionLog.count > 50 {
            connectionLog.removeFirst()
        }
    }
}

#Preview {
    NavigationView {
        DeviceManagementView()
            .environmentObject(WatchConnectivityService.shared)
    }
}
