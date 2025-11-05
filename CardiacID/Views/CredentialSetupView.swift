//
//  CredentialSetupView.swift
//  HeartID Mobile
//
//  First-time credential configuration screen
//  SECURITY: Only shown on first launch - credentials stored in Keychain
//

import SwiftUI

struct CredentialSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CredentialSetupViewModel()

    private let colors = HeartIDColors()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 30) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "lock.shield.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .foregroundColor(colors.accent)

                        Text("Secure Configuration")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(colors.text)

                        Text("Configure your API credentials securely. These will be encrypted and stored in your device's Keychain.")
                            .font(.subheadline)
                            .foregroundColor(colors.text.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 40)

                    // Configuration Sections
                    VStack(spacing: 24) {
                        // Supabase Configuration
                        ConfigurationSection(
                            title: "Supabase Configuration",
                            icon: "server.rack",
                            iconColor: .green
                        ) {
                            VStack(spacing: 16) {
                                SecureTextField(
                                    title: "API Key",
                                    placeholder: "eyJhbGci...",
                                    text: $viewModel.supabaseAPIKey,
                                    isSecure: true
                                )

                                InfoBox(
                                    message: "Find this in your Supabase project settings under API → anon/public key",
                                    type: .info
                                )
                            }
                        }

                        // EntraID Configuration
                        ConfigurationSection(
                            title: "Microsoft EntraID (Optional)",
                            icon: "building.2",
                            iconColor: .blue
                        ) {
                            VStack(spacing: 16) {
                                SecureTextField(
                                    title: "Tenant ID",
                                    placeholder: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
                                    text: $viewModel.entraIDTenantID,
                                    isSecure: false
                                )

                                SecureTextField(
                                    title: "Client ID",
                                    placeholder: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
                                    text: $viewModel.entraIDClientID,
                                    isSecure: false
                                )

                                InfoBox(
                                    message: "Find these in Azure Portal → App Registrations → Your App",
                                    type: .info
                                )
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Save Button
                    Button(action: { viewModel.saveCredentials() }) {
                        HStack {
                            if viewModel.isSaving {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Save & Continue")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(viewModel.isValid ? colors.accent : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!viewModel.isValid || viewModel.isSaving)
                    .padding(.horizontal)

                    // Skip Button (for development only)
                    #if DEBUG
                    Button(action: { dismiss() }) {
                        Text("Skip (Development Only)")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 20)
                    #endif
                }
            }
            .background(colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .alert("Setup Complete", isPresented: $viewModel.showingSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Credentials have been securely saved to your Keychain.")
            }
            .alert("Setup Error", isPresented: $viewModel.showingError) {
                Button("OK") { }
            } message: {
                Text(viewModel.errorMessage)
            }
        }
        .interactiveDismissDisabled()
    }
}

// MARK: - Configuration Section

struct ConfigurationSection<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: Content

    private let colors = HeartIDColors()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(iconColor)

                Text(title)
                    .font(.headline)
                    .foregroundColor(colors.text)
            }

            // Section Content
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding()
            .background(colors.surface)
            .cornerRadius(12)
        }
    }
}

// MARK: - Secure Text Field

struct SecureTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let isSecure: Bool

    @State private var isVisible = false
    private let colors = HeartIDColors()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(colors.text)

            HStack {
                if isSecure && !isVisible {
                    SecureField(placeholder, text: $text)
                        .textFieldStyle(PlainTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                } else {
                    TextField(placeholder, text: $text)
                        .textFieldStyle(PlainTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                if isSecure {
                    Button(action: { isVisible.toggle() }) {
                        Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

// MARK: - Info Box

struct InfoBox: View {
    let message: String
    let type: InfoType

    enum InfoType {
        case info, warning, error

        var color: Color {
            switch self {
            case .info: return .blue
            case .warning: return .orange
            case .error: return .red
            }
        }

        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: type.icon)
                .foregroundColor(type.color)
                .font(.caption)

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(type.color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - View Model

class CredentialSetupViewModel: ObservableObject {
    @Published var supabaseAPIKey = ""
    @Published var entraIDTenantID = ""
    @Published var entraIDClientID = ""

    @Published var isSaving = false
    @Published var showingSuccess = false
    @Published var showingError = false
    @Published var errorMessage = ""

    private let credentialManager = SecureCredentialManager.shared

    var isValid: Bool {
        // At minimum, Supabase API key is required
        return !supabaseAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func saveCredentials() {
        guard isValid else { return }

        isSaving = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                // Save Supabase credentials
                try self.credentialManager.store(
                    self.supabaseAPIKey.trimmingCharacters(in: .whitespacesAndNewlines),
                    forKey: .supabaseAPIKey,
                    securityLevel: .biometricRequired
                )

                // Save EntraID credentials if provided
                if !self.entraIDTenantID.isEmpty {
                    try self.credentialManager.store(
                        self.entraIDTenantID.trimmingCharacters(in: .whitespacesAndNewlines),
                        forKey: .entraIDTenantID,
                        securityLevel: .standard
                    )
                }

                if !self.entraIDClientID.isEmpty {
                    try self.credentialManager.store(
                        self.entraIDClientID.trimmingCharacters(in: .whitespacesAndNewlines),
                        forKey: .entraIDClientID,
                        securityLevel: .standard
                    )
                }

                // Success
                DispatchQueue.main.async {
                    self.isSaving = false
                    self.showingSuccess = true
                    print("✅ Credentials saved successfully to Keychain")
                }

            } catch {
                // Error
                DispatchQueue.main.async {
                    self.isSaving = false
                    self.errorMessage = error.localizedDescription
                    self.showingError = true
                    print("❌ Failed to save credentials: \(error)")
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    CredentialSetupView()
        .preferredColorScheme(.dark)
}
