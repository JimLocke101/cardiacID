import SwiftUI

@main
struct CardiacIDWatchApp: App {
    // Initialize services as StateObjects - CRITICAL for Watch connectivity!
    @StateObject private var watchConnectivity = WatchConnectivityService()
    @StateObject private var healthKitService = HealthKitService()
    @StateObject private var authService = AuthenticationService()

    init() {
        print("⌚️ HeartID Watch App Launching...")
        print("⌚️ Initializing WatchConnectivity for iOS communication")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(watchConnectivity)  // Inject for all child views
                .environmentObject(healthKitService)
                .environmentObject(authService)
        }
    }
}

