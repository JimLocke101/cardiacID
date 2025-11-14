//
//  MenuView.swift
//  CardiacID
//
//  Hamburger menu for navigation across the app
//

import SwiftUI

// MARK: - Main Menu View

struct MenuView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var authManager: AuthenticationManager

    @Binding var isPresented: Bool

    private let colors = HeartIDColors()

    var body: some View {
        NavigationView {
            ZStack {
                colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // Header with user info
                        MenuHeaderView()
                            .padding(.bottom, 20)

                        Divider()
                            .background(colors.secondary.opacity(0.3))

                        // Menu Items
                        VStack(spacing: 0) {
                            MenuItemButton(
                                icon: "person.circle.fill",
                                title: "Profile",
                                destination: AnyView(
                                    ProfileView()
                                        .environmentObject(authViewModel)
                                )
                            )

                            MenuItemButton(
                                icon: "square.and.pencil",
                                title: "Edit Registration",
                                destination: AnyView(RegistrationEditView())
                            )

                            MenuItemButton(
                                icon: "heart.text.square.fill",
                                title: "Status",
                                destination: AnyView(
                                    StatusView()
                                        .environmentObject(authManager)
                                )
                            )

                            Divider()
                                .background(colors.secondary.opacity(0.3))
                                .padding(.vertical, 10)

                            // Security Levels Section
                            Text("Security Levels")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(colors.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)

                            MenuItemButton(
                                icon: "lock.shield.fill",
                                title: "Security Settings",
                                destination: AnyView(SecuritySettingsView())
                            )

                            MenuItemButton(
                                icon: "key.fill",
                                title: "Passwordless Auth",
                                destination: AnyView(PasswordlessAuthView())
                            )

                            MenuItemButton(
                                icon: "person.badge.key.fill",
                                title: "Biometric Settings",
                                destination: AnyView(BiometricSettingsView())
                            )

                            Divider()
                                .background(colors.secondary.opacity(0.3))
                                .padding(.vertical, 10)

                            // Danger Zone
                            MenuItemButton(
                                icon: "trash.fill",
                                title: "Delete Account",
                                destination: AnyView(DeleteAccountView()),
                                isDestructive: true
                            )

                            // Exit Button
                            Button(action: {
                                handleExit()
                            }) {
                                HStack(spacing: 16) {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .font(.title3)
                                        .foregroundColor(colors.warning)
                                        .frame(width: 24)

                                    Text("Exit")
                                        .font(.body)
                                        .foregroundColor(colors.warning)

                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .background(colors.surface.opacity(0.5))
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(colors.secondary)
                    }
                }
            }
        }
    }

    private func handleExit() {
        // Sign out and close menu
        authViewModel.signOut()
        isPresented = false
    }
}

// MARK: - Menu Header View

struct MenuHeaderView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var authManager: AuthenticationManager

    private let colors = HeartIDColors()

    var body: some View {
        VStack(spacing: 12) {
            // User avatar
            ZStack {
                Circle()
                    .fill(colors.accent.opacity(0.2))
                    .frame(width: 80, height: 80)

                Image(systemName: "person.fill")
                    .font(.system(size: 40))
                    .foregroundColor(colors.accent)
            }

            // User name
            if let userName = authViewModel.currentUser?.displayName {
                Text(userName)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(colors.text)
            } else {
                Text("HeartID User")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(colors.text)
            }

            // User email
            if let userEmail = authViewModel.currentUser?.email {
                Text(userEmail)
                    .font(.caption)
                    .foregroundColor(colors.secondary)
            }

            // Authentication status badge
            HStack(spacing: 6) {
                Circle()
                    .fill(authManager.isEnrolled ? colors.success : colors.warning)
                    .frame(width: 8, height: 8)

                Text(authManager.isEnrolled ? "Enrolled" : "Not Enrolled")
                    .font(.caption)
                    .foregroundColor(colors.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(colors.surface.opacity(0.5))
            .cornerRadius(12)
        }
        .padding()
    }
}

// MARK: - Menu Item Button

struct MenuItemButton: View {
    let icon: String
    let title: String
    let destination: AnyView
    var isDestructive: Bool = false

    @State private var isNavigating = false
    private let colors = HeartIDColors()

    var body: some View {
        NavigationLink(destination: destination, isActive: $isNavigating) {
            Button(action: { isNavigating = true }) {
                HStack(spacing: 16) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(isDestructive ? colors.error : colors.accent)
                        .frame(width: 24)

                    Text(title)
                        .font(.body)
                        .foregroundColor(isDestructive ? colors.error : colors.text)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(colors.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(colors.surface.opacity(0.3))
            }
        }
    }
}

// MARK: - Hamburger Menu Button

struct HamburgerMenuButton: View {
    @Binding var showMenu: Bool
    private let colors = HeartIDColors()

    var body: some View {
        Button(action: { showMenu = true }) {
            Image(systemName: "line.3.horizontal")
                .font(.title3)
                .foregroundColor(colors.accent)
        }
    }
}

// MARK: - Placeholder Views (using existing implementations)

struct RegistrationEditView: View {
    private let colors = HeartIDColors()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Edit your registration details here")
                    .font(.body)
                    .foregroundColor(colors.secondary)
                    .padding()

                // Add registration edit form fields here
            }
            .padding()
        }
        .background(colors.background)
        .navigationTitle("Edit Registration")
    }
}

struct StatusView: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    private let colors = HeartIDColors()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // System Status Card
                VStack(alignment: .leading, spacing: 12) {
                    Text("System Status")
                        .font(.headline)
                        .foregroundColor(colors.text)

                    MenuStatusRow(label: "HeartID Service", status: .active)
                    MenuStatusRow(label: "Enrollment", status: authManager.isEnrolled ? .active : .inactive)
                    MenuStatusRow(label: "Authentication", status: authManager.authState == .authenticated ? .active : .inactive)
                    MenuStatusRow(label: "Auth State", status: authManager.authState == .idle ? .inactive : .active)
                }
                .padding()
                .background(colors.surface)
                .cornerRadius(12)
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(colors.background)
        .navigationTitle("Status")
    }
}

struct MenuStatusRow: View {
    let label: String
    let status: StatusType
    private let colors = HeartIDColors()

    enum StatusType {
        case active, inactive, warning

        var color: Color {
            switch self {
            case .active: return HeartIDColors().success
            case .inactive: return HeartIDColors().secondary
            case .warning: return HeartIDColors().warning
            }
        }

        var icon: String {
            switch self {
            case .active: return "checkmark.circle.fill"
            case .inactive: return "circle"
            case .warning: return "exclamationmark.triangle.fill"
            }
        }
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundColor(colors.text)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: status.icon)
                    .font(.caption)
                    .foregroundColor(status.color)
                Text(status == .active ? "Active" : "Inactive")
                    .font(.caption)
                    .foregroundColor(status.color)
            }
        }
    }
}

struct BiometricSettingsView: View {
    private let colors = HeartIDColors()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Configure biometric authentication settings")
                    .font(.body)
                    .foregroundColor(colors.secondary)
                    .padding()

                // Add biometric settings here
            }
            .padding()
        }
        .background(colors.background)
        .navigationTitle("Biometric Settings")
    }
}

struct DeleteAccountView: View {
    @State private var confirmationText = ""
    @State private var showingConfirmation = false
    private let colors = HeartIDColors()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Warning icon
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(colors.error)

                Text("Delete Account")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(colors.text)

                Text("This action cannot be undone. All your data, including heart patterns and authentication history, will be permanently deleted.")
                    .font(.body)
                    .foregroundColor(colors.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Confirmation input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Type 'DELETE' to confirm:")
                        .font(.caption)
                        .foregroundColor(colors.secondary)

                    TextField("DELETE", text: $confirmationText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.allCharacters)
                }
                .padding(.horizontal)

                // Delete button
                Button(action: {
                    showingConfirmation = true
                }) {
                    Text("Delete My Account")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(confirmationText == "DELETE" ? colors.error : colors.secondary.opacity(0.5))
                        .cornerRadius(12)
                }
                .disabled(confirmationText != "DELETE")
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(colors.background)
        .navigationTitle("Delete Account")
        .alert("Confirm Account Deletion", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                // Handle account deletion
                print("Account deletion requested")
            }
        } message: {
            Text("Are you absolutely sure? This action cannot be undone.")
        }
    }
}

// MARK: - Preview

#Preview {
    MenuView(isPresented: .constant(true))
        .environmentObject(AuthViewModel())
        .environmentObject(AuthenticationManager())
}
