import SwiftUI
import Combine

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isLoggingIn = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isAuthenticated = false
    
    @StateObject private var authViewModel = AuthViewModel()
    private let colors = HeartIDColors()
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                colors.background
                    .ignoresSafeArea()
                
                VStack(spacing: 30) {
                    // Logo/Header
                    VStack(spacing: 16) {
                        Image(systemName: "heart.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 60, height: 60)
                            .foregroundColor(colors.accent)
                        
                        Text("HeartID")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(colors.text)
                        
                        Text("Secure your identity with your unique cardiac signature")
                            .font(.subheadline)
                            .foregroundColor(colors.text.opacity(0.7))
                            .multilineTextAlignment(.center)
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
                            
                            SecureField("", text: $password)
                                .padding()
                                .background(colors.surface)
                                .cornerRadius(12)
                                .foregroundColor(colors.text)
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
                    
                    Spacer()
                    
                    // Sign Up Option
                    HStack {
                        Text("Don't have an account?")
                            .font(.subheadline)
                            .foregroundColor(colors.text.opacity(0.7))
                        
                        Button(action: {
                            // Show sign up screen
                        }) {
                            Text("Sign Up")
                                .font(.subheadline)
                                .foregroundColor(colors.accent)
                        }
                    }
                    .padding(.bottom, 20)
                }
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
        .preferredColorScheme(.dark)
}
