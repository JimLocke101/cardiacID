# Watch Connectivity Integration Guide
## Connecting CardiacID (iOS) with HeartID_0_7 (Watch)

---

## 🔍 Problem Analysis

### Current State:
- **iOS App (CardiacID)**: Has `WatchConnectivityService` initialized and ready
- **Watch App (HeartID_0_7)**: Has `WatchConnectivityService` but NOT initialized in main app
- **Message Format**: iOS and Watch use **different message key formats**

###Key Issues Identified:
1. ❌ Watch app `WatchConnectivityService` not injected into app environment
2. ❌ Message format mismatch between iOS and Watch
3. ❌ No app groups configured for background data sharing
4. ❌ Watch app not activating WCSession on launch

---

## ✅ Solution: Step-by-Step Integration

### Part 1: Fix Watch App (`CardiacID Watch App`)

#### Step 1: Update `CardiacIDApp.swift`

**Location**: `CardiacID Watch App/CardiacIDApp.swift`

**Current Code:**
```swift
@main
struct CardiacIDWatchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

**Replace With:**
```swift
import SwiftUI

@main
struct CardiacIDWatchApp: App {
    // Initialize WatchConnectivityService as @StateObject
    @StateObject private var watchConnectivity = WatchConnectivityService()
    @StateObject private var healthKit = HealthKitService()
    @StateObject private var authService = AuthenticationService()

    init() {
        print("🔵 HeartID Watch App Launching...")
        print("🔵 Watch Connectivity initializing...")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(watchConnectivity)
                .environmentObject(healthKit)
                .environmentObject(authService)
        }
    }
}
```

---

#### Step 2: Standardize Message Format in Watch App

**Location**: `CardiacID Watch App/Services/WatchConnectivityService.swift`

**Find this section** (around line 89):
```swift
func sendHeartPatternData(_ heartPattern: [Double], completion: @escaping (Bool) -> Void = { _ in }) {
    let message: [String: Any] = [
        "type": "heartPattern",
        "data": heartPattern,
        "timestamp": Date().timeIntervalSince1970
    ]
    sendMessage(message, completion: completion)
}
```

**Add these new methods** to align with iOS message format:
```swift
// MARK: - iOS-Compatible Message Senders

/// Send heart rate update to iOS (matches iOS WatchMessage.heartRateUpdate)
func sendHeartRateUpdate(_ heartRate: Int) {
    let message: [String: Any] = [
        "message_type": "heart_rate_update",
        "heart_rate": heartRate,
        "timestamp": Date().timeIntervalSince1970
    ]

    sendMessage(message) { success in
        if success {
            print("✅ Sent heart rate update: \(heartRate) BPM")
        } else {
            print("❌ Failed to send heart rate update")
        }
    }
}

/// Send authentication status update to iOS
func sendAuthStatus(_ status: String) {
    let message: [String: Any] = [
        "message_type": "auth_status_update",
        "auth_status": status,
        "timestamp": Date().timeIntervalSince1970
    ]

    sendMessage(message) { success in
        if success {
            print("✅ Sent auth status: \(status)")
        } else {
            print("❌ Failed to send auth status")
        }
    }
}

/// Notify iOS that enrollment is complete
func notifyEnrollmentComplete(status: String) {
    let message: [String: Any] = [
        "message_type": "enrollment_complete",
        "enrollment_status": status,
        "timestamp": Date().timeIntervalSince1970
    ]

    sendMessage(message) { success in
        if success {
            print("✅ Sent enrollment complete notification")
        } else {
            print("❌ Failed to send enrollment notification")
        }
    }
}
```

---

#### Step 3: Update Message Receiver to Handle iOS Messages

**Location**: Same file, find `handleReceivedMessage` function (around line 175)

**Replace the switch statement** with this enhanced version:
```swift
private func handleReceivedMessage(_ message: [String: Any]) {
    // Check for iOS format first (message_type)
    if let messageType = message["message_type"] as? String {
        handleiOSMessage(messageType, data: message)
        return
    }

    // Fallback to old format (type)
    guard let type = message["type"] as? String else {
        print("⚠️ Received message with unknown format: \(message)")
        return
    }

    handleWatchMessage(type, data: message)
}

/// Handle messages from iOS app using iOS format
private func handleiOSMessage(_ messageType: String, data: [String: Any]) {
    print("📱 Received iOS message: \(messageType)")

    switch messageType {
    case "start_monitoring":
        // iOS is requesting heart rate monitoring
        NotificationCenter.default.post(
            name: .init("StartHeartRateMonitoring"),
            object: nil
        )

    case "stop_monitoring":
        // iOS is requesting to stop monitoring
        NotificationCenter.default.post(
            name: .init("StopHeartRateMonitoring"),
            object: nil
        )

    case "enrollment_request":
        // iOS is requesting enrollment
        NotificationCenter.default.post(name: .enrollmentRequest, object: nil)

    case "entra_id_auth_request":
        // Handle EntraID auth request from iOS
        NotificationCenter.default.post(
            name: .init("EntraIDAuthRequest"),
            object: nil
        )

    case "passwordless_auth_request":
        // Handle passwordless auth request from iOS
        if let method = data["method"] as? String {
            NotificationCenter.default.post(
                name: .init("PasswordlessAuthRequest"),
                object: nil,
                userInfo: ["method": method]
            )
        }

    default:
        print("⚠️ Unknown iOS message type: \(messageType)")
    }
}

/// Handle messages using old format (for compatibility)
private func handleWatchMessage(_ type: String, data: [String: Any]) {
    switch type {
    case "heartPatternRequest":
        NotificationCenter.default.post(name: .heartPatternRequest, object: nil)
    case "authenticationRequest":
        NotificationCenter.default.post(name: .authenticationRequest, object: nil)
    case "enrollmentRequest":
        NotificationCenter.default.post(name: .enrollmentRequest, object: nil)
    case "settingsUpdate":
        if let settings = data["settings"] as? [String: Any] {
            NotificationCenter.default.post(name: .settingsUpdate, object: settings)
        }
    default:
        break
    }
}
```

---

### Part 2: Verify iOS App Configuration

#### Check iOS `WatchConnectivityService` Initialization

**Location**: `CardiacID/CardiacIDApp.swift` (line 18)

**Verify this exists:**
```swift
@StateObject private var watchConnectivity = WatchConnectivityService.shared
```

✅ This is already correct in your iOS app!

---

#### Update iOS to Handle Watch Messages

**Location**: `CardiacID/Services/WatchConnectivityService.swift`

**Find `handleReceivedMessage` function** (line 253) and verify it handles both formats:

**Add this at the beginning of the function:**
```swift
private func handleReceivedMessage(_ message: [String: Any]) {
    // Log all received messages for debugging
    print("📱 iOS received message from Watch: \(message)")

    // Check for iOS format (message_type)
    if let messageTypeRaw = message["message_type"] as? String,
       let messageType = WatchMessage(rawValue: messageTypeRaw) {
        handleStandardMessage(messageType, message: message)
        return
    }

    // Check for Watch format (type)
    if let typeString = message["type"] as? String {
        handleWatchFormatMessage(typeString, message: message)
        return
    }

    print("⚠️ Received message with unknown format")
}

private func handleStandardMessage(_ messageType: WatchMessage, message: [String: Any]) {
    DispatchQueue.main.async {
        switch messageType {
        case .heartRateUpdate:
            if let heartRate = message[WatchMessage.Keys.heartRate] as? Int {
                self.lastHeartRate = heartRate
                let timestamp = Date()
                self.lastHeartRateTimestamp = timestamp
                self.heartRateSubject.send((heartRate, timestamp))
                print("❤️ Received heart rate: \(heartRate) BPM")
            }

        case .authStatusUpdate:
            if let status = message[WatchMessage.Keys.authStatus] as? String {
                self.authStatusSubject.send(status)
                print("🔐 Received auth status: \(status)")
            }

        case .enrollmentComplete:
            if let status = message[WatchMessage.Keys.enrollmentStatus] as? String {
                print("✅ Enrollment complete with status: \(status)")
                // Notify app of enrollment completion
                NotificationCenter.default.post(
                    name: .init("WatchEnrollmentComplete"),
                    object: nil,
                    userInfo: ["status": status]
                )
            }

        default:
            break
        }

        // Handle any error messages
        if let error = message[WatchMessage.Keys.error] as? String {
            self.errorSubject.send(error)
        }
    }
}

private func handleWatchFormatMessage(_ type: String, message: [String: Any]) {
    DispatchQueue.main.async {
        print("⌚️ Handling Watch format message: \(type)")

        switch type {
        case "heartPattern":
            if let data = message["data"] as? [Double] {
                print("❤️ Received heart pattern data: \(data.count) samples")
            }

        case "authenticationResult":
            if let result = message["result"] as? String {
                print("🔐 Received auth result: \(result)")
                self.authStatusSubject.send(result)
            }

        case "enrollmentStatus":
            if let isEnrolled = message["isEnrolled"] as? Bool {
                print("✅ Received enrollment status: \(isEnrolled)")
                NotificationCenter.default.post(
                    name: .init("WatchEnrollmentComplete"),
                    object: nil,
                    userInfo: ["isEnrolled": isEnrolled]
                )
            }

        default:
            print("⚠️ Unknown Watch message type: \(type)")
        }
    }
}
```

---

### Part 3: Enable App Groups (Optional but Recommended)

#### iOS App

1. Open **Xcode** → Select **CardiacID** target
2. Go to **Signing & Capabilities**
3. Click **+ Capability** → Add **App Groups**
4. Check the box for: `group.ARGOS.HeartIDv0.6`

#### Watch App

1. Select **CardiacID Watch App** target
2. Go to **Signing & Capabilities**
3. Click **+ Capability** → Add **App Groups**
4. Check the box for: `group.ARGOS.HeartIDv0.6`

---

## 🧪 Testing the Connection

### Test 1: Check Connection Status

**On iOS (CardiacID)**:
```swift
// In DashboardView or any view
.onAppear {
    print("📱 iOS Watch Status:")
    print("  - Paired: \(watchConnectivity.isPaired)")
    print("  - Installed: \(watchConnectivity.isInstalled)")
    print("  - Reachable: \(watchConnectivity.isReachable)")
    print("  - Activated: \(watchConnectivity.isActivated)")
}
```

**On Watch**:
```swift
// In ContentView
.onAppear {
    print("⌚️ Watch Connection Status:")
    print("  - Connected: \(watchConnectivity.isConnected)")
    print("  - Status: \(watchConnectivity.connectionStatus)")
}
```

### Test 2: Send Test Message from iOS to Watch

Add this button to iOS `DashboardView`:
```swift
Button("Test Watch Connection") {
    watchConnectivity.startMonitoring()
}
```

### Test 3: Send Test Message from Watch to iOS

Add this to Watch `MenuView`:
```swift
Button("Send Heart Rate to iOS") {
    watchConnectivity.sendHeartRateUpdate(72)
}
```

---

## 📊 Connection Status Indicators

### iOS App - Add to DashboardView

```swift
HStack {
    Image(systemName: watchConnectivity.isReachable ? "applewatch" : "applewatch.slash")
        .foregroundColor(watchConnectivity.isReachable ? .green : .red)

    Text(watchConnectivity.isReachable ? "Watch Connected" : "Watch Disconnected")
        .font(.caption)
}
```

### Watch App - Add to MenuView or SettingsView

```swift
HStack {
    Image(systemName: watchConnectivity.isConnected ? "iphone" : "iphone.slash")
        .foregroundColor(watchConnectivity.isConnected ? .green : .red)

    Text(watchConnectivity.connectionStatus)
        .font(.caption)
}
```

---

## 🐛 Troubleshooting

### Issue: "Watch Not Paired"
**Solution**:
- Ensure iPhone and Watch are paired in Watch app
- Check Bluetooth is enabled on both devices

### Issue: "Watch App Not Installed"
**Solution**:
- Build and run Watch app from Xcode
- Or install via Watch app on iPhone

### Issue: "Watch Not Reachable"
**Solution**:
- Keep both apps in foreground
- Ensure Bluetooth is enabled
- Make sure both devices are unlocked

### Issue: Messages Not Receiving
**Solution**:
1. Check console logs for "Received message"
2. Verify message format matches (use `message_type` key)
3. Ensure `WCSession` is activated on both sides
4. Try sending when both apps are active (foreground)

---

## 🔐 Security Considerations

1. **Data Encryption**: WatchConnectivity automatically encrypts messages
2. **App Groups**: Use for secure data sharing between targets
3. **Entitlements**: Already configured in your entitlements files
4. **Background Transfer**: Use `updateApplicationContext` for offline messages

---

## 📝 Quick Reference: Message Types

### iOS → Watch Messages

| Message Type | Key | Purpose |
|--------------|-----|---------|
| `start_monitoring` | `message_type` | Start heart rate monitoring |
| `stop_monitoring` | `message_type` | Stop monitoring |
| `enrollment_request` | `message_type` | Request enrollment |
| `entra_id_auth_request` | `message_type` | EntraID authentication |
| `passwordless_auth_request` | `message_type` | Passwordless auth |

### Watch → iOS Messages

| Message Type | Keys | Purpose |
|--------------|------|---------|
| `heart_rate_update` | `message_type`, `heart_rate` | Send current heart rate |
| `auth_status_update` | `message_type`, `auth_status` | Auth status change |
| `enrollment_complete` | `message_type`, `enrollment_status` | Enrollment done |

---

## ✅ Verification Checklist

Before deploying:

- [ ] Watch app `WatchConnectivityService` initialized in `CardiacIDApp.swift`
- [ ] iOS app `WatchConnectivityService` initialized (already done)
- [ ] Message formats standardized to use `message_type` key
- [ ] Both apps handle both old and new message formats
- [ ] Connection status displayed in both apps
- [ ] Test messages sent successfully both ways
- [ ] App Groups capability added (optional)
- [ ] Console logs show "Received message" on both sides
- [ ] Background data sync tested (if needed)

---

## 🚀 Next Steps

1. **Implement Changes**: Follow Part 1 and Part 2 above
2. **Test Connection**: Use Test 1, 2, 3
3. **Add UI Indicators**: Show connection status to users
4. **Monitor Logs**: Watch Xcode console for connection events
5. **Test Edge Cases**: Airplane mode, background, etc.

---

**Last Updated**: 2025-01-17
**Compatible With**: iOS 18.5+, watchOS 11.5+
