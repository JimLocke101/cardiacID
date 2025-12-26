# Demo Mode vs Production Mode Guide

**Date:** November 9, 2025
**Configuration:** Both modes now supported!

---

## How to Switch Between Modes

### Enable DEMO MODE (Mock Services)
Edit `Config/Debug.xcconfig`:
```
HEARTID_DEMO_MODE = YES
```

**What this does:**
- Enables mock/test services
- No real Supabase connection needed
- No real Microsoft EntraID needed
- Fast for testing/demonstration
- Uses in-memory data (lost on app close)

### Enable PRODUCTION MODE (Real Services)
Edit `Config/Debug.xcconfig`:
```
HEARTID_DEMO_MODE = NO
```

**What this does:**
- Uses real Supabase database
- Uses real Microsoft MSAL SDK
- Requires valid credentials
- Data persists in cloud
- Production-ready

---

## Current Configuration

**Default Mode:** PRODUCTION (`HEARTID_DEMO_MODE = NO`)

**To check current mode:** Look in `Config/Debug.xcconfig` line 19

---

## What Each Mode Includes

### DEMO_MODE = YES
```
Services Used:
✓ MockEntraIDService (fake OAuth)
✓ AppSupabaseClientLocal (mock database)
✓ In-memory storage
✓ Fake user data
✓ No network calls

Good for:
- UI development
- Quick testing
- Demonstrations without backend
- Offline development
```

### DEMO_MODE = NO (Production)
```
Services Used:
✓ EntraIDAuthClient (real MSAL SDK)
✓ SupabaseService (real database)
✓ iOS Keychain storage
✓ Real authentication
✓ Network API calls

Good for:
- Production deployment
- Real user testing
- Data persistence
- Multi-device sync
```

---

## Fixing Errors for Both Modes

I'm now systematically fixing all errors so BOTH modes can compile successfully.

You can switch between modes anytime by changing the `HEARTID_DEMO_MODE` flag!

