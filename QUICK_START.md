# CardiacID Quick Start Guide 🚀

**Get your app running in 5 minutes!**

---

## ✅ Prerequisites Completed

- [x] All build errors fixed
- [x] Swift packages installed (MSAL, Supabase)
- [x] Xcode project configured
- [x] Supabase dashboard opened

---

## 🎯 Quick Start Steps

### Step 1: Get Supabase Credentials (2 minutes)

**The Supabase dashboard is now open in your browser.**

1. **Log in** to Supabase (if not already logged in)
2. **Select your project** from the projects list
3. Click **"Settings"** → **"API"**
4. **Copy these two values:**

   📝 **Project URL:**
   ```
   https://[your-project-id].supabase.co
   ```

   📝 **API Key (anon public):**
   ```
   eyJ... [long string]
   ```

### Step 2: Run Database Migration (1 minute)

1. In Supabase dashboard, click **"SQL Editor"** (left sidebar)
2. Click **"New query"**
3. Open this file in a text editor:
   ```
   CardiacID/Database/Migrations/001_initial_schema.sql
   ```
4. Copy all contents and paste into Supabase SQL Editor
5. Click **"Run"** (or Cmd+Enter)

**✅ Result:** 6 tables created (users, biometric_templates, etc.)

### Step 3: Launch the App (2 minutes)

**In Xcode (already open):**

1. Select **CardiacID** scheme
2. Choose **iPhone 15 Pro** simulator (or your device)
3. Press **Cmd+R** to build and run

**✅ Result:** App launches with CredentialSetupView

### Step 4: Enter Credentials in App

**When CredentialSetupView appears:**

1. **Supabase URL:** Paste your Project URL from Step 1
2. **Supabase API Key:** Paste your API Key from Step 1
3. **EntraID fields:** Leave blank for now (optional)
4. Tap **"Save Credentials"**

**✅ Result:** Credentials securely stored in Keychain

### Step 5: Test Connection

1. **Login screen** appears
2. Tap **"Sign Up"**
3. Enter:
   - Email: `test@heartid.com`
   - Password: `TestPassword123!`
4. Tap **"Sign Up"**

**✅ Expected:** User created, dashboard appears

**Check Xcode console for:**
```
✅ Supabase client initialized successfully
✅ User signed up successfully
```

---

## 🎉 Success Indicators

### You're all set if you see:

✅ App launches without crashes
✅ CredentialSetupView accepted your credentials
✅ Login screen appears
✅ Test user signs up successfully
✅ Dashboard appears after login
✅ Xcode console shows success messages

---

## 🐛 Quick Troubleshooting

### App crashes on launch?
```bash
# Clean build and retry
Xcode → Product → Clean Build Folder (Shift+Cmd+K)
# Then Cmd+R to run again
```

### "Supabase API key not found"?
- Launch the app again
- CredentialSetupView should appear automatically
- Re-enter credentials

### "Invalid API key"?
- Make sure you copied the **"anon public"** key
- NOT the "service_role" key

### Tables missing in Supabase?
- Run the migration from Step 2 again
- Verify in Supabase → Table Editor

---

## 📚 Detailed Guides

For more detailed information, see:

- **[SUPABASE_LOGIN_GUIDE.md](SUPABASE_LOGIN_GUIDE.md)** - Complete Supabase setup
- **[ALL_ERRORS_FIXED.md](ALL_ERRORS_FIXED.md)** - Build fixes applied
- **[PROJECT_COMPLETE_SUMMARY.md](PROJECT_COMPLETE_SUMMARY.md)** - Full project overview

---

## 🚀 Next Steps After Setup

### 1. Explore the App
- Dashboard view
- Biometric enrollment (requires Apple Watch)
- Technology management
- Profile settings

### 2. Test on Physical Device
- Connect iPhone via USB
- Select iPhone as target
- Build and run (Cmd+R)
- Pair Apple Watch for ECG

### 3. Configure EntraID (Optional)
- Get Microsoft Azure AD credentials
- Enter in Settings → Security Settings
- Test "View Applications" feature

---

## ⏱️ Estimated Time: 5 minutes

**Current Status:**
- ✅ Build errors fixed
- ✅ Packages installed
- ✅ Supabase dashboard opened
- ⏳ **YOU ARE HERE** → Get credentials and run app

---

*Quick Start Guide - CardiacID*
*Let's get you running!*
