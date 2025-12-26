# Systematic Fix Plan - Both Modes Support

**Goal:** Support both DEMO_MODE and PRODUCTION_MODE
**Current Errors:** ~90
**Strategy:** Fix systematically by category

---

## ✅ Step 1: Configuration (COMPLETE)

**Changes Made:**
1. ✅ Added `HEARTID_DEMO_MODE` flag to Debug.xcconfig
2. ✅ Configured Swift compiler conditions
3. ✅ Renamed `User` → `AppUser` with typealias for compatibility
4. ✅ Created DEMO_MODE_GUIDE.md

**How to Switch Modes:**
- Edit `Config/Debug.xcconfig`
- Set `HEARTID_DEMO_MODE = YES` (Demo) or `NO` (Production)

---

## 🔄 Step 2: Fix Type Ambiguity (IN PROGRESS)

### User Type - FIXED ✅
**Problem:** `User` ambiguous (Supabase Auth.User vs CardiacID User)
**Solution:** Renamed to `AppUser`, added typealias for compatibility
**Files:** Models/User.swift

### Device Type - TODO
**Problem:** Multiple `Device` definitions
**Solution:** Will rename or qualify with namespaces

### EntraIDUser Type - TODO
**Problem:** Defined in multiple files
**Solution:** Keep one canonical definition, use conditional compilation

---

## 🔄 Step 3: Conditional Compilation Structure

### Pattern to Apply:
```swift
#if DEMO_MODE
// Mock/Demo implementation
class MockEntraIDService: EntraIDService {
    // Demo code
}
#else
// Production implementation
typealias EntraIDServiceType = EntraIDAuthClient
#endif
```

### Files to Update:
- Services/Biometric/EntraIDService.swift
- Services/DeviceManagementService.swift
- Services/TechnologyIntegrationService.swift
- Views/TechnologyManagementView.swift
- Views/EnterpriseAuthView.swift

---

## 🔄 Step 4: Fix Missing Type References

### AppSupabaseClientLocal - TODO
**Error:** Cannot find 'AppSupabaseClientLocal' in scope
**Solution:** Check if defined with `#if DEMO_MODE`, add proper imports

### MockEntraIDService - TODO
**Error:** Cannot find 'MockEntraIDService' in scope
**Solution:** Already defined in Biometric/EntraIDService.swift with #if DEMO_MODE
**Fix:** Ensure DEMO_MODE flag is working

---

## 🔄 Step 5: Fix Service Integration Issues

### Data Type Conversions - TODO
**Errors:**
```
Cannot convert value of type 'HeartPattern' to expected argument type 'Data'
Cannot convert value of type '[Double]' to expected argument type 'Data'
```

**Solution:** Add proper conversion helpers

### Missing Method Parameters - TODO
**Errors:**
```
Missing arguments for parameters 'duration', 'encryptedIdentifier' in call
Extra argument 'name' in call
```

**Solution:** Fix method signatures to match

---

## Current Status

### Errors Fixed: ~15
- ✅ Deleted 5 duplicate files
- ✅ User type renamed
- ✅ DEMO_MODE configuration added

### Remaining Errors: ~75
- ⏳ Device type ambiguity
- ⏳ EntraIDUser type ambiguity
- ⏳ Missing type references (conditional compilation)
- ⏳ Data type conversions
- ⏳ Method signature mismatches
- ⏳ View binding issues

---

## Estimated Fix Time

**With your approval to proceed:**
- Type ambiguity fixes: 30 minutes
- Conditional compilation: 45 minutes
- Service integration fixes: 60 minutes
- Testing both modes: 30 minutes

**Total:** ~3 hours of systematic fixing

---

## Next Steps

I'm ready to continue with:
1. Fix Device type ambiguity
2. Fix EntraIDUser type ambiguity
3. Apply conditional compilation pattern
4. Fix all service integration issues
5. Test build in both modes

**Should I proceed?**

