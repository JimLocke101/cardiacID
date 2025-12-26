# Your CardiacID Supabase Configuration ✅

**Date:** November 5, 2025
**Status:** READY TO USE

---

## ✅ Your Supabase Project

### Project Information
```
Project Name: CardiacID
Project ID: xytycgdlafncjszhgems
Project URL: https://xytycgdlafncjszhgems.supabase.co
```

### API Credentials
```
API Key (anon public):
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh5dHljZ2RsYWZuY2pzemhnZW1zIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjIzOTc2MDIsImV4cCI6MjA3Nzk3MzYwMn0.F1uiQX0U_H78C8JATrwlpKys9UzUyaM_nMZUHNrvp7I
```

### Supabase Account Login
```
Username: CardiacID
Password: CardiacID2025!
Dashboard: https://supabase.com/dashboard/project/xytycgdlafncjszhgems
```

### Test User Account
```
Email: jimlocke101@gmail.com
Password: jimlocke1017704LockeFamily2009
```

---

## 🚀 Quick Setup (3 Steps)

### Step 1: Run Database Migration

1. **Open Supabase Dashboard:**
   ```
   https://supabase.com/dashboard/project/xytycgdlafncjszhgems
   ```

2. **Log in:**
   - Username: CardiacID
   - Password: CardiacID2025!

3. **Navigate to SQL Editor:**
   - Click **"SQL Editor"** in left sidebar
   - Click **"New query"**

4. **Run Migration:**
   - Open file: `CardiacID/Database/Migrations/001_initial_schema.sql`
   - Copy all contents
   - Paste into SQL Editor
   - Click **"Run"** (or press Cmd+Enter)

**✅ Expected Result:** 6 tables created
- users
- biometric_templates
- authentication_sessions
- devices
- activity_logs
- user_enrollments

---

### Step 2: Launch CardiacID App

**In Xcode:**
```bash
# Select CardiacID scheme
# Choose iPhone 15 Pro simulator
# Press Cmd+R to build and run
```

**✅ Expected:** App launches with CredentialSetupView

---

### Step 3: Enter Credentials in App

**When CredentialSetupView appears, enter:**

**Supabase Configuration:**
```
Supabase URL:
https://xytycgdlafncjszhgems.supabase.co

Supabase API Key:
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh5dHljZ2RsYWZuY2pzemhnZW1zIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjIzOTc2MDIsImV4cCI6MjA3Nzk3MzYwMn0.F1uiQX0U_H78C8JATrwlpKys9UzUyaM_nMZUHNrvp7I
```

**EntraID Configuration (Optional - can leave blank for now):**
```
Tenant ID: [Leave blank]
Client ID: [Leave blank]
```

**Then tap:** "Save Credentials"

**✅ Expected:** Credentials saved to Keychain, Login screen appears

---

## 🧪 Test Your Connection

### Sign Up with Test Account

1. On Login screen, tap **"Sign Up"**
2. Enter your test credentials:
   ```
   Email: jimlocke101@gmail.com
   Password: jimlocke1017704LockeFamily2009
   ```
3. Tap **"Sign Up"**

**✅ Expected Success Messages in Xcode Console:**
```
✅ Supabase client initialized successfully
✅ User signed up successfully: jimlocke101@gmail.com
✅ User profile created in database
```

### Verify in Supabase Dashboard

1. Go to Supabase dashboard
2. Click **"Authentication"** → **"Users"**
3. You should see: jimlocke101@gmail.com

4. Click **"Table Editor"** → **"users"**
5. You should see your user record with:
   - ID: [UUID]
   - Email: jimlocke101@gmail.com
   - enrollment_status: pending
   - created_at: [timestamp]

---

## 📋 Configuration Summary

### Updated Files
✅ **Config/Debug.xcconfig** - Updated with correct project ID

### Your Credentials (Quick Reference)
```bash
# For copying into app:
URL: https://xytycgdlafncjszhgems.supabase.co
KEY: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh5dHljZ2RsYWZuY2pzemhnZW1zIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjIzOTc2MDIsImV4cCI6MjA3Nzk3MzYwMn0.F1uiQX0U_H78C8JATrwlpKys9UzUyaM_nMZUHNrvp7I
```

---

## 🔧 Database Schema

The migration creates these tables:

### 1. users
```sql
- id: UUID (primary key)
- email: TEXT (unique)
- first_name: TEXT
- last_name: TEXT
- profile_image_url: TEXT
- enrollment_status: TEXT (pending/in_progress/completed)
- created_at: TIMESTAMP
- updated_at: TIMESTAMP
```

### 2. biometric_templates
```sql
- id: UUID (primary key)
- user_id: UUID (foreign key → users.id)
- encrypted_template_data: BYTEA
- encryption_key_id: TEXT
- template_version: TEXT
- quality_score: NUMERIC
- created_at: TIMESTAMP
- updated_at: TIMESTAMP
- last_used_at: TIMESTAMP
```

### 3. authentication_sessions
```sql
- id: UUID (primary key)
- user_id: UUID (foreign key → users.id)
- device_id: UUID (foreign key → devices.id)
- confidence_score: NUMERIC
- authentication_method: TEXT (ecg/ppg/hybrid)
- started_at: TIMESTAMP
- ended_at: TIMESTAMP
- session_status: TEXT (active/completed/expired)
```

### 4. devices
```sql
- id: UUID (primary key)
- user_id: UUID (foreign key → users.id)
- device_name: TEXT
- device_model: TEXT
- os_version: TEXT
- app_version: TEXT
- last_seen_at: TIMESTAMP
- registered_at: TIMESTAMP
```

### 5. activity_logs
```sql
- id: UUID (primary key)
- user_id: UUID (foreign key → users.id)
- activity_type: TEXT
- activity_details: JSONB
- ip_address: TEXT
- user_agent: TEXT
- created_at: TIMESTAMP
```

### 6. user_enrollments
```sql
- id: UUID (primary key)
- user_id: UUID (foreign key → users.id)
- enrollment_step: TEXT
- samples_collected: INTEGER
- current_quality_score: NUMERIC
- started_at: TIMESTAMP
- completed_at: TIMESTAMP
- enrollment_status: TEXT
```

---

## 🔐 Security Features

### Row Level Security (RLS)
All tables have RLS enabled with policies:

**Users can:**
- ✅ View their own data only
- ✅ Update their own profile
- ✅ Insert their own records
- ❌ Cannot view/modify other users' data

**Example Policy:**
```sql
CREATE POLICY "Users can view own profile"
    ON public.users FOR SELECT
    USING (auth.uid() = id);
```

### Encrypted Storage
- Biometric templates are encrypted client-side with AES-256-GCM
- Server only stores encrypted data (zero-knowledge)
- Encryption keys stored in iOS Keychain with biometric protection

---

## 📱 App Features Ready to Test

### 1. Authentication
- ✅ Sign up with email/password
- ✅ Sign in with existing account
- ✅ Password reset flow
- ✅ Session management

### 2. Biometric Enrollment
- ✅ 3-ECG sample collection
- ✅ Quality validation
- ✅ Template creation
- ✅ Encrypted cloud sync

### 3. Continuous Authentication
- ✅ PPG monitoring (Apple Watch)
- ✅ Confidence scoring
- ✅ Wrist detection
- ✅ Auto re-authentication

### 4. EntraID Integration (Optional)
- ⏳ Requires Microsoft Azure AD credentials
- ⏳ "View Applications" feature
- ⏳ Enterprise SSO

---

## 🐛 Troubleshooting

### "Supabase API key not found in Keychain"
**Solution:** Launch app, complete CredentialSetupView

### "Invalid API key"
**Solution:** Make sure you copied the full key (starts with `eyJ...`)

### "Connection refused"
**Solution:**
1. Check internet connection
2. Verify URL has no typos
3. Check if project is paused in Supabase dashboard

### Tables don't exist
**Solution:** Run the migration SQL in Supabase SQL Editor

### Sign up fails
**Solution:**
1. Check Xcode console for error details
2. Verify email format is valid
3. Check password meets requirements (8+ chars)

---

## 📊 Next Steps

### 1. Complete Initial Setup ✅
- [x] Update xcconfig with project ID
- [ ] Run database migration
- [ ] Launch app
- [ ] Enter credentials
- [ ] Sign up test user

### 2. Test Core Features
- [ ] Sign up / Sign in
- [ ] View dashboard
- [ ] Update profile
- [ ] Test biometric enrollment (requires Apple Watch)

### 3. Deploy to Device
- [ ] Connect iPhone via USB
- [ ] Build and run on device
- [ ] Pair Apple Watch
- [ ] Test ECG capture

### 4. Configure EntraID (Optional)
- [ ] Get Azure AD credentials
- [ ] Enter in app settings
- [ ] Test "View Applications"

---

## 🎯 Quick Commands

### Open Supabase Dashboard
```bash
open "https://supabase.com/dashboard/project/xytycgdlafncjszhgems"
```

### Open SQL Editor
```bash
open "https://supabase.com/dashboard/project/xytycgdlafncjszhgems/editor"
```

### Open Table Editor
```bash
open "https://supabase.com/dashboard/project/xytycgdlafncjszhgems/editor"
```

### Launch App in Xcode
```
Cmd+R
```

---

## 📞 Support

### Supabase Documentation
- **Dashboard:** https://supabase.com/dashboard
- **Docs:** https://supabase.com/docs
- **Swift SDK:** https://supabase.com/docs/reference/swift

### CardiacID Documentation
- **Quick Start:** QUICK_START.md
- **Login Guide:** SUPABASE_LOGIN_GUIDE.md
- **Error Fixes:** ALL_ERRORS_FIXED.md

---

**Your CardiacID app is configured and ready to connect to Supabase!**

**Next:** Run the app in Xcode (Cmd+R) and enter your credentials.

---

*CardiacID - Supabase Configuration Complete*
*Project: xytycgdlafncjszhgems*
*Date: November 5, 2025*
