// Token Endpoint for CardiacID OIDC Provider
// Issues signed id_tokens with biometric confidence claims
// Called by Entra ID during EAM authentication flow
//
// Flow: Entra ID redirects user to CardiacID authorize endpoint ->
//       User authenticates with HeartID -> CardiacID issues auth code ->
//       Entra ID exchanges code for id_token at this endpoint
//
// Deploy: supabase functions deploy oidc-token

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

const ISSUER_URL = Deno.env.get("CARDIACID_ISSUER_URL") || "https://your-project.supabase.co/functions/v1";
const SIGNING_KEY_ID = Deno.env.get("CARDIACID_SIGNING_KEY_ID") || "Y2FyZGlhY2lkLXNpZ25pbmcta2V5LXYx";

// In-memory authorization code store (use Supabase DB in production)
// Codes are single-use and expire after 5 minutes
const authorizationCodes: Map<string, AuthCodeEntry> = new Map();

interface AuthCodeEntry {
  userId: string;
  email: string;
  displayName: string;
  clientId: string;
  redirectUri: string;
  nonce?: string;
  biometricConfidence: number;
  biometricMethod: string;
  createdAt: number;
}

// Export for use by authorize endpoint
export { authorizationCodes, type AuthCodeEntry };

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
      },
    });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    // Parse the token request
    const contentType = req.headers.get("content-type") || "";
    let params: URLSearchParams;

    if (contentType.includes("application/x-www-form-urlencoded")) {
      const body = await req.text();
      params = new URLSearchParams(body);
    } else if (contentType.includes("application/json")) {
      const body = await req.json();
      params = new URLSearchParams(body);
    } else {
      return new Response(JSON.stringify({ error: "unsupported_content_type" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const grantType = params.get("grant_type");
    const code = params.get("code");
    const clientId = params.get("client_id");
    const redirectUri = params.get("redirect_uri");

    // Validate grant type
    if (grantType !== "authorization_code") {
      return new Response(
        JSON.stringify({
          error: "unsupported_grant_type",
          error_description: "Only authorization_code grant type is supported",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Validate authorization code
    if (!code) {
      return new Response(
        JSON.stringify({
          error: "invalid_request",
          error_description: "Missing authorization code",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Look up the authorization code
    const codeEntry = authorizationCodes.get(code);
    if (!codeEntry) {
      return new Response(
        JSON.stringify({
          error: "invalid_grant",
          error_description: "Invalid or expired authorization code",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Check code expiration (5 minutes)
    if (Date.now() - codeEntry.createdAt > 5 * 60 * 1000) {
      authorizationCodes.delete(code);
      return new Response(
        JSON.stringify({
          error: "invalid_grant",
          error_description: "Authorization code has expired",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Consume the code (single-use)
    authorizationCodes.delete(code);

    // Validate client_id and redirect_uri match
    if (clientId && clientId !== codeEntry.clientId) {
      return new Response(
        JSON.stringify({ error: "invalid_client", error_description: "Client ID mismatch" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Generate the id_token with CardiacID biometric claims
    const now = Math.floor(Date.now() / 1000);
    const idTokenPayload = {
      iss: ISSUER_URL,
      sub: codeEntry.userId,
      aud: codeEntry.clientId,
      exp: now + 3600, // 1 hour
      iat: now,
      nonce: codeEntry.nonce,

      // Standard OIDC claims
      email: codeEntry.email,
      name: codeEntry.displayName,
      preferred_username: codeEntry.email,

      // CardiacID biometric claims
      cardiacid_confidence: codeEntry.biometricConfidence,
      cardiacid_method: codeEntry.biometricMethod,
      cardiacid_enrolled: true,
      cardiacid_verified_at: now,
      amr: ["mfa", "hwk", "bio"], // Authentication Methods References
    };

    // Sign the id_token
    const idToken = await signJWT(idTokenPayload);

    // Token response
    const tokenResponse = {
      access_token: crypto.randomUUID(), // Opaque access token
      token_type: "Bearer",
      expires_in: 3600,
      id_token: idToken,
      scope: "openid profile email cardiacid.verify",
    };

    return new Response(JSON.stringify(tokenResponse), {
      status: 200,
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
        "Pragma": "no-cache",
      },
    });
  } catch (error) {
    console.error("Token endpoint error:", error);
    return new Response(
      JSON.stringify({
        error: "server_error",
        error_description: "Internal server error",
      }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});

// JWT signing using P-256 ECDSA (ES256)
async function signJWT(payload: Record<string, unknown>): Promise<string> {
  const header = {
    alg: "ES256",
    typ: "JWT",
    kid: SIGNING_KEY_ID, // base64-encoded kid for Entra ID compatibility
  };

  const encodedHeader = base64urlEncode(JSON.stringify(header));
  const encodedPayload = base64urlEncode(JSON.stringify(payload));
  const signingInput = `${encodedHeader}.${encodedPayload}`;

  // Get or create signing key
  const keyPair = await getSigningKey();
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    keyPair.privateKey,
    new TextEncoder().encode(signingInput)
  );

  // Convert DER signature to raw format (r || s) for JWT
  const rawSignature = derToRaw(new Uint8Array(signature));
  const encodedSignature = base64urlEncode(rawSignature);

  return `${encodedHeader}.${encodedPayload}.${encodedSignature}`;
}

function base64urlEncode(input: string | Uint8Array): string {
  let bytes: Uint8Array;
  if (typeof input === "string") {
    bytes = new TextEncoder().encode(input);
  } else {
    bytes = input;
  }

  const base64 = btoa(String.fromCharCode(...bytes));
  return base64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// Convert DER-encoded ECDSA signature to raw (r || s) format
function derToRaw(der: Uint8Array): Uint8Array {
  // DER: 0x30 <len> 0x02 <rlen> <r> 0x02 <slen> <s>
  if (der[0] !== 0x30) return der; // Not DER, assume raw

  let offset = 2;
  if (der[1] & 0x80) offset += (der[1] & 0x7f);

  // Read r
  if (der[offset] !== 0x02) return der;
  const rLen = der[offset + 1];
  const rStart = offset + 2;
  let r = der.slice(rStart, rStart + rLen);

  // Read s
  offset = rStart + rLen;
  if (der[offset] !== 0x02) return der;
  const sLen = der[offset + 1];
  const sStart = offset + 2;
  let s = der.slice(sStart, sStart + sLen);

  // Pad or trim to 32 bytes each
  r = padOrTrim(r, 32);
  s = padOrTrim(s, 32);

  const raw = new Uint8Array(64);
  raw.set(r, 0);
  raw.set(s, 32);
  return raw;
}

function padOrTrim(arr: Uint8Array, len: number): Uint8Array {
  if (arr.length === len) return arr;
  if (arr.length > len) return arr.slice(arr.length - len);
  const padded = new Uint8Array(len);
  padded.set(arr, len - arr.length);
  return padded;
}

async function getSigningKey(): Promise<CryptoKeyPair> {
  const storedKey = Deno.env.get("CARDIACID_SIGNING_PRIVATE_KEY_JWK");
  if (storedKey) {
    const privateKeyJWK = JSON.parse(storedKey);
    const privateKey = await crypto.subtle.importKey(
      "jwk",
      privateKeyJWK,
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["sign"]
    );
    const publicKeyJWK = { ...privateKeyJWK };
    delete publicKeyJWK.d;
    const publicKey = await crypto.subtle.importKey(
      "jwk",
      publicKeyJWK,
      { name: "ECDSA", namedCurve: "P-256" },
      true,
      ["verify"]
    );
    return { privateKey, publicKey } as CryptoKeyPair;
  }

  // Fallback: generate ephemeral key (development only)
  return await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"]
  );
}
