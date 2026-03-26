// Authorization Endpoint for CardiacID OIDC Provider
// Initiates the CardiacID biometric verification flow
// Called by Entra ID when a user needs to satisfy the CardiacID EAM requirement
//
// Flow:
// 1. Entra ID redirects user here with client_id, redirect_uri, nonce
// 2. A pending session is created in BOTH in-memory store AND Supabase DB
// 3. The page embeds a session_id and a deep link (cardiacid://eam?session=<id>)
// 4. CardiacID app opens, reads session_id, verifies biometrics, POSTs result
// 5. App POST writes the auth_code to both in-memory store AND Supabase DB
// 6. Browser polls with { check_status: true, session_id } every 3 seconds
//    - Checks in-memory store first (fast path, same isolate)
//    - Falls back to Supabase DB (persistent path, cross-isolate)
// 7. On verified: browser redirects to Entra ID with ?code=<auth_code>
// 8. Entra ID exchanges code at /oidc-token for id_token
//
// Deploy: supabase functions deploy oidc-authorize

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ISSUER_URL = Deno.env.get("CARDIACID_ISSUER_URL") || "https://iufsxauhrnaunglfxtly.supabase.co/functions/v1";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

// 10-minute session window — must exceed Entra ID's EAM timeout
const SESSION_TTL_MS = 10 * 60 * 1000;

// ---------------------------------------------------------------------------
// In-memory stores (fast path for same-isolate lookups)
// Supabase DB is the durable fallback for cross-isolate and cross-restart cases
// ---------------------------------------------------------------------------

interface PendingSession {
  sessionId: string;
  clientId: string;
  redirectUri: string;
  state: string | null;
  nonce: string | null;
  expiresAt: number;
}

interface VerifiedSession {
  authCode: string;
  sessionId: string;
  clientId: string;
  redirectUri: string;
  state: string | null;
  userId: string;
  email: string;
  displayName: string;
  biometricConfidence: number;
  biometricMethod: string;
  nonce: string | null;
  createdAt: number;
}

// Keyed by session_id
const pendingSessions = new Map<string, PendingSession>();
// Keyed by auth_code (written by app POST, read by token endpoint and browser poll)
export const authorizationCodes = new Map<string, VerifiedSession>();

// ---------------------------------------------------------------------------

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return corsPreflightResponse();
  }

  if (req.method === "GET") {
    return handleAuthorizationGet(new URL(req.url));
  }

  if (req.method === "POST") {
    try {
      const body = await req.json() as Record<string, unknown>;
      if (body.check_status === true) {
        return handleStatusPoll(body);
      }
      return handleBiometricVerification(body);
    } catch (error) {
      console.error("Authorization POST error:", error);
      return jsonResponse({ error: "server_error" }, 500);
    }
  }

  return jsonResponse({ error: "method_not_allowed" }, 405);
});

// ---------------------------------------------------------------------------
// GET — Entra ID sends the user's browser here to begin EAM verification
// ---------------------------------------------------------------------------
async function handleAuthorizationGet(url: URL): Promise<Response> {
  const clientId = url.searchParams.get("client_id");
  const redirectUri = url.searchParams.get("redirect_uri");
  const state = url.searchParams.get("state");
  const nonce = url.searchParams.get("nonce");

  if (!clientId || !redirectUri) {
    return jsonResponse({
      error: "invalid_request",
      error_description: "Missing client_id or redirect_uri",
    }, 400);
  }

  const sessionId = crypto.randomUUID();
  const expiresAt = Date.now() + SESSION_TTL_MS;

  // --- In-memory store (fast path) ---
  pendingSessions.set(sessionId, { sessionId, clientId, redirectUri, state, nonce, expiresAt });

  // --- Supabase DB (durable path) ---
  if (SUPABASE_URL && SUPABASE_SERVICE_KEY) {
    try {
      const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
      await supabase.from("oidc_auth_sessions").insert({
        session_id: sessionId,
        client_id: clientId,
        redirect_uri: redirectUri,
        state,
        nonce,
        status: "pending",
        expires_at: new Date(expiresAt).toISOString(),
      });
    } catch (e) {
      // Non-fatal: in-memory path will still work for same-isolate exchanges
      console.warn("Failed to persist session to Supabase:", e);
    }
  }

  const deepLink = `cardiacid://eam?session=${sessionId}`;
  const authorizeEndpoint = `${ISSUER_URL}/oidc-authorize`;
  const page = generateAuthorizationPage(sessionId, deepLink, authorizeEndpoint);

  return new Response(page, {
    status: 200,
    headers: { "Content-Type": "text/html" },
  });
}

// ---------------------------------------------------------------------------
// POST — CardiacID app submits biometric verification result
// Body: { session_id, user_id, email, display_name, biometric_confidence,
//         biometric_method, access_token? }
// ---------------------------------------------------------------------------
async function handleBiometricVerification(body: Record<string, unknown>): Promise<Response> {
  const sessionId = body.session_id as string;
  const userId = body.user_id as string;
  const email = body.email as string;
  const displayName = body.display_name as string;
  const biometricConfidence = body.biometric_confidence as number;
  const biometricMethod = body.biometric_method as string;
  const accessToken = body.access_token as string;

  if (!sessionId) {
    return jsonResponse({ error: "invalid_request", error_description: "Missing session_id" }, 400);
  }

  if (!biometricConfidence || biometricConfidence < 0.70) {
    return jsonResponse({
      error: "insufficient_biometric",
      error_description: `Biometric confidence ${Math.round((biometricConfidence || 0) * 100)}% is below the 70% minimum`,
    }, 403);
  }

  // --- Resolve session: in-memory first, Supabase fallback ---
  let sessionData: PendingSession | null = null;
  const memSession = pendingSessions.get(sessionId);
  if (memSession && Date.now() < memSession.expiresAt) {
    sessionData = memSession;
  } else if (SUPABASE_URL && SUPABASE_SERVICE_KEY) {
    try {
      const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
      const { data } = await supabase
        .from("oidc_auth_sessions")
        .select("session_id, client_id, redirect_uri, state, nonce, expires_at, status")
        .eq("session_id", sessionId)
        .eq("status", "pending")
        .single();
      if (data && new Date(data.expires_at) > new Date()) {
        sessionData = {
          sessionId: data.session_id,
          clientId: data.client_id,
          redirectUri: data.redirect_uri,
          state: data.state,
          nonce: data.nonce,
          expiresAt: new Date(data.expires_at).getTime(),
        };
      }
    } catch (e) {
      console.warn("Supabase session lookup failed:", e);
    }
  }

  if (!sessionData) {
    return jsonResponse({
      error: "invalid_request",
      error_description: "Session not found, already used, or expired",
    }, 400);
  }

  // --- Optionally validate the EntraID access token against MS Graph ---
  if (accessToken) {
    try {
      const graphResponse = await fetch("https://graph.microsoft.com/v1.0/me", {
        headers: { Authorization: `Bearer ${accessToken}` },
      });
      if (!graphResponse.ok) {
        return jsonResponse({ error: "invalid_token", error_description: "EntraID token validation failed" }, 401);
      }
    } catch {
      console.warn("EntraID token validation failed, proceeding with biometric only");
    }
  }

  // --- Generate auth code ---
  const authCode = crypto.randomUUID();
  const now = Date.now();
  const verifiedSession: VerifiedSession = {
    authCode,
    sessionId,
    clientId: sessionData.clientId,
    redirectUri: sessionData.redirectUri,
    state: sessionData.state,
    userId: userId || crypto.randomUUID(),
    email: email || "",
    displayName: displayName || "",
    biometricConfidence,
    biometricMethod: biometricMethod || "hybrid",
    nonce: sessionData.nonce,
    createdAt: now,
  };

  // --- Dual-write: in-memory + Supabase ---
  authorizationCodes.set(authCode, verifiedSession);
  pendingSessions.delete(sessionId); // session consumed, move to verified

  if (SUPABASE_URL && SUPABASE_SERVICE_KEY) {
    try {
      const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
      await supabase.from("oidc_auth_sessions").update({
        auth_code: authCode,
        user_id: verifiedSession.userId,
        email: verifiedSession.email,
        display_name: verifiedSession.displayName,
        biometric_confidence: biometricConfidence,
        biometric_method: verifiedSession.biometricMethod,
        status: "verified",
      }).eq("session_id", sessionId);

      await supabase.from("auth_events").insert({
        user_id: verifiedSession.userId,
        event_type: "eam_authorization",
        authentication_method: verifiedSession.biometricMethod,
        success: true,
        confidence_score: biometricConfidence,
        metadata: {
          client_id: sessionData.clientId,
          nonce: sessionData.nonce,
          method: "external_authentication_method",
        },
      });
    } catch (e) {
      console.warn("Failed to write verified session to Supabase:", e);
    }
  }

  console.log(`OIDC: Session ${sessionId} verified — code issued, confidence ${Math.round(biometricConfidence * 100)}%`);
  return jsonResponse({ success: true });
}

// ---------------------------------------------------------------------------
// POST { check_status: true, session_id } — Browser polls for verification
// ---------------------------------------------------------------------------
async function handleStatusPoll(body: Record<string, unknown>): Promise<Response> {
  const sessionId = body.session_id as string;
  if (!sessionId) {
    return jsonResponse({ error: "invalid_request", error_description: "Missing session_id" }, 400);
  }

  // Check in-memory verified codes first (same isolate as the app POST)
  for (const [code, session] of authorizationCodes) {
    if (session.sessionId === sessionId) {
      // Code found in-memory — already verified
      if (Date.now() - session.createdAt > SESSION_TTL_MS) {
        authorizationCodes.delete(code);
        return jsonResponse({ status: "expired" });
      }
      const redirectUrl = buildRedirectUrl(session.redirectUri, code, session.state);
      return jsonResponse({ status: "verified", redirect_uri: redirectUrl });
    }
  }

  // Supabase fallback (different isolate or restart)
  if (SUPABASE_URL && SUPABASE_SERVICE_KEY) {
    try {
      const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
      const { data } = await supabase
        .from("oidc_auth_sessions")
        .select("status, auth_code, redirect_uri, state, expires_at")
        .eq("session_id", sessionId)
        .single();

      if (!data) {
        return jsonResponse({ status: "not_found" });
      }
      if (new Date(data.expires_at) < new Date()) {
        return jsonResponse({ status: "expired" });
      }
      if (data.status === "verified" && data.auth_code) {
        const redirectUrl = buildRedirectUrl(data.redirect_uri, data.auth_code, data.state);
        return jsonResponse({ status: "verified", redirect_uri: redirectUrl });
      }
      return jsonResponse({ status: data.status });
    } catch (e) {
      console.warn("Supabase status poll failed:", e);
    }
  }

  // In-memory still shows pending (Supabase unavailable and no verification yet)
  const memPending = pendingSessions.get(sessionId);
  if (memPending) {
    if (Date.now() >= memPending.expiresAt) {
      pendingSessions.delete(sessionId);
      return jsonResponse({ status: "expired" });
    }
    return jsonResponse({ status: "pending" });
  }

  return jsonResponse({ status: "not_found" });
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

function buildRedirectUrl(redirectUri: string, code: string, state: string | null): string {
  const url = new URL(redirectUri);
  url.searchParams.set("code", code);
  if (state) url.searchParams.set("state", state);
  return url.toString();
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
  });
}

function corsPreflightResponse(): Response {
  return new Response(null, {
    status: 204,
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
    },
  });
}

function generateAuthorizationPage(
  sessionId: string,
  deepLink: string,
  authorizeEndpoint: string
): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>CardiacID Verification</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
           display: flex; justify-content: center; align-items: center;
           min-height: 100vh; margin: 0; background: #f5f5f5; }
    .card { background: white; border-radius: 16px; padding: 40px;
            max-width: 400px; width: 100%; text-align: center;
            box-shadow: 0 4px 24px rgba(0,0,0,0.1); }
    .heartbeat { font-size: 64px; animation: pulse 1.5s ease infinite; }
    @keyframes pulse { 0%,100% { transform: scale(1); } 50% { transform: scale(1.1); } }
    h1 { color: #333; margin: 16px 0 8px; }
    p { color: #666; line-height: 1.5; }
    .status { padding: 12px; border-radius: 8px; margin: 16px 0; font-weight: 500; }
    .waiting  { background: #fff3cd; color: #856404; }
    .verified { background: #d4edda; color: #155724; }
    .error    { background: #f8d7da; color: #721c24; }
    .open-btn { display: inline-block; margin: 16px 0; padding: 12px 28px;
                background: #0078d4; color: white; border-radius: 8px;
                text-decoration: none; font-weight: 600; font-size: 15px; }
    .session-box { font-family: monospace; font-size: 13px; color: #555;
                   background: #f0f0f0; padding: 8px 14px; border-radius: 6px;
                   display: inline-block; letter-spacing: 0.5px; }
    .hint { font-size: 12px; color: #999; margin-top: 20px; }
  </style>
</head>
<body>
  <div class="card">
    <div class="heartbeat">&#x2764;&#xFE0F;</div>
    <h1>CardiacID Verification</h1>
    <p>Open the CardiacID app on your iPhone to verify your identity with your heartbeat.</p>
    <a href="${deepLink}" class="open-btn">Open CardiacID App</a>
    <p style="margin-top: 12px; font-size: 13px; color: #888;">Or enter this session code in the app:</p>
    <div class="session-box">${sessionId}</div>
    <div id="status" class="status waiting">Waiting for biometric verification...</div>
    <p class="hint">This verification is required by your organization's Conditional Access policy.</p>
  </div>
  <script>
    const SESSION_ID = '${sessionId}';
    const ENDPOINT   = '${authorizeEndpoint}';
    let attempts = 0;
    const MAX_ATTEMPTS = 200; // ~10 minutes at 3s interval

    const checkInterval = setInterval(async () => {
      attempts++;
      if (attempts > MAX_ATTEMPTS) {
        clearInterval(checkInterval);
        document.getElementById('status').className = 'status error';
        document.getElementById('status').textContent = 'Session expired. Please try again.';
        return;
      }
      try {
        const res  = await fetch(ENDPOINT, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ check_status: true, session_id: SESSION_ID }),
        });
        const data = await res.json();
        if (data.status === 'verified' && data.redirect_uri) {
          clearInterval(checkInterval);
          document.getElementById('status').className = 'status verified';
          document.getElementById('status').textContent = 'Verified! Redirecting\u2026';
          window.location.href = data.redirect_uri;
        } else if (data.status === 'expired' || data.status === 'not_found') {
          clearInterval(checkInterval);
          document.getElementById('status').className = 'status error';
          document.getElementById('status').textContent = 'Session expired. Please try again.';
        }
        // 'pending' — keep polling
      } catch (_) { /* network blip — keep polling */ }
    }, 3000);
  </script>
</body>
</html>`;
}
