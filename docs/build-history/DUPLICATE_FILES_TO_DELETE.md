# Duplicate Files Causing Errors

**Root Cause:** Files with strange naming patterns (prefixes like "Models", "Services") are creating duplicate type definitions.

---

## Files to DELETE (Duplicates)

### 1. Device Duplicates
```
❌ DELETE: Services/ModelsDevice.swift
✅ KEEP: Services/Biometric/Device.swift
```
**Why:** `ModelsDevice.swift` appears to be a duplicate/misnamed file

### 2. EntraIDService Duplicates
```
❌ DELETE: Services/ServicesEntraIDService.swift
✅ KEEP: Services/EntraIDAuthClient.swift (production MSAL implementation)
❌ DELETE: Services/Biometric/EntraIDService.swift (if it's a mock)
```

### 3. SupabaseService Confusion
```
❌ DELETE: Models/Biometric/SupabaseService.swift (appears to be misplaced)
✅ KEEP: Services/SupabaseClient.swift (renamed to SupabaseService class)
```

### 4. Other Strange Files
```
Services/ModelsAPIError.swift - Should be Models/APIError.swift
Services/ModelsAuthEvent.swift - Should be Models/AuthEvent.swift
Services/ModelsDevice.swift - Should be Models/Device.swift
Services/ServicesEntraIDService.swift - Should be Services/EntraIDService.swift
```

**Pattern:** Someone copied files and added prefixes to the filenames, creating duplicates.

---

## Action Plan

I'll delete the duplicate/misnamed files systematically.

