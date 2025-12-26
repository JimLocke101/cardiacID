# Code Signing Error Fix Guide

## Error: "A valid provisioning profile for this executable was not found" (0xe8008015)

### Current Configuration
- **Bundle Identifier**: `ARGOS.CardiacID`
- **Development Team**: `PYGGR5786Z`
- **Code Sign Style**: Automatic
- **Device**: iPhone (iPhone17,1)

---

## Step-by-Step Fix

### 1. Verify Xcode Signing Settings

1. Open your project in Xcode
2. Select the **CardiacID** target (main app, not Watch app)
3. Go to **Signing & Capabilities** tab
4. Check:
   - ✅ "Automatically manage signing" is **checked**
   - ✅ **Team** is set to `PYGGR5786Z` (or your correct team)
   - ✅ **Bundle Identifier** is `ARGOS.CardiacID`
   - ✅ No red error messages

5. If you see errors:
   - Click **"Try Again"** or **"Download Manual Profiles"**
   - Wait for Xcode to resolve signing issues

### 2. Register Your Device

1. Connect your iPhone to your Mac
2. In Xcode: **Window → Devices and Simulators** (Shift+Cmd+2)
3. Select your iPhone from the left sidebar
4. Verify it shows as **"Ready"** or **"Connected"**
5. If device is not registered:
   - Trust the computer on your iPhone (if prompted)
   - Xcode should automatically register it

### 3. Verify Bundle Identifier Registration

The bundle identifier `ARGOS.CardiacID` must be registered in your Apple Developer account:

1. Go to [Apple Developer Portal](https://developer.apple.com/account)
2. Navigate to **Certificates, Identifiers & Profiles**
3. Go to **Identifiers** → **App IDs**
4. Search for `ARGOS.CardiacID`
5. If it doesn't exist:
   - Click **+** to create a new App ID
   - Enter `ARGOS.CardiacID` as the Bundle ID
   - Select required capabilities (App Groups, etc.)
   - Register it

### 4. Clean Build and Derived Data

1. In Xcode: **Product → Clean Build Folder** (Shift+Cmd+K)
2. Delete Derived Data:
   - **Xcode → Settings → Locations**
   - Click the arrow next to Derived Data path
   - Delete the folder for your project
3. Close Xcode completely
4. Reopen Xcode and your project

### 5. Verify Apple ID and Team

1. **Xcode → Settings** (Cmd+,)
2. Go to **Accounts** tab
3. Verify your Apple ID is listed
4. Select your account and click **Download Manual Profiles**
5. Ensure Team `PYGGR5786Z` is available

### 6. Check Entitlements

Your app uses App Groups. Ensure:
- App Groups are enabled in Apple Developer Portal
- The groups `group.ARGOS.HeartIDv0.6` and `group.com.heartid.ecg.shared` are registered
- They're added to your App ID in the Developer Portal

### 7. Alternative: Manual Signing (if Automatic fails)

If automatic signing continues to fail:

1. In **Signing & Capabilities**:
   - Uncheck "Automatically manage signing"
   - Select a **Provisioning Profile** manually
   - Or create one in Apple Developer Portal:
     - Go to **Profiles** → **+**
     - Select **iOS App Development**
     - Select your App ID (`ARGOS.CardiacID`)
     - Select your certificates
     - Select your device
     - Download and install the profile
     - Select it in Xcode

### 8. Trust Developer on Device

On your iPhone:
1. Go to **Settings → General → VPN & Device Management**
2. Find your developer certificate
3. Tap it and select **Trust**

### 9. Rebuild and Install

1. **Product → Clean Build Folder**
2. **Product → Build** (Cmd+B)
3. Check for any signing errors in the build log
4. **Product → Run** (Cmd+R)

---

## Common Issues and Solutions

### Issue: "No profiles for 'ARGOS.CardiacID' were found"
**Solution**: The bundle ID isn't registered. Register it in Apple Developer Portal (Step 3).

### Issue: "Device not registered"
**Solution**: Connect device, trust computer, let Xcode register it (Step 2).

### Issue: "Team ID mismatch"
**Solution**: Verify the team ID `PYGGR5786Z` matches your Apple Developer account.

### Issue: "Provisioning profile expired"
**Solution**: Download new profiles (Step 1 or 5).

### Issue: "App Groups not configured"
**Solution**: Enable App Groups in Developer Portal and add to App ID.

---

## Quick Checklist

- [ ] Xcode Signing & Capabilities shows no errors
- [ ] Device is registered and trusted
- [ ] Bundle ID exists in Apple Developer Portal
- [ ] Team ID matches your account
- [ ] App Groups are configured in Developer Portal
- [ ] Derived Data is cleaned
- [ ] Profiles are downloaded
- [ ] Developer certificate is trusted on device

---

## Still Having Issues?

If the problem persists:

1. **Check Xcode Console** for detailed error messages
2. **Check Apple Developer Portal** for any account issues
3. **Verify your Apple Developer account** is active and paid (if required)
4. **Try a different bundle identifier** temporarily to test if it's a bundle ID issue
5. **Contact Apple Developer Support** if account/billing issues

---

## Notes

- The error code `0xe8008015` specifically means "A valid provisioning profile for this executable was not found"
- This is a **code signing** issue, not a code issue
- Automatic signing should handle most cases, but manual intervention may be needed
- Ensure your Apple Developer account has the necessary permissions










