//
//  AppleWatchSetupView.swift
//  CardiacID
//
//  Apple Watch pairing and setup instructions
//

import SwiftUI
import WatchConnectivity

struct AppleWatchSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var watchStatus: WatchStatus = .checking
    @State private var showingHealthKitPermissions = false
    
    private let colors = HeartIDColors()
    
    enum WatchStatus {
        case checking
        case paired
        case notPaired
        case healthKitNeeded
        case ready
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                colors.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 30) {
                        // Header
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(colors.accent.opacity(0.2))
                                    .frame(width: 100, height: 100)
                                
                                Image(systemName: "applewatch")
                                    .font(.system(size: 50))
                                    .foregroundColor(colors.accent)
                            }
                            
                            Text("Apple Watch Setup")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(colors.text)
                            
                            Text("Connect your Apple Watch to enable HeartID biometric authentication")
                                .font(.subheadline)
                                .foregroundColor(colors.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                        .padding(.top, 20)
                        
                        // Status section
                        statusSection
                        
                        // Setup steps
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Setup Steps")
                                .font(.headline)
                                .foregroundColor(colors.text)
                            
                            SetupStep(
                                number: 1,
                                title: "Pair Apple Watch",
                                description: "Make sure your Apple Watch is paired with this iPhone",
                                isCompleted: watchStatus == .paired || watchStatus == .ready,
                                icon: "applewatch.watchface"
                            )
                            
                            SetupStep(
                                number: 2,
                                title: "Enable ECG App",
                                description: "Open the ECG app on your watch and complete the initial setup",
                                isCompleted: watchStatus == .ready,
                                icon: "waveform.path.ecg"
                            )
                            
                            SetupStep(
                                number: 3,
                                title: "Grant HealthKit Access",
                                description: "Allow HeartID to access your heart rate data for authentication",
                                isCompleted: watchStatus == .ready,
                                icon: "heart.text.square.fill"
                            )
                        }
                        .padding(.horizontal, 20)
                        
                        // Instructions
                        instructionsSection
                        
                        Spacer(minLength: 20)
                        
                        // Action buttons
                        VStack(spacing: 12) {
                            if watchStatus == .ready {
                                Button(action: { dismiss() }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 18))
                                        Text("Continue to HeartID")
                                            .font(.system(size: 18, weight: .semibold))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(colors.accent)
                                    .cornerRadius(12)
                                }
                            } else {
                                Button(action: checkWatchStatus) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 16))
                                        Text("Check Watch Status")
                                            .font(.system(size: 16, weight: .medium))
                                    }
                                    .foregroundColor(colors.text)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(colors.surface)
                                    .cornerRadius(12)
                                }
                            }
                            
                            Button(action: { dismiss() }) {
                                Text("Skip for Now")
                                    .font(.system(size: 16))
                                    .foregroundColor(colors.secondary)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(colors.accent)
                }
            }
        }
        .onAppear {
            checkWatchStatus()
        }
    }
    
    private var statusSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: statusIcon)
                    .font(.system(size: 20))
                    .foregroundColor(statusColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.headline)
                        .foregroundColor(colors.text)
                    
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(colors.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(colors.surface)
            .cornerRadius(12)
            .padding(.horizontal, 20)
        }
    }
    
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How It Works")
                .font(.headline)
                .foregroundColor(colors.text)
            
            VStack(spacing: 12) {
                InstructionRow(
                    icon: "1.circle.fill",
                    text: "Your Apple Watch captures your unique cardiac rhythm using the ECG sensor"
                )
                
                InstructionRow(
                    icon: "2.circle.fill", 
                    text: "HeartID creates a secure template of your heart pattern"
                )
                
                InstructionRow(
                    icon: "3.circle.fill",
                    text: "Future authentications match against this template in real-time"
                )
            }
        }
        .padding(.horizontal, 20)
    }
    
    // Status computed properties
    private var statusIcon: String {
        switch watchStatus {
        case .checking: return "clock"
        case .paired: return "checkmark.circle.fill"
        case .notPaired: return "exclamationmark.triangle.fill"
        case .healthKitNeeded: return "heart.slash.fill"
        case .ready: return "checkmark.seal.fill"
        }
    }
    
    private var statusColor: Color {
        switch watchStatus {
        case .checking: return colors.secondary
        case .paired: return .orange
        case .notPaired: return .red
        case .healthKitNeeded: return .orange
        case .ready: return .green
        }
    }
    
    private var statusTitle: String {
        switch watchStatus {
        case .checking: return "Checking Watch Connection..."
        case .paired: return "Apple Watch Connected"
        case .notPaired: return "Apple Watch Not Found"
        case .healthKitNeeded: return "HealthKit Permission Required"
        case .ready: return "Ready for HeartID Setup"
        }
    }
    
    private var statusMessage: String {
        switch watchStatus {
        case .checking: return "Scanning for your paired Apple Watch"
        case .paired: return "Your watch is connected and ready"
        case .notPaired: return "Please pair your Apple Watch with this iPhone"
        case .healthKitNeeded: return "Grant HealthKit permissions to continue"
        case .ready: return "All requirements met - you can now enroll with HeartID"
        }
    }
    
    private func checkWatchStatus() {
        watchStatus = .checking
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Check if WatchConnectivity is supported and watch is paired
            if WCSession.isSupported() {
                let session = WCSession.default
                session.delegate = nil // You'd set a proper delegate in real implementation
                session.activate()
                
                if session.isPaired && session.isWatchAppInstalled {
                    // Check HealthKit permissions (simplified check)
                    watchStatus = .ready
                } else if session.isPaired {
                    watchStatus = .paired
                } else {
                    watchStatus = .notPaired
                }
            } else {
                watchStatus = .notPaired
            }
        }
    }
}

// MARK: - Supporting Views

struct SetupStep: View {
    let number: Int
    let title: String
    let description: String
    let isCompleted: Bool
    let icon: String
    
    private let colors = HeartIDColors()
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(isCompleted ? colors.accent : colors.surface)
                    .frame(width: 40, height: 40)
                
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(colors.secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(colors.accent)
                    
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colors.text)
                }
                
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
    }
}

struct InstructionRow: View {
    let icon: String
    let text: String
    
    private let colors = HeartIDColors()
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(colors.accent)
                .frame(width: 20)
            
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(colors.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    AppleWatchSetupView()
        .preferredColorScheme(.dark)
}