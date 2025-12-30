# CardiacID Build Fix Guide

## 🚨 **IMMEDIATE FIX STEPS**

### Step 1: Complete Project Cleanup

```bash
# Run this in Terminal from your project directory
cd "/Users/jimlocke/Desktop/ARGOS - Project HeartID"

# Clean all build artifacts
rm -rf DerivedData
rm -rf Build
rm -rf /Users/jimlocke/Desktop/Build

# Clean Xcode derived data
rm -rf ~/Library/Developer/Xcode/DerivedData/CardiacID-*

# Reset Swift Package Manager
rm -rf ~/Library/Caches/org.swift.swiftpm/
rm -rf ~/Library/org.swift.swiftpm/
```

### Step 2: Fix File Reference Issues in Xcode

1. **Open Xcode**
2. **Project Navigator → Select your project file**
3. **Check for duplicate file references:**

   **Look for these files that might be duplicated:**
   - `SecureCredentialManager.swift`
   - Any authentication-related files

4. **Remove duplicate references:**
   - Right-click on duplicate files → "Delete" → "Remove Reference" (NOT "Move to Trash")

5. **Re-add missing files:**
   - Right-click on your project → "Add Files to CardiacID"
   - Navigate to your working folder
   - Select `SecureCredentialManager.swift`
   - **CRITICAL**: Make sure to:
     - ✅ Check "Copy items if needed"
     - ✅ Select BOTH iOS AND watchOS targets
     - ❌ Do NOT add it twice

### Step 3: Verify Target Membership

For **SecureCredentialManager.swift**:

1. **Select the file in Project Navigator**
2. **Open File Inspector (right panel)**
3. **Verify Target Membership:**
   - ✅ CardiacID (iOS)
   - ✅ CardiacID WatchKit Extension (watchOS)
   - **Make sure it's checked ONLY ONCE for each target**

### Step 4: Package Dependencies Fix

1. **File → Packages → Reset Package Caches**
2. **Check Package Dependencies:**
   - Project Settings → Package Dependencies
   - **MSAL should ONLY be added to iOS target**
   - If it's added to watchOS target, remove it

### Step 5: Build Settings Verification

**iOS Target:**
```
Bundle Identifier: com.argos.cardiacid
App Groups: group.com.argos.cardiacid
Keychain Sharing: group.com.argos.cardiacid
```

**watchOS Target:**
```
Bundle Identifier: com.argos.cardiacid.watchkitextension
App Groups: group.com.argos.cardiacid
```

### Step 6: Manual Build Process

1. **Clean Build Folder** (Product → Clean Build Folder or ⌘+Shift+K)
2. **Build iOS target first**
3. **Build watchOS target second**

## 🔧 **Xcode Project Structure Fix**

### Correct File Organization:

```
CardiacID/
├── Shared/
│   ├── SecureCredentialManager.swift          [iOS + watchOS]
│   ├── WatchConnectivityService.swift         [iOS + watchOS]
│   ├── BuildConfiguration.swift              [iOS + watchOS]
│   └── AuthenticationModels.swift            [iOS + watchOS]
├── iOS/
│   ├── PlatformAuthService.swift             [iOS only]
│   ├── MSALConfiguration.swift               [iOS only]
│   └── iOSAuthView.swift                     [iOS only]
└── watchOS/
    ├── WatchAuthService.swift                [watchOS only]
    └── WatchAuthView.swift                   [watchOS only]
```

## 🎯 **Common Build Error Solutions**

### "Multiple commands produce"
**Cause**: Same file added multiple times to same target
**Fix**: Remove duplicate references, keep only one

### "Build input file cannot be found"
**Cause**: File reference exists but file is missing
**Fix**: Re-add file to project correctly

### "lstat: No such file or directory"
**Cause**: Corrupted build artifacts
**Fix**: Clean build folder and derived data

### "Command CodeSign failed"
**Cause**: Result of above build failures
**Fix**: Fix the root cause, then rebuild

## 🚀 **Verified Build Process**

### Step-by-Step Build Verification:

1. **Clean everything:**
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/CardiacID-*
   rm -rf Build
   rm -rf DerivedData
   ```

2. **In Xcode:**
   - Product → Clean Build Folder (⌘+Shift+K)
   - File → Packages → Reset Package Caches

3. **Verify project structure:**
   - No duplicate file references
   - Correct target membership
   - MSAL only linked to iOS

4. **Build order:**
   - iOS target first
   - watchOS target second

5. **Test authentication:**
   - iOS: MSAL interactive auth
   - watchOS: Token sharing via Watch Connectivity

## 🔍 **Troubleshooting Checklist**

- [ ] All duplicate file references removed
- [ ] SecureCredentialManager.swift exists and is properly added
- [ ] MSAL package only linked to iOS target
- [ ] App Groups configured on both targets
- [ ] Bundle identifiers are correct
- [ ] Build folder cleaned
- [ ] Derived data cleared
- [ ] Package caches reset
- [ ] iOS target builds successfully
- [ ] watchOS target builds successfully

## ⚠️ **Critical Notes**

1. **NEVER add MSAL to watchOS target** - It's not supported
2. **Always clean build folder** before rebuilding after fixes
3. **Check target membership** for every shared file
4. **Use App Groups** for cross-platform data sharing
5. **Build iOS first, then watchOS** to resolve dependencies

## 🏁 **Success Indicators**

When everything is fixed correctly:
- ✅ No build errors
- ✅ No duplicate file warnings
- ✅ iOS app authenticates with MSAL
- ✅ watchOS app receives tokens from iOS
- ✅ Both apps can make authenticated API calls
- ✅ Code signing succeeds

Follow this guide step by step, and your build errors will be resolved!