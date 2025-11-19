import SwiftUI

struct MenuView: View {
    @ObservedObject var heartIDService: HeartIDService
    @State private var showingEnroll = false
    @State private var showingAuthenticate = false
    @State private var showingSystemStatus = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.red)

                        Text("CardiacID")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Menu")
                            .font(.system(size: 12))
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)

                        // Enrollment Status Badge
                        enrollmentStatusBadge
                    }
                    .padding(.bottom, 20)

                    // Main Menu Buttons
                    VStack(spacing: 12) {
                        // Enroll Button
                        NavigationLink(destination: EnrollView(heartIDService: heartIDService)) {
                            MenuButton(
                                icon: "person.badge.plus",
                                title: "Enroll",
                                subtitle: "3-ECG Template Creation",
                                color: .blue
                            )
                        }
                        .disabled(heartIDService.enrollmentState == .enrolled)

                        // Authenticate Button
                        NavigationLink(destination: AuthenticateView(heartIDService: heartIDService)) {
                            MenuButton(
                                icon: "checkmark.shield",
                                title: "Authenticate",
                                subtitle: "96-99% ECG Priority",
                                color: .green
                            )
                        }
                        .disabled(heartIDService.enrollmentState != .enrolled)

                        // System Status Button
                        NavigationLink(destination: SystemStatusView(heartIDService: heartIDService)) {
                            MenuButton(
                                icon: "chart.bar.doc.horizontal",
                                title: "System Status",
                                subtitle: "Real-time Monitoring",
                                color: .orange
                            )
                        }

                        // Settings Button
                        NavigationLink(destination: SettingsView(heartIDService: heartIDService)) {
                            MenuButton(
                                icon: "gearshape",
                                title: "Settings",
                                subtitle: "Thresholds & Configuration",
                                color: .gray
                            )
                        }
                    }
                    .padding(.horizontal)

                    // Quick Stats (if enrolled)
                    if heartIDService.enrollmentState == .enrolled {
                        quickStatsSection
                    }
                }
                .padding()
            }
            .navigationTitle("CardiacID")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            // Initialize HeartIDService on app launch
            await heartIDService.initialize()
        }
    }

    // MARK: - Components

    private var enrollmentStatusBadge: some View {
        Group {
            switch heartIDService.enrollmentState {
            case .enrolled:
                Text("Enrolled")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(8)
            case .enrolling:
                Text("Enrolling...")
                    .font(.caption)
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.yellow.opacity(0.2))
                    .cornerRadius(8)
            case .notEnrolled:
                Text("Not Enrolled")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(8)
            }
        }
    }

    private var quickStatsSection: some View {
        VStack(spacing: 12) {
            Text("Quick Stats")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                StatCard(
                    icon: "heart.fill",
                    value: "\(Int(heartIDService.currentConfidence * 100))%",
                    label: "Confidence",
                    color: confidenceColor
                )

                StatCard(
                    icon: "waveform.path.ecg",
                    value: heartIDService.isMonitoring ? "Active" : "Inactive",
                    label: "Monitoring",
                    color: heartIDService.isMonitoring ? .green : .gray
                )
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private var confidenceColor: Color {
        if heartIDService.currentConfidence >= heartIDService.thresholds.fullAccess {
            return .green
        } else if heartIDService.currentConfidence >= heartIDService.thresholds.conditionalAccess {
            return .yellow
        } else {
            return .red
        }
    }
}

// MARK: - Menu Button Component

struct MenuButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Stat Card Component

struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)

            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(color)

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(10)
    }
}

#Preview {
    MenuView(heartIDService: HeartIDService())
}
