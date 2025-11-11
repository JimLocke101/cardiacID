import Foundation

/// Configuration management for different environments
struct EnvironmentConfig {
    let entraIDAuthority: String
    let entraIDRedirectURI: String
    let supabaseURL: String
    let apiTimeout: TimeInterval
    let enableLogging: Bool
    let enableAnalytics: Bool
    
    static let current = EnvironmentConfig.development
    
    static let development = EnvironmentConfig(
        entraIDAuthority: "https://login.microsoftonline.com",
        entraIDRedirectURI: "msauth.com.heartid.app://auth",
        supabaseURL: "https://your-project.supabase.co",
        apiTimeout: 30.0,
        enableLogging: true,
        enableAnalytics: false
    )
    
    static let production = EnvironmentConfig(
        entraIDAuthority: "https://login.microsoftonline.com",
        entraIDRedirectURI: "msauth.com.heartid.app://auth",
        supabaseURL: "https://your-production-project.supabase.co",
        apiTimeout: 15.0,
        enableLogging: false,
        enableAnalytics: true
    )
    
    static let staging = EnvironmentConfig(
        entraIDAuthority: "https://login.microsoftonline.com",
        entraIDRedirectURI: "msauth.com.heartid.staging://auth",
        supabaseURL: "https://your-staging-project.supabase.co",
        apiTimeout: 20.0,
        enableLogging: true,
        enableAnalytics: false
    )
}