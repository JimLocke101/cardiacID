# Watch App Not Working - Complete Troubleshooting Guide

## Issues Identified & Solutions

### 1. **Xcode Project Configuration (Most Likely Issue)**

Your watch app code looks correct, but you likely have target configuration issues:

#### **Required Targets:**
You need **THREE** targets in your Xcode project:
1. **iOS App** target (main app)
2. **Watch App** target (watchOS app)
3. **Watch App Extension** target (deprecated in watchOS 7+, but may be needed for older versions)

#### **Check These Settings:**
1. Open your Xcode project
2. Go to Project Navigator → Select your project name
3. Check that you have these targets:
   - `CardiacID` (iOS)
   - `CardiacID Watch App` (watchOS)

#### **If Watch Targets Are Missing:**
1. Select your project in Xcode
2. Click the `+` button to add a new target
3. Choose **watchOS** → **Watch App**
4. Use bundle identifier: `com.yourcompany.cardiacid.watchkitapp`

### 2. **Bundle Identifier Issues**

**Check your bundle identifiers match this pattern:**
- iOS App: `com.yourcompany.cardiacid`
- Watch App: `com.yourcompany.cardiacid.watchkitapp`

### 3. **Deployment Target Compatibility**

**Ensure compatible versions:**
- iOS App: iOS 17.0+ (to match SwiftUI features)
- Watch App: watchOS 10.0+

### 4. **Watch App Info.plist Configuration**

Your Watch App needs these Info.plist keys:

```xml
<key>WKCompanionAppBundleIdentifier</key>
<string>com.yourcompany.cardiacid</string>
<key>WKWatchOnly</key>
<false/>
<key>CFBundleDisplayName</key>
<string>CardiacID</string>
```

### 5. **HealthKit Entitlements**

Both iOS and watchOS apps need HealthKit entitlements:

**iOS App Entitlements:**
```xml
<key>com.apple.developer.healthkit</key>
<true/>
```

**Watch App Entitlements:**
```xml
<key>com.apple.developer.healthkit</key>
<true/>
<key>com.apple.developer.healthkit.background-delivery</key>
<true/>
```

### 6. **File Target Membership**

**Ensure these files are in the WATCH target:**
- `WatchApp.swift` (new file I created)
- `MenuView.swift`
- `HeartIDService.swift`
- `SettingsView.swift`
- `HealthKitService.swift`

**To check/fix target membership:**
1. Select each file in Xcode
2. Check "Target Membership" in File Inspector
3. Ensure both iOS and watchOS targets are checked as needed

### 7. **Simulator vs Physical Device**

**HealthKit limitations:**
- **Simulator**: Limited HealthKit functionality
- **Physical Watch**: Full HealthKit access required

**Test on physical device:**
- Pair your Apple Watch
- Install both iOS and Watch apps
- Grant HealthKit permissions

### 8. **Build Settings**

**Check these build settings for Watch target:**
- **Framework Search Paths**: Include HealthKit
- **Swift Language Version**: Swift 5
- **Deployment Target**: watchOS 10.0+

### 9. **Quick Diagnostic Steps**

Run these checks in order:

#### **Step 1: Check Targets**
```bash
# In Terminal, go to your project directory
xcodebuild -list
```
You should see both iOS and watchOS targets listed.

#### **Step 2: Check Simulator Install**
1. Build for Watch Simulator
2. Check if app appears in Watch Simulator
3. If not appearing, it's a target configuration issue

#### **Step 3: Check Device Install**
1. Connect iPhone with paired Apple Watch
2. Build and install to device
3. Check Apple Watch for app icon

#### **Step 4: Check HealthKit Permissions**
Add this debug code to your watch app:
```swift
// Add to WatchApp.swift
private func debugHealthKit() {
    print("🔍 HealthKit Available: \(HKHealthStore.isHealthDataAvailable())")
    
    let healthStore = HKHealthStore()
    let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    
    let status = healthStore.authorizationStatus(for: heartRateType)
    print("🔍 HealthKit Status: \(status.rawValue)")
}
```

### 10. **Most Likely Fix**

Based on the code structure, your most likely issue is:

1. **Missing Watch App target** - Add it in Xcode
2. **Wrong bundle identifiers** - Follow the naming pattern above
3. **File target membership** - Ensure watch files are in watch target

### 11. **Alternative: Quick Test Setup**

If you want to quickly test, replace your `CardiacIDApp.swift` with the new `WatchApp.swift` I created and ensure it's properly targeted to the watchOS target.

## Next Steps

1. **First**: Check if you have a proper watchOS target in Xcode
2. **Second**: Verify bundle identifiers follow the pattern
3. **Third**: Test on physical device (Simulator has HealthKit limitations)
4. **Fourth**: Check target membership for all watch-related files

Let me know which of these steps reveals the issue!