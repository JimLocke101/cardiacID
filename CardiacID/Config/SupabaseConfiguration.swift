//
//  SupabaseConfiguration.swift
//  CardiacID
//
//  Supabase project connection configuration.
//  Follows the same pattern as MSALConfiguration.swift.
//
//  SECURITY NOTES:
//  • publishableKey  — safe to embed. It is the public client identifier,
//    equivalent to the old anon key. Anyone may see this value.
//  • anonKey (JWT)   — same trust level as publishableKey; legacy format.
//    Safe to embed.
//  • SERVICE ROLE KEY ("sb_secret_...") — NOT HERE. Never embed in iOS code.
//    It is auto-injected by Supabase into all Edge Functions. Store it only
//    via `supabase secrets set` or the Supabase dashboard Vault.
//
//  INAPPLICABLE CONFIG (for other stacks using this same Supabase project):
//  • NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_PUBLISHABLE_DEFAULT_KEY
//    → Used by Next.js web apps; not applicable to this iOS project.
//  • EXPO_PUBLIC_SUPABASE_URL / EXPO_PUBLIC_SUPABASE_KEY
//    → Used by Expo / React Native apps; not applicable to this iOS project.
//  • DATABASE_URL / DIRECT_URL / prisma/schema.prisma
//    → Used by Prisma ORM in Node.js backends; not applicable to this iOS project.
//

import Foundation

/// Central Supabase configuration for CardiacID iOS & watchOS app.
struct SupabaseConfiguration {

    // MARK: - Project Coordinates

    static let projectURL      = "https://iufsxauhrnaunglfxtly.supabase.co"
    static let projectRef      = "iufsxauhrnaunglfxtly"

    // MARK: - Client Keys (safe to embed — public identifiers)

    /// Publishable key — the recommended client-side key (new Supabase format).
    static let publishableKey  = "sb_publishable_QkVtltcanizv_HaerDFfSQ_MXt_5LyU"

    /// Anon key (legacy JWT format) — equivalent to publishableKey.
    /// Kept for SDK compatibility; both keys grant anon-level access only.
    static let anonKey         = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml1ZnN4YXVocm5hdW5nbGZ4dGx5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM5NjEwNDQsImV4cCI6MjA4OTUzNzA0NH0.ldl8u9axnWAioXggytNqi_S1yIxNJCxMIOhAsHj_Tbw"

    // MARK: - Derived URLs

    static let authURL         = "\(projectURL)/auth/v1"
    static let restURL         = "\(projectURL)/rest/v1"
    static let storageURL      = "\(projectURL)/storage/v1"
    static let realtimeURL     = "\(projectURL)/realtime/v1"
    static let functionsURL    = "\(projectURL)/functions/v1"

    /// The OIDC issuer URL — used as the `iss` claim in id_tokens issued by
    /// the CardiacID EAM Edge Functions.
    static let issuerURL       = functionsURL

    // MARK: - Validation

    static func validate() -> Bool {
        !projectURL.isEmpty &&
        !publishableKey.isEmpty &&
        !projectURL.contains("your-project") &&
        publishableKey.hasPrefix("sb_publishable_")
    }

    // MARK: - Bootstrap

    /// Writes the Supabase URL and publishable key into the iOS Keychain
    /// so all services that read from SecureCredentialManager work immediately.
    /// Call once from app startup (CardiacIDApp.initializeApp).
    @discardableResult
    static func bootstrap() -> Bool {
        guard validate() else {
            print("SupabaseConfig: ⚠️  Configuration is invalid — check SupabaseConfiguration.swift")
            return false
        }
        do {
            try SecureCredentialManager.shared.store(projectURL,     forKey: .supabaseURL)
            try SecureCredentialManager.shared.store(publishableKey, forKey: .supabaseAPIKey)
            print("SupabaseConfig: ✅ Credentials bootstrapped to Keychain")
            return true
        } catch {
            print("SupabaseConfig: ❌ Keychain bootstrap failed: \(error)")
            return false
        }
    }

    // MARK: - Debug

    static func printConfiguration() {
        print("""
        ╔══════════════════════════════════════════════════════════════════════════╗
        ║  SUPABASE CONFIGURATION                                                  ║
        ╠══════════════════════════════════════════════════════════════════════════╣
        ║  Project:    \(projectURL.padding(toLength: 47, withPad: " ", startingAt: 0)) ║
        ║  Ref:        \(projectRef.padding(toLength: 47, withPad: " ", startingAt: 0)) ║
        ║  Auth:       \(authURL.padding(toLength: 47, withPad: " ", startingAt: 0)) ║
        ║  REST:       \(restURL.padding(toLength: 47, withPad: " ", startingAt: 0)) ║
        ║  Functions:  \(functionsURL.padding(toLength: 47, withPad: " ", startingAt: 0)) ║
        ║  Key type:   publishable (safe to embed)                                 ║
        ╚══════════════════════════════════════════════════════════════════════════╝
        """)
    }
}
