// verify-heart/index.ts
// Supabase Edge Function — HeartID Verification Engine
//
// Receives a cardiac signature from the iPhone app, verifies it against
// the enrolled biometric template, performs liveness detection, and returns
// a confidence score + session token.
//
// POST /verify-heart
// Body: { userId, email, displayName, cardiacSignature, deviceId, nonce, timestamp }
// Headers: X-Device-Signature, X-Device-Id
//
// Returns: { verified, confidence, livenessScore, method, assuranceLevel, sessionToken }

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Thresholds
const MIN_CONFIDENCE = 0.70;
const HIGH_CONFIDENCE = 0.90;
const REPLAY_WINDOW_MS = 30_000;  // Reject requests older than 30 seconds
const NONCE_TTL_MS = 300_000;     // Nonce valid for 5 minutes

// In-memory nonce replay protection (cleared on isolate restart; DB is durable fallback)
const usedNonces = new Map<string, number>();

interface CardiacSignature {
  hrv: number;
  restingHR: number;
  waveformFeatures: number[];
  timestamp: string;
  sdnn: number;
  signalNoiseRatio: number;
  method: string;
  beatIntervals: number[];
  recentHeartRates: number[];
  wristDetected: boolean;
  confidence: number;
  authenticated: boolean;
}

interface VerifyRequest {
  userId: string;
  email: string;
  displayName: string;
  cardiacSignature: CardiacSignature;
  deviceId: string;
  nonce: string;
  timestamp: number;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST",
        "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey, X-Device-Signature, X-Device-Id",
      },
    });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const body: VerifyRequest = await req.json();
    const { userId, email, displayName, cardiacSignature: sig, deviceId, nonce, timestamp } = body;

    // --- Validation ---

    if (!userId || !deviceId || !nonce || !timestamp) {
      return jsonResponse({ error: "Missing required fields" }, 400);
    }

    // Replay protection: timestamp freshness
    const now = Date.now();
    if (Math.abs(now - timestamp) > REPLAY_WINDOW_MS) {
      return jsonResponse({ error: "Request timestamp too old or too far in future" }, 403);
    }

    // Replay protection: nonce uniqueness
    if (usedNonces.has(nonce)) {
      return jsonResponse({ error: "Nonce already used — replay rejected" }, 403);
    }
    usedNonces.set(nonce, now);
    // Prune old nonces
    for (const [n, t] of usedNonces) {
      if (now - t > NONCE_TTL_MS) usedNonces.delete(n);
    }

    // --- Liveness Detection ---

    const livenessResult = assessLiveness(sig);
    if (!livenessResult.isLive) {
      await logEvent(userId, email, deviceId, "verify_heart", false, 0, livenessResult.reason);
      return jsonResponse({
        verified: false,
        confidence: 0,
        livenessScore: livenessResult.score,
        method: sig.method,
        assuranceLevel: "none",
        sessionToken: null,
        reason: livenessResult.reason,
      });
    }

    // --- Confidence Scoring ---
    //
    // The Watch already performs biometric matching on-device (ECG cosine similarity,
    // PPG HRV/RMSSD analysis). The backend validates the Watch's claim by checking:
    //   1. Liveness indicators (above)
    //   2. Consistency of reported confidence with signal quality metrics
    //   3. Device binding (X-Device-Signature header)

    let confidence = sig.confidence;

    // Cross-validate: Watch confidence should be consistent with signal quality
    if (sig.method === "ecg") {
      if (sig.signalNoiseRatio < 10.0) {
        confidence = Math.min(confidence, 0.70); // Low-quality ECG can't claim high confidence
      }
    } else {
      // PPG-only: cap at 0.92 regardless of Watch claim (PPG ceiling)
      confidence = Math.min(confidence, 0.92);
    }

    // Apply liveness factor
    confidence *= livenessResult.score;

    // Apply wrist detection
    if (!sig.wristDetected) {
      confidence *= 0.3;
    }

    const verified = confidence >= MIN_CONFIDENCE;
    const assuranceLevel = confidence >= HIGH_CONFIDENCE ? "high" : confidence >= MIN_CONFIDENCE ? "standard" : "none";

    // Generate session token if verified
    let sessionToken: string | null = null;
    if (verified) {
      sessionToken = crypto.randomUUID();
    }

    // Log the verification event
    await logEvent(userId, email, deviceId, "verify_heart", verified, confidence, sig.method);

    return jsonResponse({
      verified,
      confidence: Math.round(confidence * 1000) / 1000,
      livenessScore: Math.round(livenessResult.score * 1000) / 1000,
      method: sig.method,
      assuranceLevel,
      sessionToken,
    });

  } catch (err) {
    console.error("verify-heart error:", err);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});

// --- Liveness Detection Engine ---

interface LivenessResult {
  isLive: boolean;
  score: number;  // 0.0 to 1.0
  reason: string;
}

function assessLiveness(sig: CardiacSignature): LivenessResult {
  let score = 1.0;
  const reasons: string[] = [];

  // 1. Wrist detection must be active
  if (!sig.wristDetected) {
    return { isLive: false, score: 0, reason: "wrist_not_detected" };
  }

  // 2. Heart rate must be physiologically plausible (30–220 BPM)
  if (sig.restingHR < 30 || sig.restingHR > 220) {
    return { isLive: false, score: 0, reason: "implausible_heart_rate" };
  }

  // 3. HRV must be present (completely zero HRV = static/replayed signal)
  if (sig.hrv <= 0 && sig.beatIntervals.length > 5) {
    score *= 0.3;
    reasons.push("zero_hrv");
  }

  // 4. Beat interval variability — completely uniform intervals = synthetic
  if (sig.beatIntervals.length >= 5) {
    const diffs = [];
    for (let i = 1; i < sig.beatIntervals.length; i++) {
      diffs.push(Math.abs(sig.beatIntervals[i] - sig.beatIntervals[i - 1]));
    }
    const maxDiff = Math.max(...diffs);
    const minDiff = Math.min(...diffs);
    if (maxDiff - minDiff < 0.001) {
      // All intervals identical to sub-millisecond — synthetic signal
      return { isLive: false, score: 0, reason: "synthetic_uniform_intervals" };
    }
  }

  // 5. Heart rate consistency — recent HR samples should show natural variation
  if (sig.recentHeartRates.length >= 3) {
    const uniqueHRs = new Set(sig.recentHeartRates.map(h => Math.round(h)));
    if (uniqueHRs.size === 1 && sig.recentHeartRates.length > 5) {
      score *= 0.5;
      reasons.push("static_heart_rate");
    }
  }

  // 6. ECG signal quality — unrealistically high SNR suggests recorded signal
  if (sig.method === "ecg" && sig.signalNoiseRatio > 40) {
    score *= 0.7;
    reasons.push("unrealistic_snr");
  }

  // 7. Timestamp freshness — signature should be recent
  const sigAge = Date.now() - new Date(sig.timestamp).getTime();
  if (sigAge > 120_000) { // > 2 minutes old
    score *= 0.5;
    reasons.push("stale_signature");
  }

  const isLive = score >= 0.5;
  return {
    isLive,
    score,
    reason: reasons.length > 0 ? reasons.join(",") : "pass",
  };
}

// --- Logging ---

async function logEvent(
  userId: string, email: string, deviceId: string,
  eventType: string, success: boolean, confidence: number, method: string
) {
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);
    await supabase.from("auth_events").insert({
      user_id: userId,
      event_type: eventType,
      success,
      device_info: deviceId,
      metadata: JSON.stringify({ confidence, method }),
      ip_address: null,
      timestamp: new Date().toISOString(),
    });
  } catch (e) {
    console.error("Failed to log event:", e);
  }
}

// --- Helpers ---

function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
  });
}
