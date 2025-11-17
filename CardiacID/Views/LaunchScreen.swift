import SwiftUI
import LocalAuthentication

struct LaunchScreen: View {
    // Color scheme
    private let colors = HeartIDColors()
    
    // Animation states
    @State private var scale = 0.3 // Start small for dramatic entrance
    @State private var opacity = 0.0 // Start invisible
    @State private var rotation = -45.0 // Start rotated for dynamic entrance
    @State private var showWelcomeFlow = false
    @State private var isNewUser = true
    
    // Heartbeat animation states
    @State private var heartbeatScale = 1.0
    @State private var pulseRadius: [CGFloat] = [0, 0, 0] // For radiating circles
    @State private var pulseOpacity: [Double] = [0, 0, 0]
    @State private var isAnimating = false
    
    // Dynamic entrance states
    @State private var titleOffset: CGFloat = 100
    @State private var subtitleOffset: CGFloat = 150
    @State private var indicatorsOffset: CGFloat = 200
    @State private var logoBlur: CGFloat = 20
    
    // Security and user state
    @State private var hasExistingEnrollment = false
    @State private var biometricAuthAvailable = false
    
    // Callback for app initialization completion
    let onInitializationComplete: (Bool) -> Void
    
    init(onInitializationComplete: @escaping (Bool) -> Void = { _ in }) {
        self.onInitializationComplete = onInitializationComplete
    }
    
    var body: some View {
        ZStack {
            // Debug: Quick skip option - remove in production
            #if DEBUG
            VStack {
                HStack {
                    Spacer()
                    Button("Skip") {
                        showWelcomeFlow = true
                    }
                    .padding()
                    .foregroundColor(.white)
                    .opacity(0.7)
                }
                Spacer()
            }
            .zIndex(999)
            #endif
            
            // Fully opaque background
            Color.black
                .ignoresSafeArea()
            
            // Optional: Subtle gradient overlay (fully opaque)
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black,
                    colors.background,
                    colors.accent.opacity(0.2)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            if showWelcomeFlow {
                // New user welcome flow with prominent sign-up
                WelcomeFlowView(
                    isNewUser: isNewUser,
                    hasExistingEnrollment: hasExistingEnrollment,
                    biometricAuthAvailable: biometricAuthAvailable,
                    onComplete: { userChoice in
                        onInitializationComplete(userChoice == .signUp)
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            } else {
                // Initial loading screen
                VStack(spacing: 30) {
                    // Enhanced logo with security indicators and heartbeat animation
                    ZStack {
                        // Radiating pulse circles behind the heart - heartbeat effect
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            colors.accent.opacity(0.6),
                                            colors.accent.opacity(0.2),
                                            Color.clear
                                        ]),
                                        startPoint: .center,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 3
                                )
                                .frame(width: pulseRadius[index], height: pulseRadius[index])
                                .opacity(pulseOpacity[index])
                                .animation(.easeOut(duration: 1.5).delay(Double(index) * 0.3), value: pulseRadius[index])
                                .animation(.easeOut(duration: 1.5).delay(Double(index) * 0.3), value: pulseOpacity[index])
                        
                        }
                        
                        // Static security indicator circles (behind heart)
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .stroke(colors.accent.opacity(0.15 - Double(index) * 0.05), lineWidth: 1.5)
                                .frame(width: 140 + CGFloat(index) * 25, height: 140 + CGFloat(index) * 25)
                                .scaleEffect(scale * (0.9 + Double(index) * 0.05))
                        }
                        
                        // Heart icon with ECG line - enhanced with heartbeat
                        HStack(spacing: 0) {
                            // Heart icon with security shield overlay
                            ZStack {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 72)) // Increased from 60
                                    .foregroundStyle(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.orange,
                                                Color.red.opacity(0.8)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .rotationEffect(.degrees(rotation))
                                    .scaleEffect(heartbeatScale)
                                    .blur(radius: logoBlur)
                                    .animation(.easeOut(duration: 0.8), value: logoBlur)
                                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: heartbeatScale)
                                
                                // Enhanced security shield indicator - 30% larger
                                Image(systemName: "shield.fill")
                                    .font(.system(size: 31)) // Increased 30% from 24
                                    .foregroundStyle(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                colors.accent,
                                                colors.accent.opacity(0.6)
                                            ]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .offset(x: 26, y: -26) // Adjusted for larger heart
                                    .opacity(opacity)
                                    .shadow(color: colors.accent.opacity(0.5), radius: 4, x: 0, y: 2)
                            }
                            .offset(x: -5)
                            .zIndex(1)
                            
                            // Enhanced ECG line with glow effect
                            HeartRateLine()
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            colors.accent,
                                            colors.accent.opacity(0.6),
                                            colors.accent
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
                                )
                                .frame(width: 90, height: 45) // Slightly larger
                                .offset(x: -15)
                                .shadow(color: colors.accent.opacity(0.6), radius: 8, x: 0, y: 0)
                                .opacity(opacity)
                        }
                        .scaleEffect(scale)
                    }
                    .opacity(opacity)
                    
                    // App name with security emphasis - dynamic entrance
                    VStack(spacing: 8) {
                        Text("HeartID")
                            .font(.system(size: 56, weight: .black, design: .rounded)) // Increased from 43
                            .foregroundStyle(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        colors.text,
                                        colors.accent.opacity(0.8),
                                        colors.text
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .opacity(opacity)
                            .offset(y: titleOffset)
                            .animation(.spring(response: 1.2, dampingFraction: 0.7).delay(0.5), value: titleOffset)
                            .shadow(color: colors.accent.opacity(0.3), radius: 8, x: 0, y: 4)
                        
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(colors.accent)
                            Text("Secure Biometric Authentication")
                                .font(.system(size: 18, weight: .semibold, design: .rounded)) // Increased from 16
                                .foregroundColor(colors.secondary)
                        }
                        .opacity(opacity * 0.9)
                        .offset(y: subtitleOffset)
                        .animation(.spring(response: 1.0, dampingFraction: 0.8).delay(0.8), value: subtitleOffset)
                        .shadow(color: colors.accent.opacity(0.2), radius: 4, x: 0, y: 2)
                    }
                    
                    // Loading indicator with security context
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: colors.accent))
                                .scaleEffect(0.8)
                            
                            Text("Initializing Secure Environment...")
                                .font(.caption)
                                .foregroundColor(colors.secondary)
                                .opacity(opacity * 0.6)
                        }
                        
                        // Enhanced security status indicators - 30% larger with dynamic entrance
                        HStack(spacing: 20) { // Increased spacing
                            SecurityIndicator(
                                icon: "checkmark.shield.fill",
                                text: "Encrypted",
                                isActive: true,
                                size: .large // Custom size parameter
                            )
                            
                            SecurityIndicator(
                                icon: "person.badge.shield.checkmark.fill",
                                text: "Biometric Ready",
                                isActive: biometricAuthAvailable,
                                size: .large
                            )
                            
                            SecurityIndicator(
                                icon: "network.badge.shield.half.filled",
                                text: "Secure Channel",
                                isActive: true,
                                size: .large
                            )
                        }
                        .opacity(opacity * 0.8)
                        .offset(y: indicatorsOffset)
                        .animation(.spring(response: 1.4, dampingFraction: 0.6).delay(1.2), value: indicatorsOffset)
                        .padding(.top, 12)
                    }
                    .padding(.top, 20)
                }
            }
        }
        .onAppear {
            initializeSecureLaunch()
        }
    }
    
    private func initializeSecureLaunch() {
        print("HeartID: Starting advanced secure launch initialization")
        
        // Clear all animation states and buffers first
        clearAllBuffers()
        
        // Start the dynamic entrance sequence
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.startDynamicEntrance()
        }
        
        // Store timer reference for proper cleanup
        let heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { timer in
            if !self.showWelcomeFlow && self.isAnimating {
                self.triggerHeartbeat()
            } else {
                timer.invalidate()
            }
        }
        
        // Perform security and user state checks
        Task {
            do {
                await performSecurityChecks()
                
                // Reduced animation time to 2.5 seconds instead of 5
                try await Task.sleep(nanoseconds: 2_500_000_000) // 2.5 seconds
                
                await MainActor.run {
                    print("HeartID: Loading completed, preparing dynamic transition")
                    heartbeatTimer.invalidate() // Clean up timer
                    
                    // Dynamic exit animation before showing welcome flow
                    self.performDynamicExit {
                        withAnimation(.spring(response: 1.2, dampingFraction: 0.8)) {
                            self.showWelcomeFlow = true
                        }
                    }
                }
            } catch {
                print("HeartID: Error in initialization task: \(error)")
                await MainActor.run {
                    heartbeatTimer.invalidate()
                    self.emergencyShowWelcomeFlow()
                }
            }
        }
        
        // Reduced fallback timeout to 4 seconds to match new timing
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            if !self.showWelcomeFlow {
                print("HeartID: Enhanced fallback triggered")
                heartbeatTimer.invalidate()
                self.emergencyShowWelcomeFlow()
            }
        }
    }
    
    private func performSecurityChecks() async {
        do {
            // Add timeout to prevent hanging
            try await withTimeout(seconds: 2.0) {
                // Check for existing enrollment data
                await checkExistingEnrollment()
                
                // Check biometric availability
                await checkBiometricAvailability()
                
                // Determine if this is likely a new user
                await determineUserStatus()
            }
            
            print("HeartID: Security checks completed successfully")
        } catch {
            print("HeartID: Error during security checks: \(error)")
            // Continue with default values if checks fail
            await MainActor.run {
                hasExistingEnrollment = false
                biometricAuthAvailable = false
                isNewUser = true
            }
        }
    }
    
    // Helper function to add timeout to async operations
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            
            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            
            group.cancelAll()
            return result
        }
    }
    
    struct TimeoutError: Error {
        let localizedDescription = "Operation timed out"
    }
    
    private func checkExistingEnrollment() async {
        await MainActor.run {
            do {
                // For now, assume new installation means new user
                hasExistingEnrollment = UserDefaults.standard.bool(forKey: "hasCompletedEnrollment")
                print("HeartID: Existing enrollment check completed - hasExistingEnrollment: \(hasExistingEnrollment)")
            } catch {
                print("HeartID: Error checking existing enrollment: \(error)")
                hasExistingEnrollment = false
            }
        }
    }
    
    private func checkBiometricAvailability() async {
        await MainActor.run {
            do {
                let context = LAContext()
                var error: NSError?
                
                biometricAuthAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
                if let error = error {
                    print("HeartID: Biometric availability check error: \(error.localizedDescription)")
                    biometricAuthAvailable = false
                } else {
                    print("HeartID: Biometric availability: \(biometricAuthAvailable)")
                }
            } catch {
                print("HeartID: Error checking biometric availability: \(error)")
                biometricAuthAvailable = false
            }
        }
    }
    
    private func determineUserStatus() async {
        await MainActor.run {
            do {
                // Check if app has been launched before
                let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
                isNewUser = !hasLaunchedBefore
                
                if !hasLaunchedBefore {
                    UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
                }
                
                print("HeartID: User status determined - isNewUser: \(isNewUser)")
            } catch {
                print("HeartID: Error determining user status: \(error)")
                isNewUser = true // Default to new user if error occurs
            }
        }
    }
}

// MARK: - Enhanced Animation Control Functions
extension LaunchScreen {
    private func clearAllBuffers() {
        // Reset all animation states to initial values
        scale = 0.3
        opacity = 0.0
        rotation = -45.0
        heartbeatScale = 1.0
        pulseRadius = [0, 0, 0]
        pulseOpacity = [0, 0, 0]
        titleOffset = 100
        subtitleOffset = 150
        indicatorsOffset = 200
        logoBlur = 20
        isAnimating = false
    }
    
    private func startDynamicEntrance() {
        print("HeartID: Starting dynamic entrance sequence")
        
        // Dramatic entrance sequence
        withAnimation(.spring(response: 1.8, dampingFraction: 0.6)) {
            scale = 1.0
            opacity = 1.0
            rotation = 0.0
            logoBlur = 0
        }
        
        // Staggered entrance of text elements
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 1.2, dampingFraction: 0.7)) {
                self.titleOffset = 0
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.8)) {
                self.subtitleOffset = 0
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.spring(response: 1.4, dampingFraction: 0.6)) {
                self.indicatorsOffset = 0
            }
        }
        
        // Start continuous heartbeat after entrance
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.isAnimating = true
            self.triggerHeartbeat()
        }
    }
    
    private func triggerHeartbeat() {
        guard isAnimating && !showWelcomeFlow else { return }
        
        // Heart pulse animation
        withAnimation(.easeInOut(duration: 0.15)) {
            heartbeatScale = 1.15
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.15)) {
                self.heartbeatScale = 0.95
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.heartbeatScale = 1.0
            }
        }
        
        // Radiating circles animation synchronized with heartbeat
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.2) {
                withAnimation(.easeOut(duration: 1.5)) {
                    self.pulseRadius[i] = 200 + CGFloat(i) * 50
                    self.pulseOpacity[i] = 0.8
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    withAnimation(.easeOut(duration: 0.8)) {
                        self.pulseOpacity[i] = 0.0
                    }
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.pulseRadius[i] = 0
                }
            }
        }
    }
    
    private func performDynamicExit(completion: @escaping () -> Void) {
        print("HeartID: Starting dynamic exit sequence")
        isAnimating = false
        
        // Dramatic exit animation
        withAnimation(.spring(response: 0.8, dampingFraction: 0.9)) {
            scale = 0.2
            opacity = 0.0
            titleOffset = -100
            subtitleOffset = -150
            indicatorsOffset = -200
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            completion()
        }
    }
    
    private func emergencyShowWelcomeFlow() {
        withAnimation(.spring(response: 0.6, dampingFraction: 1.0)) {
            isAnimating = false
            showWelcomeFlow = true
        }
    }
}

// MARK: - Security Indicator Component
struct SecurityIndicator: View {
    let icon: String
    let text: String
    let isActive: Bool
    let size: IndicatorSize
    
    enum IndicatorSize {
        case standard
        case large
        
        var iconSize: CGFloat {
            switch self {
            case .standard: return 14
            case .large: return 18 // 30% larger (14 * 1.3 ≈ 18)
            }
        }
        
        var textSize: CGFloat {
            switch self {
            case .standard: return 8
            case .large: return 10 // 30% larger (8 * 1.3 ≈ 10)
            }
        }
        
        var spacing: CGFloat {
            switch self {
            case .standard: return 4
            case .large: return 6
            }
        }
    }
    
    init(icon: String, text: String, isActive: Bool, size: IndicatorSize = .standard) {
        self.icon = icon
        self.text = text
        self.isActive = isActive
        self.size = size
    }
    
    private let colors = HeartIDColors()
    
    var body: some View {
        VStack(spacing: size.spacing) {
            Image(systemName: icon)
                .font(.system(size: size.iconSize, weight: .semibold))
                .foregroundStyle(
                    isActive ? 
                    LinearGradient(
                        gradient: Gradient(colors: [colors.accent, colors.accent.opacity(0.7)]),
                        startPoint: .top,
                        endPoint: .bottom
                    ) :
                    LinearGradient(
                        gradient: Gradient(colors: [colors.secondary.opacity(0.5), colors.secondary.opacity(0.3)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: isActive ? colors.accent.opacity(0.4) : Color.clear, radius: 3, x: 0, y: 1)
            
            Text(text)
                .font(.system(size: size.textSize, weight: .semibold, design: .rounded))
                .foregroundColor(isActive ? colors.text.opacity(0.9) : colors.secondary.opacity(0.5))
                .shadow(color: colors.text.opacity(0.1), radius: 1, x: 0, y: 1)
        }
        .padding(.vertical, size == .large ? 8 : 6)
        .padding(.horizontal, size == .large ? 12 : 8)
        .background(
            RoundedRectangle(cornerRadius: size == .large ? 12 : 8)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            colors.surface.opacity(0.8),
                            colors.surface.opacity(0.4)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size == .large ? 12 : 8)
                        .stroke(
                            isActive ? 
                            colors.accent.opacity(0.3) : 
                            colors.secondary.opacity(0.1), 
                            lineWidth: 1
                        )
                )
        )
        .scaleEffect(isActive ? 1.0 : 0.95)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isActive)
    }
}

// MARK: - Welcome Flow for New Users
struct WelcomeFlowView: View {
    let isNewUser: Bool
    let hasExistingEnrollment: Bool
    let biometricAuthAvailable: Bool
    let onComplete: (UserChoice) -> Void
    
    private let colors = HeartIDColors()
    @State private var currentStep = 0
    @State private var showActions = false
    
    enum UserChoice {
        case signUp
        case signIn
    }
    
    var body: some View {
        VStack(spacing: 0) { // Changed from 20 to 0 for manual control
            // Add top spacer to push content down 30%
            Spacer()
                .frame(height: 80) // Pushes content down
            
            // Progress indicator
            if isNewUser {
                HStack {
                    Text("Welcome to HeartID")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(colors.text)
                    Spacer()
                    Text("Step 1 of 2")
                        .font(.caption)
                        .foregroundColor(colors.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(colors.surface)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 25) // Spacing after progress indicator
            }
            
            // Content based on user status
            VStack(spacing: 15) { // Reduced from 20 to 15
                if isNewUser {
                    newUserContent
                } else {
                    returningUserContent
                }
            }
            
            // Flexible spacer that adjusts based on content
            Spacer()
                .frame(minHeight: 30, maxHeight: 60) // Controlled spacing
            
            // Action buttons - moved up 15%
            if showActions {
                actionButtons
                    .padding(.bottom, 20) // Reduced bottom padding
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    showActions = true
                }
            }
        }
    }
    
    private var newUserContent: some View {
        VStack(spacing: 15) { // Reduced from 20 to 15
            // Security-first messaging
            VStack(spacing: 10) { // Reduced from 12 to 10
                Image(systemName: "heart.rectangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(colors.accent)
                    .background(Color.black.opacity(0.8))
                
                Text("Secure Your Digital Life")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(colors.text)
                    .multilineTextAlignment(.center)
                
                Text("Your unique cardiac signature provides unbreakable biometric security. Get started with a quick, secure enrollment process.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colors.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            
            // Security features highlight
            VStack(spacing: 8) { // Reduced from 10 to 8
                LaunchFeatureRow(
                    icon: "shield.checkerboard", 
                    title: "Military-Grade Security", 
                    description: "Your heart pattern is encrypted and never leaves your device",
                    iconColor: colors.accent,
                    backgroundColor: colors.accent.opacity(0.8),
                    titleColor: colors.text,
                    descriptionColor: colors.secondary
                )
                LaunchFeatureRow(
                    icon: "timer", 
                    title: "Instant Access", 
                    description: "Authenticate in seconds with just your heartbeat",
                    iconColor: colors.accent,
                    backgroundColor: colors.accent.opacity(0.8),
                    titleColor: colors.text,
                    descriptionColor: colors.secondary
                )
                LaunchFeatureRow(
                    icon: "person.badge.shield.checkmark", 
                    title: "Private & Secure", 
                    description: "No passwords to remember or lose",
                    iconColor: colors.accent,
                    backgroundColor: colors.accent.opacity(0.8),
                    titleColor: colors.text,
                    descriptionColor: colors.secondary
                )
            }
            .padding(.horizontal, 30)
        }
    }
    
    private var returningUserContent: some View {
        VStack(spacing: 15) { // Reduced from 20 to 15
            Image(systemName: "person.wave.2.fill")
                .font(.system(size: 50))
                .foregroundColor(colors.accent)
            
            Text("Welcome Back")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(colors.text)
            
            if hasExistingEnrollment {
                Text("Your secure cardiac profile is ready. Sign in to continue.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colors.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            } else {
                Text("Complete your secure setup to unlock HeartID's full potential.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colors.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
        }
    }
    
    private var actionButtons: some View {
        VStack(spacing: 14) { // Reduced from 16 to 14
            if isNewUser || !hasExistingEnrollment {
                // Primary CTA - Sign Up (Active by default for new users)
                Button(action: { onComplete(.signUp) }) {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                        Text("Get Started - Create Secure Profile")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [colors.accent, colors.accent.opacity(0.8)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: colors.accent.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .padding(.horizontal, 30)
                
                // Secondary action - Sign In
                Button(action: { onComplete(.signIn) }) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill.checkmark")
                            .font(.system(size: 16))
                        Text("I Already Have an Account")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundColor(colors.text.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(colors.surface)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(colors.secondary.opacity(0.2), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 30)
            } else {
                // Existing user - prioritize sign in
                Button(action: { onComplete(.signIn) }) {
                    HStack(spacing: 12) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 20))
                        Text("Continue with HeartID")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(colors.accent)
                    .cornerRadius(16)
                    .shadow(color: colors.accent.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .padding(.horizontal, 30)
            }
        }
        .padding(.bottom, 25) // Reduced from 30 to 25
    }
}

// Custom shape for heart rate line
struct HeartRateLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let width = rect.width
        let height = rect.height
        let midHeight = height / 2
        
        // Start at left edge
        path.move(to: CGPoint(x: 0, y: midHeight))
        
        // Flat line
        path.addLine(to: CGPoint(x: width * 0.2, y: midHeight))
        
        // ECG spike
        path.addLine(to: CGPoint(x: width * 0.3, y: midHeight - height * 0.4))
        path.addLine(to: CGPoint(x: width * 0.4, y: midHeight + height * 0.4))
        path.addLine(to: CGPoint(x: width * 0.5, y: midHeight - height * 0.2))
        
        // Continue with normal line
        path.addLine(to: CGPoint(x: width * 0.6, y: midHeight))
        path.addLine(to: CGPoint(x: width, y: midHeight))
        
        return path
    }
}

// MARK: - Launch Feature Row Component
struct LaunchFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    let iconColor: Color
    let backgroundColor: Color
    let titleColor: Color
    let descriptionColor: Color
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)
            
            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(titleColor)
                
                Text(description)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(descriptionColor)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }
}

struct LaunchScreen_Previews: PreviewProvider {
    static var previews: some View {
        LaunchScreen()
            .preferredColorScheme(.dark)
    }
}
