//
//  CardiacIDApp.swift
//  CardiacID
//
//  Created by Jim Locke on 9/9/25.
//

import SwiftUI
import CoreData
import HealthKit
import Combine
#if canImport(MSAL)
import MSAL
#endif

// MARK: - App Delegate for MSAL URL Handling
/// AppDelegate is required by MSAL to handle OAuth callback URLs
/// This enables Microsoft authentication flow to complete properly
class AppDelegate: NSObject, UIApplicationDelegate {

    /// Handle URL callbacks from Microsoft authentication
    /// This is called when the user returns from the Microsoft sign-in page
    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {

        print("📱 MSAL: Received URL callback: \(url.absoluteString)")

        #if canImport(MSAL)
        // Let MSAL handle the authentication response
        let handled = MSALPublicClientApplication.handleMSALResponse(
            url,
            sourceApplication: options[UIApplication.OpenURLOptionsKey.sourceApplication] as? String
        )

        if handled {
            print("✅ MSAL: Successfully handled authentication callback")
        } else {
            print("⚠️ MSAL: URL was not handled by MSAL")
        }

        return handled
        #else
        return false
        #endif
    }
}

@main
struct CardiacIDApp: App {
    // MARK: - App Delegate for MSAL
    /// Connect the AppDelegate for MSAL URL handling
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Services and controllers
    let persistenceController = PersistenceController.shared
    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var watchConnectivity = WatchConnectivityService.shared
    @StateObject private var authViewModel = AuthViewModel()
    
    // Launch state
    @State private var isShowingLaunchScreen = true
    @State private var isAppReady = false
    
    // Track scene phase changes
    @Environment(\.scenePhase) var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if isAppReady {
                    if authViewModel.isAuthenticated {
                        // Main app content
                        ContentView()
                            .environment(\.managedObjectContext, persistenceController.container.viewContext)
                            .environmentObject(authViewModel)
                            .environmentObject(authManager)
                            .environmentObject(watchConnectivity)
                            .transition(.opacity)
                    } else {
                        // Auth screen - shows SignUp or Login based on initial flow
                        Group {
                            if authViewModel.initialFlow == .signUp {
                                SignUpView()
                                    .environmentObject(authViewModel)
                                    .transition(.move(edge: .trailing))
                            } else {
                                LoginView()
                                    .environmentObject(authViewModel)
                                    .transition(.move(edge: .leading))
                            }
                        }
                    }
                }
                
                // Launch screen overlay - shown during loading
                if isShowingLaunchScreen {
                    LaunchScreen { shouldShowSignUp in
                        // Handle the user choice from launch screen
                        if shouldShowSignUp {
                            // Direct new users to sign up flow
                            authViewModel.setInitialFlow(.signUp)
                        } else {
                            // Existing users go to sign in
                            authViewModel.setInitialFlow(.signIn)
                        }
                        
                        // Dismiss launch screen
                        withAnimation(.easeInOut(duration: 0.5)) {
                            isShowingLaunchScreen = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(2)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: authViewModel.isAuthenticated)
            .animation(.easeInOut(duration: 0.5), value: isShowingLaunchScreen)
            .animation(.easeInOut(duration: 0.3), value: authViewModel.initialFlow)
            .onAppear {
                debugLog.info("HeartID Mobile app launched")
                
                // Perform initialization tasks
                initializeApp()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                // Refresh data when app enters foreground
                if authViewModel.isAuthenticated {
                    authManager.refreshAuthenticationStatus()
                }

                // Always refresh Watch connection when entering foreground
                watchConnectivity.updateConnectionState()
                print("📱 Watch state on foreground - Paired: \(watchConnectivity.isPaired), Installed: \(watchConnectivity.isInstalled), Reachable: \(watchConnectivity.isReachable)")
            }
            // MARK: - MSAL URL Handler (iOS 14+)
            // Handle OAuth callback URLs from Microsoft authentication
            .onOpenURL { url in
                print("📱 MSAL: Received URL via onOpenURL: \(url.absoluteString)")

                #if canImport(MSAL)
                let handled = MSALPublicClientApplication.handleMSALResponse(
                    url,
                    sourceApplication: nil
                )
                print(handled ? "✅ MSAL: URL handled successfully" : "⚠️ MSAL: URL not handled")
                #endif
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                // App became active, refresh data
                if authViewModel.isAuthenticated && !isShowingLaunchScreen {
                    authManager.refreshAuthenticationStatus()
                }
            } else if scenePhase == .background {
                // App entered background, perform cleanup
                do {
                    try persistenceController.container.viewContext.save()
                } catch {
                    debugLog.error("Failed to save Core Data context", error: error)
                }
            }
        }
    }
    
    private func initializeApp() {
        // Start initialization tasks
        Task {
            // Initialize services
            debugLog.watch("Initializing watch connectivity service...")

            // CRITICAL: Explicitly start Watch monitoring
            // This ensures WCSession is activated and state is tracked
            await MainActor.run {
                watchConnectivity.startMonitoring()
                watchConnectivity.updateConnectionState()

                // Start periodic refresh every 6 seconds for responsive connection verification
                // Biometric data syncs via fire-and-forget messages
                watchConnectivity.startPeriodicStateRefresh(interval: 6.0)

                debugLog.watch("Watch connectivity initialized - Paired: \(watchConnectivity.isPaired), Installed: \(watchConnectivity.isInstalled), Reachable: \(watchConnectivity.isReachable)")
            }

            debugLog.health("Setting up HealthKit store...")
            authManager.setupHealthStore()

            // Simulate additional initialization time for better UX
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            // Mark app as ready
            await MainActor.run {
                isAppReady = true
                debugLog.info("App initialization completed")

                // Log final watch state
                debugLog.watch("Final watch state - Paired: \(watchConnectivity.isPaired), Installed: \(watchConnectivity.isInstalled), Reachable: \(watchConnectivity.isReachable)")
            }

            // Note: Launch screen dismissal is now handled by user interaction
            // The launch screen will dismiss itself after user makes a choice
        }
    }
    
    private func requestHealthKitPermissions() {
        Task {
            _ = await authManager.requestHealthKitPermissions()
        }
    }
}
