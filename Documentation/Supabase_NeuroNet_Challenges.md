# Supabase Challenges for the CardiacID NeuroNet

## Architecture Decision Record — Backend Limitations and Mitigations

**Version:** 1.0  
**Date:** April 2026  
**Author:** Argos Advanced Solutions — HeartID Engineering  
**Context:** CardiacID uses Supabase as its backend platform. This document identifies where Supabase's architecture creates friction with the NeuroNet biometric pipeline and documents the engineering decisions made to work within those constraints.

---

## 1. The Core Tension

The NeuroNet is a **compute-intensive, latency-sensitive, security-critical** biometric pipeline. Supabase is a **database-first, stateless, multi-tenant** platform designed for CRUD applications. These are fundamentally different workloads.

| NeuroNet Needs | Supabase Provides | Gap |
|----------------|-------------------|-----|
| Sub-100ms biometric decision | Edge Functions with ~50ms cold start, ~200ms warm | Marginal |
| Stateful session tracking | Stateless isolates + Postgres | Requires dual-store pattern |
| GPU/SIMD for signal processing | Deno runtime (V8 JavaScript) | No hardware acceleration |
| Persistent in-memory models | Isolates recycle unpredictably | Models cannot be cached |
| Cryptographic key persistence | Secrets survive restart; isolate memory does not | Solved with secrets |
| HIPAA/FedRAMP compliance | SOC 2 Type II only | Gap for DoD deployment |
| Binary signal data (ECG waveforms) | PostgREST optimized for JSON | bytea encoding overhead |

---

## 2. Challenge 1: No Server-Side Biometric Computation

### The Problem

The NeuroNet's most compute-intensive operations — Pan-Tompkins QRS detection, 136-feature extraction, GMM classification, Haar wavelet decomposition — require:

- **Accelerate framework** (vDSP, BLAS) for vectorized math
- **Float64 array processing** on thousands of ECG samples
- **Sub-50ms latency** for real-time authentication

Supabase Edge Functions run in **Deno** (V8 JavaScript engine). Deno has no access to:
- Apple's Accelerate framework
- GPU compute
- SIMD intrinsics
- Native FFT libraries
- Pre-trained model weights in memory

### Current Mitigation

**All NeuroNet computation runs on the Apple Watch.** The Watch has:
- Apple S9 SoC with Neural Engine
- Native Accelerate framework access
- Direct HealthKit sensor access
- Sub-125ms total pipeline latency

Supabase receives only the **output** — a confidence score, method label, and liveness metadata — not the raw ECG signal. The `verify-heart` edge function performs **validation**, not **computation**:

```
Watch: Raw ECG → Pan-Tompkins → 136 features → GMM → confidence=0.96
  ↓
iPhone: Packages confidence + metadata → POST /verify-heart
  ↓  
Supabase: Validates liveness (7 checks), cross-validates signal quality,
          applies PPG ceiling, logs to auth_events → returns verified/denied
```

### Residual Risk

The backend **trusts the Watch's reported confidence score**. The `verify-heart` function applies caps and cross-validation (e.g., PPG confidence cannot exceed 0.92, low-SNR ECG capped at 0.70), but it cannot independently verify the biometric match because it never sees the raw signal.

This is architecturally analogous to how Apple Pay works: the Secure Element performs the cryptographic operation on-device, and the server validates the signed assertion without seeing the private key. But it means a compromised Watch could in theory report a fake confidence score. The device-binding signature (Secure Enclave P-256) mitigates this — a fake score would require compromising both the Watch biometric engine and the iPhone's Secure Enclave.

### What Would Fix This

A dedicated compute backend (Azure Functions with Python + NumPy, or a bare-metal server with ONNX Runtime) could re-run the GMM classification server-side against stored enrollment templates. This would provide **independent server-side verification** at the cost of:
- Transmitting ~2KB of feature vectors per authentication (privacy concern)
- Adding ~200ms network + compute latency
- Requiring a non-Supabase compute layer

---

## 3. Challenge 2: Stateless Isolates and the Dual-Store Problem

### The Problem

The OIDC EAM flow requires three steps across separate HTTP requests:

1. **GET /oidc-authorize** — Browser arrives, session is created
2. **POST /oidc-authorize** — iPhone app posts biometric result
3. **POST /oidc-authorize** — Browser polls for status
4. **POST /oidc-token** — Entra ID exchanges auth code for JWT

Supabase Edge Functions are **stateless** — each request may land on a different isolate. An `in-memory Map` written in step 2 may not be visible in step 3 or step 4 if they hit a different isolate.

### Current Mitigation: Dual-Store Pattern

Every session write goes to **both** an in-memory `Map` (fast path) and the **Postgres `oidc_auth_sessions` table** (durable path). Every read checks memory first, then falls back to the database:

```typescript
// Write: dual-store
pendingSessions.set(sessionId, sessionData);          // Memory (fast)
await supabase.from("oidc_auth_sessions").insert(...); // Postgres (durable)

// Read: memory-first, DB fallback
let session = pendingSessions.get(sessionId);
if (!session) {
  const { data } = await supabase.from("oidc_auth_sessions")
    .select("*").eq("session_id", sessionId).single();
  session = data;
}
```

### Performance Impact

| Path | Latency | When It Happens |
|------|---------|-----------------|
| Memory hit (same isolate) | < 1 ms | Steps 2→3 within ~30 seconds |
| Postgres fallback | 15–40 ms | Steps across different isolates or after isolate recycle |

The 15–40ms Postgres penalty is acceptable for the OIDC flow (which has a 3-second browser polling interval), but it means the system cannot guarantee sub-5ms session lookups — a constraint that would matter for high-frequency biometric streaming.

### What Would Fix This

- **Redis/Upstash** as a shared in-memory cache between isolates (Supabase does not natively offer this)
- **Sticky sessions** (route all requests for a session_id to the same isolate) — not available in Supabase Edge Functions
- **Durable Objects** (Cloudflare-style stateful edge compute) — not available in Supabase

---

## 4. Challenge 3: No Background Processing / Cron Jobs

### The Problem

The NeuroNet's continuous authentication model requires periodic operations:

- **Expired challenge cleanup** — `heartid_passkey_challenges` accumulates rows
- **Session garbage collection** — `oidc_auth_sessions` with status "expired"
- **Audit log rotation** — `auth_events` grows unbounded
- **Template drift analysis** — Comparing recent authentication patterns against enrollment baselines

Supabase Edge Functions are **request-driven** — they cannot run on a schedule without an external trigger.

### Current Mitigation

The `delete_expired_challenges()` Postgres function exists but requires `pg_cron` to invoke it:

```sql
-- This function exists but is NOT automatically scheduled:
CREATE OR REPLACE FUNCTION delete_expired_challenges() RETURNS void AS $$
BEGIN
  DELETE FROM heartid_passkey_challenges
  WHERE expires_at < now() OR (used = true AND created_at < now() - interval '1 hour');
END;
$$;
```

Supabase's free and Pro tiers include the `pg_cron` extension, but it must be manually enabled and the schedule must be manually created via the SQL editor:

```sql
SELECT cron.schedule('cleanup-challenges', '*/15 * * * *',
  $$SELECT delete_expired_challenges()$$);
```

### What Would Fix This

- **Enable `pg_cron`** in the Supabase dashboard and register cleanup schedules
- For more complex background work (template drift analysis), an external scheduler (GitHub Actions, Azure Functions timer trigger) calling a Supabase Edge Function on a cron schedule

---

## 5. Challenge 4: Ephemeral Signing Keys

### The Problem

The OIDC token endpoint signs JWTs with an ES256 (P-256 ECDSA) private key. Edge Function isolates have no persistent filesystem — a key generated in one isolate is lost when that isolate recycles.

### What Happened

Before the signing key was set as a Supabase secret, every isolate cold-start generated a **new ephemeral key pair**. JWTs signed by one isolate could not be verified against the JWKS published by a different isolate. This broke the Entra ID token validation flow silently — Entra ID would fetch the JWKS, get the current isolate's public key, but the JWT was signed by a previous isolate's private key.

### Current Mitigation

The private key is now stored as a Supabase Edge Function secret (`CARDIACID_SIGNING_PRIVATE_KEY_JWK`). Every isolate loads the same key from the environment on startup:

```typescript
const stored = Deno.env.get("CARDIACID_SIGNING_PRIVATE_KEY_JWK");
const privateKeyJWK = JSON.parse(stored);
const privateKey = await crypto.subtle.importKey("jwk", privateKeyJWK, ...);
```

### Residual Risk

- The secret is stored in Supabase's infrastructure, not in a Hardware Security Module (HSM). For DoD deployment, FIPS 140-2 Level 3 requires keys to be stored in tamper-evident hardware.
- Key rotation requires manually updating the secret and redeploying functions.
- There is no automated key rotation mechanism.

### What Would Fix This

- **Azure Key Vault** or **AWS CloudHSM** for FIPS 140-2 Level 3 key storage
- A key rotation workflow that publishes both old and new keys in JWKS during the transition period
- Supabase Vault (currently in beta) may eventually provide HSM-backed secret storage

---

## 6. Challenge 5: No Native Binary Data Support in PostgREST

### The Problem

Cardiac biometric data is inherently binary:
- ECG waveforms: arrays of Float64 samples
- Biometric templates: encrypted binary blobs (AES-256-GCM sealed boxes)
- WebAuthn credentials: CBOR-encoded attestation objects
- Passkey challenge bytes: 32 bytes of cryptographic randomness

PostgREST (Supabase's REST layer) is optimized for JSON. Storing and retrieving binary data requires encoding overhead:

| Data Type | Storage Format | Encoding Overhead |
|-----------|---------------|-------------------|
| `bytea` | Hex-encoded (`\xDEADBEEF`) | 2x size |
| Base64 in `text` | Base64 string | 1.33x size |
| `jsonb` array | `[0.123, 0.456, ...]` | 8–10x size for Float64 arrays |

### Current Mitigation

- Biometric templates are **never stored in Supabase** — they live in the device Keychain (AES-256-GCM encrypted, `kSecAttrSynchronizable: false`)
- WebAuthn credentials use `bytea` columns (hex encoding, 2x overhead)
- The `verify-heart` endpoint receives cardiac signatures as JSON (readable but verbose)
- Raw ECG waveforms never leave the device

### Impact

The 2x hex encoding overhead for `bytea` is acceptable for credential storage (public keys are ~65 bytes, so 130 bytes hex). But it would be unacceptable for storing raw ECG waveforms (a 10-second recording at 512 Hz = 5,120 Float64 samples = 40,960 bytes raw → 81,920 bytes hex-encoded), which is why biometric template storage remains on-device.

### What Would Fix This

- **Supabase Storage** (S3-compatible) for large binary blobs, with PostgREST storing only a reference
- Direct Postgres binary protocol access (bypassing PostgREST) via a custom server
- Protocol Buffers or MessagePack encoding for the `verify-heart` payload instead of JSON

---

## 7. Challenge 6: Row-Level Security Cannot Express Biometric Policies

### The Problem

CardiacID's access control policies are **biometric-conditioned**: "allow access to this resource if the user's cardiac confidence is >= 0.85 AND the reading is < 5 minutes old." RLS policies in Postgres can only reference:

- `auth.uid()` — the authenticated user's ID
- `auth.role()` — `authenticated`, `anon`, or `service_role`
- Column values in the row being accessed

RLS cannot reference:
- The user's current biometric confidence score
- The freshness of their last HeartID verification
- The method of their last authentication (ECG vs. PPG)
- Whether their Watch is currently on their wrist

### Current Mitigation

Biometric policy enforcement happens **in the application layer** (Swift) and in **Edge Functions** (TypeScript), not in Postgres RLS:

```
Swift (iPhone):
  HeartAuthPolicyEngine.evaluate(result, for: .unlockProtectedFile)
  → checks confidence >= 0.75
  → checks SessionTrustManager.satisfiesTrust()
  → if allowed → proceeds to Supabase query

Edge Function (verify-heart):
  → checks liveness score >= 0.50
  → checks confidence >= 0.70
  → if passed → logs to auth_events
```

RLS handles only the coarse-grained access control (service_role for writes, authenticated users can read their own data).

### Residual Risk

A compromised client that bypasses the Swift policy engine could make direct PostgREST queries to read data from tables where the RLS policy only checks `auth.uid()`. The data itself is not biometric-gated at the database level.

### What Would Fix This

- A **Postgres function** that checks a `session_trust` table before allowing reads — e.g., `CREATE POLICY ... USING (EXISTS (SELECT 1 FROM session_trust WHERE user_id = auth.uid() AND confidence >= 0.75 AND verified_at > now() - interval '5 minutes'))`
- This would require the `verify-heart` endpoint to write a session trust row on each successful verification
- Custom RPC functions (Supabase supports `rpc()` calls to Postgres functions) that embed biometric checks

---

## 8. Challenge 7: Compliance Gap — SOC 2 vs. FedRAMP

### The Problem

Supabase holds **SOC 2 Type II** certification. DoD and federal government deployments require **FedRAMP** authorization (Moderate or High impact level). These are different certifications:

| Requirement | SOC 2 Type II | FedRAMP Moderate |
|-------------|---------------|-----------------|
| Data residency | No requirement | US-only data centers |
| Encryption at rest | Required | FIPS 140-2 validated modules |
| Key management | Provider-managed | Customer-managed or HSM |
| Penetration testing | Annual | Continuous monitoring |
| Incident response | 72-hour notification | 1-hour notification (US-CERT) |
| Personnel security | Background checks | Federal background investigation |
| Audit logging | SOC 2 controls | NIST SP 800-53 (all 325+ controls) |

### Current Mitigation

- Supabase is hosted on **AWS us-west-2** (Oregon) — US data center
- All biometric templates stay on-device (never in Supabase)
- The signing key is the only cryptographic material in Supabase
- Audit logs in `auth_events` contain metadata only (confidence scores, methods), never raw biometric data

### What Would Fix This for DoD

- **Supabase Enterprise** with a dedicated instance (not multi-tenant) in a FedRAMP-authorized AWS region (GovCloud)
- Alternatively, migrate the backend to **Azure Government** (FedRAMP High authorized) using Azure Functions + Azure Database for PostgreSQL
- The Supabase Edge Functions could be replaced with **Azure Functions** without changing the iOS client code — the client calls REST endpoints with the same JSON payloads regardless of the backend implementation

---

## 9. Challenge 8: Edge Function Cold Start Latency

### The Problem

Supabase Edge Functions run on Deno Deploy. Each function has:
- **Cold start:** ~50–150ms (first request after isolate recycle)
- **Warm response:** ~10–30ms (subsequent requests on the same isolate)

The OIDC EAM flow has a 3-second browser polling interval, so cold starts are invisible. But the `verify-heart` endpoint is called in the critical authentication path — the user is waiting on their iPhone for the result.

### Measured Latency

| Endpoint | Cold Start | Warm | Acceptable? |
|----------|-----------|------|-------------|
| `verify-heart` | ~120ms | ~25ms | Yes — under 200ms target |
| `oidc-authorize` (POST) | ~100ms | ~20ms | Yes — browser polls every 3s |
| `oidc-token` | ~130ms | ~30ms | Yes — Entra ID has 30s timeout |
| `webauthn-register` | ~150ms | ~35ms | Yes — user is waiting for passkey UI |

### Current Mitigation

None needed — current latencies are within acceptable bounds. The 120ms worst-case `verify-heart` cold start plus ~80ms network round-trip = ~200ms total, which is within the 3-second perceived-time budget for a biometric authentication flow.

### When This Becomes a Problem

If CardiacID moves to **continuous server-side verification** (streaming biometric data for real-time monitoring), the cold-start variability would be unacceptable. That workload requires a persistent connection (WebSocket) to a stateful server — which Supabase Realtime could partially address, but not for compute-intensive biometric processing.

---

## 10. Summary: What Supabase Does Well vs. Where It Falls Short

### Supabase Strengths for CardiacID

| Strength | How CardiacID Uses It |
|----------|----------------------|
| **Postgres + RLS** | 8 tables with row-level security for multi-tenant audit logging |
| **Edge Functions** | 7 serverless endpoints (OIDC, verify-heart, WebAuthn) |
| **Auth** | Supabase Auth for user registration + JWT issuance |
| **Instant API** | PostgREST auto-generates REST endpoints for all tables |
| **Secrets management** | Stores OIDC signing key, RP configuration |
| **Free tier** | Sufficient for pilot (50,000 monthly active users, 500MB database) |

### Supabase Limitations for CardiacID

| Limitation | Severity | Mitigation |
|------------|----------|------------|
| No server-side biometric compute | **High** | All NeuroNet runs on-device; server validates, not computes |
| Stateless isolates | **Medium** | Dual-store pattern (memory + Postgres) |
| No FedRAMP certification | **High** (DoD only) | Migrate to Azure Government for production |
| No HSM key storage | **Medium** | Acceptable for pilot; Azure Key Vault for production |
| No native binary data | **Low** | Templates on-device; credentials use bytea hex encoding |
| No biometric-aware RLS | **Medium** | Policy enforcement in Swift + Edge Functions |
| No background cron (without setup) | **Low** | pg_cron available but requires manual enablement |
| Cold start latency | **Low** | ~120ms worst case — within acceptable bounds |

### Recommended Migration Path for DoD Production

```
PILOT (Current)                    PRODUCTION (DoD)
─────────────────                  ─────────────────
Supabase Edge Functions    →→→     Azure Functions (FedRAMP High)
Supabase Postgres          →→→     Azure Database for PostgreSQL
Supabase Secrets           →→→     Azure Key Vault (FIPS 140-2 L3)
Supabase Auth              →→→     Microsoft Entra ID (native)
PostgREST (JSON)           →→→     Custom API (Protobuf optional)

NO CHANGES NEEDED:
  - iOS client code (same REST endpoints)
  - Watch NeuroNet (runs entirely on-device)
  - OIDC protocol (same discovery + token endpoints)
  - WebAuthn protocol (same register/authenticate flow)
```

The iOS app calls REST endpoints — it does not care whether those endpoints are Supabase Edge Functions or Azure Functions. The migration is entirely server-side.

---

*This document is produced by Argos Advanced Solutions for the CardiacID / HeartID biometric authentication platform.*
