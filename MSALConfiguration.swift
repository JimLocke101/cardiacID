//
//  MSALConfiguration.swift
//  CardiacID
//
//  MSAL configuration helper with proper credential management
//

import Foundation

#if os(iOS) && canImport(MSAL)
import MSAL

struct MSALConfiguration {
    static let shared = MSALConfiguration()
    
    private let credentialManager = SecureCredentialManager.shared
    
    // MARK: - Configuration Properties
    
    var tenantId: String {
        do {
            return try credentialManager.retrieve(forKey: .entraIDTenantID)
        } catch {
            // Fallback to environment or default
            return Bundle.main.object(forInfoDictionaryKey: "ENTRA_ID_TENANT_ID") as? String ?? ""
        }
    }
    
    var clientId: String {
        do {
            return try credentialManager.retrieve(forKey: .entraIDClientID)
        } catch {
            // Fallback to environment or default
            return Bundle.main.object(forInfoDictionaryKey: "ENTRA_ID_CLIENT_ID") as? String ?? ""
        }
    }
    
    var redirectUri: String {
        return "cardiacid://auth"
    }
    
    var scopes: [String] {
        return [
            "User.Read",
            "openid",
            "profile",
            "email"
        ]
    }
    
    // MARK: - MSAL Application Factory
    
    func createMSALApplication() throws -> MSALPublicClientApplication {
        guard !tenantId.isEmpty && !clientId.isEmpty else {
            throw MSALConfigurationError.missingConfiguration
        }
        
        let authorityURL = URL(string: "https://login.microsoftonline.com/\(tenantId)")!
        let authority = try MSALAADAuthority(url: authorityURL)
        
        let config = MSALPublicClientApplicationConfig(
            clientId: clientId,
            redirectUri: redirectUri,
            authority: authority
        )
        
        config.knownAuthorities = [authority]
        
        return try MSALPublicClientApplication(configuration: config)
    }
    
    // MARK: - Configuration Setup
    
    func setupConfiguration(tenantId: String, clientId: String) throws {
        try credentialManager.store(tenantId, forKey: .entraIDTenantID)
        try credentialManager.store(clientId, forKey: .entraIDClientID)
    }
    
    func clearConfiguration() throws {
        try credentialManager.delete(forKey: .entraIDTenantID)
        try credentialManager.delete(forKey: .entraIDClientID)
    }
    
    var isConfigured: Bool {
        return !tenantId.isEmpty && !clientId.isEmpty
    }
}

enum MSALConfigurationError: LocalizedError {
    case missingConfiguration
    case invalidConfiguration
    
    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "MSAL configuration missing. Please provide tenant ID and client ID."
        case .invalidConfiguration:
            return "MSAL configuration is invalid."
        }
    }
}

#endif