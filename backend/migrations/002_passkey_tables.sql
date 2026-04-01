-- ============================================================================
-- Migration:   002
-- Description: HeartID Passkey Backend Schema
--              Creates credential storage, challenge management, and audit
--              tables for the HeartID cardiac-gated passkey system.
-- Date:        2026-03-31
-- Author:      HeartID Dev Team
-- ============================================================================

BEGIN;

-- ============================================================================
-- TABLE: heartid_passkey_credentials
-- Stores registered WebAuthn/passkey credentials bound to HeartID users.
-- One user may have multiple credentials (multi-device passkeys).
-- ============================================================================

CREATE TABLE IF NOT EXISTS heartid_passkey_credentials (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    credential_id   bytea       NOT NULL UNIQUE,
    public_key      bytea       NOT NULL,
    sign_count      bigint      NOT NULL DEFAULT 0,
    device_type     text        NOT NULL DEFAULT 'platform',
    backed_up       boolean     NOT NULL DEFAULT false,
    transports      text[]      DEFAULT '{}',
    created_at      timestamptz NOT NULL DEFAULT now(),
    last_used_at    timestamptz,
    display_name    text
);

CREATE INDEX IF NOT EXISTS idx_passkey_credentials_user_id
    ON heartid_passkey_credentials (user_id);

-- ============================================================================
-- TABLE: heartid_passkey_challenges
-- Ephemeral challenge storage for registration and authentication ceremonies.
-- Each challenge has a 5-minute TTL and a minimum cardiac confidence gate.
-- ============================================================================

CREATE TABLE IF NOT EXISTS heartid_passkey_challenges (
    id                uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           uuid          REFERENCES auth.users(id) ON DELETE CASCADE,
    challenge_bytes   bytea         NOT NULL,
    action_type       text          NOT NULL,
    expires_at        timestamptz   NOT NULL DEFAULT (now() + interval '5 minutes'),
    used              boolean       NOT NULL DEFAULT false,
    cardiac_min_conf  numeric(5,4)  NOT NULL DEFAULT 0.8200,
    created_at        timestamptz   NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_passkey_challenges_user_expires
    ON heartid_passkey_challenges (user_id, expires_at)
    WHERE NOT used;

-- ============================================================================
-- TABLE: heartid_passkey_audit
-- Append-only audit trail for all passkey operations.
-- Records cardiac confidence at the time of each operation for compliance.
-- ============================================================================

CREATE TABLE IF NOT EXISTS heartid_passkey_audit (
    id                    uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id               uuid          REFERENCES auth.users(id),
    credential_id         bytea,
    action_type           text          NOT NULL,
    success               boolean       NOT NULL,
    cardiac_confidence    numeric(5,4),
    ip_address            inet,
    user_agent            text,
    failure_reason        text,
    created_at            timestamptz   NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_passkey_audit_user_created
    ON heartid_passkey_audit (user_id, created_at);

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE heartid_passkey_credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE heartid_passkey_challenges  ENABLE ROW LEVEL SECURITY;
ALTER TABLE heartid_passkey_audit       ENABLE ROW LEVEL SECURITY;

-- Credentials: authenticated users can SELECT their own rows only.
-- INSERT/UPDATE/DELETE are restricted to service_role (edge functions).
CREATE POLICY "credentials_select_own"
    ON heartid_passkey_credentials
    FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "credentials_service_role_all"
    ON heartid_passkey_credentials
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- Challenges: service_role only (edge functions manage lifecycle).
CREATE POLICY "challenges_service_role_all"
    ON heartid_passkey_challenges
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- Audit: authenticated users can read their own audit trail.
-- Only service_role can insert (edge functions write audit entries).
CREATE POLICY "audit_select_own"
    ON heartid_passkey_audit
    FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "audit_service_role_all"
    ON heartid_passkey_audit
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- ============================================================================
-- CLEANUP FUNCTION
-- Deletes expired or consumed challenges to prevent table bloat.
-- Should be invoked via pg_cron every 15 minutes:
--   SELECT cron.schedule(
--       'cleanup-passkey-challenges',
--       '*/15 * * * *',
--       $$SELECT delete_expired_challenges()$$
--   );
-- ============================================================================

CREATE OR REPLACE FUNCTION delete_expired_challenges()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    DELETE FROM heartid_passkey_challenges
    WHERE expires_at < now()
       OR (used = true AND created_at < now() - interval '1 hour');
END;
$$;

COMMIT;
