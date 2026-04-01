// OIDC Discovery Endpoint for CardiacID External Authentication Method (EAM)
// Serves /.well-known/openid-configuration as required by Microsoft Entra ID
// for registering CardiacID as an External Authentication Method
//
// Deploy: supabase functions deploy oidc-discovery
// URL: https://<project-ref>.supabase.co/functions/v1/oidc-discovery

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

const ISSUER_URL = Deno.env.get("CARDIACID_ISSUER_URL") || "https://iufsxauhrnaunglfxtly.supabase.co/functions/v1";

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
      },
    });
  }

  // OpenID Connect Discovery Document
  // Required fields for Entra ID EAM registration:
  // - issuer, authorization_endpoint, token_endpoint, jwks_uri
  // - id_token_signing_alg_values_supported
  // - response_types_supported, subject_types_supported
  const discoveryDocument = {
    issuer: ISSUER_URL,
    authorization_endpoint: `${ISSUER_URL}/oidc-authorize`,
    token_endpoint: `${ISSUER_URL}/oidc-token`,
    jwks_uri: `${ISSUER_URL}/oidc-jwks`,
    userinfo_endpoint: `${ISSUER_URL}/oidc-userinfo`,

    // Supported specs
    response_types_supported: ["code", "id_token", "code id_token"],
    subject_types_supported: ["public"],
    id_token_signing_alg_values_supported: ["ES256"], // P-256 ECDSA (matches WatchFIDO2Service)
    token_endpoint_auth_methods_supported: ["client_secret_post", "client_secret_basic"],
    claims_supported: [
      "sub",
      "iss",
      "aud",
      "exp",
      "iat",
      "nonce",
      "email",
      "name",
      "preferred_username",
      // CardiacID-specific claims
      "cardiacid_confidence",
      "cardiacid_method",
      "cardiacid_device_id",
      "cardiacid_enrolled",
      "cardiacid_last_ecg",
    ],
    scopes_supported: ["openid", "profile", "email", "cardiacid.verify"],
    grant_types_supported: ["authorization_code", "urn:ietf:params:oauth:grant-type:device_code"],
    code_challenge_methods_supported: ["S256"],

    // CardiacID-specific metadata
    cardiacid_version: "0.8",
    cardiacid_biometric_methods: ["ecg", "ppg", "hybrid"],
    cardiacid_minimum_confidence: 0.70,
    cardiacid_ecg_accuracy_range: "96-99%",
    cardiacid_ppg_accuracy_range: "85-92%",
  };

  return new Response(JSON.stringify(discoveryDocument, null, 2), {
    status: 200,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Cache-Control": "public, max-age=3600", // Cache for 1 hour
    },
  });
});
