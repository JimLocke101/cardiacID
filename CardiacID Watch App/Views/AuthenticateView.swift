//
//  AuthenticateView.swift
//  CardiacID Watch App
//
//  Ported from HeartID_0_7 - Enterprise-Ready Authentication Dashboard
//  Created by HeartID Team on 10/27/25.
//  Real-time authentication status dashboard with ECG priority
//

import SwiftUI
import WatchKit

/// Real-time authentication dashboard with ECG priority, continuous PPG monitoring, and step-up authentication
/// Displays confidence circle, monitoring status, quick actions, and manual authentication
struct AuthenticateView: View {
    @ObservedObject var heartIDService: HeartIDService
    @State private var showingSettings = false
    @State private var showingStepUp = false
    @State private var stepUpAction: AuthenticationAction?
    @State private var previousConfidence: Double = 0.0
    @State private var isHeartThrobbing = false
    @State private var isAuthenticating = false
    @State private var authenticateButtonColor: Color = .blue
    @State private var isSearchingForPhone = false
    @State private var searchCountdown: Int = 60
    @State private var searchTimer: Timer?
    @State private var isPulsating = false
    @State private var isMuted = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Confidence Circle
                    confidenceCircle

                    // Authentication Status
                    authenticationStatusCard

                    // Monitoring Status
                    monitoringStatusCard

                    // Quick Actions
                    quickActionsSection

                    // Integration Mode
                    integrationModeCard

                    // Manual Authentication Button
                    authenticateButton
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .navigationTitle("CardiacID")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(heartIDService: heartIDService)
            }
            .sheet(isPresented: $showingStepUp) {
                if let action = stepUpAction {
                    StepUpAuthView(heartIDService: heartIDService, action: action)
                }
            }
        }
    }

    // MARK: - Components

    private var confidenceCircle: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                    .frame(width: 100, height: 100)

                Circle()
                    .trim(from: 0, to: heartIDService.currentConfidence)
                    .stroke(confidenceColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: heartIDService.currentConfidence)

                VStack(spacing: 2) {
                    Text(confidenceDisplayText)
                        .font(.system(size: confidenceDisplayFontSize, weight: .bold, design: .rounded))
                        .foregroundColor(confidenceColor)
                        .multilineTextAlignment(.center)

                    if heartIDService.currentConfidence >= 0.75 && heartIDService.authenticationState != .unauthenticated {
                        Text("Confidence")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Text(authStatusText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(confidenceColor)
        }
    }

    private var authenticationStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Status", systemImage: "checkmark.shield.fill")
                    .font(.headline)
                    .foregroundColor(confidenceColor)

                Spacer()

                // Throbbing heart indicator with trend arrow
                if heartIDService.isMonitoring {
                    throbbingHeartIndicator
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(authStatusDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Method: \(heartIDService.isMonitoring ? "PPG Continuous" : "Inactive")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: authStatusIcon)
                    .font(.title2)
                    .foregroundColor(confidenceColor)
            }

            // Reauthenticate button when below threshold
            if heartIDService.authenticationState == .unauthenticated {
                Button {
                    reauthenticate()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Reauthenticate")
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }

    private var monitoringStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Monitoring", systemImage: "waveform.path.ecg")
                .font(.headline)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(heartIDService.isMonitoring ? "Active" : "Inactive")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(heartIDService.isMonitoring ? .green : .orange)

                    if heartIDService.isMonitoring {
                        Text("PPG sensor monitoring heart rhythm")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { heartIDService.isMonitoring },
                    set: { isOn in
                        if isOn {
                            Task { await heartIDService.startContinuousAuth() }
                        } else {
                            heartIDService.stopContinuousAuth()
                        }
                    }
                ))
                .labelsHidden()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)

            Button {
                performDoorAccess()
            } label: {
                HStack {
                    Image(systemName: "door.left.hand.open")
                    Text("Door Access (Demo)")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.caption)
            }
            .buttonStyle(.bordered)

            Button {
                performHighValueTransaction()
            } label: {
                HStack {
                    Image(systemName: "dollarsign.circle")
                    Text("High-Value Transaction")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.caption)
            }
            .buttonStyle(.bordered)
        }
    }

    private var integrationModeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Integration", systemImage: "link")
                .font(.headline)

            HStack {
                Text(heartIDService.currentIntegrationMode.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if heartIDService.currentIntegrationMode.isDemo {
                    Text("DEMO")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(4)
                }
            }

            // iPhone Search Button
            Button {
                togglePhoneSearch()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isSearchingForPhone ? "stop.circle.fill" : "applewatch.radiowaves.left.and.right")
                        .font(.caption)

                    if isSearchingForPhone {
                        Text("Searching... \(searchCountdown)s")
                            .font(.caption)
                    } else {
                        Text("Search for iPhone")
                            .font(.caption)
                    }

                    Spacer()

                    // Mute toggle
                    Button {
                        isMuted.toggle()
                        WKInterfaceDevice.current().play(.click)
                    } label: {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.caption2)
                            .foregroundColor(isMuted ? .gray : .blue)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(isSearchingForPhone ? .orange : .blue)
            .scaleEffect(isPulsating ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsating)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }

    private var authenticateButton: some View {
        Button {
            handleAuthenticatePress()
        } label: {
            HStack {
                Image(systemName: "waveform.path.ecg")
                Text("Manual ECG Authentication")
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
            }
            .font(.headline)
            .padding()
        }
        .buttonStyle(.bordered)
        .tint(authenticateButtonColor)
        .cornerRadius(12)
        .disabled(isAuthenticating)
    }

    private var throbbingHeartIndicator: some View {
        HStack(spacing: 4) {
            // Trend arrow
            if heartIDService.currentConfidence > previousConfidence {
                Text("^")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            } else if heartIDService.currentConfidence < previousConfidence {
                Text("v")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
            }

            // Throbbing heart (reduced pulse by 50%)
            Image(systemName: "heart.fill")
                .font(.title3)
                .foregroundColor(.red)
                .scaleEffect(isHeartThrobbing ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isHeartThrobbing)
        }
        .onAppear {
            isHeartThrobbing = true
            previousConfidence = heartIDService.currentConfidence
        }
        .onChange(of: heartIDService.currentConfidence) { oldValue, newValue in
            previousConfidence = oldValue
        }
    }

    // MARK: - Computed Properties

    private var confidenceDisplayText: String {
        if heartIDService.authenticationState == .unauthenticated || heartIDService.currentConfidence < 0.75 {
            return "Not\nAuthenticated"
        } else {
            return "\(Int(heartIDService.currentConfidence * 100))%"
        }
    }

    private var confidenceDisplayFontSize: CGFloat {
        if heartIDService.authenticationState == .unauthenticated || heartIDService.currentConfidence < 0.75 {
            return 18
        } else {
            return 28
        }
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

    private var authStatusText: String {
        switch heartIDService.authenticationState {
        case .authenticated:
            return "Authenticated"
        case .conditional:
            return "Conditional Access"
        case .unauthenticated:
            return "Not Authenticated"
        }
    }

    private var authStatusDescription: String {
        switch heartIDService.authenticationState {
        case .authenticated:
            return "Full access granted"
        case .conditional:
            return "Limited access - ECG step-up may be required"
        case .unauthenticated:
            return "Authentication required"
        }
    }

    private var authStatusIcon: String {
        switch heartIDService.authenticationState {
        case .authenticated:
            return "checkmark.circle.fill"
        case .conditional:
            return "exclamationmark.triangle.fill"
        case .unauthenticated:
            return "xmark.circle.fill"
        }
    }

    // MARK: - Actions

    private func handleAuthenticatePress() {
        // Haptic feedback - strong click
        WKInterfaceDevice.current().play(.click)

        // Change button color to green
        withAnimation(.easeInOut(duration: 0.2)) {
            authenticateButtonColor = .green
            isAuthenticating = true
        }

        // Perform authentication
        performManualAuthentication()

        // Gradually fade back to blue over 5 seconds
        withAnimation(.easeInOut(duration: 5.0)) {
            authenticateButtonColor = .blue
        }

        // Re-enable button after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            isAuthenticating = false
        }
    }

    private func reauthenticate() {
        Task {
            await heartIDService.performManualAuthentication()
        }
    }

    private func performManualAuthentication() {
        Task {
            await heartIDService.performManualAuthentication()
        }
    }

    private func performDoorAccess() {
        let action = AuthenticationAction(
            actionType: .doorAccess,
            requiredConfidence: heartIDService.thresholds.fullAccess,
            requiresECG: heartIDService.currentConfidence < heartIDService.thresholds.fullAccess,
            description: "Physical door access"
        )

        if action.requiresECG {
            stepUpAction = action
            showingStepUp = true
        } else {
            print("✅ Door access granted (PPG confidence sufficient)")
        }
    }

    private func performHighValueTransaction() {
        let action = AuthenticationAction(
            actionType: .highValueTransaction,
            requiredConfidence: heartIDService.thresholds.minimumAccuracy,
            requiresECG: true,
            description: "High-value transaction"
        )

        stepUpAction = action
        showingStepUp = true
    }

    private func togglePhoneSearch() {
        if isSearchingForPhone {
            stopPhoneSearch()
        } else {
            startPhoneSearch()
        }
    }

    private func startPhoneSearch() {
        if !isMuted {
            WKInterfaceDevice.current().play(.start)
        }

        isPulsating = true
        isSearchingForPhone = true
        searchCountdown = 60

        searchTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] timer in
            if searchCountdown > 0 {
                searchCountdown -= 1

                let watchConnectivity = WatchConnectivityService.shared
                if watchConnectivity.isConnected {
                    handlePhoneFound()
                    timer.invalidate()
                }
            } else {
                handleSearchTimeout()
                timer.invalidate()
            }
        }
    }

    private func stopPhoneSearch() {
        searchTimer?.invalidate()
        searchTimer = nil
        isSearchingForPhone = false
        isPulsating = false
        searchCountdown = 60
        WKInterfaceDevice.current().play(.stop)
    }

    private func handlePhoneFound() {
        isSearchingForPhone = false
        isPulsating = false
        searchTimer?.invalidate()
        searchTimer = nil

        if !isMuted {
            WKInterfaceDevice.current().play(.success)
        }

        print("✅ iPhone connection established!")
    }

    private func handleSearchTimeout() {
        isSearchingForPhone = false
        isPulsating = false
        searchCountdown = 60

        if !isMuted {
            WKInterfaceDevice.current().play(.failure)
        }

        print("⏱ iPhone search timed out after 60 seconds")
    }
}

// MARK: - StepUpAuthView

/// ECG step-up authentication for high-security actions
struct StepUpAuthView: View {
    @ObservedObject var heartIDService: HeartIDService
    let action: AuthenticationAction
    @Environment(\.dismiss) private var dismiss
    @State private var isAuthenticating = false
    @State private var authResult: AuthenticationResult?
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: actionIcon)
                            .font(.system(size: 50))
                            .foregroundColor(.red)

                        Text("Step-Up Authentication")
                            .font(.headline)

                        Text(action.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top)

                    Divider()

                    // Result or Instructions
                    if let result = authResult {
                        resultView(result)
                    } else if isAuthenticating {
                        authenticatingView
                    } else {
                        instructionsView
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isAuthenticating)
                }
            }
            .alert("Authentication Error", isPresented: $showError) {
                Button("OK") {
                    showError = false
                }
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
        }
    }

    private var instructionsView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("This action requires ECG verification")
                    .font(.caption)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Text("1.").fontWeight(.bold)
                        Text("Record a 30-second ECG in the Health app").font(.caption)
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Text("2.").fontWeight(.bold)
                        Text("We'll verify your cardiac signature").font(.caption)
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Text("3.").fontWeight(.bold)
                        Text("Authentication result will appear here").font(.caption)
                    }
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)

            VStack(spacing: 8) {
                HStack {
                    Text("Required Confidence:").font(.caption)
                    Spacer()
                    Text("\(Int(action.requiredConfidence * 100))%")
                        .font(.caption).fontWeight(.bold).foregroundColor(.blue)
                }

                HStack {
                    Text("Expected Accuracy:").font(.caption)
                    Spacer()
                    Text("96-99%").font(.caption).fontWeight(.bold).foregroundColor(.green)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)

            Button {
                performStepUpAuth()
            } label: {
                if isAuthenticating {
                    ProgressView().progressViewStyle(.circular)
                } else {
                    Text("Begin ECG Authentication").fontWeight(.semibold)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(isAuthenticating)

            Button("Open Health App") {
                openHealthApp()
            }
            .buttonStyle(.bordered)
            .font(.caption)
        }
    }

    private var authenticatingView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.5)
            Text("Waiting for ECG...").font(.caption).foregroundColor(.secondary)
            Text("Please record an ECG in the Health app").font(.caption2).foregroundColor(.secondary).multilineTextAlignment(.center)
            Text("Timeout: 3 minutes").font(.caption2).foregroundColor(.orange)
        }
        .padding()
    }

    private func resultView(_ result: AuthenticationResult) -> some View {
        VStack(spacing: 16) {
            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(result.success ? .green : .red)

            Text(result.success ? "Authentication Successful" : "Authentication Failed")
                .font(.headline)
                .foregroundColor(result.success ? .green : .red)

            VStack(spacing: 8) {
                HStack {
                    Text("Confidence Score:").font(.caption)
                    Spacer()
                    Text("\(Int(result.confidenceScore * 100))%")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(result.success ? .green : .red)
                }

                HStack {
                    Text("Required:").font(.caption)
                    Spacer()
                    Text("\(Int(action.requiredConfidence * 100))%").font(.caption).foregroundColor(.secondary)
                }

                HStack {
                    Text("Template Match:").font(.caption)
                    Spacer()
                    Text("\(Int(result.decisionFactors.templateMatch * 100))%").font(.caption).foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)

            VStack(alignment: .leading, spacing: 8) {
                Text("Decision Factors").font(.caption).fontWeight(.semibold)

                HStack {
                    Image(systemName: "waveform.path.ecg")
                    Text("Liveness: \(Int(result.decisionFactors.livenessScore * 100))%").font(.caption2)
                    Spacer()
                }

                HStack {
                    Image(systemName: "applewatch")
                    Text("Device Trust: \(Int(result.decisionFactors.deviceTrust * 100))%").font(.caption2)
                    Spacer()
                }

                HStack {
                    Image(systemName: result.decisionFactors.wristDetection ? "checkmark.circle" : "xmark.circle")
                    Text("Wrist Detection: \(result.decisionFactors.wristDetection ? "Yes" : "No")").font(.caption2)
                    Spacer()
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)

            if result.success {
                Text("Access granted to: \(action.description)")
                    .font(.caption).foregroundColor(.green).multilineTextAlignment(.center)
                    .padding().background(Color.green.opacity(0.1)).cornerRadius(8)
            } else {
                Text("Access denied. Please try again or contact support.")
                    .font(.caption).foregroundColor(.red).multilineTextAlignment(.center)
                    .padding().background(Color.red.opacity(0.1)).cornerRadius(8)
            }

            Button(result.success ? "Done" : "Try Again") {
                if result.success {
                    dismiss()
                } else {
                    authResult = nil
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(result.success ? .green : .red)
        }
    }

    private var actionIcon: String {
        switch action.actionType {
        case .doorAccess: return "door.left.hand.open"
        case .documentAccess: return "doc.text.fill"
        case .highValueTransaction: return "dollarsign.circle.fill"
        case .criticalSystemAccess: return "lock.shield.fill"
        case .generalAccess: return "key.fill"
        case .enterpriseLogin: return "building.2.fill"
        case .pacsEntry: return "door.sliding.left.hand.open"
        case .patientRecordAccess: return "cross.case.fill"
        }
    }

    private func performStepUpAuth() {
        isAuthenticating = true
        errorMessage = nil

        Task {
            do {
                let result = try await heartIDService.performECGStepUp(for: action)
                isAuthenticating = false
                authResult = result
            } catch {
                isAuthenticating = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func openHealthApp() {
        if URL(string: "x-apple-health://") != nil {
            print("Opening Health app for ECG recording")
        }
    }
}

#Preview {
    AuthenticateView(heartIDService: HeartIDService())
}
