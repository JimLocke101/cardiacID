# CardiacID Project Structure

**Last Updated:** December 26, 2025  
**Phase:** 2 Complete - Architecture Stabilized

---

## Directory Organization

```
CardiacID/
├── CardiacID/                      # iOS App Target
│   ├── Models/
│   │   ├── Biometric/             # Biometric authentication models
│   │   └── ...                    # Other model types
│   ├── Services/
│   │   ├── Biometric/             # HeartID, HealthKit services
│   │   ├── EntraIDAuthClient.swift
│   │   ├── EncryptionService.swift
│   │   └── WatchConnectivityService.swift
│   ├── Views/                     # SwiftUI views
│   ├── Utils/                     # iOS-specific utilities
│   └── CardiacIDApp.swift         # App entry point
│
├── CardiacID Watch App/           # watchOS App Target
│   ├── Models/                    # Watch-specific models
│   ├── Services/
│   │   ├── EncryptionService.swift        # XenonX support
│   │   └── WatchConnectivityService.swift
│   ├── Views/                     # Watch UI
│   └── Utils/                     # Watch-specific utilities
│
├── CardiacIDTests/                # iOS Unit Tests
├── CardiacIDUITests/              # iOS UI Tests
├── CardiacID Watch AppTests/      # Watch Unit Tests
├── CardiacID Watch AppUITests/    # Watch UI Tests
│
├── Shared/                        # ⭐ NEW: Shared Code (Phase 2)
│   ├── Models/                    # Models used by both targets
│   ├── Utils/
│   │   └── HeartIDColors.swift   # Consolidated color scheme
│   └── Services/                  # Shared service protocols
│
├── DeveloperUtilities/            # ⭐ NEW: Development Tools (Phase 2)
│   ├── BuildErrorSolutions.swift  # Build error documentation
│   └── CompilationFixes.swift     # Compilation fix utilities
│
├── Archive/                       # ⭐ NEW: Archived Code (Phase 1)
│   └── OrphanedFiles_2025-12-26/  # 16 orphaned files from .xcodeproj
│
├── docs/                          # ⭐ NEW: Documentation (Phase 2)
│   ├── api/                       # API & dependency documentation
│   ├── architecture/              # Architecture & code reviews
│   ├── build-history/             # Build errors & fixes (62 files)
│   ├── deployment/                # Deployment & production guides
│   ├── PROJECT_STRUCTURE.md       # This file
│   └── *.md                       # Other docs
│
├── Config/                        # Configuration files
├── Database/                      # Database schemas
│
└── README.md                      # Project README (root only)
```

---

## File Organization Rules

### ✅ DO
- Keep **only README.md** in project root
- Put all documentation in `/docs/` subdirectories
- Use `/Shared/` for code used by multiple targets
- Put development/debug tools in `/DeveloperUtilities/`
- Archive deprecated code in `/Archive/` with manifest

### ❌ DON'T
- **NEVER** put Swift files in `.xcodeproj/` directory
- Don't duplicate files between iOS and Watch targets without good reason
- Don't put test files in main app bundles
- Don't put documentation in source directories

---

## Target Membership

### iOS Target (CardiacID)
**Package Dependencies:**
- MSAL (Microsoft Authentication Library)

**Key Services:**
- EntraIDAuthClient - Enterprise authentication
- EncryptionService - AES-256-GCM with keychain
- WatchConnectivityService - iPhone side of Watch communication
- HealthKitService - Health data integration
- HeartIDService - Biometric authentication

### watchOS Target (CardiacID Watch App)
**Package Dependencies:**
- ✅ Removed unused Supabase packages (Phase 2)

**Key Services:**
- EncryptionService - XenonX result encryption
- WatchConnectivityService - Watch side of communication
- WatchHeartRateService - PPG data collection

---

## Platform-Specific Implementations

### Files with Intentional Duplication

#### EncryptionService.swift
**Why duplicated:** Different encryption requirements per platform

- **iOS (`CardiacID/Services/`):**
  - Uses SecureCredentialManager
  - Full keychain integration
  - Enterprise-grade key management

- **Watch (`CardiacID Watch App/Services/`):**
  - Simplified for watchOS constraints
  - XenonX result encryption
  - Hardcoded key (⚠️ TODO: Use keychain)

#### WatchConnectivityService.swift
**Why duplicated:** Platform-specific WatchConnectivity APIs

- **iOS:** Session delegate, iPhone-specific methods
- **Watch:** Watch-specific message handling

#### HeartPattern.swift
**Why duplicated:** Platform-specific health data

- **iOS:** No HealthKit import, uses qualityScore/confidence
- **Watch:** HealthKit integration, HeartRateSample struct

---

## Recently Consolidated (Phase 2)

### HeartIDColors.swift
**Status:** Consolidated to `Shared/Utils/`  
**Previous locations:**
- `CardiacID/Utils/HeartIDColors.swift` (99% identical)
- `CardiacID Watch App/Utils/HeartIDColors.swift` (99% identical)

**Current state:** 
- Canonical version in `Shared/Utils/`
- Original files preserved for backward compatibility
- **Action needed:** Update Xcode project to use shared version

---

## Build Artifacts (Gitignored)

The following are **automatically generated** and ignored by git:

- `.build/` - Swift Package Manager build cache
- `DerivedData/` - Xcode build outputs
- `xcuserdata/` - User-specific Xcode settings
- `*.xcworkspace` (except project workspace)

---

## Documentation Organization

### `/docs/api/`
API documentation, dependency guides, package setup

### `/docs/architecture/`
Code architecture, reviews, assessments

### `/docs/build-history/`
**62 files** documenting build errors and fixes over time
- Shows evolution of project
- Valuable for understanding past issues
- Organized chronologically

### `/docs/deployment/`
Production deployment guides, integration docs

---

## Anti-Patterns Eliminated

### Phase 1 Cleanup
✅ Removed 16 Swift files from `.xcodeproj/` directory  
✅ Eliminated duplicate type definitions  
✅ Removed test files from main app bundle  
✅ Fixed package dependency mismatches  

### Phase 2 Cleanup
✅ Moved 62 documentation files to `/docs/`  
✅ Consolidated duplicate HeartIDColors.swift  
✅ Moved build utilities out of `/Models/`  
✅ Removed unused Supabase packages  
✅ Created comprehensive .gitignore  

---

## Maintenance Guidelines

### Adding New Files

**Models:**
- iOS-only → `CardiacID/Models/`
- Watch-only → `CardiacID Watch App/Models/`
- Shared → `Shared/Models/`

**Services:**
- Follow same pattern as Models
- Consider protocol-based approach for shared interfaces

**Documentation:**
- Technical docs → `/docs/architecture/`
- Build issues → `/docs/build-history/`
- API docs → `/docs/api/`
- Deployment → `/docs/deployment/`

### Before Committing

1. Run `git status` to check for unintended files
2. Verify no build artifacts included (.gitignore should catch)
3. Ensure documentation in `/docs/`, not root
4. Check no Swift files in `.xcodeproj/`

---

## Migration Notes

### From Phase 1 → Phase 2

**Files Moved:**
- 62 markdown files → `/docs/` subdirectories
- 2 build utility files → `/DeveloperUtilities/`
- 1 shared utility → `/Shared/Utils/`

**Files Removed:**
- 3 test placeholder files (empty stubs)

**Configuration Changes:**
- Watch target: Removed 5 unused Supabase package dependencies
- Added comprehensive .gitignore

---

## Next Steps (Phase 3+)

### High Priority
1. Update Xcode project to reference `Shared/HeartIDColors.swift`
2. Remove duplicate HeartIDColors from iOS and Watch targets
3. Consider protocol-based EncryptionService for better sharing

### Medium Priority
1. Evaluate HeartPattern consolidation (may require conditional compilation)
2. Review developer utilities for production readiness
3. Clean up `.build/` directory (already gitignored)

### Low Priority
1. Archive old build history docs (keep only recent)
2. Create automated tests for file organization
3. Document coding standards

---

## Questions?

See `/docs/` for comprehensive documentation on:
- Build errors and solutions
- Architecture decisions
- Deployment procedures
- API integration

**Maintainers:** This structure was established in Phase 1-2 cleanup (Dec 2025). Please maintain these conventions to prevent regression.
