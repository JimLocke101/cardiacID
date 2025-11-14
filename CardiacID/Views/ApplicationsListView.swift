//
//  ApplicationsListView.swift
//  HeartID Mobile
//
//  Enterprise applications view - displays user's EntraID applications
//  This is the implementation of the "View Applications" button in TechnologyManagementView
//

import SwiftUI

struct ApplicationsListView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ApplicationsListViewModel()

    private let colors = HeartIDColors()

    var body: some View {
        NavigationView {
            ZStack {
                colors.background
                    .ignoresSafeArea()

                if viewModel.isLoading {
                    LoadingView()
                } else if let error = viewModel.errorMessage {
                    ErrorView(message: error, onRetry: {
                        Task { await viewModel.loadApplications() }
                    })
                } else if viewModel.applications.isEmpty {
                    EmptyStateView()
                } else {
                    ApplicationsList(applications: viewModel.applications)
                }
            }
            .navigationTitle("My Applications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { Task { await viewModel.loadApplications() } }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(colors.accent)
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
        .task {
            await viewModel.loadApplications()
        }
    }
}

// MARK: - Applications List

struct ApplicationsList: View {
    let applications: [GraphApplication]
    private let colors = HeartIDColors()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(applications, id: \.id) { application in
                    ApplicationCard(application: application)
                }
            }
            .padding()
        }
    }
}

// MARK: - Application Card

struct ApplicationCard: View {
    let application: GraphApplication
    private let colors = HeartIDColors()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Application Icon & Name
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(colors.accent.opacity(0.1))
                        .frame(width: 48, height: 48)

                    Image(systemName: "app.fill")
                        .font(.title3)
                        .foregroundColor(colors.accent)
                }

                // Name & ID
                VStack(alignment: .leading, spacing: 4) {
                    Text(application.displayName ?? "Unknown Application")
                        .font(.headline)
                        .foregroundColor(colors.text)

                    if let appId = application.appId {
                        Text("App ID: \(appId.prefix(20))...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Status Badge
                StatusBadge(text: "Active", color: .green)
            }

            // Divider
            Divider()

            // Details
            VStack(alignment: .leading, spacing: 8) {
                if let audience = application.signInAudience {
                    DetailRow(
                        icon: "person.2.fill",
                        title: "Sign-in Audience",
                        value: formatAudience(audience)
                    )
                }

                DetailRow(
                    icon: "key.fill",
                    title: "Authentication",
                    value: "OAuth 2.0 / OpenID Connect"
                )

                DetailRow(
                    icon: "lock.shield.fill",
                    title: "HeartID Integration",
                    value: "Available"
                )
            }

            // Action Buttons
            HStack(spacing: 12) {
                ActionButton(
                    title: "Configure",
                    icon: "gearshape.fill",
                    color: colors.accent
                ) {
                    // TODO: Navigate to app configuration
                }

                ActionButton(
                    title: "Test Auth",
                    icon: "checkmark.shield.fill",
                    color: .green
                ) {
                    // TODO: Test authentication
                }
            }
        }
        .padding()
        .background(colors.surface)
        .cornerRadius(12)
    }

    private func formatAudience(_ audience: String) -> String {
        switch audience {
        case "AzureADMyOrg": return "Single Tenant"
        case "AzureADMultipleOrgs": return "Multi-Tenant"
        case "AzureADandPersonalMicrosoftAccount": return "Work & Personal"
        case "PersonalMicrosoftAccount": return "Personal Only"
        default: return audience
        }
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 16)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)

                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(color.opacity(0.1))
            .foregroundColor(color)
            .cornerRadius(8)
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.1))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

// MARK: - Loading View

struct LoadingView: View {
    private let colors = HeartIDColors()

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: colors.accent))
                .scaleEffect(1.5)

            Text("Loading applications...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    private let colors = HeartIDColors()

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("Error Loading Applications")
                .font(.headline)
                .foregroundColor(colors.text)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: onRetry) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .padding()
                .background(colors.accent)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding()
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    private let colors = HeartIDColors()

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "app.dashed")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Applications Found")
                .font(.headline)
                .foregroundColor(colors.text)

            Text("You don't have any enterprise applications configured yet.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: {}) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Application")
                }
                .padding()
                .background(colors.accent)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding()
    }
}

// MARK: - View Model

@MainActor
class ApplicationsListViewModel: ObservableObject {
    @Published var applications: [GraphApplication] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let authClient = EntraIDAuthClient.shared

    func loadApplications() async {
        isLoading = true
        errorMessage = nil

        do {
            // Ensure we're authenticated
            if !authClient.isAuthenticated {
                // Try to sign in silently
                let _ = try await authClient.signInSilently()
            }

            // Get access token
            let accessToken = try await authClient.getAccessToken()

            // Create Graph API client
            let graphClient = MicrosoftGraphClient(accessToken: accessToken)

            // Fetch user's applications
            let apps = try await graphClient.getUserApplications()

            await MainActor.run {
                self.applications = apps
                self.isLoading = false
            }

            print("✅ Loaded \(apps.count) applications")

        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }

            print("❌ Failed to load applications: \(error)")
        }
    }
}

// MARK: - Preview

#Preview {
    ApplicationsListView()
        .preferredColorScheme(.dark)
}
