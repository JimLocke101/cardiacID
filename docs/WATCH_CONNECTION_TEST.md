# Watch Connection Testing Guide

## ✅ Changes Applied

### Watch App (CardiacID Watch App)
1. ✅ **Initialized WatchConnectivityService** in `CardiacIDApp.swift`
2. ✅ **Added iOS-compatible message methods** to `WatchConnectivityService.swift`
3. ✅ **Enhanced message receiver** to handle both iOS and legacy formats

### iOS App (CardiacID)
1. ✅ **Enhanced message handler** to support both iOS and Watch formats
2. ✅ **Added detailed logging** for debugging connection issues

---

## 🧪 Testing the Connection

### Step 1: Verify Connection Status

**On iOS** - Add this to any view (e.g., `DashboardView.swift`):

```swift
.onAppear {
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("📱 iOS WATCH CONNECTION STATUS:")
    print("  ├─ Paired: \(watchConnectivity.isPaired)")
    print("  ├─ Installed: \(watchConnectivity.isInstalled)")
    print("  ├─ Reachable: \(watchConnectivity.isReachable)")
    print("  └─ Activated: \(watchConnectivity.isActivated)")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
}
```

**On Watch** - Add this to `ContentView.swift` or `MenuView.swift`:

```swift
@EnvironmentObject var watchConnectivity: WatchConnectivityService

var body: some View {
    // ... your existing code ...
    .onAppear {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("⌚️ WATCH CONNECTION STATUS:")
        print("  ├─ Connected: \(watchConnectivity.isConnected)")
        print("  └─ Status: \(watchConnectivity.connectionStatus)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}
```

---

### Step 2: Add Connection Status UI

**iOS - Add to DashboardView:**

```swift
// Add this to your view hierarchy
HStack(spacing: 8) {
    Image(systemName: watchConnectivity.isReachable ? "applewatch" : "applewatch.slash")
        .font(.title3)
        .foregroundColor(watchConnectivity.isReachable ? .green : .red)

    VStack(alignment: .leading, spacing: 2) {
        Text("Apple Watch")
            .font(.caption)
            .fontWeight(.medium)
        Text(watchConnectivity.isReachable ? "Connected" : "Disconnected")
            .font(.caption2)
            .foregroundColor(.secondary)
    }
}
.padding(8)
.background(Color.secondary.opacity(0.1))
.cornerRadius(8)
```

**Watch - Add to MenuView or SettingsView:**

```swift
@EnvironmentObject var watchConnectivity: WatchConnectivityService

// Add this to your view
HStack(spacing: 8) {
    Image(systemName: watchConnectivity.isConnected ? "iphone" : "iphone.slash")
        .foregroundColor(watchConnectivity.isConnected ? .green : .red)

    VStack(alignment: .leading) {
        Text("iPhone")
            .font(.caption)
        Text(watchConnectivity.connectionStatus)
            .font(.caption2)
            .foregroundColor(.secondary)
    }
}
```

---

### Step 3: Test Sending Messages

**iOS → Watch Test Button:**

Add this to any iOS view (like DashboardView or SettingsView):

```swift
Button("Test Watch Connection") {
    print("📱 iOS: Testing Watch connection...")
    watchConnectivity.startMonitoring()
}
.buttonStyle(.bordered)
```

**Watch → iOS Test Button:**

Add this to Watch MenuView or SettingsView:

```swift
@EnvironmentObject var watchConnectivity: WatchConnectivityService

Button("Send Test to iPhone") {
    print("⌚️ Watch: Sending test heart rate to iOS...")
    watchConnectivity.sendHeartRateToiOS(72)
}
.buttonStyle(.bordered)
```

---

### Step 4: Test Heart Rate Monitoring

**Watch - Send Real Heart Rate:**

When you have actual heart rate data (from HealthKit), send it to iOS:

```swift
// In your HealthKit capture code
func onHeartRateUpdated(_ heartRate: Int) {
    watchConnectivity.sendHeartRateToiOS(heartRate)
}
```

**iOS - Listen for Heart Rate:**

Add this to DashboardView or any view that needs heart rate data:

```swift
.onReceive(watchConnectivity.heartRatePublisher) { (heartRate, timestamp) in
    print("❤️ iOS: Received heart rate from Watch: \(heartRate) BPM at \(timestamp)")
    // Update your UI here
}
```

---

## 📊 Expected Console Output

### When Both Apps Launch Successfully:

**iOS Console:**
```
📱 iOS Watch Connection Check:
  Paired: true
  Installed: true
  Reachable: true  ← Should be TRUE
  Activated: true
```

**Watch Console:**
```
⌚️ HeartID Watch App Launching...
⌚️ Initializing WatchConnectivity for iOS communication
⌚️ Watch Connection Check:
  Connected: true  ← Should be TRUE
  Status: Connected to iOS
```

### When Sending Test Message (iOS → Watch):

**iOS Console:**
```
📱 iOS: Testing Watch connection...
```

**Watch Console:**
```
⌚️ Watch received message: ["message_type": "start_monitoring"]
📱 Watch: Processing iOS message type: start_monitoring
⌚️ Watch: iOS requested start monitoring
```

### When Sending Heart Rate (Watch → iOS):

**Watch Console:**
```
⌚️ Watch: Sending test heart rate to iOS...
✅ Watch: Sent heart rate to iOS: 72 BPM
```

**iOS Console:**
```
📱 iOS received message from Watch: ["message_type": "heart_rate_update", "heart_rate": 72, ...]
❤️ iOS: Received heart rate from Watch: 72 BPM
```

---

## 🔧 Troubleshooting

### Issue: "Watch Not Reachable" on iOS

**Solutions:**
1. ✅ **Ensure both apps are running in foreground**
2. ✅ **Check Bluetooth is enabled on both devices**
3. ✅ **Verify iPhone and Watch are paired** (Settings → Bluetooth)
4. ✅ **Rebuild Watch app** from Xcode
5. ✅ **Check console for activation errors**

### Issue: "iOS App Not Reachable" on Watch

**Solutions:**
1. ✅ **Keep iOS app in foreground** (background requires different message method)
2. ✅ **Check watch is unlocked**
3. ✅ **Verify WCSession activation** (check console logs)
4. ✅ **Try airplane mode OFF on both devices**

### Issue: Messages Not Receiving

**Debug Steps:**
1. ✅ **Check console logs** for "received message"
2. ✅ **Verify message format** (should see `message_type` key)
3. ✅ **Ensure `@EnvironmentObject` is injected** in views
4. ✅ **Try sending when both apps are active**

### Issue: "Unknown message format"

**Solution:**
- This means you're using old message format
- Use new iOS-compatible methods:
  - `sendHeartRateToiOS()` instead of `sendHeartPatternData()`
  - `sendAuthStatusToiOS()` instead of `sendAuthenticationResult()`

---

## ✅ Verification Checklist

Before testing:
- [ ] Watch app built and installed on Apple Watch
- [ ] iOS app built and installed on iPhone
- [ ] Both devices paired via Watch app
- [ ] Bluetooth enabled on both devices
- [ ] Both apps launched and in foreground
- [ ] Console logs visible in Xcode

During testing:
- [ ] iOS shows "Reachable: true"
- [ ] Watch shows "Connected: true"
- [ ] Test button sends message successfully
- [ ] Console shows "received message" on receiving side
- [ ] Heart rate data appears in iOS when sent from Watch

---

## 🎯 Quick Test Procedure

1. **Build Watch App** (Xcode → Select Watch scheme → Run)
2. **Build iOS App** (Xcode → Select iOS scheme → Run)
3. **Check Console** for connection status logs
4. **Tap test button** on iOS to ping Watch
5. **Tap test button** on Watch to send heart rate
6. **Verify logs** show message received on both sides

---

## 📝 Next Steps After Successful Connection

Once connection is working:

1. **Integrate with real HealthKit data** on Watch
2. **Update UI** to show live heart rate from Watch
3. **Add enrollment sync** between Watch and iOS
4. **Implement authentication flow** using Watch biometrics
5. **Add background sync** using `updateApplicationContext`

---

**Last Updated**: 2025-01-17
**Status**: ✅ Ready for Testing
