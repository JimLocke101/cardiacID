//
//  SignUpView.swift
//  CardiacID
//
//  Secure user registration flow with validation
//

import SwiftUI
import Combine

struct SignUpView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authViewModel: AuthViewModel
    
    // Navigation control - to properly switch between SignUp and Login
    @State private var showingLogin = false

    // Form fields
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    // UI state
    @State private var isRegistering = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var acceptedTerms = false
    @State private var showPasswordRequirements = false
    @State private var passwordStrength: PasswordStrength = .weak

    private let colors = HeartIDColors()

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 30) {
                        // Header with Apple Watch requirement
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(colors.accent.opacity(0.2))
                                    .frame(width: 80, height: 80)

                                HStack(spacing: -8) {
                                    Image(systemName: "person.badge.plus.fill")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 32, height: 32)
                                        .foregroundColor(colors.accent)
                                    
                                    Image(systemName: "applewatch")
                                        .font(.system(size: 28))
                                        .foregroundColor(colors.accent)
                                }
                            }

                            Text("Create Your HeartID")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(colors.text)

                            VStack(spacing: 8) {
                                Text("Join the future of secure authentication")
                                    .font(.subheadline)
                                    .foregroundColor(colors.secondary)
                                    .multilineTextAlignment(.center)
                                
                                // Apple Watch requirement notice
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                    Text("Apple Watch with ECG required for enrollment")
                                        .font(.caption)
                                        .foregroundColor(colors.secondary)
                                        .fontWeight(.medium)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(colors.surface.opacity(0.5))
                                .cornerRadius(12)
                            }
                        }
                        .padding(.top, 20)

                        // Form Fields
                        VStack(spacing: 20) {
                            // Name fields
                            HStack(spacing: 12) {
                                FormField(
                                    title: "First Name",
                                    placeholder: "John",
                                    text: $firstName,
                                    icon: "person.fill"
                                )

                                FormField(
                                    title: "Last Name",
                                    placeholder: "Doe",
                                    text: $lastName,
                                    icon: "person.fill"
                                )
                            }

                            // Email field
                            FormField(
                                title: "Email Address",
                                placeholder: "john.doe@example.com",
                                text: $email,
                                icon: "envelope.fill",
                                keyboardType: .emailAddress,
                                autocapitalization: .never
                            )

                            // Password field with strength indicator
                            VStack(alignment: .leading, spacing: 8) {
                                FormField(
                                    title: "Password",
                                    placeholder: "Create a strong password",
                                    text: $password,
                                    icon: "lock.fill",
                                    isSecure: true
                                )
                                .onChange(of: password) { newValue in
                                    passwordStrength = calculatePasswordStrength(newValue)
                                }

                                // Password strength indicator
                                if !password.isEmpty {
                                    PasswordStrengthView(strength: passwordStrength)
                                }

                                // Password requirements
                                Button(action: {
                                    withAnimation {
                                        showPasswordRequirements.toggle()
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: showPasswordRequirements ? "chevron.down" : "chevron.right")
                                            .font(.caption)
                                        Text("Password Requirements")
                                            .font(.caption)
                                    }
                                    .foregroundColor(colors.secondary)
                                }

                                if showPasswordRequirements {
                                    PasswordRequirementsView(password: password)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }

                            // Confirm password field
                            FormField(
                                title: "Confirm Password",
                                placeholder: "Re-enter your password",
                                text: $confirmPassword,
                                icon: "lock.shield.fill",
                                isSecure: true
                            )

                            // Password match indicator
                            if !confirmPassword.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: passwordsMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(passwordsMatch ? colors.success : colors.error)
                                    Text(passwordsMatch ? "Passwords match" : "Passwords don't match")
                                        .font(.caption)
                                        .foregroundColor(passwordsMatch ? colors.success : colors.error)
                                }
                            }
                        }
                        .padding(.horizontal, 30)

                        // Terms acceptance
                        VStack(spacing: 16) {
                            Toggle(isOn: $acceptedTerms) {
                                HStack(spacing: 4) {
                                    Text("I accept the")
                                        .font(.caption)
                                        .foregroundColor(colors.text.opacity(0.8))
                                    Button(action: {
                                        // Show terms
                                    }) {
                                        Text("Terms & Conditions")
                                            .font(.caption)
                                            .foregroundColor(colors.accent)
                                            .underline()
                                    }
                                    Text("and")
                                        .font(.caption)
                                        .foregroundColor(colors.text.opacity(0.8))
                                    Button(action: {
                                        // Show privacy policy
                                    }) {
                                        Text("Privacy Policy")
                                            .font(.caption)
                                            .foregroundColor(colors.accent)
                                            .underline()
                                    }
                                }
                            }
                            .tint(colors.accent)
                            .padding(.horizontal, 30)

                            // Security notice with Apple Watch info
                            VStack(spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "shield.checkered")
                                        .font(.caption)
                                        .foregroundColor(colors.accent)

                                    Text("Your data is encrypted end-to-end and stored securely")
                                        .font(.caption)
                                        .foregroundColor(colors.secondary)
                                }
                                
                                // Apple Watch setup info
                                VStack(spacing: 8) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "applewatch.radiowaves.left.and.right")
                                            .font(.caption)
                                            .foregroundColor(colors.accent)
                                        Text("Next: Cardiac Enrollment with Apple Watch")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(colors.text)
                                    }
                                    
                                    Text("After registration, you'll use your Apple Watch's ECG sensor to create your unique cardiac signature. This takes about 2 minutes.")
                                        .font(.caption2)
                                        .foregroundColor(colors.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 8)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(colors.accent.opacity(0.1))
                                .cornerRadius(8)
                            }
                            .padding(.horizontal, 30)
                        }

                        // Sign up button
                        Button(action: signUp) {
                            if isRegistering {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.0)
                            } else {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.shield.fill")
                                        .font(.system(size: 18))
                                    Text("Create My HeartID")
                                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                                }
                                .foregroundColor(.white)
                            }
                        }
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
                        .padding(.horizontal, 30)
                        .disabled(!isFormValid || isRegistering)
                        .opacity(isFormValid ? 1.0 : 0.5)

                        // Already have account - Fixed navigation
                        HStack {
                            Text("Already have an account?")
                                .font(.subheadline)
                                .foregroundColor(colors.secondary)

                            Button(action: { 
                                // Set the auth flow to sign in and dismiss this view
                                authViewModel.setInitialFlow(.signIn)
                                dismiss() 
                            }) {
                                Text("Sign In")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(colors.accent)
                            }
                        }
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { 
                        // Fixed: Go back to Login screen instead of just dismissing
                        authViewModel.setInitialFlow(.signIn)
                        dismiss() 
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(colors.secondary)
                    }
                }
            }
            .alert("Registration Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
        .onReceive(authViewModel.$authError) { error in
            if let error = error {
                errorMessage = error
                showError = true
            }
        }
        .onReceive(authViewModel.$isLoading) { loading in
            isRegistering = loading
        }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        !firstName.isEmpty &&
        !lastName.isEmpty &&
        isValidEmail(email) &&
        passwordStrength != .weak &&
        passwordsMatch &&
        acceptedTerms
    }

    private var passwordsMatch: Bool {
        password == confirmPassword && !password.isEmpty
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }

    private func calculatePasswordStrength(_ password: String) -> PasswordStrength {
        var strength = 0

        if password.count >= 8 { strength += 1 }
        if password.count >= 12 { strength += 1 }
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil { strength += 1 }
        if password.rangeOfCharacter(from: .lowercaseLetters) != nil { strength += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { strength += 1 }
        if password.rangeOfCharacter(from: CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;:,.<>?")) != nil { strength += 1 }

        switch strength {
        case 0...2: return .weak
        case 3...4: return .medium
        case 5...6: return .strong
        default: return .weak
        }
    }

    private func signUp() {
        guard isFormValid else { return }

        let fullName = "\(firstName) \(lastName)"
        authViewModel.register(name: fullName, email: email, password: password)
    }
}

// MARK: - Form Field Component

struct FormField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let icon: String
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .words
    var isSecure: Bool = false

    private let colors = HeartIDColors()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(colors.text.opacity(0.8))

            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(colors.accent)
                    .frame(width: 20)

                if isSecure {
                    SecureField(placeholder, text: $text)
                        .foregroundColor(colors.text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .textInputAutocapitalization(autocapitalization)
                        .autocorrectionDisabled()
                        .foregroundColor(colors.text)
                }
            }
            .padding()
            .background(colors.surface)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(colors.secondary.opacity(0.2), lineWidth: 1)
            )
        }
    }
}

// MARK: - Password Strength

enum PasswordStrength {
    case weak, medium, strong

    var color: Color {
        switch self {
        case .weak: return .red
        case .medium: return .orange
        case .strong: return .green
        }
    }

    var text: String {
        switch self {
        case .weak: return "Weak"
        case .medium: return "Medium"
        case .strong: return "Strong"
        }
    }
}

struct PasswordStrengthView: View {
    let strength: PasswordStrength
    private let colors = HeartIDColors()

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Rectangle()
                    .fill(barColor(for: index))
                    .frame(height: 4)
                    .cornerRadius(2)
            }

            Text(strength.text)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(strength.color)
        }
    }

    private func barColor(for index: Int) -> Color {
        switch strength {
        case .weak:
            return index == 0 ? strength.color : colors.secondary.opacity(0.2)
        case .medium:
            return index <= 1 ? strength.color : colors.secondary.opacity(0.2)
        case .strong:
            return strength.color
        }
    }
}

struct PasswordRequirementsView: View {
    let password: String
    private let colors = HeartIDColors()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RequirementRow(
                text: "At least 8 characters",
                isMet: password.count >= 8
            )
            RequirementRow(
                text: "Contains uppercase letter",
                isMet: password.rangeOfCharacter(from: .uppercaseLetters) != nil
            )
            RequirementRow(
                text: "Contains lowercase letter",
                isMet: password.rangeOfCharacter(from: .lowercaseLetters) != nil
            )
            RequirementRow(
                text: "Contains number",
                isMet: password.rangeOfCharacter(from: .decimalDigits) != nil
            )
            RequirementRow(
                text: "Contains special character",
                isMet: password.rangeOfCharacter(from: CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;:,.<>?")) != nil
            )
        }
        .padding(12)
        .background(colors.surface.opacity(0.5))
        .cornerRadius(8)
    }
}

struct RequirementRow: View {
    let text: String
    let isMet: Bool
    private let colors = HeartIDColors()

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundColor(isMet ? colors.success : colors.secondary.opacity(0.5))

            Text(text)
                .font(.caption)
                .foregroundColor(isMet ? colors.text : colors.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    SignUpView()
        .environmentObject(AuthViewModel())
        .preferredColorScheme(.dark)
}
