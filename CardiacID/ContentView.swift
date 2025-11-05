//
//  ContentView.swift
//  HeartID Mobile
//
//  Created by Jim Locke on 5/27/25.
//

import SwiftUI
import CoreData
import HealthKit
import Combine

struct ContentView: View {
    // Environment and state objects
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var authManager: AuthenticationManager
    @EnvironmentObject private var watchConnectivity: WatchConnectivityService
    @EnvironmentObject private var authViewModel: AuthViewModel
    
    // State properties
    @State private var selectedTab = 0
    @State private var showingEnrollment = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""
    @State private var isFirstLaunch = true
    @State private var showingWearableCheck = false
    @State private var showingWearableRequired = false
    @State private var showingEnrollmentRequired = false
    @State private var isDemoMode = false
    
    // Haptic feedback generator
    private let hapticFeedback = UINotificationFeedbackGenerator()
    private let selectionFeedback = UISelectionFeedbackGenerator()
    
    // Color scheme
    private let colors = HeartIDColors()
    
    // Subscriptions
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        ZStack {
            // Main app content
            TabView(selection: $selectedTab) {
                // Dashboard
                NavigationView {
                    DashboardView()
                }
                .tabItem {
                    Label("Dashboard", systemImage: "heart.fill")
                }
                .tag(0)
                .badge(authManager.authState == .warning ? "!" : nil)
                
                // Device Management
                NavigationView {
                    DeviceManagementView()
                }
                .tabItem {
                    Label("Devices", systemImage: "applewatch")
                }
                .tag(1)
                .badge(watchConnectivity.isPaired && !watchConnectivity.isActivated ? "!" : nil)
                
                // Activity
                NavigationView {
                    ActivityLogView()
                }
                .tabItem {
                    Label("Activity", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(2)
                
                // Technology Management
                NavigationView {
                    TechnologyManagementView()
                }
                .tabItem {
                    Label("Technology", systemImage: "wrench.and.screwdriver")
                }
                .tag(3)
                
                // Settings
                NavigationView {
                    SettingsView()
                }
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(4)
            }
            
            // Demo mode overlay
            if isDemoMode {
                VStack {
                    Text("DEMO")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .opacity(0.5)
                        .padding(.top, 50)
                    Spacer()
                }
            }
            
            // Wearable connectivity check overlay
            if showingWearableCheck {
                WearableCheckView(
                    onComplete: {
                        showingWearableCheck = false
                        checkWearableStatus()
                    }
                )
            }
            
            // Wearable required screen
            if showingWearableRequired {
                WearableRequiredView(
                    onDemoMode: {
                        showingWearableRequired = false
                        isDemoMode = true
                    }
                )
            }
            
            // Enrollment required screen
            if showingEnrollmentRequired {
                EnrollmentRequiredView(
                    onDemoMode: {
                        showingEnrollmentRequired = false
                        isDemoMode = true
                    }
                )
            }
        }
        .sheet(isPresented: $showingEnrollment) {
            EnrollmentView()
                .environmentObject(authManager)
        }
        .onChange(of: selectedTab) { newValue in
            // Provide haptic feedback on tab change
            selectionFeedback.selectionChanged()
        }
        .accentColor(colors.accent)
        .preferredColorScheme(.dark)
        .onAppear {
            // Check if we need to show enrollment
            checkEnrollmentStatus()
            setupSubscriptions()
            
            // Initialize haptic feedback
            hapticFeedback.prepare()
            selectionFeedback.prepare()
            
            // Check wearable connectivity after authentication
            if authViewModel.isAuthenticated {
                checkWearableConnectivity()
            }
        }
        .onDisappear {
            cancellables.removeAll()
        }
        .alert(isPresented: $showingAlert) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $showingEnrollment) {
            EnrollmentView()
                .environmentObject(authManager)
                .environmentObject(watchConnectivity)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge) // Accessibility: support dynamic type but limit max size
    }
    
    // MARK: - Setup
    
    private func setupSubscriptions() {
        // Watch for errors from watch connectivity
        watchConnectivity.errorPublisher
            .sink { errorMessage in
                alertTitle = "Watch Connection Error"
                alertMessage = errorMessage
                showingAlert = true
                hapticFeedback.notificationOccurred(.error)
            }
            .store(in: &cancellables)
        
        // Watch for auth state changes
        authManager.$authState
            .sink { state in
                if case .authenticated = state, !isFirstLaunch {
                    hapticFeedback.notificationOccurred(.success)
                } else if case .failed(let reason) = state {
                    alertTitle = "Authentication Failed"
                    alertMessage = reason
                    showingAlert = true
                    hapticFeedback.notificationOccurred(.error)
                }
                isFirstLaunch = false
            }
            .store(in: &cancellables)
        
        // Watch for enrollment status changes
        authManager.$isEnrolled
            .sink { isEnrolled in
                if isEnrolled && !showingEnrollment {
                    // User completed enrollment, start monitoring
                    authManager.startMonitoring()
                }
            }
            .store(in: &cancellables)
        
        // Watch for authentication status changes
        authViewModel.$isAuthenticated
            .sink { isAuthenticated in
                print("🔐 Authentication status changed: \(isAuthenticated)")
                if isAuthenticated {
                    // User just signed in, check enrollment status
                    print("📝 User authenticated, checking enrollment status...")
                    checkEnrollmentStatus()
                }
            }
            .store(in: &cancellables)
    }
    
    private func checkEnrollmentStatus() {
        print("🔍 Checking enrollment status...")
        // Check if user is authenticated
        if !authViewModel.isAuthenticated {
            print("❌ User not authenticated, skipping enrollment check")
            return
        }
        
        print("✅ User is authenticated")
        print("📊 AuthManager isEnrolled: \(authManager.isEnrolled)")
        print("📊 AuthManager authState: \(authManager.authState)")
        
        // Check if user is enrolled, if not, show enrollment
        if !authManager.isEnrolled {
            print("📝 User not enrolled, showing enrollment screen")
            showingEnrollment = true
        } else if authManager.authState == .idle {
            print("🔄 User enrolled, starting monitoring...")
            // Only start monitoring if HealthKit is available
            if HKHealthStore.isHealthDataAvailable() {
                authManager.startMonitoring()
            } else {
                // In simulator or device without HealthKit, just set to demo mode
                print("🏥 HealthKit not available, setting demo mode")
                isDemoMode = true
            }
        }
    }
    
    private func checkWearableConnectivity() {
        // Show checking screen first
        showingWearableCheck = true
        
        // Simulate checking wearable connectivity
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            checkWearableStatus()
        }
    }
    
    private func checkWearableStatus() {
        // Check if wearable is connected
        if !watchConnectivity.isPaired {
            // No wearable connected
            showingWearableRequired = true
        } else if !authManager.isEnrolled {
            // Wearable connected but not enrolled
            showingEnrollmentRequired = true
        } else {
            // Everything is good, proceed normally
            // Start monitoring if enrolled
            authManager.startMonitoring()
        }
    }
}

// MARK: - Wearable Connectivity Views

struct WearableCheckView: View {
    let onComplete: () -> Void
    @State private var progress: Double = 0.0
    @State private var isAnimating = false
    
    private let colors = HeartIDColors()
    
    var body: some View {
        ZStack {
            // Background
            colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Animated heart icon
                Image(systemName: "heart.fill")
                    .font(.system(size: 80))
                    .foregroundColor(colors.accent)
                    .scaleEffect(isAnimating ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)
                
                Text("Checking Wearable Device")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(colors.text)
                
                Text("Please wait while we check your connected wearable device...")
                    .font(.body)
                    .foregroundColor(colors.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // Progress bar
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle())
                    .frame(height: 8)
                    .padding(.horizontal)
                
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(colors.secondary)
            }
            .padding()
        }
        .onAppear {
            isAnimating = true
            startProgress()
        }
    }
    
    private func startProgress() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            progress += 0.05
            if progress >= 1.0 {
                timer.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onComplete()
                }
            }
        }
    }
}

struct WearableRequiredView: View {
    let onDemoMode: () -> Void
    
    private let colors = HeartIDColors()
    
    var body: some View {
        ZStack {
            // Background
            colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Warning icon
                Image(systemName: "applewatch.slash")
                    .font(.system(size: 80))
                    .foregroundColor(colors.warning)
                
                Text("Wearable Device Required")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(colors.text)
                
                Text("Please connect to a wearable device to use HeartID. A compatible Apple Watch or other supported wearable is required for heart rate monitoring.")
                    .font(.body)
                    .foregroundColor(colors.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
                
                // Demo mode button
                VStack(spacing: 20) {
                    Button("Continue in Demo Mode") {
                        onDemoMode()
                    }
                    .buttonStyle(DemoButtonStyle(colors: colors))
                    
                    Text("esc")
                        .font(.caption)
                        .foregroundColor(colors.secondary)
                        .opacity(0.7)
                }
            }
            .padding()
        }
    }
}

struct EnrollmentRequiredView: View {
    let onDemoMode: () -> Void
    
    private let colors = HeartIDColors()
    
    var body: some View {
        ZStack {
            // Background
            colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Warning icon
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 80))
                    .foregroundColor(colors.warning)
                
                Text("Enrollment Required")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(colors.text)
                
                Text("Enrollment must be completed on your wearable device before you can use HeartID. Please complete the enrollment process on your Apple Watch.")
                    .font(.body)
                    .foregroundColor(colors.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
                
                // Demo mode button
                VStack(spacing: 20) {
                    Button("Continue in Demo Mode") {
                        onDemoMode()
                    }
                    .buttonStyle(DemoButtonStyle(colors: colors))
                    
                    Text("esc")
                        .font(.caption)
                        .foregroundColor(colors.secondary)
                        .opacity(0.7)
                }
            }
            .padding()
        }
    }
}

struct DemoButtonStyle: ButtonStyle {
    let colors: HeartIDColors
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .background(colors.accent)
            .foregroundColor(.black)
            .cornerRadius(12)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Color Scheme
// struct HeartIDColors {
    // let background = Color("Background")
    // let surface = Color("Surface")
    // let accent = Color("Accent")
    // let text = Color("Text")
    
    // Semantic colors
    // let success = Color.green.opacity(0.8)
    // let warning = Color.yellow.opacity(0.8)
    // let error = Color.red.opacity(0.8)
//}

// MARK: - Custom Button Style
struct HeartIDButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(HeartIDColors().accent)
            .cornerRadius(12)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3), value: configuration.isPressed)
    }
}

// MARK: - Formatters
private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

// MARK: - Preview
#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
