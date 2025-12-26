# Supabase Login & Configuration Guide

**Date:** November 5, 2025
**Purpose:** Connect CardiacID app to your Supabase project

---

## Step 1: Log into Supabase Dashboard

### Open Supabase Dashboard
```
https://app.supabase.com
```

**Login with:**
- Your Supabase account email
- Or sign in with GitHub/Google

---

## Step 2: Find Your Project Credentials

### Navigate to Your Project
1. After logging in, you'll see your projects list
2. Look for your HeartID/CardiacID project
3. Click on the project to open it

### Get API Credentials
Once in your project dashboard:

1. **Click on "Settings"** (gear icon in left sidebar)
2. **Click on "API"** in the Settings menu
3. You'll see your credentials:

---

## Required Credentials

### 1. Project URL
```
Look for: "Project URL"
Format: https://[YOUR-PROJECT-ID].supabase.co
Example: https://abcdefghijk.supabase.co
```

**Copy this!** You'll need it for the app.

### 2. API Key (anon/public)
```
Look for: "Project API keys"
Section: "anon public"
Format: Long string starting with "eyJ..."
```

**Copy this!** This is your public API key.

⚠️ **Important:** Copy the "anon public" key, NOT the "service_role" key.

### 3. Project Reference ID
```
Look for: "Project ID" or "Reference ID"
Format: Short alphanumeric string
Example: abcdefghijk
```

**Copy this!** This is usually part of your project URL.

---

## Step 3: Verify Database Setup

### Check if Tables Exist
1. In Supabase dashboard, click **"Table Editor"** (in left sidebar)
2. You should see these tables:
   - `users`
   - `biometric_templates`
   - `authentication_sessions`
   - `devices`
   - `activity_logs`
   - `user_enrollments`

### If Tables Don't Exist
Run the database migration I created:

1. In Supabase dashboard, click **"SQL Editor"** (in left sidebar)
2. Click **"New query"**
3. Open the migration file on your computer:
   ```
   CardiacID/Database/Migrations/001_initial_schema.sql
   ```
4. Copy the entire contents
5. Paste into Supabase SQL Editor
6. Click **"Run"** (or press Cmd+Enter)

**Expected Result:** All 6 tables created with Row Level Security enabled.

---

## Step 4: Configure App with Credentials

### Option A: First-Time App Launch (Recommended)

1. **Build and run the app** in Xcode (Cmd+R)
2. The app will detect missing credentials
3. **CredentialSetupView will appear automatically**
4. Enter your credentials:

   **Supabase Configuration:**
   - **Supabase URL:** [Paste your Project URL]
   - **Supabase API Key:** [Paste your anon public key]

   **EntraID Configuration (Optional for now):**
   - **Tenant ID:** [Leave blank or enter Microsoft tenant]
   - **Client ID:** [Leave blank or enter Microsoft app client ID]

5. Tap **"Save Credentials"**
6. Credentials are securely stored in iOS Keychain with biometric protection

### Option B: Manual Configuration (Advanced)

If you prefer to configure via command line or script:

```swift
// This happens automatically when you use CredentialSetupView,
// but here's what it does under the hood:

import Foundation
import Security

let credentialManager = SecureCredentialManager.shared

// Store Supabase URL
try credentialManager.store(
    "https://[YOUR-PROJECT-ID].supabase.co",
    forKey: .supabaseURL,
    securityLevel: .standard
)

// Store Supabase API Key
try credentialManager.store(
    "eyJ...[YOUR-API-KEY]",
    forKey: .supabaseAPIKey,
    securityLevel: .biometricRequired
)
```

---

## Step 5: Test Connection

### Run Connection Test

1. **Launch the app** (should be running from Step 4)
2. You should see the **Login screen**
3. Try to **sign up** with a test account:
   - Email: `test@heartid.com`
   - Password: `TestPassword123!`

4. **Watch the console** in Xcode for connection messages:

**Expected Success Messages:**
```
✅ Supabase client initialized successfully
✅ User signed up successfully: test@heartid.com
✅ User profile created in database
```

**If you see errors:**
```
❌ Failed to initialize Supabase client: [error details]
```

Check:
- URL is correct (no trailing slash)
- API key is the "anon public" key
- Your internet connection is working
- Supabase project is active (not paused)

---

## Step 6: Verify Database Records

### Check User Was Created

1. Go back to **Supabase dashboard**
2. Click **"Table Editor"**
3. Click on **"users"** table
4. You should see your test user:
   - ID: UUID
   - Email: test@heartid.com
   - enrollment_status: pending
   - created_at: [timestamp]

### Check Authentication

1. In Supabase dashboard, click **"Authentication"** (in left sidebar)
2. Click **"Users"** tab
3. You should see your test user listed

---

## Common Issues & Solutions

### Issue 1: "Supabase API key not found in Keychain"

**Cause:** Credentials haven't been configured yet.

**Solution:**
1. Launch the app
2. Complete CredentialSetupView
3. Restart the app

### Issue 2: "Invalid API key"

**Cause:** Wrong API key was copied (might be service_role instead of anon).

**Solution:**
1. Go back to Supabase dashboard → Settings → API
2. Copy the "anon public" key (NOT service_role)
3. Re-enter in CredentialSetupView

### Issue 3: "Connection refused" or "Network error"

**Cause:** URL is incorrect or project is paused.

**Solution:**
1. Verify URL format: `https://[project-id].supabase.co` (no trailing slash)
2. Check if Supabase project is paused (free tier pauses after inactivity)
3. In dashboard, click "Restore project" if paused

### Issue 4: Tables don't exist / "relation does not exist"

**Cause:** Database migration hasn't been run.

**Solution:**
1. Go to Supabase dashboard → SQL Editor
2. Run the migration: `CardiacID/Database/Migrations/001_initial_schema.sql`
3. Verify tables appear in Table Editor

---

## Quick Reference: Where to Find Everything

### In Supabase Dashboard:
- **Project URL:** Settings → API → Project URL
- **API Key:** Settings → API → Project API keys → anon public
- **Project ID:** Settings → General → Reference ID
- **SQL Editor:** Left sidebar → SQL Editor
- **Table Editor:** Left sidebar → Table Editor
- **Auth Users:** Left sidebar → Authentication → Users

### In CardiacID App:
- **Credential Setup:** Appears automatically on first launch
- **Re-configure:** Settings → Security Settings → Manage Credentials
- **View Connection Status:** Dashboard → Shows "Connected to Supabase"

---

## Next Steps After Successful Login

### 1. Create Your Real User Account
- Use your actual email
- Use a strong password
- Verify email (check Supabase Auth settings)

### 2. Test Biometric Enrollment
- Navigate to Biometric Enrollment
- Complete 3-ECG enrollment
- Verify template syncs to Supabase (encrypted)

### 3. Test EntraID Integration (Optional)
- Configure EntraID credentials in CredentialSetupView
- Tap "View Applications" button
- Sign in with Microsoft account

### 4. Deploy to Physical Device
- Connect iPhone via USB
- Build and run on device (Cmd+R)
- Pair with Apple Watch for ECG capture

---

## Security Best Practices

### ✅ DO:
- Use the "anon public" API key in the app
- Store credentials in Keychain (done automatically)
- Use biometric protection for sensitive keys
- Enable Row Level Security (RLS) on all tables
- Use different credentials for dev/staging/production

### ❌ DON'T:
- Never use the "service_role" key in the app
- Never commit credentials to Git
- Never share API keys publicly
- Never disable RLS on production tables

---

## Your Credentials Template

Fill this out as you gather your credentials:

```
Supabase Project Name: _________________________
Project URL: https://_________________________.supabase.co
Project ID: _________________________
API Key (anon public): eyJ_________________________
Region: _________________________
```

**Keep this information secure!** These credentials give access to your database.

---

## Support & Documentation

### Supabase Documentation:
- **Getting Started:** https://supabase.com/docs
- **Swift SDK:** https://supabase.com/docs/reference/swift
- **Authentication:** https://supabase.com/docs/guides/auth
- **Database:** https://supabase.com/docs/guides/database
- **Row Level Security:** https://supabase.com/docs/guides/auth/row-level-security

### CardiacID Documentation:
- **Setup Guide:** DEPENDENCY_SETUP_GUIDE.md
- **Error Fixes:** ALL_ERRORS_FIXED.md
- **Project Summary:** PROJECT_COMPLETE_SUMMARY.md

---

## Troubleshooting Checklist

Before asking for help, verify:

- [ ] I'm logged into Supabase dashboard
- [ ] I can see my project
- [ ] I've copied the correct Project URL
- [ ] I've copied the "anon public" API key (not service_role)
- [ ] Database tables exist (ran migration)
- [ ] App has been built successfully (no compile errors)
- [ ] I've entered credentials in CredentialSetupView
- [ ] I can see connection messages in Xcode console

---

*Generated with [Claude Code](https://claude.com/claude-code)*
*CardiacID - Supabase Login Guide*
*Date: November 5, 2025*
