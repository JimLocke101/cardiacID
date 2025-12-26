# Supabase Credentials for CardiacID

**Project ID:** bzxzugwguozsymqezvig
**Account:** jimlocke101@gmail.com

---

## Your Supabase Configuration

### Project URL
```
https://bzxzugwguozsymqezvig.supabase.co
```

### Project Dashboard
```
https://supabase.com/dashboard/project/bzxzugwguozsymqezvig
```

---

## To Get Your API Key

**I've opened your project dashboard. Now:**

1. **Log in** if prompted:
   - Email: jimlocke101@gmail.com
   - Password: [use your password]

2. **Once logged in, navigate to:**
   - Click **"Settings"** (gear icon in left sidebar)
   - Click **"API"** under Settings
   - Look for **"Project API keys"**

3. **Copy the "anon public" key:**
   - It's a long string starting with `eyJ...`
   - This is safe to use in your app
   - DO NOT use the "service_role" key

---

## Quick Setup Command

Once you have your API key, you can quickly test the connection:

### Your Supabase URL (ready to use):
```
https://bzxzugwguozsymqezvig.supabase.co
```

### Your API Key:
```
[Get this from Settings → API → "anon public"]
```

---

## Next Steps

### 1. Get API Key (1 minute)
- Follow instructions above
- Copy the "anon public" key

### 2. Run Database Migration (1 minute)
- In your open Supabase dashboard
- Click **"SQL Editor"** (left sidebar)
- Click **"New query"**
- Copy contents from: `CardiacID/Database/Migrations/001_initial_schema.sql`
- Paste and click **"Run"**

### 3. Launch CardiacID App
```bash
# In Xcode, press Cmd+R
```

### 4. Enter Credentials in App
When CredentialSetupView appears:
- **Supabase URL:** `https://bzxzugwguozsymqezvig.supabase.co`
- **Supabase API Key:** [Paste your anon public key]
- Tap "Save Credentials"

---

## Testing Connection

After entering credentials, test by signing up:
- Email: test@heartid.com
- Password: TestPassword123!

Check Xcode console for:
```
✅ Supabase client initialized successfully
✅ User signed up successfully
```

---

**Security Note:** Keep your API keys secure. The "anon public" key is safe for client apps, but never commit it to public repositories.

---

*CardiacID Supabase Setup*
*Project: bzxzugwguozsymqezvig*
