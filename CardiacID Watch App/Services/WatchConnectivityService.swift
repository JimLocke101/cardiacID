import Foundation
import WatchConnectivity
import Combine

/// Service for handling communication between watchOS and iOS apps
/// Enterprise-ready with AES-256 encrypted template sync support
class WatchConnectivityService: NSObject, ObservableObject {
    // Singleton instance for app-wide access
    static let shared = WatchConnectivityService()

    @Published var isConnected = false
    @Published var lastMessage: [String: Any]?
    @Published var connectionStatus: String = "Not Connected"

    private var session: WCSession?

    /// Thread-safe lock for cached biometric data
    private let biometricDataLock = NSLock()
    private var cachedBiometricData: [String: Any]?

    /// Flag to track initialization state
    private var isInitialized = false

    private override init() {
        super.init()
        // CRITICAL: Keep init synchronous to prevent Watch app launch timeout
        // setupWatchConnectivity is safe - just sets delegate and activates
        setupWatchConnectivity()
        setupNotificationObservers()
        isInitialized = true
        print("⌚️ WatchConnectivityService: Initialization complete")
    }
    
    private func setupWatchConnectivity() {
        guard WCSession.isSupported() else {
            connectionStatus = "Watch Connectivity Not Supported"
            return
        }
        
        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }
    
    private func setupNotificationObservers() {
        // Listen for enrollment status updates
        NotificationCenter.default.addObserver(
            forName: .init("SendEnrollmentStatus"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let isEnrolled = notification.userInfo?["isEnrolled"] as? Bool {
                self?.sendEnrollmentStatus(isEnrolled) { success in
                    if success {
                        print("Enrollment status sent to iOS app successfully")
                    } else {
                        print("Failed to send enrollment status to iOS app")
                    }
                }
            }
        }
        
        // Listen for authentication result updates
        NotificationCenter.default.addObserver(
            forName: .init("SendAuthenticationResult"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let result = notification.userInfo?["result"] as? AuthenticationResult {
                self?.sendAuthenticationResult(result) { success in
                    if success {
                        print("Authentication result sent to iOS app successfully")
                    } else {
                        print("Failed to send authentication result to iOS app")
                    }
                }
            }
        }
    }
    
    /// Send message to iOS companion app (fire-and-forget to prevent blocking)
    func sendMessage(_ message: [String: Any], completion: @escaping (Bool) -> Void = { _ in }) {
        guard let session = session, session.isReachable else {
            connectionStatus = "iOS App Not Reachable"
            completion(false)
            return
        }

        // CRITICAL: Use nil replyHandler for fire-and-forget to prevent Watch hangs
        // The Watch app was crashing/hanging when using replyHandler
        session.sendMessage(message, replyHandler: nil) { error in
            DispatchQueue.main.async {
                self.connectionStatus = "Error: \(error.localizedDescription)"
                completion(false)
            }
        }
        completion(true)
    }

    /// Send message with reply handler (only use when you NEED the response)
    /// WARNING: This can cause Watch hangs if iOS doesn't respond quickly
    func sendMessageWithReply(_ message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void, errorHandler: @escaping (Error) -> Void) {
        guard let session = session, session.isReachable else {
            errorHandler(NSError(domain: "WatchConnectivity", code: -1, userInfo: [NSLocalizedDescriptionKey: "iOS App Not Reachable"]))
            return
        }

        session.sendMessage(message, replyHandler: { response in
            DispatchQueue.main.async {
                self.lastMessage = response
                replyHandler(response)
            }
        }, errorHandler: { error in
            DispatchQueue.main.async {
                self.connectionStatus = "Error: \(error.localizedDescription)"
                errorHandler(error)
            }
        })
    }
    
    /// Send heart pattern data to iOS app
    func sendHeartPatternData(_ heartPattern: [Double], completion: @escaping (Bool) -> Void = { _ in }) {
        let message: [String: Any] = [
            "type": "heartPattern",
            "data": heartPattern,
            "timestamp": Date().timeIntervalSince1970
        ]
        sendMessage(message, completion: completion)
    }
    
    /// Send authentication result to iOS app
    func sendAuthenticationResult(_ result: AuthenticationResult, completion: @escaping (Bool) -> Void = { _ in }) {
        let methodString: String
        switch result.method {
        case .ppgContinuous:
            methodString = "ppgContinuous"
        case .ecgSingle:
            methodString = "ecgSingle"
        case .ecgMultiple:
            methodString = "ecgMultiple"
        case .hybrid:
            methodString = "hybrid"
        }
        
        let message: [String: Any] = [
            "type": "authenticationResult",
            "success": result.success,
            "confidenceScore": result.confidenceScore,
            "method": methodString,
            "requiresStepUp": result.requiresStepUp,
            "timestamp": result.timestamp.timeIntervalSince1970
        ]
        sendMessage(message, completion: completion)
    }
    
    /// Send enrollment status to iOS app
    func sendEnrollmentStatus(_ isEnrolled: Bool, completion: @escaping (Bool) -> Void = { _ in }) {
        let message: [String: Any] = [
            "type": "enrollmentStatus",
            "isEnrolled": isEnrolled,
            "timestamp": Date().timeIntervalSince1970
        ]
        sendMessage(message, completion: completion)
    }

    /// Send enrollment completion with user details to iOS app
    /// Called by HeartIDService after successful 3-ECG enrollment
    func sendEnrollmentComplete(userId: String, firstName: String, lastName: String) {
        let message: [String: Any] = [
            "message_type": "enrollment_complete",
            "user_id": userId,
            "first_name": firstName,
            "last_name": lastName,
            "timestamp": Date().timeIntervalSince1970
        ]
        sendMessage(message) { success in
            if success {
                print("✅ Watch: Sent enrollment complete to iOS - \(firstName) \(lastName)")
            } else {
                print("❌ Watch: Failed to send enrollment complete to iOS")
            }
        }
    }

    /// Send authentication status update to iOS app with heart rate
    /// Called by HeartIDService during continuous authentication
    func sendAuthenticationStatus(confidence: Double, authenticated: Bool, userName: String, heartRate: Int = 0) {
        let message: [String: Any] = [
            "message_type": "auth_status_update",
            "confidence": confidence,
            "authenticated": authenticated,
            "user_name": userName,
            "heart_rate": heartRate,  // ✅ NOW SENDING HEART RATE!
            "timestamp": Date().timeIntervalSince1970
        ]
        sendMessage(message) { success in
            if success {
                print("✅ Watch: Sent auth status to iOS - \(userName): \(Int(confidence * 100))%, HR: \(heartRate) bpm")
            } else {
                print("❌ Watch: Failed to send auth status to iOS")
            }
        }
    }
    
    /// Request data from iOS app
    func requestData(_ dataType: String, completion: @escaping (Bool) -> Void = { _ in }) {
        let message: [String: Any] = [
            "type": "requestData",
            "dataType": dataType,
            "timestamp": Date().timeIntervalSince1970
        ]
        sendMessage(message, completion: completion)
    }

    // MARK: - iOS-Compatible Message Methods

    /// Send heart rate update to iOS using iOS-compatible format
    func sendHeartRateToiOS(_ heartRate: Int) {
        let message: [String: Any] = [
            "message_type": "heart_rate_update",  // iOS format key
            "heart_rate": heartRate,
            "timestamp": Date().timeIntervalSince1970
        ]

        sendMessage(message) { success in
            if success {
                print("✅ Watch: Sent heart rate to iOS: \(heartRate) BPM")
            } else {
                print("❌ Watch: Failed to send heart rate to iOS")
            }
        }
    }

    /// Send authentication status to iOS using iOS-compatible format
    func sendAuthStatusToiOS(_ status: String) {
        let message: [String: Any] = [
            "message_type": "auth_status_update",  // iOS format key
            "auth_status": status,
            "timestamp": Date().timeIntervalSince1970
        ]

        sendMessage(message) { success in
            if success {
                print("✅ Watch: Sent auth status to iOS: \(status)")
            } else {
                print("❌ Watch: Failed to send auth status to iOS")
            }
        }
    }

    /// Notify iOS that enrollment is complete using iOS-compatible format
    func notifyEnrollmentCompleteToiOS(_ status: String) {
        let message: [String: Any] = [
            "message_type": "enrollment_complete",  // iOS format key
            "enrollment_status": status,
            "timestamp": Date().timeIntervalSince1970
        ]

        sendMessage(message) { success in
            if success {
                print("✅ Watch: Sent enrollment complete to iOS")
            } else {
                print("❌ Watch: Failed to send enrollment status to iOS")
            }
        }
    }

    // MARK: - Biometric Data Response for Live Biometric Data

    /// Send biometric data response to iOS for Live Biometric Data display
    /// Uses PPG data when actively monitoring, falls back to last ECG when not
    private func sendBiometricDataResponse() {
        // Request biometric data from HeartIDService via notification
        NotificationCenter.default.post(
            name: .init("BiometricDataRequest"),
            object: nil,
            userInfo: ["replyHandler": { [weak self] (data: [String: Any]) in
                self?.sendMessage(data) { success in
                    if success {
                        print("✅ Watch: Sent biometric data response to iOS")
                    } else {
                        print("❌ Watch: Failed to send biometric data response to iOS")
                    }
                }
            }]
        )
    }

    /// Send biometric data directly (called by HeartIDService)
    /// Fire and forget - non-blocking to prevent system hangs
    func sendBiometricDataToiOS(
        confidence: Double,
        heartRate: Int,
        method: String,
        isActiveMonitoring: Bool,
        userName: String,
        authenticated: Bool
    ) {
        guard let session = session, session.isReachable else {
            print("⌚️ Watch: iOS not reachable, skipping biometric data send")
            return
        }

        let message: [String: Any] = [
            "message_type": "biometric_data_response",
            "confidence": confidence,
            "heart_rate": heartRate,
            "method": method,  // "ppg" or "ecg"
            "is_active_monitoring": isActiveMonitoring,
            "user_name": userName,
            "authenticated": authenticated,
            "timestamp": Date().timeIntervalSince1970
        ]

        // Fire and forget - no completion handler to prevent blocking
        session.sendMessage(message, replyHandler: nil) { error in
            // Only log errors, don't block
            print("⌚️ Watch: Biometric data send failed: \(error.localizedDescription)")
        }

        let methodLabel = isActiveMonitoring ? "PPG (active)" : "ECG (last reading)"
        print("⌚️ Watch: Sent biometric data - \(methodLabel): \(Int(confidence * 100))%, HR: \(heartRate) bpm")
    }

    // MARK: - Periodic Heartbeat to iOS

    /// Timer for sending periodic heartbeat to iOS
    private var heartbeatTimer: Timer?

    /// Start sending periodic heartbeat messages to iOS
    /// This ensures iOS knows the Watch is connected even if WCSession.isReachable is intermittently false
    func startHeartbeat(interval: TimeInterval = 10.0) {
        stopHeartbeat()

        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.sendHeartbeat()
        }

        // Send initial heartbeat immediately
        sendHeartbeat()
        print("⌚️ Watch: Started heartbeat with interval: \(interval)s")
    }

    /// Stop sending heartbeat messages
    func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    /// Send a heartbeat message to iOS to confirm connection
    private func sendHeartbeat() {
        guard let session = session, session.isReachable else {
            return
        }

        let message: [String: Any] = [
            "message_type": "watch_heartbeat",
            "timestamp": Date().timeIntervalSince1970,
            "is_active": true
        ]

        // Fire and forget - no completion handler to prevent blocking
        session.sendMessage(message, replyHandler: nil) { error in
            // Silently ignore errors - heartbeat is best-effort
            print("⌚️ Watch: Heartbeat failed (non-critical): \(error.localizedDescription)")
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityService: WCSessionDelegate {
    /// CRITICAL: All WCSessionDelegate methods MUST be nonisolated to prevent threading issues
    /// that were causing Watch app crashes/hangs
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // Capture state synchronously before async dispatch
        let isReachable = session.isReachable
        let newState = activationState

        Task { @MainActor in
            switch newState {
            case .activated:
                self.isConnected = isReachable
                self.connectionStatus = isReachable ? "Connected to iOS" : "iOS App Not Reachable"
            case .inactive:
                self.isConnected = false
                self.connectionStatus = "Inactive"
            case .notActivated:
                self.isConnected = false
                self.connectionStatus = "Not Activated"
            @unknown default:
                self.isConnected = false
                self.connectionStatus = "Unknown State"
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        // Capture state synchronously before async dispatch
        let isReachable = session.isReachable

        Task { @MainActor in
            self.isConnected = isReachable
            self.connectionStatus = isReachable ? "Connected to iOS" : "iOS App Not Reachable"
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        // Capture message copy for async dispatch
        let messageCopy = message

        Task { @MainActor in
            self.lastMessage = messageCopy
            self.handleReceivedMessage(messageCopy)
        }
    }

    /// CRITICAL: This delegate handles ping requests - must respond synchronously for pings
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        // Check for ping message - respond synchronously to prevent timeout
        if let messageType = message["message_type"] as? String, messageType == "ping" {
            // Respond to ping immediately without dispatching to main thread
            let response: [String: Any] = [
                "message_type": "pong",
                "ping_id": message["ping_id"] as? String ?? "",
                "original_timestamp": message["timestamp"] as? TimeInterval ?? 0,
                "pong_timestamp": Date().timeIntervalSince1970,
                "source": "watchOS"
            ]
            replyHandler(response)
            return
        }

        // Check for biometric_data_request - use cached data for thread safety
        if let messageType = message["message_type"] as? String, messageType == "biometric_data_request" {
            // Use thread-safe cached biometric data
            biometricDataLock.lock()
            let cachedData = cachedBiometricData ?? [
                "message_type": "biometric_data_response",
                "confidence": 0.0,
                "heart_rate": 0,
                "method": "unknown",
                "is_active_monitoring": false,
                "user_name": "",
                "authenticated": false,
                "timestamp": Date().timeIntervalSince1970
            ]
            biometricDataLock.unlock()

            replyHandler(cachedData)

            // Also trigger async update for fresh data
            let messageCopy = message
            Task { @MainActor in
                self.handleReceivedMessage(messageCopy, replyHandler: nil)
            }
            return
        }

        // Capture message copy for async dispatch
        let messageCopy = message

        // For other messages, dispatch to main actor and send acknowledgment
        Task { @MainActor in
            self.lastMessage = messageCopy
            self.handleReceivedMessage(messageCopy, replyHandler: replyHandler)
        }
    }

    /// Update cached biometric data (called from HeartIDService)
    func updateCachedBiometricData(_ data: [String: Any]) {
        biometricDataLock.lock()
        cachedBiometricData = data
        biometricDataLock.unlock()
    }
    
    private func handleReceivedMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)? = nil) {
        print("⌚️ Watch received message: \(message)")

        // Check for iOS format first (message_type key)
        if let messageType = message["message_type"] as? String {
            handleiOSMessage(messageType, data: message, replyHandler: replyHandler)
            return
        }

        // Fallback to legacy format (type key) for backward compatibility
        if let type = message["type"] as? String {
            handleLegacyMessage(type, data: message)
            replyHandler?(["status": "received"])
            return
        }

        print("⚠️ Watch: Unknown message format received")
        replyHandler?(["status": "unknown_format"])
    }

    /// Handle messages from iOS app using iOS format (message_type key)
    private func handleiOSMessage(_ messageType: String, data: [String: Any], replyHandler: (([String: Any]) -> Void)? = nil) {
        print("📱 Watch: Processing iOS message type: \(messageType)")

        switch messageType {
        case "start_monitoring":
            // iOS is requesting heart rate monitoring
            print("⌚️ Watch: iOS requested start monitoring")
            NotificationCenter.default.post(
                name: .init("StartHeartRateMonitoring"),
                object: nil
            )

        case "stop_monitoring":
            // iOS is requesting to stop monitoring
            print("⌚️ Watch: iOS requested stop monitoring")
            NotificationCenter.default.post(
                name: .init("StopHeartRateMonitoring"),
                object: nil
            )

        case "enrollment_request":
            // iOS is requesting enrollment
            print("⌚️ Watch: iOS requested enrollment")
            NotificationCenter.default.post(name: .enrollmentRequest, object: nil)

        case "entra_id_auth_request":
            // Handle EntraID authentication request from iOS
            print("⌚️ Watch: iOS requested EntraID auth")
            NotificationCenter.default.post(
                name: .init("EntraIDAuthRequest"),
                object: nil
            )

        case "entra_id_auth_result":
            // Handle EntraID auth result from iOS
            if let success = data["success"] as? Bool {
                print("🔐 Watch: Received EntraID auth result from iOS: \(success)")
                NotificationCenter.default.post(
                    name: .init("EntraIDAuthResultReceived"),
                    object: nil,
                    userInfo: ["success": success]
                )
            }

        case "passwordless_auth_request":
            // Handle passwordless auth request from iOS
            print("⌚️ Watch: iOS requested passwordless auth")
            if let method = data["method"] as? String {
                NotificationCenter.default.post(
                    name: .init("PasswordlessAuthRequest"),
                    object: nil,
                    userInfo: ["method": method]
                )
            }

        case "biometric_data_request":
            // iOS is requesting current biometric data for Live Biometric Data display
            // Handle asynchronously to prevent blocking
            print("⌚️ Watch: iOS requested biometric data update")
            sendBiometricDataResponse()
            replyHandler?(["status": "biometric_data_requested"])
            return

        default:
            print("⚠️ Watch: Unknown iOS message type: \(messageType)")
        }

        // Send acknowledgment for handled messages
        replyHandler?(["status": "received"])
    }

    /// Handle legacy format messages (type key) for backward compatibility
    private func handleLegacyMessage(_ type: String, data: [String: Any]) {
        print("🔄 Watch: Processing legacy message type: \(type)")

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
}

// MARK: - Notification Names

extension Notification.Name {
    static let heartPatternRequest = Notification.Name("heartPatternRequest")
    static let authenticationRequest = Notification.Name("authenticationRequest")
    static let enrollmentRequest = Notification.Name("enrollmentRequest")
    static let settingsUpdate = Notification.Name("settingsUpdate")
}
