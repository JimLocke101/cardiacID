//
//  ProfileView.swift
//  HeartID Mobile
//
//  Created by Jim Locke on 5/27/25.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Profile header
                VStack(spacing: 16) {
                    // Avatar
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 100, height: 100)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                        )
                    
                    // User info
                    VStack(spacing: 8) {
                        Text("\(authViewModel.currentUser?.firstName ?? "") \(authViewModel.currentUser?.lastName ?? "")")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(authViewModel.currentUser?.email ?? "")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(16)
                
                // Profile options
                VStack(spacing: 12) {
                    ProfileRow(icon: "person.circle", title: "Personal Information", action: {})
                    ProfileRow(icon: "heart.circle", title: "Heart Pattern", action: {})
                    ProfileRow(icon: "shield.circle", title: "Security Settings", action: {})
                    ProfileRow(icon: "bell.circle", title: "Notifications", action: {})
                    ProfileRow(icon: "questionmark.circle", title: "Help & Support", action: {})
                }
                
                Spacer()
                
                // Logout button
                Button(action: {
                    authViewModel.signOut()
                    dismiss()
                }) {
                    Text("Log Out")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(12)
                }
            }
            .padding()
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ProfileRow: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 30)
                
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthViewModel())
}
