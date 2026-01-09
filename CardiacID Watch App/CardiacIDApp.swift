import SwiftUI

@main
struct CardiacIDWatchApp: App {
    // Initialize HeartIDService as StateObject - Main orchestrator
    @StateObject private var heartIDService = HeartIDService()
    @State private var isAppReady = false
    @State private var startupTimedOut = false

    /// Maximum startup time before showing UI anyway (45 seconds)
    private static let maxStartupTime: TimeInterval = 45.0

    init() {
        print("⌚️ CardiacID Watch App Launching...")
        print("⌚️ DOD-Level Biometric Authentication - 96-99% Accuracy")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isAppReady || startupTimedOut {
                    MenuView(heartIDService: heartIDService)
                } else {
                    // Simple loading view during startup
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                        Text("Starting...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .task {
                await initializeWithTimeout()
            }
        }
    }

    /// Initialize app with 45-second timeout to prevent hang
    private func initializeWithTimeout() async {
        let startTime = Date()

        // Start timeout timer
        Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.maxStartupTime * 1_000_000_000))
            if !isAppReady {
                print("⚠️ Watch: Startup timeout - showing UI anyway")
                await MainActor.run {
                    startupTimedOut = true
                }
            }
        }

        // Perform initialization
        await heartIDService.initialize()

        let elapsed = Date().timeIntervalSince(startTime)
        print("⌚️ Watch: App ready in \(String(format: "%.1f", elapsed))s")

        await MainActor.run {
            isAppReady = true
        }
    }
}
