import SwiftUI
import LocalAuthentication

struct LaunchScreen: View {
    // Color scheme
    private let colors = HeartIDColors()
    
    // Animation states
    @State private var scale = 0.7
    @State private var opacity = 0.0
    @State private var rotation = -20.0
    @State private var showWelcomeFlow = false
    @State private var isNewUser = true
    @State private var loadingComplete = false
    
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
            // Background gradient with enhanced security visual
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(UIColor.systemBackground),
                    colors.background.opacity(0.3),
                    colors.accent.opacity(0.1)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            if loadingComplete && showWelcomeFlow {
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
                    // Enhanced logo with security indicators
                    ZStack {
                        // Multiple pulsing circles for security effect
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .stroke(colors.accent.opacity(0.3 - Double(index) * 0.1), lineWidth: 2)
                                .frame(width: 120 + CGFloat(index) * 20, height: 120 + CGFloat(index) * 20)
                                .scaleEffect(scale * (1.0 + Double(index) * 0.1))
                        }
                        
                        // Heart icon with ECG line
                        HStack(spacing: 0) {
                            // Heart icon with security shield overlay
                            ZStack {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(colors.accent)
                                    .rotationEffect(.degrees(rotation))
                                
                                // Security shield indicator
                                Image(systemName: "shield.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(colors.accent.opacity(0.8))
                                    .offset(x: 20, y: -20)
                                    .opacity(opacity)
                            }
                            .offset(x: -5)
                            .zIndex(1)
                            
                            // Enhanced ECG line
                            HeartRateLine()
                                .stroke(colors.accent, lineWidth: 3)
                                .frame(width: 80, height: 40)
                                .offset(x: -15)
                        }
                        .scaleEffect(scale)
                    }
                    .opacity(opacity)
                    
                    // App name with security emphasis
                    VStack(spacing: 8) {
                        Text("HeartID")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(colors.text)
                            .opacity(opacity)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "lock.shield.fill")
                                .font(.caption)
                                .foregroundColor(colors.accent)
                            Text("Secure Biometric Authentication")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundColor(colors.secondary)
                        }
                        .opacity(opacity * 0.8)
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
                        
                        // Security status indicators
                        HStack(spacing: 16) {
                            SecurityIndicator(
                                icon: "checkmark.shield.fill",
                                text: "Encrypted",
                                isActive: true
                            )
                            
                            SecurityIndicator(
                                icon: "person.badge.shield.checkmark.fill",
                                text: "Biometric Ready",
                                isActive: biometricAuthAvailable
                            )
                            
                            SecurityIndicator(
                                icon: "network.badge.shield.half.filled",
                                text: "Secure Channel",
                                isActive: true
                            )
                        }
                        .opacity(opacity * 0.7)
                        .padding(.top, 8)
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
        // Start logo animation
        withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
            scale = 1.0
            opacity = 1.0
            rotation = 0.0
        }
        
        // Perform security and user state checks
        Task {
            await performSecurityChecks()
            
            // Simulate secure initialization time
            try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5 seconds
            
            await MainActor.run {
                loadingComplete = true
                
                // Show welcome flow with slight delay for smooth transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        showWelcomeFlow = true
                    }
                }
            }
        }
    }
    
    private func performSecurityChecks() async {
        // Check for existing enrollment data
        await checkExistingEnrollment()
        
        // Check biometric availability
        await checkBiometricAvailability()
        
        // Determine if this is likely a new user
        await determineUserStatus()
    }
    
    private func checkExistingEnrollment() async {
        // Check for existing heart pattern enrollment
        // This would integrate with your AuthenticationService
        await MainActor.run {
            // For now, assume new installation means new user
            hasExistingEnrollment = UserDefaults.standard.bool(forKey: "hasCompletedEnrollment")
        }
    }
    
    private func checkBiometricAvailability() async {
        let context = LAContext()
        var error: NSError?
        
        await MainActor.run {
            biometricAuthAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        }
    }
    
    private func determineUserStatus() async {
        await MainActor.run {
            // Check if app has been launched before
            let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
            isNewUser = !hasLaunchedBefore
            
            if !hasLaunchedBefore {
                UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            }
        }
    }
}

// MARK: - Security Indicator Component
struct SecurityIndicator: View {
    let icon: String
    let text: String
    let isActive: Bool
    
    private let colors = HeartIDColors()
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isActive ? colors.accent : colors.secondary.opacity(0.5))
            
            Text(text)
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundColor(isActive ? colors.text.opacity(0.8) : colors.secondary.opacity(0.5))
        }
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
        VStack(spacing: 40) {
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
            }
            
            // Content based on user status
            VStack(spacing: 30) {
                if isNewUser {
                    newUserContent
                } else {
                    returningUserContent
                }
            }
            
            Spacer()
            
            // Action buttons
            if showActions {
                actionButtons
            }
        }
        .padding(.top, 40)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    showActions = true
                }
            }
        }
    }
    
    private var newUserContent: some View {
        VStack(spacing: 24) {
            // Security-first messaging
            VStack(spacing: 16) {
                Image(systemName: "heart.rectangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(colors.accent)
                
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
            VStack(spacing: 12) {
                FeatureRow(
                    icon: "shield.checkerboard", 
                    title: "Military-Grade Security", 
                    description: "Your heart pattern is encrypted and never leaves your device",
                    iconColor: colors.accent,
                    backgroundColor: colors.accent.opacity(0.2),
                    titleColor: colors.text,
                    descriptionColor: colors.secondary
                )
                FeatureRow(
                    icon: "timer", 
                    title: "Instant Access", 
                    description: "Authenticate in seconds with just your heartbeat",
                    iconColor: colors.accent,
                    backgroundColor: colors.accent.opacity(0.2),
                    titleColor: colors.text,
                    descriptionColor: colors.secondary
                )
                FeatureRow(
                    icon: "person.badge.shield.checkmark", 
                    title: "Private & Secure", 
                    description: "No passwords to remember or lose",
                    iconColor: colors.accent,
                    backgroundColor: colors.accent.opacity(0.2),
                    titleColor: colors.text,
                    descriptionColor: colors.secondary
                )
            }
            .padding(.horizontal, 30)
        }
    }
    
    private var returningUserContent: some View {
        VStack(spacing: 20) {
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
        VStack(spacing: 16) {
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
        .padding(.bottom, 30)
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

struct LaunchScreen_Previews: PreviewProvider {
    static var previews: some View {
        LaunchScreen()
            .preferredColorScheme(.dark)
    }
}
