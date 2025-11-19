import SwiftUI

@main
struct CardiacIDWatchApp: App {
    // Initialize HeartIDService as StateObject - Main orchestrator
    @StateObject private var heartIDService = HeartIDService()

    init() {
        print("⌚️ CardiacID Watch App Launching...")
        print("⌚️ DOD-Level Biometric Authentication - 96-99% Accuracy")
    }

    var body: some Scene {
        WindowGroup {
            MenuView(heartIDService: heartIDService)
        }
    }
}
