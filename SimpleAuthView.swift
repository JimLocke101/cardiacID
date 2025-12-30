//
//  SimpleAuthView.swift
//  CardiacID
//
//  Simplified authentication view that works on both iOS and watchOS
//  This replaces complex UI implementations to avoid build issues
//

import SwiftUI

struct SimpleAuthView: View {
    @StateObject private var authService = SimpleAuthService.shared
    @State private var showingError = false
    
    var body: some View {
        NavigationView {
            Group {
                if authService.isAuthenticated {
                    authenticatedView
                } else {
                    unauthenticatedView
                }
            }
            .navigationTitle("CardiacID")
            .alert("Error", isPresented: $showingError) {
                Button("OK") { 
                    authService.errorMessage = nil
                }
            } message: {
                Text(authService.errorMessage ?? "Unknown error")
            }
            .onChange(of: authService.errorMessage) { errorMessage in
                showingError = errorMessage != nil
            }
        }
    }
    
    // MARK: - Authenticated View
    
    private var authenticatedView: some View {
        VStack(spacing: spacing.large) {
            if let user = authService.currentUser {
                VStack(spacing: spacing.medium) {
                    // User avatar
                    Circle()
                        .fill(Color.blue)
                        .frame(width: sizes.avatarSize, height: sizes.avatarSize)
                        .overlay(
                            Text(user.initials)
                                .foregroundColor(.white)
                                .font(fonts.avatar)
                        )
                    
                    // User info
                    Text(user.displayName)
                        .font(fonts.name)
                        .multilineTextAlignment(.center)
                    
                    Text(user.email)
                        .font(fonts.email)
                        .foregroundColor(.secondary)
                        .lineLimit(emailLineLimit)
                }
            }
            
            // Actions
            VStack(spacing: spacing.small) {
                Button("Sign Out") {
                    Task {
                        await authService.signOut()
                    }
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
                .controlSize(sizes.buttonSize)
                
                #if os(iOS)
                Text("Platform: iOS")
                    .font(.caption)
                    .foregroundColor(.secondary)
                #elseif os(watchOS)
                Text("Platform: watchOS")
                    .font(.caption)
                    .foregroundColor(.secondary)
                #endif
            }
        }
        .padding()
    }
    
    // MARK: - Unauthenticated View
    
    private var unauthenticatedView: some View {
        VStack(spacing: spacing.large) {
            // Icon
            Image(systemName: platformIcon)
                .font(.system(size: sizes.iconSize))
                .foregroundColor(.blue)
            
            // Title
            Text("Welcome")
                .font(fonts.title)
            
            // Subtitle
            Text(platformSubtitle)
                .font(fonts.subtitle)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            // Sign in button
            Button(signInButtonTitle) {
                Task {
                    try? await authService.signIn()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(authService.isLoading)
            .controlSize(sizes.buttonSize)
            
            // Loading indicator
            if authService.isLoading {
                ProgressView(loadingText)
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(sizes.progressScale)
            }
            
            // Debug info
            #if DEBUG
            VStack {
                Text("Debug Mode")
                    .font(.caption2)
                    .foregroundColor(.orange)
                
                #if canImport(MSAL)
                Text("MSAL Available")
                    .font(.caption2)
                    .foregroundColor(.green)
                #else
                Text("MSAL Not Available")
                    .font(.caption2)
                    .foregroundColor(.orange)
                #endif
            }
            .padding(.top, spacing.small)
            #endif
        }
        .padding()
    }
    
    // MARK: - Platform-specific content
    
    private var platformIcon: String {
        #if os(iOS)
        return "iphone"
        #elseif os(watchOS)
        return "applewatch"
        #else
        return "heart.fill"
        #endif
    }
    
    private var platformSubtitle: String {
        #if os(iOS)
        return "Sign in with your Microsoft account"
        #elseif os(watchOS)
        return "Authenticate to get started"
        #else
        return "Get started with CardiacID"
        #endif
    }
    
    private var signInButtonTitle: String {
        #if os(iOS)
        return "Sign In"
        #elseif os(watchOS)
        return "Sign In"
        #else
        return "Authenticate"
        #endif
    }
    
    private var loadingText: String {
        #if os(iOS)
        return "Signing in..."
        #elseif os(watchOS)
        return "Please wait..."
        #else
        return "Loading..."
        #endif
    }
    
    // MARK: - Platform-specific sizing
    
    private var sizes: ViewSizes {
        #if os(iOS)
        return .iOS
        #elseif os(watchOS)
        return .watchOS
        #else
        return .macOS
        #endif
    }
    
    private var fonts: ViewFonts {
        #if os(iOS)
        return .iOS
        #elseif os(watchOS)
        return .watchOS
        #else
        return .macOS
        #endif
    }
    
    private var spacing: ViewSpacing {
        #if os(iOS)
        return .iOS
        #elseif os(watchOS)
        return .watchOS
        #else
        return .macOS
        #endif
    }
    
    private var emailLineLimit: Int {
        #if os(watchOS)
        return 1
        #else
        return 2
        #endif
    }
}

// MARK: - Platform-specific styling

struct ViewSizes {
    let avatarSize: CGFloat
    let iconSize: CGFloat
    let buttonSize: ControlSize
    let progressScale: CGFloat
    
    static let iOS = ViewSizes(
        avatarSize: 80,
        iconSize: 60,
        buttonSize: .regular,
        progressScale: 1.0
    )
    
    static let watchOS = ViewSizes(
        avatarSize: 50,
        iconSize: 40,
        buttonSize: .small,
        progressScale: 0.8
    )
    
    static let macOS = ViewSizes(
        avatarSize: 100,
        iconSize: 80,
        buttonSize: .large,
        progressScale: 1.2
    )
}

struct ViewFonts {
    let avatar: Font
    let name: Font
    let email: Font
    let title: Font
    let subtitle: Font
    
    static let iOS = ViewFonts(
        avatar: .title2.bold(),
        name: .title2.bold(),
        email: .subheadline,
        title: .title.bold(),
        subtitle: .body
    )
    
    static let watchOS = ViewFonts(
        avatar: .headline.bold(),
        name: .headline.bold(),
        email: .caption,
        title: .headline.bold(),
        subtitle: .caption
    )
    
    static let macOS = ViewFonts(
        avatar: .title.bold(),
        name: .title.bold(),
        email: .title3,
        title: .largeTitle.bold(),
        subtitle: .title3
    )
}

struct ViewSpacing {
    let small: CGFloat
    let medium: CGFloat
    let large: CGFloat
    
    static let iOS = ViewSpacing(
        small: 8,
        medium: 16,
        large: 24
    )
    
    static let watchOS = ViewSpacing(
        small: 4,
        medium: 8,
        large: 16
    )
    
    static let macOS = ViewSpacing(
        small: 12,
        medium: 24,
        large: 36
    )
}

// MARK: - Preview

#Preview("iOS Auth View") {
    SimpleAuthView()
}

#if os(watchOS)
#Preview("watchOS Auth View") {
    SimpleAuthView()
}
#endif