// JWKS (JSON Web Key Set) Endpoint for CardiacID OIDC Provider
// Serves the public signing keys used to verify CardiacID id_tokens
// Uses P-256 ECDSA (ES256) matching the FIDO2 key format in WatchFIDO2Service
//
// CRITICAL: The `kid` (Key ID) in the JWT header and JWKS must be base64-encoded
// for Entra ID EAM compatibility (Microsoft requires this)
//
// Deploy: supabase functions deploy oidc-jwks

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

// In production, these keys should be stored in Supabase Vault or environment secrets
// and rotated periodically. This generates a deterministic key for development.
const SIGNING_KEY_ID = Deno.env.get("CARDIACID_SIGNING_KEY_ID") || "Y2FyZGlhY2lkLXNpZ25pbmcta2V5LXYx"; // base64("cardiacid-signing-key-v1")

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type",
      },
    });
  }

  try {
    // Generate or retrieve the ECDSA P-256 signing key pair
    // In production: load from Supabase Vault / environment
    const keyPair = await getOrCreateSigningKey();

    // Export the public key in JWK format
    const publicKeyJWK = await crypto.subtle.exportKey("jwk", keyPair.publicKey);

    // JWKS response with the public key
    // kid MUST be base64-encoded for Entra ID EAM compatibility
    const jwks = {
      keys: [
        {
          kty: "EC",
          crv: "P-256",
          use: "sig",
          alg: "ES256",
          kid: SIGNING_KEY_ID, // base64-encoded key ID (Entra ID requirement)
          x: publicKeyJWK.x,
          y: publicKeyJWK.y,
        },
      ],
    };

    return new Response(JSON.stringify(jwks, null, 2), {
      status: 200,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Cache-Control": "public, max-age=86400", // Cache for 24 hours
      },
    });
  } catch (error) {
    console.error("JWKS error:", error);
    return new Response(JSON.stringify({ error: "Failed to generate JWKS" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});

// Key management - generates a P-256 ECDSA key pair
// In production, store the private key in Supabase Vault and load it here
async function getOrCreateSigningKey(): Promise<CryptoKeyPair> {
  // Check if we have a stored key in environment
  const storedPrivateKey = Deno.env.get("CARDIACID_SIGNING_PRIVATE_KEY_JWK");

  if (storedPrivateKey) {
    try {
      const privateKeyJWK = JSON.parse(storedPrivateKey);
      const privateKey = await crypto.subtle.importKey(
        "jwk",
        privateKeyJWK,
        { name: "ECDSA", namedCurve: "P-256" },
        true,
        ["sign"]
      );

      // Derive the public key from private key JWK
      const publicKeyJWK = { ...privateKeyJWK };
      delete publicKeyJWK.d; // Remove private component
      const publicKey = await crypto.subtle.importKey(
        "jwk",
        publicKeyJWK,
        { name: "ECDSA", namedCurve: "P-256" },
        true,
        ["verify"]
      );

      return { privateKey, publicKey } as CryptoKeyPair;
    } catch (e) {
      console.warn("Failed to load stored key, generating new one:", e);
    }
  }

  // Generate a new key pair (for development/initial setup)
  // IMPORTANT: In production, export this key and store it in environment secrets
  const keyPair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true, // extractable
    ["sign", "verify"]
  );

  // Log the private key JWK for initial setup (store this in env secrets)
  const privateKeyJWK = await crypto.subtle.exportKey("jwk", keyPair.privateKey);
  console.log("SETUP: Store this as CARDIACID_SIGNING_PRIVATE_KEY_JWK environment secret:");
  console.log(JSON.stringify(privateKeyJWK));

  return keyPair;
}
