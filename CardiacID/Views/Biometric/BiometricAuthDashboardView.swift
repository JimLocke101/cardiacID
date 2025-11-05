//
//  BiometricAuthDashboardView.swift
//  CardiacID
//
//  Created for Phase 5 - iOS UI Implementation
//  Real-time biometric authentication dashboard
//

import SwiftUI

struct BiometricAuthDashboardView: View {
    @StateObject private var viewModel = BiometricAuthDashboardViewModel()
    @State private var showingEnrollment = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(hex: "1a1a2e"), Color(hex: "16213e")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if viewModel.isEnrolled {
                enrolledContent
            } else {
                notEnrolledContent
            }
        }
        .sheet(isPresented: $showingEnrollment) {
            BiometricEnrollmentView()
        }
        .task {
            await viewModel.initialize()
        }
    }

    // MARK: - Not Enrolled

    private var notEnrolledContent: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Color(hex: "e94560").opacity(0.2))
                    .frame(width: 140, height: 140)

                Image(systemName: "heart.circle")
                    .font(.system(size: 70))
                    .foregroundColor(Color(hex: "e94560"))
            }

            VStack(spacing: 16) {
                Text("HeartID Not Configured")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                Text("Enroll your cardiac biometric to get started")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            Button(action: { showingEnrollment = true }) {
                Text("Enroll Now")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 200, height: 56)
                    .background(Color(hex: "e94560"))
                    .cornerRadius(16)
            }
            .padding(.top, 16)

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Enrolled Content

    private var enrolledContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Authentication Status Card
                authStatusCard

                // Confidence Gauge
                confidenceGauge

                // Quick Stats
                quickStats

                // Monitoring Status
                monitoringStatus

                // Actions
                actionButtons
            }
            .padding(24)
        }
    }

    // MARK: - Auth Status Card

    private var authStatusCard: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Authentication Status")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))

                    Text(viewModel.authStateText)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(viewModel.authStateColor)
                }

                Spacer()

                // Status indicator
                ZStack {
                    Circle()
                        .fill(viewModel.authStateColor.opacity(0.2))
                        .frame(width: 60, height: 60)

                    Circle()
                        .fill(viewModel.authStateColor)
                        .frame(width: 20, height: 20)
                        .scaleEffect(viewModel.pulseAnimation ? 1.2 : 1.0)
                        .opacity(viewModel.pulseAnimation ? 0.5 : 1.0)
                        .animation(Animation.easeInOut(duration: 1.5).repeatForever(), value: viewModel.pulseAnimation)
                }
            }

            if viewModel.isMonitoring {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: "e94560"))

                    Text("Continuous monitoring active")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))

                    Spacer()

                    if viewModel.isWatchOnWrist {
                        Image(systemName: "applewatch")
                            .font(.system(size: 16))
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "applewatch.slash")
                            .font(.system(size: 16))
                            .foregroundColor(.red)
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
            }
        }
        .padding(24)
        .background(Color.white.opacity(0.05))
        .cornerRadius(20)
    }

    // MARK: - Confidence Gauge

    private var confidenceGauge: some View {
        VStack(spacing: 16) {
            Text("Current Confidence")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)

            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 20)
                    .frame(width: 200, height: 200)

                // Progress circle
                Circle()
                    .trim(from: 0, to: viewModel.currentConfidence)
                    .stroke(
                        viewModel.confidenceGradient,
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 1.0), value: viewModel.currentConfidence)

                // Center text
                VStack(spacing: 4) {
                    Text("\(Int(viewModel.currentConfidence * 100))%")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.white)

                    Text(viewModel.confidenceLevelText)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            // Threshold indicators
            HStack(spacing: 24) {
                ThresholdIndicator(label: "Min", value: viewModel.minimumThreshold, color: .red)
                ThresholdIndicator(label: "Conditional", value: viewModel.conditionalThreshold, color: .yellow)
                ThresholdIndicator(label: "Full", value: viewModel.fullAccessThreshold, color: .green)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .background(Color.white.opacity(0.05))
        .cornerRadius(20)
    }

    // MARK: - Quick Stats

    private var quickStats: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Stats")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatBox(
                    icon: "waveform.path.ecg",
                    title: "Last ECG",
                    value: viewModel.lastECGTime ?? "Never",
                    color: Color(hex: "e94560")
                )

                StatBox(
                    icon: "heart.fill",
                    title: "Heart Rate",
                    value: viewModel.currentHeartRate > 0 ? "\(Int(viewModel.currentHeartRate)) bpm" : "--",
                    color: Color(hex: "e94560")
                )

                StatBox(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Peak ECG",
                    value: viewModel.peakECG != nil ? "\(Int(viewModel.peakECG! * 100))%" : "--",
                    color: .green
                )

                StatBox(
                    icon: "chart.bar.fill",
                    title: "Peak PPG",
                    value: viewModel.peakPPG != nil ? "\(Int(viewModel.peakPPG! * 100))%" : "--",
                    color: .blue
                )
            }
        }
        .padding(24)
        .background(Color.white.opacity(0.05))
        .cornerRadius(20)
    }

    // MARK: - Monitoring Status

    private var monitoringStatus: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Monitoring Status")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)

            VStack(spacing: 12) {
                StatusRow(
                    icon: "applewatch",
                    label: "Watch Status",
                    value: viewModel.isWatchOnWrist ? "On Wrist" : "Not Detected",
                    isActive: viewModel.isWatchOnWrist
                )

                StatusRow(
                    icon: "waveform.path.ecg",
                    label: "PPG Monitoring",
                    value: viewModel.isMonitoring ? "Active" : "Inactive",
                    isActive: viewModel.isMonitoring
                )

                StatusRow(
                    icon: "lock.shield.fill",
                    label: "Security Level",
                    value: viewModel.securityLevelText,
                    isActive: true
                )

                StatusRow(
                    icon: "clock.fill",
                    label: "Next Check",
                    value: viewModel.nextCheckTime ?? "Calculating...",
                    isActive: viewModel.isMonitoring
                )
            }
        }
        .padding(24)
        .background(Color.white.opacity(0.05))
        .cornerRadius(20)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Manual authentication
            Button(action: { viewModel.performManualAuth() }) {
                HStack {
                    Image(systemName: "checkmark.shield.fill")
                    Text("Manual Authentication")
                    Spacer()
                    if viewModel.isAuthenticating {
                        ProgressView()
                            .tint(.white)
                    }
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color(hex: "e94560"))
                .cornerRadius(16)
            }
            .disabled(viewModel.isAuthenticating)

            // Settings
            Button(action: { /* TODO: Show settings */ }) {
                HStack {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.white.opacity(0.1))
                .cornerRadius(16)
            }
        }
    }
}

// MARK: - Supporting Views

struct ThresholdIndicator: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)

            Text("\(Int(value * 100))%")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}

struct StatBox: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))

                Text(value)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

struct StatusRow: View {
    let icon: String
    let label: String
    let value: String
    let isActive: Bool

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(isActive ? Color(hex: "e94560") : .gray)
                .frame(width: 32)

            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.7))

            Spacer()

            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isActive ? .white : .gray)
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .cornerRadius(10)
    }
}

// MARK: - ViewModel

@MainActor
class BiometricAuthDashboardViewModel: ObservableObject {
    @Published var isEnrolled = false
    @Published var currentConfidence: Double = 0.0
    @Published var isMonitoring = false
    @Published var isWatchOnWrist = false
    @Published var currentHeartRate: Double = 0.0
    @Published var lastECGTime: String? = nil
    @Published var peakECG: Double? = nil
    @Published var peakPPG: Double? = nil
    @Published var pulseAnimation = false
    @Published var isAuthenticating = false

    private let heartIDService = HeartIDService()
    private let hybridStorage = HybridTemplateStorageService()
    private var updateTimer: Timer?

    var authStateText: String {
        switch heartIDService.authenticationState {
        case .authenticated:
            return "Authenticated"
        case .conditional:
            return "Conditional"
        case .unauthenticated:
            return "Unauthenticated"
        }
    }

    var authStateColor: Color {
        switch heartIDService.authenticationState {
        case .authenticated:
            return .green
        case .conditional:
            return .yellow
        case .unauthenticated:
            return .red
        }
    }

    var confidenceLevelText: String {
        if currentConfidence >= fullAccessThreshold {
            return "Full Access"
        } else if currentConfidence >= conditionalThreshold {
            return "Conditional"
        } else {
            return "Low"
        }
    }

    var confidenceGradient: AngularGradient {
        if currentConfidence >= fullAccessThreshold {
            return AngularGradient(colors: [.green, .green.opacity(0.5)], center: .center)
        } else if currentConfidence >= conditionalThreshold {
            return AngularGradient(colors: [.yellow, .yellow.opacity(0.5)], center: .center)
        } else {
            return AngularGradient(colors: [.red, .red.opacity(0.5)], center: .center)
        }
    }

    var minimumThreshold: Double {
        return heartIDService.thresholds.minimumAccuracy
    }

    var conditionalThreshold: Double {
        return heartIDService.thresholds.conditionalAccess
    }

    var fullAccessThreshold: Double {
        return heartIDService.thresholds.fullAccess
    }

    var securityLevelText: String {
        return "Standard" // TODO: Make configurable
    }

    var nextCheckTime: String? {
        guard isMonitoring else { return nil }
        // TODO: Calculate from battery settings
        return "in 15 min"
    }

    func initialize() async {
        // Check if enrolled
        isEnrolled = hybridStorage.hasTemplate()

        if isEnrolled {
            // Initialize HeartID service
            await heartIDService.initialize()

            // Start monitoring
            updateState()
            startPeriodicUpdates()
            startPulseAnimation()
        }
    }

    private func updateState() {
        currentConfidence = heartIDService.currentConfidence
        isMonitoring = heartIDService.isMonitoring
        isWatchOnWrist = heartIDService.isWatchOnWrist
        currentHeartRate = heartIDService.currentHeartRate
        lastECGTime = heartIDService.mostRecentECGTime
        peakECG = heartIDService.peakECGInInterval
        peakPPG = heartIDService.peakPPGInInterval
    }

    private func startPeriodicUpdates() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateState()
            }
        }
    }

    private func startPulseAnimation() {
        pulseAnimation = true
    }

    func performManualAuth() {
        isAuthenticating = true

        Task {
            await heartIDService.performManualAuthentication()

            await MainActor.run {
                isAuthenticating = false
                updateState()
            }
        }
    }

    deinit {
        updateTimer?.invalidate()
    }
}

#Preview {
    BiometricAuthDashboardView()
}
