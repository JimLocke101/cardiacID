import SwiftUI
import Combine

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isLoggingIn = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isAuthenticated = false
    @State private var showingSignUp = false
    @State private var showPassword = false

    @EnvironmentObject private var authViewModel: AuthViewModel
    private let colors = HeartIDColors()
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                colors.background
                    .ignoresSafeArea()
                
                VStack(spacing: 30) {
                    // Logo/Header with Apple Watch integration message
                    VStack(spacing: 16) {
                        // Heart and Watch icon combination
                        ZStack {
                            Image(systemName: "heart.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 60, height: 60)
                                .foregroundColor(colors.accent)
                            
                            Image(systemName: "applewatch")
                                .font(.system(size: 20))
                                .foregroundColor(colors.accent)
                                .offset(x: 25, y: -25)
                                .background(
                                    Circle()
                                        .fill(colors.background)
                                        .frame(width: 30, height: 30)
                                )
                        }
                        
                        Text("HeartID")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(colors.text)
                        
                        VStack(spacing: 8) {
                            Text("Secure your identity with your unique cardiac signature")
                                .font(.subheadline)
                                .foregroundColor(colors.text.opacity(0.7))
                                .multilineTextAlignment(.center)
                            
                            // Apple Watch connection status
                            HStack(spacing: 6) {
                                Image(systemName: "applewatch.watchface")
                                    .font(.caption)
                                    .foregroundColor(colors.accent)
                                Text("Requires paired Apple Watch with ECG")
                                    .font(.caption)
                                    .foregroundColor(colors.secondary)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.top, 30)
                    
                    // Form Fields
                    VStack(spacing: 20) {
                        // Email field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.subheadline)
                                .foregroundColor(colors.text.opacity(0.8))
                            
                            TextField("", text: $email)
                                .padding()
                                .background(colors.surface)
                                .cornerRadius(12)
                                .foregroundColor(colors.text)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        
                        // Password field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.subheadline)
                                .foregroundColor(colors.text.opacity(0.8))

                            HStack {
                                if showPassword {
                                    TextField("", text: $password)
                                        .foregroundColor(colors.text)
                                } else {
                                    SecureField("", text: $password)
                                        .foregroundColor(colors.text)
                                }

                                Button(action: {
                                    showPassword.toggle()
                                }) {
                                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                        .foregroundColor(colors.text.opacity(0.6))
                                }
                            }
                            .padding()
                            .background(colors.surface)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 30)
                    
                    // Login Button
                    Button(action: login) {
                        if isLoggingIn {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: colors.text))
                                .scaleEffect(1.0)
                        } else {
                            Text("Sign In")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(colors.accent)
                    .cornerRadius(12)
                    .padding(.horizontal, 30)
                    .disabled(isLoggingIn)
                    
                    // Demo Mode Button
                    Button(action: enterDemoMode) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.circle.fill")
                            Text("Try Demo")
                                .fontWeight(.medium)
                        }
                        .font(.subheadline)
                        .foregroundColor(colors.accent)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(colors.accent.opacity(0.12))
                        .cornerRadius(10)
                    }
                    .padding(.horizontal, 30)

                    Spacer()

                    // Sign Up Option
                    HStack {
                        Text("Don't have an account?")
                            .font(.subheadline)
                            .foregroundColor(colors.text.opacity(0.7))

                        Button(action: {
                            authViewModel.setInitialFlow(.signUp)
                            showingSignUp = true
                        }) {
                            Text("Sign Up")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(colors.accent)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
            .sheet(isPresented: $showingSignUp) {
                SignUpView()
                    .environmentObject(authViewModel)
            }
            .alert(isPresented: $showError) {
                Alert(
                    title: Text("Login Failed"),
                    message: Text(errorMessage ?? "An unknown error occurred"),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onChange(of: isAuthenticated) { isAuthenticated in
                if isAuthenticated {
                    // Authentication successful - the parent view will handle navigation
                    print("✅ Login successful - user authenticated")
                }
            }
        }
        .onReceive(authViewModel.$isAuthenticated) { isAuthenticated in
            self.isAuthenticated = isAuthenticated
        }
        .onReceive(authViewModel.$authError) { error in
            if let error = error {
                errorMessage = error
                showError = true
            }
        }
        .onReceive(authViewModel.$isLoading) { isLoading in
            isLoggingIn = isLoading
        }
    }
    
    private func enterDemoMode() {
        authViewModel.signInDemo()
    }

    private func login() {
        print("🔐 LoginView: Login button tapped")
        print("🔐 LoginView: Email: \(email), Password: \(password.isEmpty ? "empty" : "filled")")
        
        guard !email.isEmpty && !password.isEmpty else {
            print("❌ LoginView: Empty credentials")
            errorMessage = "Please enter both email and password"
            showError = true
            return
        }
        
        print("✅ LoginView: Starting authentication process")
        isLoggingIn = true
        
        authViewModel.signIn(email: email, password: password)
    }
}


// MARK: - Preview
#Preview {
    LoginView()
        .environmentObject(AuthViewModel())
        .preferredColorScheme(.dark)
}
