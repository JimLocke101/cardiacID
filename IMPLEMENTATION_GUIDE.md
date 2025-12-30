# CardiacID MSAL Integration - Complete Implementation Guide

## 🚀 Overview

This is a complete, tested solution for integrating MSAL (Microsoft Authentication Library) with your CardiacID project that supports both iOS and watchOS platforms. The solution resolves the build errors you were experiencing and provides a robust cross-platform authentication system.

## 🔧 Project Setup Instructions

### 1. Clean Build Environment

First, clean your build environment:

```bash
# In Xcode
Product → Clean Build Folder (⌘+Shift+K)

# Or via command line
cd /path/to/your/project
rm -rf DerivedData
rm -rf Build
```

### 2. Package Dependencies Configuration

In Xcode:

1. **Remove existing MSAL package** (if added incorrectly)
   - Go to Project Settings → Package Dependencies
   - Remove any existing MSAL entries

2. **Add MSAL correctly**:
   - Add Package: `https://github.com/AzureAD/microsoft-authentication-library-for-objc`
   - Version: `1.3.0` or later
   - **Important**: Only add to iOS target, NOT watchOS target

### 3. Target Configuration

#### iOS Target:
- ✅ Link MSAL framework
- ✅ Add all authentication files
- ✅ Enable App Groups capability: `group.com.argos.cardiacid`

#### watchOS Target:
- ❌ Do NOT link MSAL framework
- ✅ Add shared authentication files (exclude iOS-specific MSAL code)
- ✅ Enable App Groups capability: `group.com.argos.cardiacid`

### 4. Info.plist Configuration

Add to both iOS and watchOS Info.plist:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>com.argos.cardiacid.auth</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>cardiacid</string>
        </array>
    </dict>
</array>
```

### 5. Entitlements Configuration

Create/update entitlements files:

#### iOS: `CardiacID.entitlements`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.argos.cardiacid</string>
    </array>
    <key>keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)group.com.argos.cardiacid</string>
    </array>
</dict>
</plist>
```

#### watchOS: `CardiacID WatchKit Extension.entitlements`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.argos.cardiacid</string>
    </array>
</dict>
</plist>
```

## 📁 File Organization

### Core Authentication Files (Both Platforms):
- `PlatformAuthService.swift` - Main authentication service
- `SecureCredentialManager.swift` - Cross-platform credential storage
- `WatchConnectivityService.swift` - Cross-platform communication
- `BuildConfiguration.swift` - Build configuration and feature flags
- `UnifiedAuthView.swift` - Cross-platform authentication UI

### iOS-Only Files:
- `MSALConfiguration.swift` - MSAL configuration helper
- `iOSAuthView.swift` - iOS-specific authentication UI

### watchOS-Only Files:
- `WatchAuthView.swift` - watchOS-specific authentication UI
- `WatchAuthService.swift` - watchOS authentication service

### Testing:
- `CardiacIDTests.swift` - Comprehensive test suite

## 🔐 Configuration Setup

### 1. EntraID Application Registration

1. Go to Azure Portal → Azure Active Directory → App Registrations
2. Create new registration:
   - Name: `CardiacID Mobile`
   - Supported account types: Choose appropriate option
   - Redirect URI: `cardiacid://auth`

3. Note down:
   - **Application (client) ID**
   - **Directory (tenant) ID**

### 2. Code Configuration

In your app, configure the credentials:

```swift
// In your app initialization
let msalConfig = MSALConfiguration.shared
try msalConfig.setupConfiguration(
    tenantId: "your-tenant-id-here",
    clientId: "your-client-id-here"
)
```

## 🔄 Authentication Flow

### iOS Flow:
1. User taps "Sign In" → MSAL interactive authentication
2. User authenticates with Microsoft
3. iOS app receives tokens
4. Tokens shared with watchOS via Watch Connectivity

### watchOS Flow:
1. User taps "Authenticate" → Request sent to iOS
2. iOS handles MSAL authentication
3. Tokens sent back to watchOS
4. watchOS stores tokens for API calls

## 🧪 Testing

Run the comprehensive test suite:

```swift
// Tests validate:
// ✅ Platform detection
// ✅ Credential storage/retrieval
// ✅ MSAL configuration
// ✅ Watch connectivity
// ✅ Security/encryption
// ✅ End-to-end integration
```

## 📱 Usage Examples

### iOS Implementation:
```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        UnifiedAuthView()
    }
}
```

### watchOS Implementation:
```swift
import SwiftUI

struct WatchContentView: View {
    var body: some View {
        NavigationView {
            UnifiedAuthView()
        }
    }
}
```

## 🛠️ Build Process

### Build Order:
1. Clean build folder
2. Build iOS target first
3. Build watchOS target second
4. Archive for distribution

### Conditional Compilation:
The code uses proper platform conditionals:
- `#if os(iOS)` - iOS-specific code
- `#if os(watchOS)` - watchOS-specific code
- `#if canImport(MSAL)` - MSAL availability check

## 🔍 Troubleshooting

### Common Issues:

1. **"No library for watchOS found"**
   - Solution: Remove MSAL from watchOS target dependencies

2. **"PackageDescription import error"**
   - Solution: Don't add Package.swift as source file

3. **"Code signing failed"**
   - Solution: Clean build folder and rebuild

4. **"Session not activated"**
   - Solution: Ensure App Groups are configured correctly

### Debug Information:
```swift
// Add to app launch
let config = BuildConfiguration.shared
config.printConfiguration()
```

## 🏁 Final Verification

After implementation, verify:

1. ✅ iOS app builds successfully
2. ✅ watchOS app builds successfully  
3. ✅ Authentication works on iOS
4. ✅ Tokens are shared with watchOS
5. ✅ API calls work from both platforms
6. ✅ Tests pass on both platforms

## 📋 Checklist

- [ ] Clean build environment
- [ ] Configure package dependencies correctly
- [ ] Set up App Groups on both targets
- [ ] Add proper entitlements
- [ ] Configure EntraID application
- [ ] Set tenant and client IDs
- [ ] Test authentication flow
- [ ] Verify cross-platform communication
- [ ] Run comprehensive tests
- [ ] Build and archive successfully

This solution provides a robust, tested, and maintainable authentication system that properly handles the platform differences between iOS and watchOS while maintaining security and user experience.