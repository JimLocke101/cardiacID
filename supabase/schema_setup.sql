-- CardiacID Supabase Schema Setup
-- Run this in the Supabase SQL editor to create required tables
-- These tables are also backed by in-memory Maps within each Edge Function
-- for same-invocation performance; Supabase provides cross-invocation persistence.

-- =========================================================
-- OIDC Auth Sessions
-- Tracks pending browser sessions (waiting for CardiacID app
-- to POST biometric verification), then holds issued auth codes
-- until Entra ID exchanges them at the /oidc-token endpoint.
-- =========================================================
CREATE TABLE IF NOT EXISTS oidc_auth_sessions (
  session_id        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id         TEXT        NOT NULL,
  redirect_uri      TEXT        NOT NULL,
  state             TEXT,
  nonce             TEXT,
  auth_code         UUID        UNIQUE,             -- populated after app verifies
  user_id           TEXT,
  email             TEXT,
  display_name      TEXT,
  biometric_confidence DOUBLE PRECISION,
  biometric_method  TEXT,
  status            TEXT        NOT NULL DEFAULT 'pending',
    -- pending | verified | consumed | expired
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at        TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '10 minutes')
);

-- Fast code lookup at /oidc-token endpoint
CREATE INDEX IF NOT EXISTS idx_oidc_sessions_auth_code
  ON oidc_auth_sessions(auth_code);

-- Fast status-poll lookup by session_id is covered by the PK index.

-- Auto-expire stale sessions (run periodically or via pg_cron)
-- DELETE FROM oidc_auth_sessions WHERE expires_at < NOW();

-- Row-level security: only the service role key may read/write
ALTER TABLE oidc_auth_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "service_role_only" ON oidc_auth_sessions
  USING (auth.role() = 'service_role');

-- =========================================================
-- Authentication Events
-- Append-only audit log written by iOS app and Edge Functions.
-- =========================================================
CREATE TABLE IF NOT EXISTS auth_events (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             TEXT,
  event_type          TEXT        NOT NULL,
    -- e.g. "eam_authorization", "authentication", "fallback_triggered"
  authentication_method TEXT      NOT NULL,
  success             BOOLEAN     NOT NULL,
  confidence_score    DOUBLE PRECISION,
  failure_reason      TEXT,
  metadata            JSONB,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_auth_events_user_id  ON auth_events(user_id);
CREATE INDEX IF NOT EXISTS idx_auth_events_created  ON auth_events(created_at DESC);

ALTER TABLE auth_events ENABLE ROW LEVEL SECURITY;

-- Service role can read/write all rows (Edge Functions, admin)
CREATE POLICY "service_role_full_access" ON auth_events
  USING (auth.role() = 'service_role');

-- Authenticated iOS users can insert their own events
CREATE POLICY "authenticated_insert_own" ON auth_events
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid()::text = user_id);

-- Authenticated users can read their own events
CREATE POLICY "authenticated_select_own" ON auth_events
  FOR SELECT TO authenticated
  USING (auth.uid()::text = user_id);

-- =========================================================
-- Access Control Config
-- Maps EntraID group IDs or name prefixes to resource
-- permissions, replacing the keyword-heuristic fallback
-- in AccessControlService.swift.
-- =========================================================
CREATE TABLE IF NOT EXISTS access_control_config (
  id              UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id        TEXT,           -- Entra ID group object ID (exact match)
  group_prefix    TEXT,           -- display name prefix (fallback matching)
  resource_type   TEXT    NOT NULL,
    -- "door" | "computer" | "file"
  resource_name   TEXT    NOT NULL,
  access_level    TEXT    NOT NULL DEFAULT 'user',
    -- "viewer" | "user" | "admin"
  requires_heartid BOOLEAN NOT NULL DEFAULT FALSE,
  minimum_confidence DOUBLE PRECISION NOT NULL DEFAULT 0.70,
  location        TEXT,
  requires_fido2  BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_acc_config_group_id ON access_control_config(group_id);

ALTER TABLE access_control_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY "service_role_only" ON access_control_config
  USING (auth.role() = 'service_role');
