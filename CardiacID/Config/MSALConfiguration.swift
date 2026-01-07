//
//  MSALConfiguration.swift
//  CardiacID
//
//  Azure EntraID / MSAL Configuration
//  Contains the app registration details from Azure Portal
//

import Foundation

/// Central configuration for Azure EntraID / MSAL authentication
/// Values are from the Azure App Registration: CardiacID_0_8
struct MSALConfiguration {
    // MARK: - Azure App Registration Details

    /// Application (client) ID from Azure App Registration
    static let clientID = "c6414bc9-b537-4305-b277-a86f63fdb5ed"

    /// Directory (tenant) ID from Azure App Registration
    static let tenantID = "71fec99d-2fb1-4c59-b8a0-32d27906433f"

    /// Object ID from Azure App Registration
    static let objectID = "6cfce22c-5111-4860-ba8f-2f75cb8cae48"

    /// Display name of the app registration
    static let displayName = "CardiacID_0_8"

    // MARK: - MSAL Configuration

    /// Authority URL for authentication
    static let authority = "https://login.microsoftonline.com/\(tenantID)"

    /// Bundle ID of the app
    static let bundleID = "ARGOS.CardiacID"

    /// Redirect URI for MSAL authentication callbacks
    /// Format: msauth.[bundle-id]://auth
    static let redirectURI = "msauth.\(bundleID)://auth"

    // MARK: - API Scopes

    /// Scopes for Microsoft Graph API access
    static let enterpriseScopes: [String] = [
        "User.Read",
        "Application.Read.All",
        "Group.Read.All",
        "Directory.Read.All"
    ]

    /// Basic scopes for user authentication
    static let basicScopes: [String] = [
        "User.Read",
        "openid",
        "profile",
        "email"
    ]

    // MARK: - Validation

    /// Validates that the configuration is complete
    static func validate() -> Bool {
        return !clientID.isEmpty &&
               !tenantID.isEmpty &&
               !redirectURI.isEmpty &&
               clientID != "YOUR_CLIENT_ID" &&
               tenantID != "YOUR_TENANT_ID"
    }

    /// Prints configuration for debugging
    static func printConfiguration() {
        print("""
        ╔═══════════════════════════════════════════════════════════════════════╗
        ║  MSAL CONFIGURATION                                                    ║
        ╠═══════════════════════════════════════════════════════════════════════╣
        ║  App Name:      \(displayName.padding(toLength: 45, withPad: " ", startingAt: 0)) ║
        ║  Client ID:     \(clientID.padding(toLength: 45, withPad: " ", startingAt: 0)) ║
        ║  Tenant ID:     \(tenantID.padding(toLength: 45, withPad: " ", startingAt: 0)) ║
        ║  Object ID:     \(objectID.padding(toLength: 45, withPad: " ", startingAt: 0)) ║
        ║  Redirect URI:  \(redirectURI.padding(toLength: 45, withPad: " ", startingAt: 0)) ║
        ║  Bundle ID:     \(bundleID.padding(toLength: 45, withPad: " ", startingAt: 0)) ║
        ╚═══════════════════════════════════════════════════════════════════════╝
        """)
    }
}
