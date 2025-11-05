-- ============================================================================
-- HeartID Mobile - Initial Database Schema
-- ============================================================================
-- Version: 1.0.0
-- Date: January 2025
-- Description: Production database schema for HeartID biometric authentication
-- Security: Row Level Security (RLS) enabled on all tables
-- ============================================================================

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- USERS TABLE
-- ============================================================================
-- Stores user profile information
-- Synced with Supabase Auth (auth.users)

CREATE TABLE public.users (
    -- Primary key (matches auth.users.id)
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Profile information
    email TEXT UNIQUE NOT NULL,
    full_name TEXT,
    avatar_url TEXT,

    -- Enrollment status
    enrollment_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (enrollment_status IN ('pending', 'in_progress', 'completed', 'revoked')),
    enrollment_completed_at TIMESTAMPTZ,

    -- Account metadata
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login_at TIMESTAMPTZ,

    -- Soft delete
    deleted_at TIMESTAMPTZ
);

-- Indexes
CREATE INDEX idx_users_email ON public.users(email);
CREATE INDEX idx_users_enrollment_status ON public.users(enrollment_status);
CREATE INDEX idx_users_deleted_at ON public.users(deleted_at) WHERE deleted_at IS NOT NULL;

-- Row Level Security
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Users can read their own profile
CREATE POLICY "Users can view own profile"
    ON public.users FOR SELECT
    USING (auth.uid() = id);

-- Users can update their own profile
CREATE POLICY "Users can update own profile"
    ON public.users FOR UPDATE
    USING (auth.uid() = id);

-- Trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON public.users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- BIOMETRIC_TEMPLATES TABLE
-- ============================================================================
-- Stores encrypted biometric templates for heart pattern authentication
-- SECURITY: Templates are encrypted client-side before storage

CREATE TABLE public.biometric_templates (
    -- Primary key
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Foreign key to users
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,

    -- Encrypted biometric data
    template_data BYTEA NOT NULL, -- Encrypted BiometricTemplate JSON
    encryption_method TEXT NOT NULL DEFAULT 'AES-256-GCM',
    encryption_key_id TEXT, -- Reference to encryption key (if using key management)

    -- Template metadata
    quality_score FLOAT NOT NULL CHECK (quality_score >= 0 AND quality_score <= 1),
    confidence_level FLOAT NOT NULL CHECK (confidence_level >= 0 AND confidence_level <= 1),
    sample_count INTEGER NOT NULL CHECK (sample_count > 0),

    -- Device information
    device_model TEXT NOT NULL,
    device_os_version TEXT NOT NULL,
    watch_model TEXT,
    watch_os_version TEXT,

    -- Versioning
    template_version TEXT NOT NULL DEFAULT '1.0',

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_verified_at TIMESTAMPTZ,

    -- Soft delete
    deleted_at TIMESTAMPTZ,

    -- Constraints
    UNIQUE(user_id, deleted_at) -- One active template per user
);

-- Indexes
CREATE INDEX idx_biometric_templates_user_id ON public.biometric_templates(user_id);
CREATE INDEX idx_biometric_templates_quality ON public.biometric_templates(quality_score);
CREATE INDEX idx_biometric_templates_created_at ON public.biometric_templates(created_at DESC);

-- Row Level Security
ALTER TABLE public.biometric_templates ENABLE ROW LEVEL SECURITY;

-- Users can read their own templates
CREATE POLICY "Users can view own biometric templates"
    ON public.biometric_templates FOR SELECT
    USING (auth.uid() = user_id);

-- Users can insert their own templates
CREATE POLICY "Users can insert own biometric templates"
    ON public.biometric_templates FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Users can update their own templates
CREATE POLICY "Users can update own biometric templates"
    ON public.biometric_templates FOR UPDATE
    USING (auth.uid() = user_id);

-- Trigger to update updated_at
CREATE TRIGGER update_biometric_templates_updated_at
    BEFORE UPDATE ON public.biometric_templates
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- DEVICES TABLE
-- ============================================================================
-- Stores registered devices for each user

CREATE TABLE public.devices (
    -- Primary key
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Foreign key to users
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,

    -- Device information
    device_identifier TEXT NOT NULL, -- Unique device ID
    device_name TEXT NOT NULL,
    device_type TEXT NOT NULL CHECK (device_type IN ('apple_watch', 'galaxy_watch', 'oura_ring', 'iphone', 'android', 'other')),
    device_model TEXT,
    os_version TEXT,

    -- Device status
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'active', 'inactive', 'revoked')),

    -- Sync information
    last_sync_date TIMESTAMPTZ,
    last_heartbeat_at TIMESTAMPTZ,

    -- Registration
    registered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    activated_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    revocation_reason TEXT,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Constraints
    UNIQUE(user_id, device_identifier)
);

-- Indexes
CREATE INDEX idx_devices_user_id ON public.devices(user_id);
CREATE INDEX idx_devices_status ON public.devices(status);
CREATE INDEX idx_devices_type ON public.devices(device_type);
CREATE INDEX idx_devices_last_sync ON public.devices(last_sync_date DESC);

-- Row Level Security
ALTER TABLE public.devices ENABLE ROW LEVEL SECURITY;

-- Users can read their own devices
CREATE POLICY "Users can view own devices"
    ON public.devices FOR SELECT
    USING (auth.uid() = user_id);

-- Users can insert their own devices
CREATE POLICY "Users can insert own devices"
    ON public.devices FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Users can update their own devices
CREATE POLICY "Users can update own devices"
    ON public.devices FOR UPDATE
    USING (auth.uid() = user_id);

-- Trigger to update updated_at
CREATE TRIGGER update_devices_updated_at
    BEFORE UPDATE ON public.devices
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- AUTH_EVENTS TABLE
-- ============================================================================
-- Stores authentication event history (audit log)
-- SECURITY: Append-only (no updates allowed)

CREATE TABLE public.auth_events (
    -- Primary key
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Foreign keys
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    device_id UUID REFERENCES public.devices(id) ON DELETE SET NULL,

    -- Event information
    event_type TEXT NOT NULL CHECK (event_type IN ('enrollment', 'authentication', 'step_up_auth', 'revocation', 'login', 'logout')),
    authentication_method TEXT CHECK (authentication_method IN ('ecg', 'ppg', 'hybrid', 'password', 'biometric', 'oauth')),

    -- Result
    success BOOLEAN NOT NULL,
    confidence_score FLOAT CHECK (confidence_score >= 0 AND confidence_score <= 1),
    failure_reason TEXT,

    -- Context
    ip_address INET,
    user_agent TEXT,
    location_lat FLOAT,
    location_lon FLOAT,
    location_name TEXT,

    -- Metadata
    metadata JSONB, -- Additional event-specific data

    -- Timestamp
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Prevent future timestamps
    CONSTRAINT check_timestamp_not_future CHECK (timestamp <= NOW())
);

-- Indexes
CREATE INDEX idx_auth_events_user_id ON public.auth_events(user_id);
CREATE INDEX idx_auth_events_device_id ON public.auth_events(device_id);
CREATE INDEX idx_auth_events_timestamp ON public.auth_events(timestamp DESC);
CREATE INDEX idx_auth_events_event_type ON public.auth_events(event_type);
CREATE INDEX idx_auth_events_success ON public.auth_events(success);
CREATE INDEX idx_auth_events_metadata ON public.auth_events USING GIN(metadata);

-- Row Level Security
ALTER TABLE public.auth_events ENABLE ROW LEVEL SECURITY;

-- Users can read their own auth events
CREATE POLICY "Users can view own auth events"
    ON public.auth_events FOR SELECT
    USING (auth.uid() = user_id);

-- Users can insert their own auth events
CREATE POLICY "Users can insert own auth events"
    ON public.auth_events FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- NO UPDATE POLICY - Auth events are immutable

-- ============================================================================
-- ENTERPRISE_INTEGRATIONS TABLE
-- ============================================================================
-- Stores enterprise integration configurations (EntraID, etc.)

CREATE TABLE public.enterprise_integrations (
    -- Primary key
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Foreign key to users
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,

    -- Integration type
    integration_type TEXT NOT NULL CHECK (integration_type IN ('entraid', 'azure_ad', 'okta', 'google_workspace', 'custom')),
    integration_name TEXT NOT NULL,

    -- Configuration (encrypted)
    config_data JSONB NOT NULL,
    encrypted_credentials BYTEA, -- Encrypted credential data

    -- Status
    status TEXT NOT NULL DEFAULT 'inactive'
        CHECK (status IN ('active', 'inactive', 'error', 'pending')),

    -- Connection info
    last_sync_at TIMESTAMPTZ,
    last_error TEXT,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Constraints
    UNIQUE(user_id, integration_type, integration_name)
);

-- Indexes
CREATE INDEX idx_enterprise_integrations_user_id ON public.enterprise_integrations(user_id);
CREATE INDEX idx_enterprise_integrations_type ON public.enterprise_integrations(integration_type);
CREATE INDEX idx_enterprise_integrations_status ON public.enterprise_integrations(status);

-- Row Level Security
ALTER TABLE public.enterprise_integrations ENABLE ROW LEVEL SECURITY;

-- Users can manage their own integrations
CREATE POLICY "Users can manage own integrations"
    ON public.enterprise_integrations
    USING (auth.uid() = user_id);

-- Trigger to update updated_at
CREATE TRIGGER update_enterprise_integrations_updated_at
    BEFORE UPDATE ON public.enterprise_integrations
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- SYSTEM_METRICS TABLE
-- ============================================================================
-- Stores system-wide performance and usage metrics

CREATE TABLE public.system_metrics (
    -- Primary key
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Metric information
    metric_name TEXT NOT NULL,
    metric_value FLOAT NOT NULL,
    metric_unit TEXT,

    -- Dimensions
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    device_id UUID REFERENCES public.devices(id) ON DELETE SET NULL,

    -- Additional context
    tags JSONB,

    -- Timestamp
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_system_metrics_name ON public.system_metrics(metric_name);
CREATE INDEX idx_system_metrics_timestamp ON public.system_metrics(timestamp DESC);
CREATE INDEX idx_system_metrics_user_id ON public.system_metrics(user_id);
CREATE INDEX idx_system_metrics_tags ON public.system_metrics USING GIN(tags);

-- Row Level Security
ALTER TABLE public.system_metrics ENABLE ROW LEVEL SECURITY;

-- Users can view their own metrics
CREATE POLICY "Users can view own metrics"
    ON public.system_metrics FOR SELECT
    USING (auth.uid() = user_id);

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function to get active biometric template for a user
CREATE OR REPLACE FUNCTION get_active_template(p_user_id UUID)
RETURNS TABLE (
    id UUID,
    template_data BYTEA,
    quality_score FLOAT,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        bt.id,
        bt.template_data,
        bt.quality_score,
        bt.created_at
    FROM public.biometric_templates bt
    WHERE bt.user_id = p_user_id
      AND bt.deleted_at IS NULL
    ORDER BY bt.created_at DESC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get user authentication statistics
CREATE OR REPLACE FUNCTION get_user_auth_stats(p_user_id UUID, p_days INTEGER DEFAULT 30)
RETURNS TABLE (
    total_attempts BIGINT,
    successful_attempts BIGINT,
    failed_attempts BIGINT,
    success_rate FLOAT,
    avg_confidence FLOAT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*)::BIGINT AS total_attempts,
        COUNT(*) FILTER (WHERE success = TRUE)::BIGINT AS successful_attempts,
        COUNT(*) FILTER (WHERE success = FALSE)::BIGINT AS failed_attempts,
        (COUNT(*) FILTER (WHERE success = TRUE)::FLOAT / NULLIF(COUNT(*), 0)::FLOAT) AS success_rate,
        AVG(confidence_score) FILTER (WHERE confidence_score IS NOT NULL) AS avg_confidence
    FROM public.auth_events
    WHERE user_id = p_user_id
      AND timestamp >= NOW() - (p_days || ' days')::INTERVAL
      AND event_type IN ('authentication', 'step_up_auth');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- INITIAL DATA
-- ============================================================================

-- Grant permissions for authenticated users
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

COMMENT ON TABLE public.users IS 'User profiles synced with Supabase Auth';
COMMENT ON TABLE public.biometric_templates IS 'Encrypted heart pattern biometric templates';
COMMENT ON TABLE public.devices IS 'Registered wearable devices for biometric capture';
COMMENT ON TABLE public.auth_events IS 'Immutable audit log of all authentication events';
COMMENT ON TABLE public.enterprise_integrations IS 'Enterprise SSO integrations (EntraID, etc.)';
COMMENT ON TABLE public.system_metrics IS 'System performance and usage metrics';
