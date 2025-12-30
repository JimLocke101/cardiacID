//
//  iOSAuthView.swift
//  CardiacID iOS
//
//  Example iOS authentication view
//

import SwiftUI

struct iOSAuthView: View {
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
            .navigationTitle("EntraID Auth")
            .alert("Authentication Error", isPresented: $showingError) {
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
        VStack(spacing: 20) {
            if let user = authService.currentUser {
                VStack(spacing: 12) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 80, height: 80)
                        .overlay(
                            Text(user.initials)
                                .foregroundColor(.white)
                                .font(.title2.bold())
                        )
                    
                    Text(user.displayName)
                        .font(.title2.bold())
                    
                    Text(user.email)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Platform: \(user.platform)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Button("Refresh Profile") {
                Task {
                    try? await authService.refreshUserProfile()
                }
            }
            .buttonStyle(.borderedProminent)
            
            Button("Sign Out") {
                Task {
                    await authService.signOut()
                }
            }
            .buttonStyle(.bordered)
            .foregroundColor(.red)
            
            Spacer()
        }
        .padding()
    }
    
    private var unauthenticatedView: some View {
        VStack(spacing: 30) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text("Welcome to CardiacID")
                .font(.title.bold())
            
            Text("Sign in with your EntraID account to continue")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Button("Sign In") {
                Task {
                    try? await authService.signIn()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(authService.isLoading)
            
            if authService.isLoading {
                ProgressView("Signing in...")
                    .progressViewStyle(CircularProgressViewStyle())
            }
            
            Spacer()
        }
        .padding()
    }
}

#Preview {
    iOSAuthView()
}