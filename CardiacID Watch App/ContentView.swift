//
//  ContentView.swift
//  HeartID_WatchApp_V3 Watch App
//
//  Created by Jim Locke on 9/16/25.
//

import SwiftUI
import Combine
import HealthKit

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var showLoginScreen = true
    @State private var username = ""
    @State private var password = ""
    @State private var loginError = ""
    @State private var isAuthenticated = false
    @State private var isUserEnrolled = false
    @State private var showEnrollmentFlow = false
    
    var body: some View {
        if showLoginScreen || !isAuthenticated {
            LoginView(
                username: $username,
                password: $password,
                loginError: $loginError,
                onLogin: performLogin
            )
        } else if !isUserEnrolled || showEnrollmentFlow {
            // Show enrollment flow if user is not enrolled
            EnrollmentFlowView(
                isEnrolled: $isUserEnrolled,
                showEnrollment: $showEnrollmentFlow,
                onEnrollmentComplete: {
                    isUserEnrolled = true
                    showEnrollmentFlow = false
                    selectedTab = 0 // Go to landing screen
                }
            )
        } else {
            TabView(selection: $selectedTab) {
                // Landing Screen
                LandingView()
                    .tag(0)
                
                // Menu Screen
                MenuView()
                    .tag(1)
                
                // Enroll Screen
                EnrollView()
                    .tag(2)
                
                // Authenticate Screen
                AuthenticateView()
                    .tag(3)
                
                // Settings Screen
                SettingsView()
                    .tag(4)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        }
    }
    
    private func performLogin() {
        // Validate inputs
        guard !username.isEmpty && !password.isEmpty else {
            loginError = "Please enter both username and password"
            print("❌ Login failed - Empty credentials")
            return
        }

        // TODO: Replace with real Supabase authentication
        // For now, authenticate with any valid email format
        guard username.contains("@") && username.contains(".") else {
            loginError = "Please enter a valid email address"
            print("❌ Login failed - Invalid email format")
            return
        }

        // Simulate authentication (replace with real Supabase call)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isAuthenticated = true
            self.showLoginScreen = false
            self.loginError = ""

            // Check if user is enrolled
            self.checkEnrollmentStatus()

            print("✅ Login successful - User authenticated: \(self.username)")
        }
    }
    
    private func checkEnrollmentStatus() {
        // Simulate checking enrollment status
        // In a real app, this would check UserDefaults, Core Data, or a service
        let enrollmentKey = "isUserEnrolled_\(username)"
        
        do {
            isUserEnrolled = UserDefaults.standard.bool(forKey: enrollmentKey)
            
            if !isUserEnrolled {
                print("📝 User not enrolled - showing enrollment flow")
                showEnrollmentFlow = true
            } else {
                print("✅ User already enrolled - proceeding to main app")
                showEnrollmentFlow = false
            }
        } catch {
            print("❌ Error checking enrollment status: \(error)")
            // Default to showing enrollment flow if there's an error
            isUserEnrolled = false
            showEnrollmentFlow = true
        }
    }
}

struct LandingView: View {
    @State private var navigateToMenu = false
    @State private var showContent = false
    @State private var holdTimer: Timer?
    @State private var holdProgress: Double = 0
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if showContent {
                    // HeartID Logo/Icon
                    Image(systemName: "heart.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                    
                    Text("HeartID")
                        .font(.system(size: 28)) // Reduced from .largeTitle (34pt) by 16%
                        .fontWeight(.bold)
                    
                    Text("Biometric Authentication")
                        .font(.system(size: 16)) // Reduced from .headline (17pt) by 16%
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Navigation Buttons
                    VStack(spacing: 15) {
                        NavigationButton(
                            title: "Menu",
                            icon: "list.bullet",
                            action: { navigateToMenu = true }
                        )
                        
                        NavigationButton(
                            title: "Enroll",
                            icon: "person.badge.plus",
                            action: { /* Navigate to enroll */ }
                        )
                        
                        NavigationButton(
                            title: "Authenticate",
                            icon: "checkmark.shield",
                            action: { /* Navigate to authenticate */ }
                        )
                        
                        NavigationButton(
                            title: "Settings",
                            icon: "gear",
                            action: { /* Navigate to settings */ }
                        )
                    }
                    
                    Spacer()
                } else {
                    // 6-second hold screen
                    VStack(spacing: 20) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.red)
                        
                        Text("HeartID")
                            .font(.system(size: 28)) // Reduced by 16%
                            .fontWeight(.bold)
                        
                        Text("Biometric Authentication")
                            .font(.system(size: 16)) // Reduced by 16%
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        // Hold progress indicator
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 6)
                                    .frame(width: 60, height: 60)
                                
                                Circle()
                                    .trim(from: 0, to: holdProgress)
                                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                    .frame(width: 60, height: 60)
                                    .rotationEffect(.degrees(-90))
                                    .animation(.linear(duration: 0.1), value: holdProgress)
                                
                                Text("\(Int(holdProgress * 6))")
                                    .font(.headline)
                                    .fontWeight(.bold)
                            }
                            
                            Text("Hold to continue...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .onAppear {
                        startHoldTimer()
                    }
                }
            }
            .padding()
        }
        .sheet(isPresented: $navigateToMenu) {
            MenuView()
        }
    }
    
    private func startHoldTimer() {
        holdProgress = 0
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            holdProgress += 0.1 / 6.0 // 6 seconds total
            
            if holdProgress >= 1.0 {
                timer.invalidate()
                withAnimation(.easeInOut(duration: 0.5)) {
                    showContent = true
                }
            }
        }
    }
}

struct NavigationButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct LoginView: View {
    @Binding var username: String
    @Binding var password: String
    @Binding var loginError: String
    let onLogin: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // HeartID Logo
                Image(systemName: "heart.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.red)
                
                Text("HeartID")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Enterprise Login")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Login Form
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Username")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        TextField("Enter username", text: $username)
                            .disableAutocorrection(true)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        SecureField("Enter password", text: $password)
                    }
                    
                    if !loginError.isEmpty {
                        Text(loginError)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                    
                    Button("Login") {
                        onLogin()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .font(.headline)
                }
                .padding(.horizontal, 20)
                
                Spacer()
            }
            .padding()
        }
    }
}

// MARK: - Enrollment Flow View
struct EnrollmentFlowView: View {
    @Binding var isEnrolled: Bool
    @Binding var showEnrollment: Bool
    let onEnrollmentComplete: () -> Void
    
    @State private var currentStep = 0
    @State private var enrollmentProgress: Double = 0.0
    @State private var isCapturing = false
    @State private var captureProgress: Double = 0.0
    @State private var heartRateSamples: [Double] = []
    @State private var showSuccess = false
    
    private let totalSteps = 4
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Progress indicator
                VStack(spacing: 12) {
                    Text("Initial Enrollment")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    ProgressView(value: enrollmentProgress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(height: 8)
                    
                    Text("Step \(currentStep + 1) of \(totalSteps)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                
                // Step content
                Group {
                    switch currentStep {
                    case 0:
                        WelcomeStepView()
                    case 1:
                        InstructionsStepView()
                    case 2:
                        CaptureStepView(
                            isCapturing: $isCapturing,
                            captureProgress: $captureProgress,
                            heartRateSamples: $heartRateSamples
                        )
                    case 3:
                        CompletionStepView(
                            showSuccess: $showSuccess,
                            onComplete: completeEnrollment
                        )
                    default:
                        WelcomeStepView()
                    }
                }
                .padding()
                
                // Navigation buttons
                HStack(spacing: 16) {
                    if currentStep > 0 {
                        Button("Back") {
                            withAnimation {
                                currentStep -= 1
                                updateProgress()
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    
                    Spacer()
                    
                    Button(currentStep == totalSteps - 1 ? "Complete" : "Next") {
                        if currentStep == totalSteps - 1 {
                            completeEnrollment()
                        } else if currentStep == 2 {
                            // Start capture when moving to step 3
                            isCapturing = true
                            withAnimation {
                                currentStep += 1
                                updateProgress()
                            }
                        } else {
                            withAnimation {
                                currentStep += 1
                                updateProgress()
                            }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(currentStep == 2 && isCapturing) // Only disable during active capture
                }
                .padding()
            }
        }
        .onAppear {
            updateProgress()
        }
    }
    
    private func updateProgress() {
        enrollmentProgress = Double(currentStep) / Double(totalSteps - 1)
    }
    
    private func completeEnrollment() {
        // Save enrollment status
        let enrollmentKey = "isUserEnrolled_john.doe@acme.com"
        UserDefaults.standard.set(true, forKey: enrollmentKey)
        
        // Show success animation
        withAnimation(.easeInOut(duration: 1.0)) {
            showSuccess = true
        }
        
        // Complete enrollment after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            onEnrollmentComplete()
        }
    }
}

// MARK: - Enrollment Step Views
struct WelcomeStepView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)
            
            Text("Welcome to HeartID")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Let's set up your biometric authentication. This process will take just a few minutes.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
    }
}

struct InstructionsStepView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 50))
                .foregroundColor(.blue)
            
            Text("How it Works")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 12) {
                InstructionRow(icon: "1.circle.fill", text: "Place your finger on the heart rate sensor")
                InstructionRow(icon: "2.circle.fill", text: "Hold still for 30 seconds")
                InstructionRow(icon: "3.circle.fill", text: "We'll capture your unique heart pattern")
                InstructionRow(icon: "4.circle.fill", text: "Use this for secure authentication")
            }
        }
    }
}

struct CaptureStepView: View {
    @Binding var isCapturing: Bool
    @Binding var captureProgress: Double
    @Binding var heartRateSamples: [Double]
    
    @StateObject private var healthKitService = HealthKitService()
    @State private var timeRemaining = 30
    @State private var currentHeartRate: Double = 0
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        VStack(spacing: 20) {
            // Pulsing Heart Icon
            Image(systemName: "heart.fill")
                .font(.system(size: 60))
                .foregroundColor(isCapturing ? .red : .gray)
                .scaleEffect(isCapturing ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isCapturing)
            
            // Status Text
            Text(isCapturing ? "Capturing Heart Pattern..." : "Ready to Capture")
                .font(.title2)
                .fontWeight(.bold)
            
            if isCapturing {
                VStack(spacing: 12) {
                    // Current Heart Rate Display
                    if currentHeartRate > 0 {
                        Text("\(Int(currentHeartRate)) BPM")
                            .font(.headline)
                            .foregroundColor(.red)
                    }
                    
                    // Time Remaining
                    Text("\(timeRemaining) seconds remaining")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    // Growing Progress Bar
                    ProgressView(value: captureProgress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: .red))
                        .frame(height: 8)
                        .scaleEffect(x: 1.0, y: 2.0, anchor: .center)
                        .animation(.easeInOut(duration: 0.3), value: captureProgress)
                }
            } else {
                VStack(spacing: 8) {
                    Text("Tap 'Next' to begin capturing your heart pattern")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    
                    if !healthKitService.isAuthorized {
                        Text("HealthKit authorization required")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .onAppear {
            if isCapturing {
                startCapture()
            }
        }
        .onChange(of: isCapturing) { newValue in
            if newValue {
                startCapture()
            } else {
                stopCapture()
            }
        }
        .onReceive(healthKitService.$isCapturing) { capturing in
            isCapturing = capturing
        }
        .onReceive(healthKitService.$captureProgress) { progress in
            captureProgress = progress
            timeRemaining = max(0, 30 - Int(progress * 30))
        }
        .onReceive(healthKitService.$currentHeartRate) { heartRate in
            currentHeartRate = heartRate
        }
        .onReceive(healthKitService.$errorMessage) { error in
            if let error = error {
                errorMessage = error
                showingError = true
            }
        }
        .alert("HealthKit Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func startCapture() {
        print("🔄 Starting heart rate capture...")
        
        // Check if HealthKit is available
        guard HKHealthStore.isHealthDataAvailable() else {
            print("⚠️ HealthKit not available - simulating capture")
            // Simulate capture in demo mode
            simulateHeartRateCapture()
            return
        }
        
        // Request authorization if needed
        if !healthKitService.isAuthorized {
            print("🔐 Requesting HealthKit authorization...")
            healthKitService.requestAuthorization()
        }
        
        // Start the actual HealthKit capture
        healthKitService.startHeartRateCapture(duration: 30.0)
        
        // Subscribe to heart rate samples
        healthKitService.heartRatePublisher
            .sink { samples in
                print("📊 Received \(samples.count) heart rate samples")
                heartRateSamples = samples.map { $0.value }
            }
            .store(in: &cancellables)
    }
    
    private func simulateHeartRateCapture() {
        // Simulate heart rate capture for demo purposes
        print("🎭 Simulating heart rate capture...")
        isCapturing = true
        
        // Simulate progress updates
        var progress: Double = 0
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            progress += 0.01
            captureProgress = min(progress, 1.0)
            
            // Simulate heart rate data
            let simulatedHeartRate = Double.random(in: 60...100)
            currentHeartRate = simulatedHeartRate
            heartRateSamples.append(simulatedHeartRate)
            
            if progress >= 1.0 {
                timer.invalidate()
                isCapturing = false
                print("✅ Simulated capture completed")
            }
        }
    }
    
    private func stopCapture() {
        healthKitService.stopHeartRateCapture()
    }
}

struct CompletionStepView: View {
    @Binding var showSuccess: Bool
    let onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: showSuccess ? "checkmark.circle.fill" : "clock.fill")
                .font(.system(size: 60))
                .foregroundColor(showSuccess ? .green : .orange)
                .scaleEffect(showSuccess ? 1.2 : 1.0)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: showSuccess)
            
            Text(showSuccess ? "Enrollment Complete!" : "Processing...")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(showSuccess ? "Your heart pattern has been saved securely. You can now use HeartID for authentication." : "Please wait while we process your heart pattern data.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
    }
}

struct InstructionRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            Text(text)
                .font(.body)
            
            Spacer()
        }
    }
}

// MARK: - Button Styles
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyle.Configuration) -> some View {
        configuration.label
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyle.Configuration) -> some View {
        configuration.label
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.gray.opacity(0.2))
            .foregroundColor(.primary)
            .cornerRadius(12)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthenticationService())
        .environmentObject(HealthKitService())
        .environmentObject(BackgroundTaskService())
        .environmentObject(DataManager())
}

