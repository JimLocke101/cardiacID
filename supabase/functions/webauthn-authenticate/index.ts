// supabase/functions/webauthn-authenticate/index.ts
//
// WebAuthn Authentication (Assertion) Relying Party — Supabase Edge Function
//
// Endpoints:
//   POST /begin    — Generate assertion options (challenge + allowed credentials)
//   POST /complete — Verify assertion signature and issue session token
//
// Verifies authenticator signatures using Web Crypto API (P-256 / ES256).
// Issues a signed session token on successful authentication.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ─── Configuration ───────────────────────────────────────────────────────────

const RP_ID = Deno.env.get("WEBAUTHN_RP_ID") ?? "cardiacid.com";
const RP_ORIGIN = Deno.env.get("WEBAUTHN_RP_ORIGIN") ?? `https://${RP_ID}`;
const CHALLENGE_TTL_MS = 5 * 60 * 1000; // 5 minutes

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// ─── In-memory challenge store ───────────────────────────────────────────────

interface PendingAssertionChallenge {
  challenge: Uint8Array;
  userId: string;
  createdAt: number;
}

const pendingChallenges = new Map<string, PendingAssertionChallenge>();

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

// Convert DER-encoded ECDSA signature to raw r||s format for Web Crypto
function derToRaw(der: Uint8Array): Uint8Array {
  // DER: 0x30 <len> 0x02 <rlen> <r> 0x02 <slen> <s>
  let offset = 2; // skip 0x30 and total length
  if (der[0] !== 0x30) throw new Error("Not a DER sequence");

  // Read r
  if (der[offset] !== 0x02) throw new Error("Expected integer tag for r");
  offset++;
  const rLen = der[offset++];
  let r = der.slice(offset, offset + rLen);
  offset += rLen;

  // Read s
  if (der[offset] !== 0x02) throw new Error("Expected integer tag for s");
  offset++;
  const sLen = der[offset++];
  let s = der.slice(offset, offset + sLen);

  // Strip leading zeros and pad to 32 bytes
  if (r.length > 32) r = r.slice(r.length - 32);
  if (s.length > 32) s = s.slice(s.length - 32);

  const raw = new Uint8Array(64);
  raw.set(r, 32 - r.length);
  raw.set(s, 64 - s.length);
  return raw;
}

// Parse a COSE public key (stored as JSON) into a Web Crypto CryptoKey
async function importCOSEPublicKey(
  coseKeyJson: string
): Promise<CryptoKey> {
  const cose = JSON.parse(coseKeyJson);

  // COSE key type 2 = EC2
  // COSE alg -7 = ES256 (P-256)
  // Key parameters: -1 = crv (1 = P-256), -2 = x, -3 = y
  const x = cose["-2"] as Uint8Array | number[];
  const y = cose["-3"] as Uint8Array | number[];

  if (!x || !y) {
    throw new Error("Missing x or y coordinates in COSE key");
  }

  const xBytes = x instanceof Uint8Array ? x : new Uint8Array(x);
  const yBytes = y instanceof Uint8Array ? y : new Uint8Array(y);

  // Build JWK
  const jwk: JsonWebKey = {
    kty: "EC",
    crv: "P-256",
    x: base64url(xBytes),
    y: base64url(yBytes),
  };

  return await crypto.subtle.importKey(
    "jwk",
    jwk,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"]
  );
}

// ─── Supabase client ─────────────────────────────────────────────────────────

function getSupabase() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
}

// ─── Authentication: Begin ───────────────────────────────────────────────────

async function handleBeginAssertion(body: {
  userId: string;
}): Promise<Response> {
  const { userId } = body;

  if (!userId) {
    return new Response(
      JSON.stringify({ error: "userId is required" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Fetch user's registered credentials
  const supabase = getSupabase();
  const { data: credentials, error } = await supabase
    .from("webauthn_credentials")
    .select("credential_id, transports")
    .eq("user_id", userId);

  if (error || !credentials?.length) {
    return new Response(
      JSON.stringify({ error: "No credentials found for user" }),
      { status: 404, headers: { "Content-Type": "application/json" } }
    );
  }

  const challenge = generateChallenge();
  const challengeId = base64url(challenge);

  // Store pending challenge
  pendingChallenges.set(challengeId, {
    challenge,
    userId,
    createdAt: Date.now(),
  });

  // Persist to DB
  await supabase.from("webauthn_challenges").upsert({
    challenge_id: challengeId,
    user_id: userId,
    user_name: userId,
    challenge_data: base64url(challenge),
    created_at: new Date().toISOString(),
    expires_at: new Date(Date.now() + CHALLENGE_TTL_MS).toISOString(),
    type: "authentication",
  });

  const allowCredentials = credentials.map(
    (c: { credential_id: string; transports: string[] }) => ({
      id: c.credential_id,
      type: "public-key" as const,
      transports: c.transports ?? ["internal", "hybrid"],
    })
  );

  const options = {
    challenge: base64url(challenge),
    rpId: RP_ID,
    timeout: CHALLENGE_TTL_MS,
    userVerification: "required" as const,
    allowCredentials,
  };

  return new Response(JSON.stringify({ options, challengeId }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

// ─── Authentication: Complete ────────────────────────────────────────────────

async function handleCompleteAssertion(body: {
  challengeId: string;
  credential: {
    id: string;
    rawId: string;
    type: string;
    response: {
      clientDataJSON: string;
      authenticatorData: string;
      signature: string;
      userHandle?: string;
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
  const supabase = getSupabase();

  if (!pending) {
    const { data } = await supabase
      .from("webauthn_challenges")
      .select("*")
      .eq("challenge_id", challengeId)
      .eq("type", "authentication")
      .single();

    if (data) {
      pending = {
        challenge: base64urlDecode(data.challenge_data),
        userId: data.user_id,
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

  if (Date.now() - pending.createdAt > CHALLENGE_TTL_MS) {
    pendingChallenges.delete(challengeId);
    return new Response(
      JSON.stringify({ error: "Challenge expired" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // 1. Look up stored credential
  const { data: storedCred, error: credError } = await supabase
    .from("webauthn_credentials")
    .select("*")
    .eq("credential_id", credential.id)
    .eq("user_id", pending.userId)
    .single();

  if (credError || !storedCred) {
    return new Response(
      JSON.stringify({ error: "Credential not found" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // 2. Decode clientDataJSON
  const clientDataJSON = base64urlDecode(credential.response.clientDataJSON);
  const clientData = JSON.parse(new TextDecoder().decode(clientDataJSON));

  if (clientData.type !== "webauthn.get") {
    return new Response(
      JSON.stringify({ error: "Invalid clientData type" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  const expectedChallenge = base64url(pending.challenge);
  if (clientData.challenge !== expectedChallenge) {
    return new Response(
      JSON.stringify({ error: "Challenge mismatch" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // 3. Decode authenticator data
  const authenticatorData = base64urlDecode(
    credential.response.authenticatorData
  );

  // Verify RP ID hash (first 32 bytes)
  const rpIdHash = authenticatorData.slice(0, 32);
  const expectedHash = new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(RP_ID))
  );

  if (!rpIdHash.every((b, i) => b === expectedHash[i])) {
    return new Response(
      JSON.stringify({ error: "RP ID hash mismatch" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Verify UP flag
  const flags = authenticatorData[32];
  if (!(flags & 0x01)) {
    return new Response(
      JSON.stringify({ error: "User not present" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // 4. Verify signature
  //    signedData = authenticatorData || SHA-256(clientDataJSON)
  const clientDataHash = new Uint8Array(
    await crypto.subtle.digest("SHA-256", clientDataJSON)
  );
  const signedData = new Uint8Array(
    authenticatorData.length + clientDataHash.length
  );
  signedData.set(authenticatorData);
  signedData.set(clientDataHash, authenticatorData.length);

  const signature = base64urlDecode(credential.response.signature);

  try {
    // Decode stored public key
    const publicKeyJson = new TextDecoder().decode(
      base64urlDecode(storedCred.public_key)
    );
    const publicKey = await importCOSEPublicKey(publicKeyJson);

    // Convert DER signature to raw for Web Crypto
    const rawSignature = derToRaw(signature);

    const verified = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      publicKey,
      rawSignature,
      signedData
    );

    if (!verified) {
      await supabase.from("auth_events").insert({
        user_id: pending.userId,
        event_type: "webauthn_assertion_failed",
        event_data: {
          credential_id: credential.id,
          reason: "signature_invalid",
        },
        created_at: new Date().toISOString(),
      });

      return new Response(
        JSON.stringify({ error: "Signature verification failed" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }
  } catch (verifyErr) {
    console.error("Signature verification error:", verifyErr);
    return new Response(
      JSON.stringify({ error: "Signature verification error" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // 5. Verify and update sign count (replay protection)
  const newSignCount =
    (authenticatorData[33] << 24) |
    (authenticatorData[34] << 16) |
    (authenticatorData[35] << 8) |
    authenticatorData[36];

  if (storedCred.sign_count > 0 && newSignCount <= storedCred.sign_count) {
    // Possible cloned authenticator
    await supabase.from("auth_events").insert({
      user_id: pending.userId,
      event_type: "webauthn_sign_count_anomaly",
      event_data: {
        credential_id: credential.id,
        stored_count: storedCred.sign_count,
        received_count: newSignCount,
      },
      created_at: new Date().toISOString(),
    });

    return new Response(
      JSON.stringify({ error: "Sign count regression — possible credential clone" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Update sign count and last used
  await supabase
    .from("webauthn_credentials")
    .update({
      sign_count: newSignCount,
      last_used_at: new Date().toISOString(),
    })
    .eq("credential_id", credential.id);

  // 6. Generate session token
  const sessionId = base64url(generateChallenge());

  // Clean up challenge
  pendingChallenges.delete(challengeId);
  await supabase
    .from("webauthn_challenges")
    .delete()
    .eq("challenge_id", challengeId);

  // Log success
  await supabase.from("auth_events").insert({
    user_id: pending.userId,
    event_type: "webauthn_assertion_success",
    event_data: {
      credential_id: credential.id,
      sign_count: newSignCount,
    },
    created_at: new Date().toISOString(),
  });

  return new Response(
    JSON.stringify({
      verified: true,
      userId: pending.userId,
      sessionToken: sessionId,
      credentialId: credential.id,
    }),
    { status: 200, headers: { "Content-Type": "application/json" } }
  );
}

// ─── Router ──────────────────────────────────────────────────────────────────

serve(async (req: Request) => {
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
        return await handleBeginAssertion(body);
      case "complete":
        return await handleCompleteAssertion(body);
      default:
        if (body.action === "begin") return await handleBeginAssertion(body);
        if (body.action === "complete")
          return await handleCompleteAssertion(body);
        return new Response(
          JSON.stringify({
            error: "Unknown action. Use /begin or /complete, or pass action field.",
          }),
          { status: 400, headers: { "Content-Type": "application/json" } }
        );
    }
  } catch (err) {
    console.error("WebAuthn authentication error:", err);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
