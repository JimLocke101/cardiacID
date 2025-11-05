# Dependency Setup Guide - Fix Import Errors

**Status:** Missing Swift Package Dependencies
**Issue:** MSAL and Supabase packages not properly configured in Xcode project

---

## Problem

The following import errors are occurring:
```
Unable to find module dependency: 'MSAL'
Unable to find module dependency: 'Supabase'
Unable to find module dependency: 'Auth'
Unable to find module dependency: 'PostgREST'
```

**Root Cause:** The Xcode project has Supabase v2.5.1 configured but needs v2.37.0, and MSAL is completely missing.

---

## Solution: Add Swift Packages in Xcode

### Step 1: Open Project in Xcode

1. Navigate to:
   ```
   /Users/jimlocke/Desktop/ARGOS - Project HeartID/HeartID Apps/HeartID_folder/
   HeartID Mobile Nov 4 - No Tech Menu (Backup Sep 17 1130)/Cardiac ID/CardiacID/
   ```

2. Double-click `CardiacID.xcodeproj` to open in Xcode

---

### Step 2: Update Supabase Package

1. In Xcode, select the **CardiacID** project in the navigator (top item)
2. Select the **CardiacID** target
3. Click the **Package Dependencies** tab
4. Find **supabase-swift** in the list
5. Select it and click the **"-"** button to remove it
6. Click the **"+"** button to add a new package
7. Enter this URL:
   ```
   https://github.com/supabase/supabase-swift.git
   ```
8. In **Dependency Rule**, select "Up to Next Major Version"
9. Enter minimum version: `2.37.0`
10. Click **Add Package**
11. When the package options appear, select these products:
    - ✅ Supabase
    - ✅ Auth
    - ✅ PostgREST
    - ✅ Realtime
    - ✅ Storage
12. Make sure they're added to the **CardiacID** target
13. Click **Add Package**

---

### Step 3: Add MSAL Package

1. Still in **Package Dependencies** tab, click the **"+"** button
2. Enter this URL:
   ```
   https://github.com/AzureAD/microsoft-authentication-library-for-objc.git
   ```
3. In **Dependency Rule**, select "Up to Next Major Version"
4. Enter minimum version: `2.5.1`
5. Click **Add Package**
6. When the package options appear, select:
    - ✅ MSAL
7. Make sure it's added to the **CardiacID** target
8. Click **Add Package**

---

### Step 4: Resolve Packages

1. In Xcode menu, go to **File** → **Packages** → **Resolve Package Versions**
2. Wait for Xcode to download and resolve all packages (may take 1-2 minutes)
3. Check for any errors in the **Package Dependencies** section

---

### Step 5: Clean Build Folder

1. In Xcode menu, go to **Product** → **Clean Build Folder** (or press Shift+Cmd+K)
2. Wait for cleaning to complete

---

### Step 6: Build Project

1. Select a target device (e.g., iPhone 15 Pro simulator)
2. Press **Cmd+B** to build
3. Verify all import errors are resolved

---

## Alternative: Command Line Fix (Advanced)

If you prefer command line, you can try resolving packages via `xcodebuild`:

```bash
cd "/Users/jimlocke/Desktop/ARGOS - Project HeartID/HeartID Apps/HeartID_folder/HeartID Mobile Nov 4 - No Tech Menu (Backup Sep 17 1130)/Cardiac ID/CardiacID"

# Resolve packages
xcodebuild -resolvePackageDependencies -project CardiacID.xcodeproj -scheme CardiacID

# Clean build folder
xcodebuild clean -project CardiacID.xcodeproj -scheme CardiacID

# Build
xcodebuild build -project CardiacID.xcodeproj -scheme CardiacID -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

**Note:** This requires the packages to already be added to the project file, which they're not (MSAL is missing).

---

## Verification

After completing the steps, verify these imports work:

**EntraIDAuthClient.swift:**
```swift
import Foundation
import MSAL  // Should work now
```

**SupabaseClient.swift:**
```swift
import Foundation
import Supabase  // Should work now
import Auth      // Should work now
import PostgREST // Should work now
import Combine
```

---

## Troubleshooting

### Issue: "Package Resolution Failed"

**Solution:**
1. Check internet connection
2. Go to **File** → **Packages** → **Reset Package Caches**
3. Try resolving again

### Issue: "Version Conflict"

**Solution:**
1. Remove all packages
2. Add them one at a time in this order:
   - Supabase first
   - MSAL second
3. Resolve after each addition

### Issue: "Product Not Found"

**Solution:**
1. Make sure you selected the correct products when adding packages
2. Go to target's **General** tab → **Frameworks, Libraries, and Embedded Content**
3. Click "+" and manually add:
   - MSAL
   - Supabase
   - Auth
   - PostgREST

### Issue: Still Getting Import Errors

**Solution:**
1. Clean Build Folder (Shift+Cmd+K)
2. Delete DerivedData:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData
   ```
3. Quit and restart Xcode
4. Rebuild

---

## Note About Package.swift

The `Package.swift` file we created is **not used by Xcode projects**. It's only for Swift Package Manager libraries.

The Xcode project uses its own package management system defined in `project.pbxproj`.

**You can safely ignore or delete the Package.swift file** at the root of the CardiacID directory - it won't affect the Xcode project.

---

## Expected Result

After following these steps, you should see:

✅ No import errors
✅ Green build indicator
✅ All files compile successfully
✅ Package dependencies shown in Project Navigator under "Package Dependencies"

---

## Next Steps After Fix

Once dependencies are resolved:

1. **Configure Credentials**
   - Launch app
   - Complete CredentialSetupView
   - Enter Supabase API key and URL
   - Enter EntraID credentials

2. **Test Basic Functionality**
   - Test Supabase connection
   - Test EntraID sign-in
   - Verify no runtime errors

3. **Physical Testing**
   - Deploy to real iPhone
   - Test with Apple Watch
   - Verify ECG capture works

---

*Last Updated: January 2025*
