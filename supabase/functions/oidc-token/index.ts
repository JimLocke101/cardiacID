// Token Endpoint for CardiacID OIDC Provider
// Issues signed id_tokens with biometric confidence claims
// Called by Entra ID during EAM authentication flow
//
// Flow: Entra ID redirects user to CardiacID authorize endpoint ->
//       User authenticates with HeartID -> CardiacID issues auth code ->
//       Entra ID exchanges code for id_token at this endpoint
//
// Code lookup strategy:
//   1. Check in-memory authorizationCodes Map (fast path — same Edge Function isolate)
//   2. Fall back to Supabase DB (durable path — cross-isolate or restart)
//
// Deploy: supabase functions deploy oidc-token

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ISSUER_URL = Deno.env.get("CARDIACID_ISSUER_URL") || "https://iufsxauhrnaunglfxtly.supabase.co/functions/v1";
const SIGNING_KEY_ID = Deno.env.get("CARDIACID_SIGNING_KEY_ID") || "Y2FyZGlhY2lkLXNpZ25pbmcta2V5LXYx";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

// ---------------------------------------------------------------------------
// In-memory authorization code store (fast path for same-isolate exchanges)
// Written by oidc-authorize when the app posts a verified biometric.
// Supabase DB is the durable fallback when the token request lands on a
// different isolate.
// ---------------------------------------------------------------------------

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

// Re-exported so oidc-authorize can write directly into this Map
// when both functions run in the same isolate.
export const authorizationCodes = new Map<string, AuthCodeEntry>();

// 5-minute code lifetime
const CODE_TTL_MS = 5 * 60 * 1000;

// ---------------------------------------------------------------------------

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
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  try {
    const contentType = req.headers.get("content-type") || "";
    let params: URLSearchParams;

    if (contentType.includes("application/x-www-form-urlencoded")) {
      params = new URLSearchParams(await req.text());
    } else if (contentType.includes("application/json")) {
      params = new URLSearchParams(await req.json());
    } else {
      return jsonResponse({ error: "unsupported_content_type" }, 400);
    }

    const grantType   = params.get("grant_type");
    const code         = params.get("code");
    const clientId     = params.get("client_id");
    const redirectUri  = params.get("redirect_uri"); // validated against stored entry below
    const codeVerifier = params.get("code_verifier"); // PKCE S256 verifier

    if (grantType !== "authorization_code") {
      return jsonResponse({
        error: "unsupported_grant_type",
        error_description: "Only authorization_code grant type is supported",
      }, 400);
    }

    if (!code) {
      return jsonResponse({
        error: "invalid_request",
        error_description: "Missing authorization code",
      }, 400);
    }

    // -----------------------------------------------------------------------
    // Resolve the authorization code
    // Step 1 — in-memory Map (fast path, same isolate as oidc-authorize)
    // Step 2 — Supabase DB (durable path, cross-isolate)
    // -----------------------------------------------------------------------
    let codeEntry: AuthCodeEntry | null = null;

    const memEntry = authorizationCodes.get(code);
    if (memEntry) {
      if (Date.now() - memEntry.createdAt > CODE_TTL_MS) {
        authorizationCodes.delete(code);
        return jsonResponse({
          error: "invalid_grant",
          error_description: "Authorization code has expired",
        }, 400);
      }
      codeEntry = memEntry;
      authorizationCodes.delete(code); // single-use
    } else if (SUPABASE_URL && SUPABASE_SERVICE_KEY) {
      // Fallback: look up in Supabase
      const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
      const { data, error } = await supabase
        .from("oidc_auth_sessions")
        .select("user_id, email, display_name, client_id, redirect_uri, nonce, biometric_confidence, biometric_method, status, expires_at, session_id")
        .eq("auth_code", code)
        .eq("status", "verified")
        .single();

      if (error || !data) {
        return jsonResponse({
          error: "invalid_grant",
          error_description: "Invalid or expired authorization code",
        }, 400);
      }

      if (new Date(data.expires_at) < new Date()) {
        return jsonResponse({
          error: "invalid_grant",
          error_description: "Authorization code has expired",
        }, 400);
      }

      // Consume the code in Supabase (single-use)
      await supabase
        .from("oidc_auth_sessions")
        .update({ status: "consumed" })
        .eq("session_id", data.session_id);

      codeEntry = {
        userId:              data.user_id,
        email:               data.email || "",
        displayName:         data.display_name || "",
        clientId:            data.client_id,
        redirectUri:         data.redirect_uri,
        nonce:               data.nonce ?? undefined,
        biometricConfidence: data.biometric_confidence,
        biometricMethod:     data.biometric_method || "hybrid",
        createdAt:           Date.now(),
      };
    }

    if (!codeEntry) {
      return jsonResponse({
        error: "invalid_grant",
        error_description: "Invalid or expired authorization code",
      }, 400);
    }

    // Validate client_id and redirect_uri if provided
    if (clientId && clientId !== codeEntry.clientId) {
      return jsonResponse({
        error: "invalid_client",
        error_description: "Client ID mismatch",
      }, 400);
    }
    if (redirectUri && redirectUri !== codeEntry.redirectUri) {
      return jsonResponse({
        error: "invalid_grant",
        error_description: "Redirect URI mismatch",
      }, 400);
    }

    // -----------------------------------------------------------------------
    // PKCE validation — if the authorization request included a code_challenge,
    // the token request MUST include a matching code_verifier.
    // -----------------------------------------------------------------------
    const storedChallenge = (codeEntry as any).codeChallenge ?? null;

    if (storedChallenge) {
      if (!codeVerifier) {
        return jsonResponse({
          error: "invalid_grant",
          error_description: "PKCE code_verifier required but missing",
        }, 400);
      }
      // S256: BASE64URL(SHA256(code_verifier)) must equal stored code_challenge
      const encoder = new TextEncoder();
      const digest  = await crypto.subtle.digest("SHA-256", encoder.encode(codeVerifier));
      const computed = base64urlEncode(new Uint8Array(digest));
      if (computed !== storedChallenge) {
        return jsonResponse({
          error: "invalid_grant",
          error_description: "PKCE code_verifier does not match code_challenge",
        }, 403);
      }
    }

    // -----------------------------------------------------------------------
    // Build and sign the id_token
    // -----------------------------------------------------------------------
    const now = Math.floor(Date.now() / 1000);
    const idTokenPayload = {
      iss: ISSUER_URL,
      sub: codeEntry.userId,
      aud: codeEntry.clientId,
      exp: now + 3600,
      iat: now,
      nonce: codeEntry.nonce,

      // Standard OIDC claims
      email:              codeEntry.email,
      name:               codeEntry.displayName,
      preferred_username: codeEntry.email,

      // CardiacID biometric claims (readable by Entra ID Conditional Access)
      cardiacid_confidence:   codeEntry.biometricConfidence,
      cardiacid_method:       codeEntry.biometricMethod,
      cardiacid_enrolled:     true,
      cardiacid_verified_at:  now,
      amr: ["mfa", "hwk", "bio"], // Authentication Methods References
    };

    const idToken = await signJWT(idTokenPayload);

    return new Response(JSON.stringify({
      access_token: crypto.randomUUID(), // opaque access token
      token_type:   "Bearer",
      expires_in:   3600,
      id_token:     idToken,
      scope:        "openid profile email cardiacid.verify",
    }), {
      status: 200,
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
        "Pragma": "no-cache",
      },
    });
  } catch (error) {
    console.error("Token endpoint error:", error);
    return jsonResponse({
      error: "server_error",
      error_description: "Internal server error",
    }, 500);
  }
});

// ---------------------------------------------------------------------------
// JWT helpers — ES256 (P-256 ECDSA), required by Entra ID EAM
// ---------------------------------------------------------------------------

async function signJWT(payload: Record<string, unknown>): Promise<string> {
  const header = { alg: "ES256", typ: "JWT", kid: SIGNING_KEY_ID };
  const encodedHeader  = base64urlEncode(JSON.stringify(header));
  const encodedPayload = base64urlEncode(JSON.stringify(payload));
  const signingInput   = `${encodedHeader}.${encodedPayload}`;

  const keyPair   = await getSigningKey();
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    keyPair.privateKey,
    new TextEncoder().encode(signingInput)
  );

  const rawSignature   = derToRaw(new Uint8Array(signature));
  const encodedSig     = base64urlEncode(rawSignature);
  return `${encodedHeader}.${encodedPayload}.${encodedSig}`;
}

function base64urlEncode(input: string | Uint8Array): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  const base64 = btoa(String.fromCharCode(...bytes));
  return base64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** Convert DER-encoded ECDSA signature to raw r||s (64 bytes) for JWT */
function derToRaw(der: Uint8Array): Uint8Array {
  if (der[0] !== 0x30) return der;
  let offset = 2;
  if (der[1] & 0x80) offset += (der[1] & 0x7f);

  if (der[offset] !== 0x02) return der;
  const rLen = der[offset + 1];
  const rStart = offset + 2;
  let r = der.slice(rStart, rStart + rLen);

  offset = rStart + rLen;
  if (der[offset] !== 0x02) return der;
  const sLen = der[offset + 1];
  const sStart = offset + 2;
  let s = der.slice(sStart, sStart + sLen);

  r = padOrTrim(r, 32);
  s = padOrTrim(s, 32);
  const raw = new Uint8Array(64);
  raw.set(r, 0);
  raw.set(s, 32);
  return raw;
}

function padOrTrim(arr: Uint8Array, len: number): Uint8Array<ArrayBuffer> {
  // Copy through new Uint8Array() to guarantee ArrayBuffer (not ArrayBufferLike),
  // which is required for TypedArray.set() compatibility in TypeScript 5.5+.
  const copied = new Uint8Array(arr);
  if (copied.length === len) return copied;
  if (copied.length > len)   return copied.slice(copied.length - len);
  const padded = new Uint8Array(len);
  padded.set(copied, len - copied.length);
  return padded;
}

async function getSigningKey(): Promise<CryptoKeyPair> {
  const stored = Deno.env.get("CARDIACID_SIGNING_PRIVATE_KEY_JWK");
  if (stored) {
    const privateKeyJWK = JSON.parse(stored);
    const privateKey = await crypto.subtle.importKey(
      "jwk", privateKeyJWK,
      { name: "ECDSA", namedCurve: "P-256" },
      false, ["sign"]
    );
    const publicKeyJWK = { ...privateKeyJWK };
    delete publicKeyJWK.d;
    const publicKey = await crypto.subtle.importKey(
      "jwk", publicKeyJWK,
      { name: "ECDSA", namedCurve: "P-256" },
      true, ["verify"]
    );
    return { privateKey, publicKey } as CryptoKeyPair;
  }
  // Ephemeral key — development only (tokens won't be verifiable after restart)
  console.warn("SETUP: No CARDIACID_SIGNING_PRIVATE_KEY_JWK set — using ephemeral key. Set this secret before production deployment.");
  return await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]
  );
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
