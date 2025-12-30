//
//  UnifiedAuthView.swift
//  CardiacID
//
//  Unified authentication view that works on both iOS and watchOS
//

import SwiftUI
import Combine

struct UnifiedAuthView: View {
    @StateObject private var authService = AuthServiceFactory.createAuthService() as! (any ObservableObject & AuthenticationServiceProtocol)
    @State private var showingError = false
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if authService.isAuthenticated {
                authenticatedView
            } else {
                unauthenticatedView
            }
        }
        .alert("Authentication Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(authService.errorMessage ?? "Unknown error")
        }
        .onChange(of: authService.errorMessage) { errorMessage in
            showingError = errorMessage != nil
        }
    }
    
    private var authenticatedView: some View {
        VStack(spacing: 20) {
            if let user = authService.currentUser {
                VStack(spacing: 12) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: frameSize.avatarSize, height: frameSize.avatarSize)
                        .overlay(
                            Text(user.initials)
                                .foregroundColor(.white)
                                .font(frameSize.avatarFont)
                        )
                    
                    Text(user.displayName)
                        .font(frameSize.nameFont)
                        .multilineTextAlignment(.center)
                    
                    Text(user.email)
                        .font(frameSize.emailFont)
                        .foregroundColor(.secondary)
                        .lineLimit(frameSize.emailLineLimit)
                }
            }
            
            VStack(spacing: 12) {
                Button("Refresh") {
                    Task {
                        try? await authService.refreshToken()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(frameSize.buttonControlSize)
                
                Button("Sign Out") {
                    Task {
                        try? await authService.signOut()
                    }
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
                .controlSize(frameSize.buttonControlSize)
            }
        }
        .padding()
    }
    
    private var unauthenticatedView: some View {
        VStack(spacing: frameSize.spacing) {
            Image(systemName: platformIcon)
                .font(.system(size: frameSize.iconSize))
                .foregroundColor(.blue)
            
            Text("Welcome to CardiacID")
                .font(frameSize.titleFont)
                .multilineTextAlignment(.center)
            
            Text(platformMessage)
                .font(frameSize.subtitleFont)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(buttonTitle) {
                Task {
                    try? await authService.signIn()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(authService.isLoading)
            .controlSize(frameSize.buttonControlSize)
            
            if authService.isLoading {
                ProgressView(loadingMessage)
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(frameSize.progressScale)
            }
        }
        .padding()
    }
    
    // MARK: - Platform-specific properties
    
    private var platformIcon: String {
        #if os(iOS)
        return "heart.circle.fill"
        #elseif os(watchOS)
        return "applewatch"
        #else
        return "heart.fill"
        #endif
    }
    
    private var platformMessage: String {
        #if os(iOS)
        return "Sign in with your EntraID account to continue"
        #elseif os(watchOS)
        return "Authenticate via iPhone to continue"
        #else
        return "Authentication required"
        #endif
    }
    
    private var buttonTitle: String {
        #if os(iOS)
        return "Sign In with EntraID"
        #elseif os(watchOS)
        return "Authenticate"
        #else
        return "Sign In"
        #endif
    }
    
    private var loadingMessage: String {
        #if os(iOS)
        return "Signing in..."
        #elseif os(watchOS)
        return "Contacting iPhone..."
        #else
        return "Loading..."
        #endif
    }
    
    // MARK: - Platform-specific sizing
    
    private var frameSize: FrameSize {
        #if os(iOS)
        return FrameSize.iOS
        #elseif os(watchOS)
        return FrameSize.watchOS
        #else
        return FrameSize.macOS
        #endif
    }
}

// MARK: - Frame Size Configuration

struct FrameSize {
    let avatarSize: CGFloat
    let avatarFont: Font
    let nameFont: Font
    let emailFont: Font
    let emailLineLimit: Int
    let titleFont: Font
    let subtitleFont: Font
    let iconSize: CGFloat
    let spacing: CGFloat
    let buttonControlSize: ControlSize
    let progressScale: CGFloat
    
    static let iOS = FrameSize(
        avatarSize: 80,
        avatarFont: .title2.bold(),
        nameFont: .title2.bold(),
        emailFont: .subheadline,
        emailLineLimit: 2,
        titleFont: .title.bold(),
        subtitleFont: .body,
        iconSize: 80,
        spacing: 30,
        buttonControlSize: .regular,
        progressScale: 1.0
    )
    
    static let watchOS = FrameSize(
        avatarSize: 50,
        avatarFont: .headline.bold(),
        nameFont: .headline.bold(),
        emailFont: .caption,
        emailLineLimit: 1,
        titleFont: .headline.bold(),
        subtitleFont: .caption,
        iconSize: 40,
        spacing: 16,
        buttonControlSize: .small,
        progressScale: 0.8
    )
    
    static let macOS = FrameSize(
        avatarSize: 100,
        avatarFont: .title.bold(),
        nameFont: .title.bold(),
        emailFont: .title3,
        emailLineLimit: 3,
        titleFont: .largeTitle.bold(),
        subtitleFont: .title3,
        iconSize: 100,
        spacing: 40,
        buttonControlSize: .large,
        progressScale: 1.2
    )
}

#Preview("iOS Auth View") {
    UnifiedAuthView()
}

#if os(watchOS)
#Preview("watchOS Auth View") {
    UnifiedAuthView()
}
#endif