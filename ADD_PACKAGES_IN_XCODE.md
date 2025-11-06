# Add Packages in Xcode - Step by Step Guide

**Issue:** Missing package product 'MSAL' and 'Supabase'
**Solution:** Add packages through Xcode UI (required for proper linking)

---

## Why This is Needed

Swift Package products **must be added through Xcode's UI** because:
1. Xcode needs to inspect the Package.swift manifest
2. Product names must match exactly what the package exposes
3. Xcode handles framework vs library differences automatically
4. Manual editing of project.pbxproj can cause mismatches

---

## Step-by-Step Instructions

### Step 1: Open Project in Xcode

The project should already be open. If not:
```bash
open "/Users/jimlocke/Desktop/ARGOS - Project HeartID/HeartID Apps/HeartID_folder/HeartID Mobile Nov 4 - No Tech Menu (Backup Sep 17 1130)/Cardiac ID/CardiacID/CardiacID.xcodeproj"
```

---

### Step 2: Select CardiacID Target

1. In Xcode, click on **CardiacID** project (blue icon) in the left sidebar
2. In the main editor, select the **CardiacID** target (under TARGETS)
3. Click the **"General"** tab at the top

---

### Step 3: Add Supabase Package

1. Scroll down to **"Frameworks, Libraries, and Embedded Content"** section
2. Click the **"+"** button (bottom left of that section)
3. In the popup, you'll see two sections:
   - Top: "iOS" frameworks
   - Bottom: "Swift Package Manager" packages

4. In the Swift Package Manager section, you should see:
   - **Supabase** (from supabase-swift)
   - Various sub-packages

5. **Select "Supabase"** (the main one)
6. Click **"Add"**

---

### Step 4: Add MSAL Package

1. Still in the same **"Frameworks, Libraries, and Embedded Content"** section
2. Click the **"+"** button again
3. In the Swift Package Manager section, look for:
   - **MSAL** (from microsoft-authentication-library-for-objc)

4. **Select "MSAL"**
5. Click **"Add"**

---

### Step 5: Verify Packages Were Added

In the **"Frameworks, Libraries, and Embedded Content"** section, you should now see:

```
✅ Supabase (supabase-swift)
✅ MSAL (microsoft-authentication-library-for-objc)
✅ SwiftAlgorithms (swift-algorithms) - if needed
```

Each should show "Do Not Embed" in the right column (this is correct for Swift Packages).

---

### Step 6: Alternative Method - General Tab

If the above doesn't work, try this method:

1. With CardiacID target selected
2. Click **"Build Phases"** tab
3. Expand **"Link Binary With Libraries"**
4. Click the **"+"** button
5. In the popup, scroll to "Swift Package Manager" section
6. Add **Supabase** and **MSAL**

---

### Step 7: Build the Project

1. Press **Cmd+B** to build
2. Check for errors in the build log

**Expected Result:** ✅ Build succeeds, no "Missing package product" errors

---

## Troubleshooting

### Issue: Don't See Packages in the List

**Solution:**
1. Go to **File → Packages → Resolve Package Versions**
2. Wait for packages to resolve (1-2 minutes)
3. Try adding packages again

### Issue: "No such module 'Supabase'" After Adding

**Solution:**
1. Clean build folder: **Product → Clean Build Folder** (Shift+Cmd+K)
2. Restart Xcode
3. Build again: **Cmd+B**

### Issue: Packages Show But Can't Add

**Solution:**
1. Go to project settings → **Package Dependencies** tab
2. Verify packages are listed:
   - supabase-swift (2.37.0)
   - microsoft-authentication-library-for-objc (2.6.0)
3. If not, click **"+"** and re-add the package URLs

---

## Package URLs (If Needed to Re-Add)

### Supabase
```
https://github.com/supabase/supabase-swift.git
Minimum Version: 2.37.0
```

### MSAL
```
https://github.com/AzureAD/microsoft-authentication-library-for-objc.git
Minimum Version: 2.5.1
```

---

## Visual Guide

### Where to Click:

```
Xcode Window
├─ Left Sidebar
│  └─ 📁 CardiacID (project)  ← Click here
│
└─ Main Editor (after clicking project)
   ├─ PROJECT: CardiacID
   └─ TARGETS
      └─ CardiacID  ← Select this target
         ├─ General  ← Click this tab
         │  └─ Frameworks, Libraries, and Embedded Content
         │     └─ + button  ← Click to add packages
         │
         └─ Build Phases  ← Or use this tab
            └─ Link Binary With Libraries
               └─ + button  ← Alternative method
```

---

## What Xcode Does Automatically

When you add packages through the UI, Xcode:

1. **Inspects Package.swift** from the downloaded package
2. **Discovers available products** (libraries/frameworks)
3. **Validates product names** against what's actually available
4. **Updates project.pbxproj** with correct references
5. **Configures build settings** automatically
6. **Sets up module search paths**

This is why manual editing often fails - we can't see what products the package actually exposes without Xcode's help.

---

## After Adding Packages

### Test Your Imports

Create a simple test to verify packages work:

```swift
// Add this temporarily to CardiacIDApp.swift

import Supabase  // Should work
import MSAL      // Should work

func testPackages() {
    print("Supabase imported successfully")
    print("MSAL imported successfully")
}
```

If no errors, packages are working!

---

## Why Manual Editing Failed

### What I Tried:
```swift
// In project.pbxproj
packageProductDependencies = (
    FBPKG001SUPABASE000001 /* Supabase */,  // ❌ Guessed name
    FBPKG002MSAL000000001 /* MSAL */,       // ❌ Guessed name
);
```

### Why It Failed:
- Product names must **exactly match** what Package.swift declares
- MSAL might expose as "MSAL_iOS" or "MSAL-iOS" or just "MSAL"
- Supabase might have sub-products we don't know about
- Only Xcode can see the actual Package.swift manifest

---

## Summary

### What You Need to Do:

1. **Open Xcode** (should already be open)
2. **Select CardiacID target** → General tab
3. **Add Supabase** package product (+ button)
4. **Add MSAL** package product (+ button)
5. **Build** (Cmd+B)

**Time Required:** 2-3 minutes

**Expected Result:** Build succeeds, import errors gone!

---

## Alternative: Command Line (Advanced)

If you prefer command line, this is more complex:

```bash
# This requires understanding of Package.swift format
# and exact product names, which is why UI is recommended
```

**Recommendation:** Use Xcode UI - it's designed for this!

---

*Add Packages in Xcode - Required Step*
*CardiacID - Package Product Linking*
*Date: November 5, 2025*
