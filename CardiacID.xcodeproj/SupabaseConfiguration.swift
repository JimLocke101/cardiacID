import Foundation
import Supabase

/// Supabase client configuration and management
class SupabaseConfiguration {
    
    // MARK: - Singleton
    static let shared = SupabaseConfiguration()
    
    // MARK: - Supabase Client
    let client: SupabaseClient
    
    private init() {
        let config = EnvironmentConfig.current
        
        // Initialize Supabase client with your credentials
        client = SupabaseClient(
            supabaseURL: URL(string: config.supabaseURL)!,
            supabaseKey: config.supabaseAnonKey
        )
        
        print("✅ Supabase client initialized")
        print("   URL: \(config.supabaseURL)")
        print("   Project ID: \(config.supabaseProjectID)")
    }
    
    // MARK: - Convenience Access
    
    /// Access the shared Supabase client
    static var client: SupabaseClient {
        return shared.client
    }
}

// MARK: - Global Access
/// Global Supabase client for easy access throughout the app
let supabase = SupabaseConfiguration.client

// MARK: - Usage Examples
/*
 Usage Examples:
 
 // Using the global client
 let todos = try await supabase.from("todos").select().execute().value
 
 // Using the shared instance
 let client = SupabaseConfiguration.shared.client
 let result = try await client.from("users").select().execute()
 
 // Direct access to client
 let data = try await SupabaseConfiguration.client.from("table").select().execute()
 */