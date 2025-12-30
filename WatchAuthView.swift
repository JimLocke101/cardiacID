//
//  WatchAuthView.swift
//  CardiacID watchOS
//
//  Example watchOS authentication view
//

import SwiftUI

#if os(watchOS)
struct WatchAuthView: View {
    @StateObject private var authService = UnifiedAuthService.shared
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
            .navigationTitle("Auth")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(authService.errorMessage ?? "Unknown error")
            }
            .onChange(of: authService.errorMessage) { errorMessage in
                showingError = errorMessage != nil
            }
        }
    }
    
    private var authenticatedView: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let user = authService.currentUser {
                    VStack(spacing: 8) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 60, height: 60)
                            .overlay(
                                Text(user.initials)
                                    .foregroundColor(.white)
                                    .font(.headline.bold())
                            )
                        
                        Text(user.displayName)
                            .font(.headline.bold())
                            .multilineTextAlignment(.center)
                        
                        Text(user.email)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                VStack(spacing: 12) {
                    Button("Refresh") {
                        Task {
                            try? await authService.refreshUserProfile()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                    Button("Sign Out") {
                        Task {
                            await authService.signOut()
                        }
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 8)
        }
    }
    
    private var unauthenticatedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.red)
            
            Text("CardiacID")
                .font(.headline.bold())
            
            Text("Connect to iPhone to sign in")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Authenticate") {
                Task {
                    try? await authService.signIn()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(authService.isLoading)
            .controlSize(.small)
            
            if authService.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(0.8)
                
                Text("Contacting iPhone...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

#Preview {
    WatchAuthView()
}
#endif