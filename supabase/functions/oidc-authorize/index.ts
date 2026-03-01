// Authorization Endpoint for CardiacID OIDC Provider
// Initiates the CardiacID biometric verification flow
// Called by Entra ID when a user needs to satisfy the CardiacID EAM requirement
//
// Flow:
// 1. Entra ID redirects user to this endpoint with client_id, redirect_uri, nonce
// 2. This endpoint checks if the user has an active CardiacID session (biometric verified)
// 3. If verified: issues authorization code and redirects back to Entra ID
// 4. If not verified: shows a page instructing the user to verify on their CardiacID app
// 5. Entra ID exchanges the code for id_token at the token endpoint
//
// Deploy: supabase functions deploy oidc-authorize

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ISSUER_URL = Deno.env.get("CARDIACID_ISSUER_URL") || "https://your-project.supabase.co/functions/v1";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

// Shared auth code store (in production, use Supabase DB)
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

serve(async (req: Request) => {
  const url = new URL(req.url);

  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
      },
    });
  }

  // Extract OIDC authorization parameters
  const clientId = url.searchParams.get("client_id");
  const redirectUri = url.searchParams.get("redirect_uri");
  const responseType = url.searchParams.get("response_type") || "code";
  const scope = url.searchParams.get("scope") || "openid";
  const state = url.searchParams.get("state");
  const nonce = url.searchParams.get("nonce");

  // POST handling: CardiacID app submits biometric verification result
  if (req.method === "POST") {
    try {
      const body = await req.json();
      return await handleBiometricVerification(body, clientId, redirectUri, state, nonce);
    } catch (error) {
      console.error("Authorization POST error:", error);
      return new Response(JSON.stringify({ error: "server_error" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }
  }

  // GET handling: Entra ID redirects user here
  if (!clientId || !redirectUri) {
    return new Response(
      JSON.stringify({
        error: "invalid_request",
        error_description: "Missing client_id or redirect_uri",
      }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Return a page that:
  // 1. Checks for an active CardiacID biometric session
  // 2. If found, auto-submits the verification
  // 3. If not, shows instructions to verify with CardiacID app
  const authorizationPage = generateAuthorizationPage(
    clientId,
    redirectUri,
    state,
    nonce,
    `${ISSUER_URL}/oidc-authorize`
  );

  return new Response(authorizationPage, {
    status: 200,
    headers: { "Content-Type": "text/html" },
  });
});

async function handleBiometricVerification(
  body: Record<string, unknown>,
  clientId: string | null,
  redirectUri: string | null,
  state: string | null,
  nonce: string | null
): Promise<Response> {
  const userId = body.user_id as string;
  const email = body.email as string;
  const displayName = body.display_name as string;
  const biometricConfidence = body.biometric_confidence as number;
  const biometricMethod = body.biometric_method as string;
  const accessToken = body.access_token as string;

  // Validate biometric confidence
  if (!biometricConfidence || biometricConfidence < 0.70) {
    return new Response(
      JSON.stringify({
        error: "insufficient_biometric",
        error_description: `Biometric confidence ${Math.round((biometricConfidence || 0) * 100)}% is below the 70% minimum`,
      }),
      { status: 403, headers: { "Content-Type": "application/json" } }
    );
  }

  // Validate the user's EntraID token if provided
  if (accessToken) {
    try {
      const graphResponse = await fetch("https://graph.microsoft.com/v1.0/me", {
        headers: { Authorization: `Bearer ${accessToken}` },
      });
      if (!graphResponse.ok) {
        return new Response(
          JSON.stringify({ error: "invalid_token", error_description: "EntraID token validation failed" }),
          { status: 401, headers: { "Content-Type": "application/json" } }
        );
      }
    } catch {
      // Token validation failed, continue without it
      console.warn("EntraID token validation failed, proceeding with biometric only");
    }
  }

  // Generate authorization code
  const code = crypto.randomUUID();
  authorizationCodes.set(code, {
    userId: userId || crypto.randomUUID(),
    email: email || "",
    displayName: displayName || "",
    clientId: clientId || "",
    redirectUri: redirectUri || "",
    nonce: nonce || undefined,
    biometricConfidence,
    biometricMethod: biometricMethod || "hybrid",
    createdAt: Date.now(),
  });

  // Log the authentication event
  if (SUPABASE_URL && SUPABASE_SERVICE_KEY) {
    try {
      const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
      await supabase.from("auth_events").insert({
        user_id: userId,
        event_type: "eam_authorization",
        authentication_method: biometricMethod || "hybrid",
        success: true,
        confidence_score: biometricConfidence,
        metadata: JSON.stringify({
          client_id: clientId,
          nonce,
          method: "external_authentication_method",
        }),
      });
    } catch (e) {
      console.warn("Failed to log auth event:", e);
    }
  }

  // Build redirect URL with authorization code
  if (redirectUri) {
    const redirectUrl = new URL(redirectUri);
    redirectUrl.searchParams.set("code", code);
    if (state) redirectUrl.searchParams.set("state", state);

    return new Response(JSON.stringify({ redirect_uri: redirectUrl.toString(), code }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ code }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

function generateAuthorizationPage(
  clientId: string,
  redirectUri: string,
  state: string | null,
  nonce: string | null,
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
            max-width: 400px; text-align: center; box-shadow: 0 4px 24px rgba(0,0,0,0.1); }
    .heartbeat { font-size: 64px; animation: pulse 1.5s ease infinite; }
    @keyframes pulse { 0%,100% { transform: scale(1); } 50% { transform: scale(1.1); } }
    h1 { color: #333; margin: 16px 0 8px; }
    p { color: #666; line-height: 1.5; }
    .status { padding: 12px; border-radius: 8px; margin: 16px 0; }
    .waiting { background: #fff3cd; color: #856404; }
    .verified { background: #d4edda; color: #155724; }
    .error { background: #f8d7da; color: #721c24; }
  </style>
</head>
<body>
  <div class="card">
    <div class="heartbeat">&#x2764;&#xFE0F;</div>
    <h1>CardiacID Verification</h1>
    <p>Open the CardiacID app on your Apple Watch to verify your identity with your heartbeat.</p>
    <div id="status" class="status waiting">
      Waiting for biometric verification...
    </div>
    <p style="font-size: 12px; color: #999;">
      This verification is requested by your organization's security policy.
    </p>
  </div>
  <script>
    // Poll for biometric verification from CardiacID app
    // The app will POST to this endpoint when verification is complete
    const params = new URLSearchParams(window.location.search);
    const checkInterval = setInterval(async () => {
      try {
        const response = await fetch(window.location.href, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            check_status: true,
            client_id: '${clientId}',
          })
        });
        const data = await response.json();
        if (data.redirect_uri) {
          clearInterval(checkInterval);
          document.getElementById('status').className = 'status verified';
          document.getElementById('status').textContent = 'Verified! Redirecting...';
          window.location.href = data.redirect_uri;
        }
      } catch (e) { /* keep polling */ }
    }, 3000);
  </script>
</body>
</html>`;
}
