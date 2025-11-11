# Testing Guide for Critical Fixes
**Date:** November 9, 2025
**Purpose:** Verify all 5 critical fixes are working correctly

---

## Pre-Testing Checklist

### 1. Clean Build Environment
```bash
# In Xcode:
1. Product → Clean Build Folder (Cmd+Shift+K)
2. Close Xcode
3. Delete DerivedData folder:
   rm -rf ~/Library/Developer/Xcode/DerivedData/CardiacID-*
4. Reopen Xcode
```

### 2. Verify Configuration
Open `Config/Debug.xcconfig` and verify:
```
HEARTID_DEMO_MODE = NO    # For production mode testing
# OR
HEARTID_DEMO_MODE = YES   # For demo mode testing
```

### 3. Build the Project
```bash
# In Xcode:
1. Select target: CardiacID (iOS)
2. Select device: iPhone 15 Simulator (or any iOS 15+ device)
3. Product → Build (Cmd+B)
```

**Expected Result:** ✅ Build succeeds with 0 errors

**If build fails:** Check error messages and refer to COMPREHENSIVE_CODE_ASSESSMENT.md

---

## Test 1: AppSupabaseClient ObservableObject

### Purpose
Verify that @Published properties correctly notify observers

### Test Steps

1. **Create a test view** (or use existing AuthViewModel):
```swift
import SwiftUI

struct TestSupabaseView: View {
    @ObservedObject var service = SupabaseService.shared

    var body: some View {
        VStack {
            Text("Authenticated: \(service.isAuthenticated ? "Yes" : "No")")
            Text("User: \(service.currentUser?.displayName ?? "None")")

            Button("Test Sign In") {
                // This should trigger view update
                Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    // The view should update when this changes
                }
            }
        }
    }
}
```

2. **Run the view** and observe:
   - Text displays current state
   - Button press triggers state change
   - View updates automatically

### Expected Results
✅ View displays current authentication state
✅ View updates when isAuthenticated changes
✅ View updates when currentUser changes
✅ No console warnings about non-ObservableObject

### Failure Indicators
❌ View doesn't update after state change
❌ Console warning: "Publishing changes from background threads is not allowed"
❌ Console error about ObservableObject protocol

---

## Test 2: NFCService Encryption Methods

### Purpose
Verify encryption/decryption works without crashes

### Test Steps

1. **Test HeartPattern Encryption** (in a test or view):
```swift
func testHeartPatternEncryption() async {
    let nfcService = NFCService()

    // Create a test heart pattern
    let pattern = HeartPattern(
        heartRateData: [60.0, 65.0, 70.0, 68.0],
        duration: 10.0,
        encryptedIdentifier: "test-id",
        qualityScore: 0.9,
        confidence: 0.85
    )

    // This should not crash
    // NFCService internally calls encryption methods
    let mockTag = NFCTagData(
        type: .heartID,
        data: Data(),
        timestamp: Date(),
        deviceId: "test-device"
    )

    nfcService.authenticateWithHeartPattern(pattern, via: mockTag)

    // Wait a bit for async completion
    try? await Task.sleep(nanoseconds: 2_000_000_000)

    print("✅ Encryption test completed without crash")
}
```

2. **Test NFC Data Exchange**:
```swift
func testNFCDataExchange() {
    let nfcService = NFCService()
    let testData = "Test Data".data(using: .utf8)!
    let mockTag = NFCTagData(type: .ndef, data: Data(), timestamp: Date(), deviceId: "test")

    let cancellable = nfcService.exchangeData(testData, with: mockTag)
        .sink(
            receiveCompletion: { completion in
                switch completion {
                case .finished:
                    print("✅ Data exchange completed")
                case .failure(let error):
                    print("⚠️ Data exchange failed: \(error)")
                }
            },
            receiveValue: { data in
                print("✅ Received response data: \(data?.count ?? 0) bytes")
            }
        )

    // Keep cancellable alive
    _ = cancellable
}
```

### Expected Results
✅ No crashes during encryption
✅ No crashes during decryption
✅ Methods complete successfully
✅ Token generation works (doesn't return nil unexpectedly)

### Failure Indicators
❌ App crashes with "Thread 1: Fatal error: Unexpectedly found nil"
❌ Console error: "Cannot convert value of type..."
❌ Build error about encrypt/decrypt methods

---

## Test 3: AuthenticationManager Event Logging

### Purpose
Verify AuthEvent is created with correct structure

### Test Steps

1. **Trigger Authentication** (use existing auth flow or test):
```swift
func testAuthenticationEventLogging() {
    let authManager = AuthenticationManager()

    // Trigger authentication
    authManager.startMonitoring()

    // Wait for heart rate capture
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
        // Check that event was logged
        if let lastEvent = authManager.lastAuthEvents.first {
            print("✅ Event logged:")
            print("  - ID: \(lastEvent.id)")
            print("  - User ID: \(lastEvent.userId)")
            print("  - Event Type: \(lastEvent.eventType)")
            print("  - Success: \(lastEvent.success)")
            print("  - Metadata: \(lastEvent.metadata ?? [:])")

            // Verify structure
            assert(!lastEvent.id.isEmpty, "Event should have ID")
            assert(!lastEvent.userId.isEmpty, "Event should have userId")
            assert(lastEvent.metadata?["heartRate"] != nil, "Should have heartRate in metadata")
        } else {
            print("⚠️ No events logged yet")
        }
    }
}
```

### Expected Results
✅ AuthEvent created without compilation errors
✅ Event has all required properties (id, userId, eventType, etc.)
✅ Metadata contains heartRate and details
✅ Events appear in lastAuthEvents array

### Failure Indicators
❌ Compilation error: "Argument passed to call that takes no arguments"
❌ Runtime error: "Missing required parameter"
❌ Console error about property access

---

## Test 4: DashboardView Data Loading

### Purpose
Verify async/await data loading works correctly

### Test Steps

1. **Navigate to Dashboard**:
   - Launch app
   - Navigate to Dashboard screen
   - Observe data loading

2. **Check Console Output**:
```
Expected console output:
✅ Loading recent events...
✅ Events loaded successfully (or error message)
✅ Loading connected devices...
✅ Devices loaded successfully (or error message)
```

3. **Verify UI Updates**:
   - Recent events section shows events (or empty state)
   - Connected devices section shows devices (or empty state)
   - No crashes during data loading

### Test Code (Already in DashboardView.swift):
```swift
// This should now work without errors:
private func loadRecentEvents() {
    Task {
        do {
            let events = try await SupabaseService.shared.getRecentAuthEvents(limit: 5)
            await MainActor.run {
                self.recentEvents = events
            }
        } catch {
            print("Failed to load recent events: \(error)")
            await MainActor.run {
                self.recentEvents = []
            }
        }
    }
}
```

### Expected Results
✅ Dashboard loads without crashes
✅ Data loading functions complete (even if returning empty arrays)
✅ UI updates on main thread
✅ No compilation errors about publishers

### Failure Indicators
❌ Compilation error: "Cannot convert value of type 'async throws -> [AuthEvent]'"
❌ Runtime error: "Publishing changes from background threads"
❌ App hangs or freezes on dashboard

---

## Test 5: DashboardView Event Type Display

### Purpose
Verify all event types display with correct labels

### Test Steps

1. **Create Test Events** (for thorough testing):
```swift
func testAllEventTypes() {
    let eventTypes: [AuthEvent.EventType] = [
        .biometricAuth,
        .passwordAuth,
        .signIn,
        .signOut,
        .failedAttempt,
        .accountLocked,
        .passwordReset,
        .tokenRefresh
    ]

    let dashboardView = DashboardView()

    for eventType in eventTypes {
        let event = AuthEvent(
            id: UUID().uuidString,
            userId: "test-user",
            eventType: eventType,
            timestamp: Date(),
            deviceId: "test-device",
            ipAddress: nil,
            location: nil,
            success: true,
            metadata: nil
        )

        let description = dashboardView.eventDescription(for: event)
        print("✅ \(eventType.rawValue): \(description)")
    }
}
```

2. **Verify Output**:
```
Expected descriptions:
✅ biometricAuth: Authentication Successful
✅ passwordAuth: Authentication Successful
✅ signIn: Sign In Successful
✅ signOut: Sign Out Successful
✅ failedAttempt: Failed Attempt Failed
✅ accountLocked: Account Locked Failed
✅ passwordReset: Password Reset Successful
✅ tokenRefresh: Token Refresh Successful
```

### Expected Results
✅ All event types have descriptions
✅ No compilation errors about missing cases
✅ Switch statement exhaustive (no default needed)

### Failure Indicators
❌ Compilation error: "Switch must be exhaustive"
❌ Compilation error: "Type 'AuthEvent.EventType' has no member 'authentication'"
❌ Runtime crash from unhandled case

---

## Test 6: SecuritySettingsView Data Loading

### Purpose
Verify SecuritySettingsView also loads data correctly

### Test Steps

1. **Navigate to Security Settings**:
   - Open app
   - Go to Settings
   - Navigate to Security Settings

2. **Check Console**:
```
Expected:
✅ Loading security data...
✅ Recent events loaded (or error)
```

3. **Verify UI**:
   - Recent activity section displays
   - No crashes
   - Data loads asynchronously

### Expected Results
✅ Security settings loads without crashes
✅ Recent events display correctly
✅ Loading state handled properly

### Failure Indicators
❌ Compilation error in loadSecurityData()
❌ App crashes when navigating to security settings
❌ Infinite loading state

---

## Integration Tests

### Test Scenario 1: Complete Authentication Flow

1. **Steps**:
   - Launch app
   - Sign in with demo credentials
   - Verify user state updates
   - Navigate to dashboard
   - Verify events display
   - Sign out

2. **Expected**:
   - ✅ Sign in updates SupabaseService.shared.isAuthenticated
   - ✅ Dashboard shows user info
   - ✅ Events load and display
   - ✅ Sign out clears user state

### Test Scenario 2: Demo Mode vs Production Mode

1. **Test Demo Mode**:
```bash
# Set in Config/Debug.xcconfig:
HEARTID_DEMO_MODE = YES
```
   - Build and run
   - Sign in with any credentials
   - Should bypass real authentication
   - Should use mock data

2. **Test Production Mode**:
```bash
# Set in Config/Debug.xcconfig:
HEARTID_DEMO_MODE = NO
```
   - Build and run
   - Sign in requires valid credentials
   - Uses real Supabase (if configured)

### Expected Results
✅ Both modes build successfully
✅ Demo mode uses mock services
✅ Production mode uses real services
✅ Can switch between modes by changing flag

---

## Performance Tests

### Memory Leaks Check

1. **Use Instruments**:
```
Xcode → Product → Profile (Cmd+I)
Select "Leaks" template
Run app through authentication flow
```

2. **Expected**:
   - ✅ No memory leaks in authentication flow
   - ✅ Proper weak self usage prevents retain cycles
   - ✅ Combine subscriptions stored properly

### Async/Await Performance

1. **Check Main Thread**:
```swift
// All UI updates should happen on main thread
Task {
    let data = try await loadData()
    await MainActor.run {
        // UI updates here ✅
        self.displayData = data
    }
}
```

2. **Expected**:
   - ✅ No "Purple warnings" about main thread violations
   - ✅ UI remains responsive during data loading
   - ✅ Proper MainActor usage

---

## Common Issues and Solutions

### Issue 1: Build Fails with Package Errors
**Solution:**
```
1. File → Packages → Reset Package Caches
2. File → Packages → Resolve Package Versions
3. Clean build folder
4. Rebuild
```

### Issue 2: "Cannot find type 'AuthEvent'"
**Solution:**
- Verify AuthEvent.swift is in target membership
- Clean and rebuild
- Check import statements

### Issue 3: Simulator Crashes
**Solution:**
- Reset simulator: Device → Erase All Content and Settings
- Try different simulator (iPhone 14, 15, etc.)
- Check for iOS version compatibility

### Issue 4: Published Properties Not Updating Views
**Solution:**
- Verify class conforms to ObservableObject
- Verify properties marked with @Published
- Verify view uses @ObservedObject or @StateObject
- Check that updates happen on main thread

---

## Success Criteria

### All Tests Pass ✅
- [ ] Build succeeds with 0 errors
- [ ] AppSupabaseClient publishes changes correctly
- [ ] NFCService encryption methods work without crashes
- [ ] AuthEvent logging works with correct structure
- [ ] DashboardView loads data using async/await
- [ ] Event types display with correct labels
- [ ] SecuritySettingsView loads data correctly
- [ ] Demo mode and production mode both work
- [ ] No memory leaks detected
- [ ] No main thread violations

### Known Limitations (Not Critical)
- ⚠️ HeartPattern encoding inconsistency (runtime issue, not compilation)
- ⚠️ Keychain storage inefficiency (performance issue)
- ⚠️ Some services don't check demo mode

---

## Next Steps After Testing

### If All Tests Pass ✅
**Option 1:** Deploy to TestFlight
**Option 2:** Fix high-priority data integrity issues
**Option 3:** Continue with feature development

### If Tests Fail ❌
1. Note which specific test failed
2. Check error messages
3. Review COMPREHENSIVE_CODE_ASSESSMENT.md for details
4. Ask for help with specific error

---

## Reporting Results

When reporting test results, please provide:

1. **Build Status**:
   - ✅ or ❌ Build succeeded
   - Number of errors (if any)
   - Error messages

2. **Test Results**:
   - Which tests passed ✅
   - Which tests failed ❌
   - Screenshots of any errors

3. **Console Output**:
   - Any warnings or errors
   - Unexpected behavior

4. **Questions**:
   - Anything unclear
   - Any unexpected behavior
   - Performance concerns

---

**You're now ready to test! Start with a clean build (Cmd+Shift+K) and then build (Cmd+B).**

Good luck! 🚀
