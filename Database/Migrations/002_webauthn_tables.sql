-- 002_webauthn_tables.sql
-- WebAuthn Relying Party credential and challenge storage
-- Required by: webauthn-register, webauthn-authenticate Edge Functions

-- ─── Challenges (ephemeral, TTL-managed) ─────────────────────────────────────

CREATE TABLE IF NOT EXISTS webauthn_challenges (
    challenge_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    user_name TEXT NOT NULL,
    challenge_data TEXT NOT NULL,         -- base64url-encoded challenge bytes
    type TEXT NOT NULL CHECK (type IN ('registration', 'authentication')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT valid_ttl CHECK (expires_at > created_at)
);

-- Auto-cleanup expired challenges
CREATE INDEX IF NOT EXISTS idx_webauthn_challenges_expires
    ON webauthn_challenges (expires_at);

-- ─── Credentials (permanent, one per passkey) ────────────────────────────────

CREATE TABLE IF NOT EXISTS webauthn_credentials (
    credential_id TEXT PRIMARY KEY,       -- base64url-encoded credential ID
    user_id TEXT NOT NULL,
    user_name TEXT NOT NULL,
    public_key TEXT NOT NULL,             -- base64url-encoded COSE public key (JSON)
    public_key_algorithm INTEGER NOT NULL DEFAULT -7,  -- COSE algorithm (-7 = ES256)
    sign_count INTEGER NOT NULL DEFAULT 0,
    aaguid TEXT,                          -- authenticator AAGUID
    attestation_format TEXT DEFAULT 'none',
    transports TEXT[] DEFAULT ARRAY['internal', 'hybrid'],
    backed_up BOOLEAN DEFAULT FALSE,      -- BE flag (backup eligibility)
    device_type TEXT DEFAULT 'single_device' CHECK (device_type IN ('single_device', 'multi_device')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ               -- soft-delete for credential revocation
);

CREATE INDEX IF NOT EXISTS idx_webauthn_credentials_user
    ON webauthn_credentials (user_id);

CREATE INDEX IF NOT EXISTS idx_webauthn_credentials_active
    ON webauthn_credentials (user_id) WHERE revoked_at IS NULL;

-- ─── RLS Policies ────────────────────────────────────────────────────────────
-- Service role bypasses RLS; these are for future client-side access

ALTER TABLE webauthn_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE webauthn_credentials ENABLE ROW LEVEL SECURITY;

-- Service role (Edge Functions) can do anything
CREATE POLICY "service_role_challenges" ON webauthn_challenges
    FOR ALL USING (TRUE) WITH CHECK (TRUE);

CREATE POLICY "service_role_credentials" ON webauthn_credentials
    FOR ALL USING (TRUE) WITH CHECK (TRUE);

-- ─── Cleanup function for expired challenges ─────────────────────────────────

CREATE OR REPLACE FUNCTION cleanup_expired_webauthn_challenges()
RETURNS void AS $$
BEGIN
    DELETE FROM webauthn_challenges WHERE expires_at < NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Schedule cleanup (run via pg_cron or Supabase scheduled function)
-- SELECT cron.schedule('cleanup-webauthn-challenges', '*/5 * * * *', 'SELECT cleanup_expired_webauthn_challenges()');
