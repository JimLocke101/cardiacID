//
//  WatchApp.swift
//  CardiacID Watch App
//
//  Main entry point for watchOS app
//

import SwiftUI
import WatchKit
import HealthKit

@main
struct CardiacIDWatchApp: App {
    @StateObject private var heartIDService = HeartIDService()
    
    init() {
        print("⌚️ CardiacID Watch App Launching...")
        print("⌚️ DOD-Level Biometric Authentication - 96-99% Accuracy")
        
        // Setup watch-specific configurations
        setupWatchApp()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(heartIDService)
        }
        .backgroundTask(.appRefresh("heartid.background")) {
            // Handle background app refresh
            await handleBackgroundRefresh()
        }
    }
    
    private func setupWatchApp() {
        // Request HealthKit permissions early
        requestHealthKitPermissions()
        
        // Set up background app refresh
        scheduleBackgroundRefresh()
    }
    
    private func requestHealthKitPermissions() {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("❌ HealthKit not available on this device")
            return
        }
        
        let healthStore = HKHealthStore()
        let typesToRead: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        ]
        
        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { success, error in
            DispatchQueue.main.async {
                if success {
                    print("✅ HealthKit authorization granted")
                } else {
                    print("❌ HealthKit authorization failed: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
    }
    
    private func scheduleBackgroundRefresh() {
        let refreshDate = Date().addingTimeInterval(60 * 15) // 15 minutes
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: refreshDate,
            userInfo: ["type": "heartid.monitoring"]
        ) { error in
            if let error = error {
                print("❌ Failed to schedule background refresh: \(error.localizedDescription)")
            } else {
                print("✅ Background refresh scheduled")
            }
        }
    }
    
    private func handleBackgroundRefresh() async {
        print("🔄 Handling background refresh...")
        
        // Perform background monitoring if user is enrolled
        if heartIDService.enrollmentState == .enrolled {
            await heartIDService.performBackgroundConfidenceCheck()
        }
        
        // Reschedule next refresh
        scheduleBackgroundRefresh()
    }
}

// MARK: - Main Content View for Watch

struct ContentView: View {
    @EnvironmentObject var heartIDService: HeartIDService
    @State private var showingLaunchScreen = true
    
    var body: some View {
        Group {
            if showingLaunchScreen {
                WatchLaunchScreen {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        showingLaunchScreen = false
                    }
                }
            } else {
                MenuView(heartIDService: heartIDService)
            }
        }
    }
}

// MARK: - Watch-specific Launch Screen

struct WatchLaunchScreen: View {
    let onComplete: () -> Void
    @State private var scale: CGFloat = 0.1
    @State private var opacity: Double = 0.0
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.system(size: 30))
                .foregroundColor(.red)
                .scaleEffect(scale)
                .opacity(opacity)
            
            Text("CardiacID")
                .font(.title3)
                .fontWeight(.bold)
                .opacity(opacity)
            
            Text("Initializing...")
                .font(.caption2)
                .foregroundColor(.secondary)
                .opacity(opacity * 0.8)
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                scale = 1.0
                opacity = 1.0
            }
            
            // Auto-dismiss after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                onComplete()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(HeartIDService())
}