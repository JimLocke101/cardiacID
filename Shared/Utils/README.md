# Shared Utilities

This directory contains utility code shared between iOS and watchOS targets.

## Files

### HeartIDColors.swift
Consolidated color scheme for HeartID branding.

**Previously duplicated in:**
- `CardiacID/Utils/HeartIDColors.swift` (iOS)
- `CardiacID Watch App/Utils/HeartIDColors.swift` (watchOS)

**Current status:** 
- Consolidated version maintained here
- Original files preserved in targets for backward compatibility
- **TODO:** Update Xcode project to reference this shared file instead of duplicates

**Usage:**
```swift
import SwiftUI

let colors = HeartIDColors()
Text("Hello").foregroundColor(colors.accent)
```
