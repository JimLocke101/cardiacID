# HeartID Database Schema

Production-grade PostgreSQL database schema for HeartID biometric authentication system.

## Overview

This database schema supports:
- ✅ **User Management** - Profiles synced with Supabase Auth
- ✅ **Biometric Templates** - Encrypted heart pattern storage
- ✅ **Device Management** - Multi-device support per user
- ✅ **Authentication Events** - Immutable audit trail
- ✅ **Enterprise Integrations** - EntraID, Azure AD, etc.
- ✅ **System Metrics** - Performance monitoring

## Security Features

### Row Level Security (RLS)
- **Enabled on ALL tables**
- Users can only access their own data
- Prevents unauthorized data access
- Enforced at database level

### Encryption
- **Biometric templates:** Client-side encryption before storage
- **Enterprise credentials:** Encrypted BYTEA storage
- **Algorithm:** AES-256-GCM

### Audit Trail
- **Immutable auth_events table** - No updates allowed
- **All authentication attempts logged**
- **Includes IP address, user agent, location**
- **Compliance-ready**

## Tables

### 1. users
Stores user profile information, synced with Supabase Auth.

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY,  -- Matches auth.users.id
    email TEXT UNIQUE NOT NULL,
    full_name TEXT,
    enrollment_status TEXT CHECK (...),
    created_at TIMESTAMPTZ,
    ...
);
```

**Key Features:**
- Soft delete support (`deleted_at`)
- Enrollment workflow tracking
- Last login timestamp
- Automatic `updated_at` trigger

**RLS Policies:**
- Users can view their own profile
- Users can update their own profile

---

### 2. biometric_templates
Stores encrypted heart pattern biometric templates.

```sql
CREATE TABLE biometric_templates (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    template_data BYTEA NOT NULL,  -- Encrypted!
    quality_score FLOAT CHECK (0 <= quality_score <= 1),
    sample_count INTEGER,
    ...
);
```

**CRITICAL SECURITY:**
- Templates are **NEVER** stored unencrypted
- Client-side encryption using AES-256-GCM
- Only encrypted BYTEA is sent to database
- Encryption key NEVER leaves device

**Key Features:**
- One active template per user (UNIQUE constraint)
- Quality scoring for template validation
- Device metadata for troubleshooting
- Template versioning support

**RLS Policies:**
- Users can view/insert/update their own templates only

---

### 3. devices
Registered wearable devices for biometric capture.

```sql
CREATE TABLE devices (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    device_identifier TEXT NOT NULL,
    device_type TEXT CHECK (...),
    status TEXT CHECK (...),
    ...
);
```

**Supported Device Types:**
- `apple_watch` - Primary biometric capture device
- `galaxy_watch` - Samsung Galaxy Watch support
- `oura_ring` - Oura Ring integration
- `iphone` - iPhone companion app
- `android` - Android companion app
- `other` - Custom devices

**Device Lifecycle:**
1. **Pending** - Device registered, awaiting activation
2. **Active** - Device in use for authentication
3. **Inactive** - Device temporarily disabled
4. **Revoked** - Device permanently disabled

**Key Features:**
- Unique constraint per user+device
- Last heartbeat tracking
- Revocation audit trail

---

### 4. auth_events
Immutable audit log of all authentication events.

```sql
CREATE TABLE auth_events (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    device_id UUID REFERENCES devices(id),
    event_type TEXT CHECK (...),
    success BOOLEAN NOT NULL,
    confidence_score FLOAT,
    timestamp TIMESTAMPTZ NOT NULL,
    ...
);
```

**Event Types:**
- `enrollment` - Initial biometric enrollment
- `authentication` - Standard authentication
- `step_up_auth` - High-security step-up authentication
- `revocation` - Device/template revocation
- `login` - User login
- `logout` - User logout

**Authentication Methods:**
- `ecg` - ECG-based authentication (96-99% accuracy)
- `ppg` - PPG-based authentication (85-92% accuracy)
- `hybrid` - Combined ECG/PPG
- `password` - Traditional password
- `biometric` - Device biometric (Face ID/Touch ID)
- `oauth` - OAuth providers (EntraID, etc.)

**SECURITY:**
- **Append-only table** - No UPDATE policy
- Cannot be modified after insertion
- Compliance-ready audit trail

---

### 5. enterprise_integrations
Enterprise SSO integration configurations.

```sql
CREATE TABLE enterprise_integrations (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    integration_type TEXT CHECK (...),
    config_data JSONB NOT NULL,
    encrypted_credentials BYTEA,
    ...
);
```

**Supported Integrations:**
- `entraid` - Microsoft EntraID (Azure AD)
- `azure_ad` - Legacy Azure AD
- `okta` - Okta SSO
- `google_workspace` - Google Workspace
- `custom` - Custom SAML/OAuth providers

**Key Features:**
- Encrypted credential storage
- Last sync tracking
- Error logging for debugging
- Multi-integration support per user

---

### 6. system_metrics
System performance and usage metrics.

```sql
CREATE TABLE system_metrics (
    id UUID PRIMARY KEY,
    metric_name TEXT NOT NULL,
    metric_value FLOAT NOT NULL,
    user_id UUID REFERENCES users(id),
    timestamp TIMESTAMPTZ NOT NULL,
    ...
);
```

**Use Cases:**
- Performance monitoring
- Usage analytics
- Error rate tracking
- Confidence score trends

---

## Helper Functions

### get_active_template(user_id UUID)
Returns the current active biometric template for a user.

```sql
SELECT * FROM get_active_template('user-uuid-here');
```

**Returns:**
- `id` - Template ID
- `template_data` - Encrypted template BYTEA
- `quality_score` - Template quality (0-1)
- `created_at` - Creation timestamp

---

### get_user_auth_stats(user_id UUID, days INTEGER)
Returns authentication statistics for a user over the last N days.

```sql
SELECT * FROM get_user_auth_stats('user-uuid-here', 30);
```

**Returns:**
- `total_attempts` - Total authentication attempts
- `successful_attempts` - Successful authentications
- `failed_attempts` - Failed authentications
- `success_rate` - Success rate (0-1)
- `avg_confidence` - Average confidence score

---

## Migration Guide

### Step 1: Access Supabase Dashboard

1. Go to [supabase.com](https://supabase.com)
2. Open your project: `bzxzugwguozsymqezvig`
3. Navigate to **SQL Editor**

### Step 2: Run Migration

1. Copy contents of `Migrations/001_initial_schema.sql`
2. Paste into SQL Editor
3. Click **Run**
4. Wait for completion (~30 seconds)

### Step 3: Verify Schema

Run this query to verify tables were created:

```sql
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;
```

**Expected output:**
- `auth_events`
- `biometric_templates`
- `devices`
- `enterprise_integrations`
- `system_metrics`
- `users`

### Step 4: Verify RLS Policies

```sql
SELECT schemaname, tablename, policyname
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;
```

**Expected:** 3+ policies per table

---

## Querying Examples

### Get User Profile
```sql
SELECT * FROM users WHERE id = auth.uid();
```

### Get User's Devices
```sql
SELECT * FROM devices
WHERE user_id = auth.uid()
ORDER BY created_at DESC;
```

### Get Recent Auth Events
```sql
SELECT * FROM auth_events
WHERE user_id = auth.uid()
ORDER BY timestamp DESC
LIMIT 50;
```

### Get Authentication Statistics
```sql
SELECT * FROM get_user_auth_stats(auth.uid(), 30);
```

---

## Data Flow

### Enrollment Flow
```
1. User completes enrollment on Apple Watch
2. Client encrypts BiometricTemplate
3. INSERT into biometric_templates (encrypted BYTEA)
4. UPDATE users SET enrollment_status = 'completed'
5. INSERT into auth_events (event_type = 'enrollment')
```

### Authentication Flow
```
1. User authenticates via ECG/PPG
2. Client compares against template
3. INSERT into auth_events (success, confidence_score)
4. UPDATE users SET last_login_at = NOW()
```

### Device Registration Flow
```
1. User pairs Apple Watch
2. INSERT into devices (status = 'pending')
3. User activates device
4. UPDATE devices SET status = 'active', activated_at = NOW()
5. INSERT into auth_events (event_type = 'authentication')
```

---

## Backup & Recovery

### Automated Backups
Supabase automatically backs up your database daily.

**Retention:** 7 days (Pro plan), 30 days (Enterprise)

### Manual Backup
```bash
# Via Supabase CLI
supabase db dump -f backup.sql
```

### Restore from Backup
```bash
supabase db push backup.sql
```

---

## Performance Optimization

### Indexes Created
- All foreign keys
- Frequently queried columns
- Timestamp columns (DESC order)
- JSONB columns (GIN indexes)

### Query Optimization Tips
1. Always filter by `user_id` first
2. Use `auth.uid()` in queries (RLS optimized)
3. Add indexes for custom queries
4. Use `EXPLAIN ANALYZE` for slow queries

---

## Monitoring

### Key Metrics to Track
- Average authentication time
- Template quality scores
- Failed authentication rate
- Device heartbeat frequency

### Query for Monitoring
```sql
-- Failed auth rate (last 24 hours)
SELECT
    COUNT(*) FILTER (WHERE success = FALSE)::FLOAT / COUNT(*)::FLOAT AS failure_rate
FROM auth_events
WHERE timestamp >= NOW() - INTERVAL '24 hours';
```

---

## Security Best Practices

### ✅ DO:
- Always encrypt biometric templates client-side
- Use prepared statements (SQL injection prevention)
- Validate all input data
- Log all authentication events
- Monitor for suspicious patterns

### ❌ DON'T:
- Store unencrypted biometric data
- Share database credentials
- Disable Row Level Security
- Allow UPDATE on auth_events table
- Store passwords in plaintext

---

## Compliance

This schema supports compliance with:
- **GDPR** - User data ownership, right to deletion
- **HIPAA** - Audit trails, encryption at rest
- **SOC 2** - Access controls, monitoring
- **CCPA** - Data privacy, user consent

---

## Troubleshooting

### Issue: RLS Blocking Queries

**Symptom:** Queries return 0 rows despite data existing

**Solution:**
```sql
-- Check if RLS is causing issue
SET ROLE postgres;
SELECT * FROM users;  -- Should return all users
RESET ROLE;
```

### Issue: Migration Fails

**Symptom:** "relation already exists" error

**Solution:**
```sql
-- Drop existing tables (CAUTION: Data loss!)
DROP TABLE IF EXISTS auth_events CASCADE;
DROP TABLE IF EXISTS biometric_templates CASCADE;
DROP TABLE IF EXISTS devices CASCADE;
DROP TABLE IF EXISTS enterprise_integrations CASCADE;
DROP TABLE IF EXISTS system_metrics CASCADE;
DROP TABLE IF EXISTS users CASCADE;
```

---

## Support

For issues or questions:
1. Check logs in Supabase Dashboard → Logs
2. Review RLS policies
3. Verify user authentication (auth.uid())
4. Contact support@heartid.com

---

*Last Updated: January 2025*
*Schema Version: 1.0.0*
