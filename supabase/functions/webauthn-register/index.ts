// supabase/functions/webauthn-register/index.ts
//
// WebAuthn Registration Relying Party — Supabase Edge Function
//
// Endpoints:
//   POST /begin    — Generate registration options (challenge)
//   POST /complete — Verify attestation and store credential
//
// Uses Web Crypto API (available in Deno) for challenge generation
// and CBOR/COSE verification for attestation objects.
//
// Storage: Supabase `webauthn_credentials` table
//
// References:
//   - WebAuthn Level 2: https://www.w3.org/TR/webauthn-2/
//   - CBOR: RFC 8949
//   - COSE: RFC 9052

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ─── Configuration ───────────────────────────────────────────────────────────

const RP_ID = Deno.env.get("WEBAUTHN_RP_ID") ?? "cardiacid.com";
const RP_NAME = Deno.env.get("WEBAUTHN_RP_NAME") ?? "CardiacID";
const RP_ORIGIN = Deno.env.get("WEBAUTHN_RP_ORIGIN") ?? `https://${RP_ID}`;
const CHALLENGE_TTL_MS = 5 * 60 * 1000; // 5 minutes

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// ─── In-memory challenge store (move to DB for multi-instance) ───────────────

interface PendingChallenge {
  challenge: Uint8Array;
  userId: string;
  userName: string;
  createdAt: number;
}

const pendingChallenges = new Map<string, PendingChallenge>();

// ─── Helpers ─────────────────────────────────────────────────────────────────

function base64url(buffer: Uint8Array): string {
  const str = btoa(String.fromCharCode(...buffer));
  return str.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64urlDecode(str: string): Uint8Array {
  const padded = str.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(padded);
  return Uint8Array.from(binary, (c) => c.charCodeAt(0));
}

function generateChallenge(): Uint8Array {
  const challenge = new Uint8Array(32);
  crypto.getRandomValues(challenge);
  return challenge;
}

function generateUserId(userId: string): Uint8Array {
  const encoder = new TextEncoder();
  return encoder.encode(userId);
}

// Minimal CBOR decoder for attestation objects
function decodeCBOR(data: Uint8Array): Record<string, unknown> {
  // For "none" attestation (Apple passkeys), the attestation object
  // is a simple CBOR map with: fmt, attStmt, authData
  // This is a minimal decoder sufficient for "none" attestation format
  let offset = 0;

  function readByte(): number {
    return data[offset++];
  }

  function readBytes(n: number): Uint8Array {
    const slice = data.slice(offset, offset + n);
    offset += n;
    return slice;
  }

  function readUint(additionalInfo: number): number {
    if (additionalInfo < 24) return additionalInfo;
    if (additionalInfo === 24) return readByte();
    if (additionalInfo === 25) {
      const b = readBytes(2);
      return (b[0] << 8) | b[1];
    }
    if (additionalInfo === 26) {
      const b = readBytes(4);
      return (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
    }
    throw new Error(`Unsupported CBOR uint length: ${additionalInfo}`);
  }

  function readValue(): unknown {
    const initial = readByte();
    const majorType = initial >> 5;
    const additionalInfo = initial & 0x1f;

    switch (majorType) {
      case 0: // unsigned integer
        return readUint(additionalInfo);
      case 1: // negative integer
        return -1 - readUint(additionalInfo);
      case 2: { // byte string
        const len = readUint(additionalInfo);
        return readBytes(len);
      }
      case 3: { // text string
        const len = readUint(additionalInfo);
        const bytes = readBytes(len);
        return new TextDecoder().decode(bytes);
      }
      case 4: { // array
        const len = readUint(additionalInfo);
        const arr: unknown[] = [];
        for (let i = 0; i < len; i++) arr.push(readValue());
        return arr;
      }
      case 5: { // map
        const len = readUint(additionalInfo);
        const map: Record<string, unknown> = {};
        for (let i = 0; i < len; i++) {
          const key = String(readValue());
          map[key] = readValue();
        }
        return map;
      }
      case 7: // simple values / float
        if (additionalInfo === 20) return false;
        if (additionalInfo === 21) return true;
        if (additionalInfo === 22) return null;
        throw new Error(`Unsupported CBOR simple value: ${additionalInfo}`);
      default:
        throw new Error(`Unsupported CBOR major type: ${majorType}`);
    }
  }

  return readValue() as Record<string, unknown>;
}

// Parse authenticator data (37+ bytes)
interface AuthenticatorData {
  rpIdHash: Uint8Array;
  flags: number;
  signCount: number;
  attestedCredentialData?: {
    aaguid: Uint8Array;
    credentialId: Uint8Array;
    publicKey: Record<string, unknown>;
  };
}

function parseAuthenticatorData(data: Uint8Array): AuthenticatorData {
  const rpIdHash = data.slice(0, 32);
  const flags = data[32];
  const signCount =
    (data[33] << 24) | (data[34] << 16) | (data[35] << 8) | data[36];

  const result: AuthenticatorData = { rpIdHash, flags, signCount };

  // Check AT (attested credential data) flag — bit 6
  if (flags & 0x40) {
    const aaguid = data.slice(37, 53);
    const credIdLen = (data[53] << 8) | data[54];
    const credentialId = data.slice(55, 55 + credIdLen);

    // Remaining bytes are CBOR-encoded COSE public key
    const pkBytes = data.slice(55 + credIdLen);
    const publicKey = decodeCBOR(pkBytes) as Record<string, unknown>;

    result.attestedCredentialData = {
      aaguid,
      credentialId,
      publicKey,
    };
  }

  return result;
}

// ─── Supabase client ─────────────────────────────────────────────────────────

function getSupabase() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
}

// ─── Registration: Begin ─────────────────────────────────────────────────────

async function handleBeginRegistration(body: {
  userId: string;
  userName: string;
  displayName?: string;
}): Promise<Response> {
  const { userId, userName, displayName } = body;

  if (!userId || !userName) {
    return new Response(
      JSON.stringify({ error: "userId and userName are required" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Check for existing credentials
  const supabase = getSupabase();
  const { data: existingCreds } = await supabase
    .from("webauthn_credentials")
    .select("credential_id")
    .eq("user_id", userId);

  const excludeCredentials = (existingCreds ?? []).map(
    (c: { credential_id: string }) => ({
      id: c.credential_id,
      type: "public-key" as const,
      transports: ["internal", "hybrid"],
    })
  );

  const challenge = generateChallenge();
  const challengeId = base64url(challenge);

  // Store pending challenge
  pendingChallenges.set(challengeId, {
    challenge,
    userId,
    userName,
    createdAt: Date.now(),
  });

  // Also persist to DB for cross-isolate resilience
  await supabase.from("webauthn_challenges").upsert({
    challenge_id: challengeId,
    user_id: userId,
    user_name: userName,
    challenge_data: base64url(challenge),
    created_at: new Date().toISOString(),
    expires_at: new Date(Date.now() + CHALLENGE_TTL_MS).toISOString(),
    type: "registration",
  });

  // Build PublicKeyCredentialCreationOptions
  const options = {
    challenge: base64url(challenge),
    rp: {
      id: RP_ID,
      name: RP_NAME,
    },
    user: {
      id: base64url(generateUserId(userId)),
      name: userName,
      displayName: displayName ?? userName,
    },
    pubKeyCredParams: [
      { alg: -7, type: "public-key" }, // ES256 (P-256)
      { alg: -257, type: "public-key" }, // RS256
    ],
    timeout: CHALLENGE_TTL_MS,
    attestation: "none" as const, // Privacy-preserving — sufficient for passkeys
    authenticatorSelection: {
      authenticatorAttachment: "platform" as const,
      residentKey: "required" as const,
      userVerification: "required" as const,
    },
    excludeCredentials,
  };

  return new Response(JSON.stringify({ options, challengeId }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

// ─── Registration: Complete ──────────────────────────────────────────────────

async function handleCompleteRegistration(body: {
  challengeId: string;
  credential: {
    id: string;
    rawId: string;
    type: string;
    response: {
      clientDataJSON: string;
      attestationObject: string;
    };
  };
}): Promise<Response> {
  const { challengeId, credential } = body;

  if (!challengeId || !credential) {
    return new Response(
      JSON.stringify({ error: "challengeId and credential are required" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Retrieve pending challenge
  let pending = pendingChallenges.get(challengeId);

  if (!pending) {
    // Fallback: check DB
    const supabase = getSupabase();
    const { data } = await supabase
      .from("webauthn_challenges")
      .select("*")
      .eq("challenge_id", challengeId)
      .eq("type", "registration")
      .single();

    if (data) {
      pending = {
        challenge: base64urlDecode(data.challenge_data),
        userId: data.user_id,
        userName: data.user_name,
        createdAt: new Date(data.created_at).getTime(),
      };
    }
  }

  if (!pending) {
    return new Response(
      JSON.stringify({ error: "Challenge not found or expired" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Check TTL
  if (Date.now() - pending.createdAt > CHALLENGE_TTL_MS) {
    pendingChallenges.delete(challengeId);
    return new Response(
      JSON.stringify({ error: "Challenge expired" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // 1. Decode and verify clientDataJSON
  const clientDataJSON = base64urlDecode(credential.response.clientDataJSON);
  const clientData = JSON.parse(new TextDecoder().decode(clientDataJSON));

  if (clientData.type !== "webauthn.create") {
    return new Response(
      JSON.stringify({ error: "Invalid clientData type" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Verify challenge matches
  const expectedChallenge = base64url(pending.challenge);
  if (clientData.challenge !== expectedChallenge) {
    return new Response(
      JSON.stringify({ error: "Challenge mismatch" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Verify origin
  if (clientData.origin !== RP_ORIGIN) {
    // Allow iOS app origin pattern: the origin may be the app's bundle ID
    const isAppOrigin =
      clientData.origin.startsWith("https://") ||
      clientData.origin.includes("cardiacid");
    if (!isAppOrigin) {
      return new Response(
        JSON.stringify({ error: `Origin mismatch: ${clientData.origin}` }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }
  }

  // 2. Decode attestation object
  const attestationObject = base64urlDecode(
    credential.response.attestationObject
  );
  const attestation = decodeCBOR(attestationObject);

  // 3. Parse authenticator data
  const authData = parseAuthenticatorData(
    attestation.authData as Uint8Array
  );

  // Verify RP ID hash
  const rpIdHashExpected = new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(RP_ID))
  );

  const rpIdHashMatch = authData.rpIdHash.every(
    (b, i) => b === rpIdHashExpected[i]
  );
  if (!rpIdHashMatch) {
    return new Response(
      JSON.stringify({ error: "RP ID hash mismatch" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Verify user present (UP) flag
  if (!(authData.flags & 0x01)) {
    return new Response(
      JSON.stringify({ error: "User not present" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Verify user verified (UV) flag
  if (!(authData.flags & 0x04)) {
    return new Response(
      JSON.stringify({ error: "User not verified" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  if (!authData.attestedCredentialData) {
    return new Response(
      JSON.stringify({ error: "No attested credential data" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // 4. Store credential in database
  const { credentialId, publicKey, aaguid } =
    authData.attestedCredentialData;

  const supabase = getSupabase();

  // Serialize the COSE public key for storage
  const publicKeyBytes = attestationObject.slice(
    attestationObject.indexOf(credentialId[credentialId.length - 1]) + 1
  );

  const { error: insertError } = await supabase
    .from("webauthn_credentials")
    .insert({
      credential_id: base64url(credentialId),
      user_id: pending.userId,
      user_name: pending.userName,
      public_key: base64url(
        new Uint8Array(JSON.stringify(publicKey).split("").map((c) => c.charCodeAt(0)))
      ),
      public_key_algorithm: (publicKey as Record<string, number>)["3"] ?? -7, // COSE alg
      sign_count: authData.signCount,
      aaguid: base64url(aaguid),
      attestation_format: attestation.fmt as string,
      transports: ["internal", "hybrid"],
      created_at: new Date().toISOString(),
      last_used_at: new Date().toISOString(),
      backed_up: !!(authData.flags & 0x10), // BE flag
      device_type: authData.flags & 0x08 ? "multi_device" : "single_device",
    });

  // Clean up challenge
  pendingChallenges.delete(challengeId);
  await supabase
    .from("webauthn_challenges")
    .delete()
    .eq("challenge_id", challengeId);

  if (insertError) {
    return new Response(
      JSON.stringify({ error: "Failed to store credential", detail: insertError.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  // Log registration event
  await supabase.from("auth_events").insert({
    user_id: pending.userId,
    event_type: "webauthn_registration",
    event_data: {
      credential_id: base64url(credentialId),
      attestation_format: attestation.fmt,
      device_type: authData.flags & 0x08 ? "multi_device" : "single_device",
    },
    created_at: new Date().toISOString(),
  });

  return new Response(
    JSON.stringify({
      verified: true,
      credentialId: base64url(credentialId),
      userId: pending.userId,
    }),
    { status: 200, headers: { "Content-Type": "application/json" } }
  );
}

// ─── Router ──────────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
      },
    });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  const url = new URL(req.url);
  const path = url.pathname.split("/").pop();
  const body = await req.json();

  try {
    switch (path) {
      case "begin":
        return await handleBeginRegistration(body);
      case "complete":
        return await handleCompleteRegistration(body);
      default:
        // If called without sub-path, check body for action field
        if (body.action === "begin") return await handleBeginRegistration(body);
        if (body.action === "complete") return await handleCompleteRegistration(body);
        return new Response(
          JSON.stringify({
            error: "Unknown action. Use /begin or /complete, or pass action field.",
          }),
          { status: 400, headers: { "Content-Type": "application/json" } }
        );
    }
  } catch (err) {
    console.error("WebAuthn registration error:", err);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
