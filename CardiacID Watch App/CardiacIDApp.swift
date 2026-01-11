import SwiftUI
import WatchKit
import WatchConnectivity

@main
struct CardiacIDWatchApp: App {
    // MARK: - State Objects

    /// Main service orchestrating biometric authentication
    /// Using StateObject wrapper for proper lifecycle management
    @StateObject private var heartIDService: HeartIDService

    /// Watch connectivity for iPhone communication - singleton
    /// Note: WatchConnectivityService.shared delays WCSession activation until after init
    @ObservedObject private var watchConnectivity = WatchConnectivityService.shared

    // MARK: - State
    @State private var isInitialized = false

    // MARK: - Initialization

    init() {
        // FIXED: Use _heartIDService StateObject initializer to avoid issues
        _heartIDService = StateObject(wrappedValue: HeartIDService())
        print("⌚️ CardiacID Watch App Launching...")
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            MenuView(heartIDService: heartIDService)
                .environmentObject(watchConnectivity)
                .onAppear {
                    if !isInitialized {
                        performInitialization()
                    }
                }
        }
    }

    // MARK: - Initialization

    private func performInitialization() {
        print("⌚️ Initializing app...")
        isInitialized = true

        // CRITICAL: Delay all heavy initialization to prevent Watch app from being killed
        // watchOS has strict launch time requirements - the app MUST be responsive within seconds
        // Heavy init work (HealthKit, ExtendedRuntime) must be deferred

        // Start extended runtime session after app is stable (2 seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            print("⌚️ Starting ExtendedRuntimeManager...")
            ExtendedRuntimeManager.shared.startSession()
        }

        // Initialize HeartIDService after extended runtime starts (3 seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            Task { @MainActor in
                await self.initializeServices()
            }
        }
    }

    private func initializeServices() async {
        print("⌚️ Starting service initialization...")

        // Simple initialization without complex timeout logic
        // HeartIDService.initialize() is designed to not block indefinitely
        await heartIDService.initialize()

        print("⌚️ ✅ Services initialized")
    }
}
