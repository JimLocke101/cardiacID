# Azure EntraID / MSAL Integration Setup Guide

This guide walks you through completing the Azure EntraID integration for CardiacID.

## Configuration Values (Already Applied)

The following values from your Azure App Registration have been configured in `MSALConfiguration.swift`:

| Setting | Value |
|---------|-------|
| Display Name | CardiacID_0_8 |
| Client ID | c6414bc9-b537-4305-b277-a86f63fdb5ed |
| Tenant ID | 71fec99d-2fb1-4c59-b8a0-32d27906433f |
| Object ID | 6cfce22c-5111-4860-ba8f-2f75cb8cae48 |
| Redirect URI | msauth.ARGOS.CardiacID://auth |

## Step 1: Configure Xcode Project Settings

### Add URL Schemes (Required for MSAL callback)

1. Open `CardiacID.xcodeproj` in Xcode
2. Select the **CardiacID** target (iOS app)
3. Go to **Info** tab
4. Expand **URL Types**
5. Click **+** to add a new URL Type:
   - **Identifier**: `com.microsoft.msal`
   - **URL Schemes**: `msauth.ARGOS.CardiacID`
   - **Role**: Editor

### Add LSApplicationQueriesSchemes (Required for Microsoft Authenticator)

1. Still in the **Info** tab
2. Click **+** to add a new key
3. Add **LSApplicationQueriesSchemes** (Array)
4. Add two items:
   - `msauthv2`
   - `msauthv3`

### Alternative: Use the Info.plist File

If you prefer, copy the contents of `CardiacID/Info.plist` and:
1. In Xcode, select the CardiacID target
2. Go to Build Settings
3. Search for "Info.plist"
4. Set **Generate Info.plist File** to `NO`
5. Set **Info.plist File** to `CardiacID/Info.plist`

## Step 2: Configure Azure Portal

### Add Redirect URI in Azure

1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to: **App registrations** → **CardiacID_0_8** → **Authentication**
3. Under **Platform configurations**, click **Add a platform**
4. Select **iOS / macOS**
5. Enter Bundle ID: `ARGOS.CardiacID`
6. The Redirect URI will be auto-generated: `msauth.ARGOS.CardiacID://auth`
7. Click **Configure**

### Verify API Permissions

1. Go to: **App registrations** → **CardiacID_0_8** → **API permissions**
2. Ensure these permissions are added:

| Permission | Type | Status |
|------------|------|--------|
| User.Read | Delegated | ✓ Granted |
| openid | Delegated | ✓ Granted |
| profile | Delegated | ✓ Granted |
| email | Delegated | ✓ Granted |

3. If needed, click **Grant admin consent** for your organization

## Step 3: Test Authentication

1. Build and run the app on a device or simulator
2. Navigate to the Enterprise Auth or Settings screen
3. Tap "Sign in with Microsoft"
4. You should see the Microsoft sign-in page
5. Enter your organizational credentials
6. Upon success, you'll be redirected back to the app

## Troubleshooting

### "Redirect URI mismatch" Error
- Verify the redirect URI in Azure matches exactly: `msauth.ARGOS.CardiacID://auth`
- Check that the Bundle ID is `ARGOS.CardiacID`

### "AADSTS50011: Reply URL does not match"
- The redirect URI in Azure doesn't match the app's configuration
- Add the exact redirect URI from the error message to Azure Portal

### App doesn't return after sign-in
- Check that URL Schemes are correctly configured in Xcode
- Verify LSApplicationQueriesSchemes includes `msauthv2` and `msauthv3`
- Check the console for MSAL callback messages

### "MSAL not configured" Error
- Verify MSAL is included in Package.swift dependencies
- Clean build folder (Cmd+Shift+K) and rebuild

## Files Modified

- `CardiacID/Config/MSALConfiguration.swift` - Azure credentials
- `CardiacID/Services/EntraIDAuthClient.swift` - Updated to use MSALConfiguration
- `CardiacID/CardiacIDApp.swift` - Added AppDelegate for URL handling

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        CardiacIDApp                              │
│  ┌─────────────────┐                                            │
│  │   AppDelegate   │◄── Handles msauth:// URL callbacks         │
│  └────────┬────────┘                                            │
│           │                                                      │
│           ▼                                                      │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    EntraIDAuthClient                         ││
│  │  ┌─────────────────┐  ┌─────────────────────────────────┐  ││
│  │  │MSALConfiguration│  │  MSALPublicClientApplication    │  ││
│  │  │ • clientID      │──│  • acquireToken()               │  ││
│  │  │ • tenantID      │  │  • acquireTokenSilent()         │  ││
│  │  │ • redirectURI   │  │  • signOut()                    │  ││
│  │  └─────────────────┘  └─────────────────────────────────┘  ││
│  └─────────────────────────────────────────────────────────────┘│
│                              │                                   │
│                              ▼                                   │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                   Microsoft Graph API                        ││
│  │  • /me (User profile)                                       ││
│  │  • /me/memberOf (Groups)                                    ││
│  │  • /applications (Enterprise apps)                          ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```
