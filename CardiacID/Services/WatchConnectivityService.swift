//
//  WatchConnectivityService.swift
//  CardiacID
//
//  Cross-platform Watch Connectivity service for iOS and watchOS
//  Handles authentication token sharing and device communication
//

import Foundation
import Combine

#if os(iOS)
import WatchConnectivity
import UIKit
#elseif os(watchOS)
import WatchConnectivity
import WatchKit
#endif

// MARK: - Watch Message Types

enum WatchMessageType: String, CaseIterable {
    case authRequest = "auth_request"
    case authResult = "auth_result"
    case heartRateUpdate = "heart_rate_update"
    case enrollmentRequest = "enrollment_request"
    case enrollmentComplete = "enrollment_complete"
    case healthData = "health_data"
    case signOut = "sign_out"
}

// MARK: - Watch Message (Standard Format)

enum WatchMessage: String {
    case heartRateUpdate = "heart_rate_update"
    case authStatusUpdate = "auth_status_update"
    case enrollmentComplete = "enrollment_complete"
    case entraIDAuthRequest = "entra_id_auth_request"
    case entraIDAuthResult = "entra_id_auth_result"
    case passwordlessAuthRequest = "passwordless_auth_request"

    struct Keys {
        static let messageType = "message_type"
        static let heartRate = "heart_rate"
        static let authStatus = "auth_status"
        static let enrollmentStatus = "enrollment_status"
        static let success = "success"
        static let token = "token"
        static let refreshToken = "refresh_token"
        static let expiresAt = "expires_at"
        static let error = "error"
    }
}

// MARK: - Authentication Result

struct WatchAuthenticationResult {
    let isSuccess: Bool
    let token: String?
    let refreshToken: String?
    let expiresAt: Date?
    let errorMessage: String?
    let method: String?

    var isValid: Bool {
        guard isSuccess, let token = token, !token.isEmpty else { return false }
        if let expiresAt = expiresAt {
            return expiresAt > Date()
        }
        return true
    }
}

// MARK: - Watch Connectivity Service

@MainActor
class WatchConnectivityService: NSObject, ObservableObject {
    static let shared = WatchConnectivityService()

    @Published private(set) var isReachable = false
    @Published private(set) var isPaired = false
    @Published private(set) var isInstalled = false
    @Published private(set) var isActivated = false
    @Published private(set) var lastHeartRate: Int = 0
    @Published private(set) var lastHeartRateTimestamp: Date?
    @Published private(set) var lastError: String?

    // MARK: - Live Biometric Data from Watch

    /// Current biometric confidence from Watch (PPG when active, ECG when not)
    @Published private(set) var liveBiometricConfidence: Double = 0.0
    /// Current biometric method ("ppg" when actively monitoring, "ecg" for last reading)
    @Published private(set) var liveBiometricMethod: String = ""
    /// Whether Watch is actively monitoring (PPG mode)
    @Published private(set) var isWatchActivelyMonitoring: Bool = false
    /// User name from Watch biometric data
    @Published private(set) var liveBiometricUserName: String = ""
    /// Whether user is authenticated according to Watch
    @Published private(set) var liveBiometricAuthenticated: Bool = false
    /// Timestamp of last biometric data update
    @Published private(set) var liveBiometricTimestamp: Date?

    private let session: WCSession
    private var authCompletionHandler: ((WatchAuthenticationResult) -> Void)?

    // Publishers for reactive UI
    private let heartRateSubject = PassthroughSubject<(Int, Date), Never>()
    private let authStatusSubject = PassthroughSubject<String, Never>()
    private let errorSubject = PassthroughSubject<String, Never>()

    // MARK: - Ping/Pong Connection Verification

    /// Whether the Watch connection has been verified via ping/pong
    @Published private(set) var connectionVerified: Bool = false
    /// Round-trip latency from last successful ping
    @Published private(set) var roundTripLatency: TimeInterval?
    /// Last ping sent time for debouncing
    private var lastPingSentTime: Date?
    /// Minimum time between pings (6 seconds to prevent spam)
    private let minimumPingInterval: TimeInterval = 6.0
    /// Keep-alive ping timer
    private var keepAliveTimer: Timer?

    var heartRatePublisher: AnyPublisher<(Int, Date), Never> {
        heartRateSubject.eraseToAnyPublisher()
    }

    var authStatusPublisher: AnyPublisher<String, Never> {
        authStatusSubject.eraseToAnyPublisher()
    }

    var errorPublisher: AnyPublisher<String, Never> {
        errorSubject.eraseToAnyPublisher()
    }

    private override init() {
        self.session = WCSession.default
        super.init()

        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }
    }

    // MARK: - Public Monitoring Methods

    func startMonitoring() {
        if WCSession.isSupported() && session.activationState != .activated {
            session.activate()
        }
        print("WatchConnectivityService: Monitoring started")
    }

    func stopMonitoring() {
        print("WatchConnectivityService: Monitoring stopped")
    }

    // MARK: - Connection State Management

    /// Timer for periodic state refresh (syncs with biometric data updates)
    private var stateRefreshTimer: Timer?

    /// Update connection state from session and request biometric data
    func updateConnectionState() {
        #if os(iOS)
        let currentPaired = session.isPaired
        let currentInstalled = session.isWatchAppInstalled
        let currentReachable = session.isReachable
        let currentActivated = session.activationState == .activated

        // Only update if changed to avoid unnecessary UI updates
        if isPaired != currentPaired { isPaired = currentPaired }
        if isInstalled != currentInstalled { isInstalled = currentInstalled }
        if isReachable != currentReachable { isReachable = currentReachable }
        if isActivated != currentActivated { isActivated = currentActivated }

        print("📱 WatchConnectivity State - Paired: \(isPaired), Installed: \(isInstalled), Reachable: \(isReachable), Activated: \(isActivated)")

        // Request biometric data update if connected
        if currentReachable {
            requestBiometricDataUpdate()
        }
        #elseif os(watchOS)
        let currentReachable = session.isReachable
        let currentActivated = session.activationState == .activated

        if isReachable != currentReachable { isReachable = currentReachable }
        if isActivated != currentActivated { isActivated = currentActivated }

        print("⌚ WatchConnectivity State - Reachable: \(isReachable), Activated: \(isActivated)")
        #endif
    }

    /// Request biometric data update from Watch (fire and forget - non-blocking)
    private func requestBiometricDataUpdate() {
        #if os(iOS)
        guard session.isReachable else { return }

        // Use message_type key for iOS format (Watch expects this)
        // Fire and forget - no reply handler to prevent blocking
        let message: [String: Any] = [
            "message_type": "biometric_data_request",
            "timestamp": Date().timeIntervalSince1970
        ]

        // Send without waiting for reply - Watch will send response via separate message
        session.sendMessage(message, replyHandler: nil) { error in
            // Only log errors, don't block
            print("📱 Biometric data request failed: \(error.localizedDescription)")
        }
        #endif
    }

    /// Start periodic state refresh to catch pairing changes and update biometric data
    /// Default interval is 6 seconds for responsive connection verification
    func startPeriodicStateRefresh(interval: TimeInterval = 6.0) {
        stopPeriodicStateRefresh()

        stateRefreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateConnectionState()
            }
        }
        print("📱 Started periodic state refresh with interval: \(interval)s (connection verification)")
    }

    /// Stop periodic state refresh
    func stopPeriodicStateRefresh() {
        stateRefreshTimer?.invalidate()
        stateRefreshTimer = nil
    }

    /// Start connection keep-alive pings (default 10 seconds for responsive connection verification)
    func startConnectionKeepAlive(interval: TimeInterval = 10.0) {
        stopConnectionKeepAlive()

        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendPing()
            }
        }
        print("📱 Connection keep-alive started with interval: \(interval)s")
    }

    /// Stop connection keep-alive
    func stopConnectionKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        print("📱 Connection keep-alive stopped")
    }

    // MARK: - Ping/Pong Methods

    /// Send a ping to the Watch to verify connection (with debouncing)
    func sendPing(completion: ((Bool, TimeInterval?) -> Void)? = nil) {
        // Debounce: prevent rapid-fire pings that can overwhelm the Watch
        if let lastPing = lastPingSentTime,
           Date().timeIntervalSince(lastPing) < minimumPingInterval {
            print("📱 Ping debounced - too soon since last ping (\(String(format: "%.1f", Date().timeIntervalSince(lastPing)))s)")
            completion?(connectionVerified, roundTripLatency)
            return
        }

        guard session.isReachable else {
            print("📱 Watch not reachable, skipping ping")
            connectionVerified = false
            completion?(false, nil)
            return
        }

        let pingId = UUID().uuidString
        let pingTimestamp = Date().timeIntervalSince1970
        lastPingSentTime = Date()

        let message: [String: Any] = [
            "message_type": "ping",
            "ping_id": pingId,
            "timestamp": pingTimestamp
        ]

        session.sendMessage(message, replyHandler: { [weak self] response in
            Task { @MainActor in
                guard let self = self else { return }

                // Verify this is the pong we're expecting
                guard let responseType = response["message_type"] as? String,
                      responseType == "pong",
                      let responsePingId = response["ping_id"] as? String,
                      responsePingId == pingId else {
                    print("📱 Invalid pong response")
                    completion?(false, nil)
                    return
                }

                // Calculate round-trip latency
                let pongTimestamp = Date().timeIntervalSince1970
                let latency = pongTimestamp - pingTimestamp

                self.connectionVerified = true
                self.roundTripLatency = latency
                print("📱 Ping successful - latency: \(String(format: "%.0f", latency * 1000))ms")

                completion?(true, latency)
            }
        }, errorHandler: { [weak self] error in
            Task { @MainActor in
                self?.connectionVerified = false
                self?.roundTripLatency = nil
                print("📱 Ping failed: \(error.localizedDescription)")
                completion?(false, nil)
            }
        })
    }

    // MARK: - Authentication Methods

    #if os(iOS)
    /// Request EntraID authentication - sends request to trigger auth flow
    func requestEntraIDAuthentication() -> Result<Void, Error> {
        guard session.isReachable else {
            return .failure(NSError(domain: "WatchConnectivity", code: -1,
                                   userInfo: [NSLocalizedDescriptionKey: "Watch not reachable"]))
        }

        let message: [String: Any] = [
            WatchMessage.Keys.messageType: WatchMessage.entraIDAuthRequest.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            Task { @MainActor in
                self.errorSubject.send("Failed to send EntraID auth request: \(error.localizedDescription)")
            }
        }

        return .success(())
    }

    func sendAuthResult(_ result: WatchAuthenticationResult) async {
        guard session.isReachable else {
            print("Watch not reachable, cannot send auth result")
            return
        }

        let message: [String: Any] = [
            "type": WatchMessageType.authResult.rawValue,
            "success": result.isSuccess,
            "token": result.token ?? "",
            "error": result.errorMessage ?? "",
            "expires_at": result.expiresAt?.timeIntervalSince1970 ?? 0,
            "timestamp": Date().timeIntervalSince1970
        ]

        session.sendMessage(message, replyHandler: { reply in
            print("Auth result sent successfully: \(reply)")
        }) { error in
            print("Failed to send auth result: \(error)")
            Task { @MainActor in
                self.errorSubject.send("Failed to send authentication result: \(error.localizedDescription)")
            }
        }
    }

    /// Send EntraID authentication result to Watch
    func sendEntraIDAuthResult(success: Bool, token: String?, error: String?) {
        let message: [String: Any] = [
            WatchMessage.Keys.messageType: WatchMessage.entraIDAuthResult.rawValue,
            WatchMessage.Keys.success: success,
            WatchMessage.Keys.token: token ?? "",
            WatchMessage.Keys.error: error ?? "",
            "timestamp": Date().timeIntervalSince1970
        ]

        sendMessage(message)
    }

    /// Send EntraID authentication result to Watch using WatchAuthenticationResult
    func sendEntraIDAuthResult(_ result: WatchAuthenticationResult) async {
        sendEntraIDAuthResult(
            success: result.isSuccess,
            token: result.token,
            error: result.errorMessage
        )
    }

    /// Send passwordless authentication request
    func sendPasswordlessAuthRequest(email: String, code: String? = nil) {
        let message: [String: Any] = [
            WatchMessage.Keys.messageType: WatchMessage.passwordlessAuthRequest.rawValue,
            "email": email,
            "code": code ?? "",
            "timestamp": Date().timeIntervalSince1970
        ]

        sendMessage(message)
    }

    /// Send passwordless authentication request with method and heart pattern data
    func sendPasswordlessAuthRequest(method: String, heartPattern: Data) async {
        let message: [String: Any] = [
            WatchMessage.Keys.messageType: WatchMessage.passwordlessAuthRequest.rawValue,
            "method": method,
            "heartPattern": heartPattern.base64EncodedString(),
            "timestamp": Date().timeIntervalSince1970
        ]

        sendMessage(message)
    }
    #endif

    #if os(watchOS)
    func requestAuthenticationFromiOS() async -> WatchAuthenticationResult {
        guard session.isReachable else {
            return WatchAuthenticationResult(
                isSuccess: false,
                token: nil,
                refreshToken: nil,
                expiresAt: nil,
                errorMessage: "iPhone not reachable",
                method: nil
            )
        }

        let message: [String: Any] = [
            "type": WatchMessageType.authRequest.rawValue,
            "platform": "watchOS",
            "timestamp": Date().timeIntervalSince1970
        ]

        return await withCheckedContinuation { continuation in
            self.authCompletionHandler = { result in
                continuation.resume(returning: result)
            }

            session.sendMessage(message, replyHandler: { reply in
                print("Auth request acknowledged: \(reply)")
            }) { error in
                let errorResult = WatchAuthenticationResult(
                    isSuccess: false,
                    token: nil,
                    refreshToken: nil,
                    expiresAt: nil,
                    errorMessage: error.localizedDescription,
                    method: nil
                )
                continuation.resume(returning: errorResult)
            }
        }
    }
    #endif

    // MARK: - Health Data Methods

    func sendHeartRate(_ heartRate: Int) {
        let message: [String: Any] = [
            "type": WatchMessageType.heartRateUpdate.rawValue,
            "heart_rate": heartRate,
            "timestamp": Date().timeIntervalSince1970
        ]

        sendMessage(message)
    }

    func requestEnrollment() {
        let message: [String: Any] = [
            "type": WatchMessageType.enrollmentRequest.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ]

        sendMessage(message)
    }

    // MARK: - Generic Message Sending

    private func sendMessage(_ message: [String: Any]) {
        guard session.activationState == .activated else {
            errorSubject.send("Watch session not activated")
            return
        }

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                Task { @MainActor in
                    self.errorSubject.send("Message send failed: \(error.localizedDescription)")
                }
            }
        } else {
            // Fallback to application context
            do {
                try session.updateApplicationContext(message)
                print("Message sent via application context")
            } catch {
                errorSubject.send("Failed to send message: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.isActivated = activationState == .activated
            if let error = error {
                print("Watch session activation error: \(error.localizedDescription)")
                self.errorSubject.send("Watch connection error: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            self.isActivated = false
        }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            self.isActivated = false
        }
        // Reactivate the session
        WCSession.default.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isPaired = session.isPaired
            self.isInstalled = session.isWatchAppInstalled
        }
    }
    #endif

    // Receive message from watch
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.handleReceivedMessage(message, session: session, replyHandler: nil)
        }
    }

    // Receive message with reply from watch
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            self.handleReceivedMessage(message, session: session, replyHandler: replyHandler)
        }
    }

    // Receive updated application context
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.handleReceivedMessage(applicationContext, session: WCSession.default, replyHandler: nil)
        }
    }

    // MARK: - Message Handling

    private func handleReceivedMessage(_ message: [String: Any], session: WCSession, replyHandler: (([String: Any]) -> Void)?) {
        print("Received message: \(message)")

        // Check for iOS format first (message_type key)
        if let messageTypeRaw = message[WatchMessage.Keys.messageType] as? String,
           let messageType = WatchMessage(rawValue: messageTypeRaw) {
            handleStandardMessage(messageType, message: message)
            replyHandler?(["status": "received"])
            return
        }

        // Check for Watch legacy format (type key)
        if let typeString = message["type"] as? String {
            // Handle authentication requests from watchOS
            if typeString == "auth_request" {
                #if os(iOS)
                handleAuthRequest(session: session, replyHandler: replyHandler)
                #else
                replyHandler?(["success": false, "error": "Not supported on this platform"])
                #endif
                return
            }

            handleWatchFormatMessage(typeString, message: message)
            replyHandler?(["status": "received"])
            return
        }

        print("Received message with unknown format")
        replyHandler?(["status": "unknown_format"])
    }

    #if os(iOS)
    private func handleAuthRequest(session: WCSession, replyHandler: (([String: Any]) -> Void)?) {
        Task { @MainActor in
            do {
                // Trigger authentication on iOS using EntraIDAuthClient
                let user = try await EntraIDAuthClient.shared.signIn()

                // Get the access token
                if let accessToken = try? SecureCredentialManager.shared.retrieve(forKey: .entraIDAccessToken) {
                    // Send successful auth result back to watch
                    let authMessage: [String: Any] = [
                        "type": "auth_result",
                        "success": true,
                        "token": accessToken,
                        "user": [
                            "id": user.id,
                            "displayName": user.displayName,
                            "email": user.email,
                            "tenantId": user.tenantId ?? ""
                        ],
                        "expires_at": Date().addingTimeInterval(3600).timeIntervalSince1970,
                        "scopes": ["User.Read", "Application.Read.All", "Group.Read.All"]
                    ]

                    // Send via session message
                    if session.isReachable {
                        session.sendMessage(authMessage, replyHandler: nil)
                    }

                    replyHandler?(["success": true, "message": "Authentication completed"])
                } else {
                    replyHandler?(["success": false, "error": "Failed to retrieve access token"])
                }
            } catch {
                // Send error back to watch
                let errorMessage: [String: Any] = [
                    "type": "auth_result",
                    "success": false,
                    "error": error.localizedDescription
                ]

                if session.isReachable {
                    session.sendMessage(errorMessage, replyHandler: nil)
                }

                replyHandler?(["success": false, "error": error.localizedDescription])
            }
        }
    }
    #endif

    /// Handle messages using standard iOS WatchMessage format
    private func handleStandardMessage(_ messageType: WatchMessage, message: [String: Any]) {
        switch messageType {
        case .heartRateUpdate:
            if let heartRate = message[WatchMessage.Keys.heartRate] as? Int {
                self.lastHeartRate = heartRate
                let timestamp = Date()
                self.lastHeartRateTimestamp = timestamp
                self.heartRateSubject.send((heartRate, timestamp))
                print("Received heart rate from Watch: \(heartRate) BPM")
            }

        case .authStatusUpdate:
            // Also extract heart rate from auth status updates
            if let heartRate = message["heart_rate"] as? Int {
                self.lastHeartRate = heartRate
                let timestamp = Date()
                self.lastHeartRateTimestamp = timestamp
                self.heartRateSubject.send((heartRate, timestamp))
            }

            if let status = message[WatchMessage.Keys.authStatus] as? String {
                self.authStatusSubject.send(status)
                print("Received auth status from Watch: \(status)")
            }

        case .enrollmentComplete:
            if let status = message[WatchMessage.Keys.enrollmentStatus] as? String {
                print("Enrollment complete with status: \(status)")
                NotificationCenter.default.post(
                    name: .watchEnrollmentComplete,
                    object: nil,
                    userInfo: ["status": status]
                )
            }

        case .entraIDAuthRequest:
            print("Received EntraID auth request from Watch")
            NotificationCenter.default.post(
                name: .watchEntraIDAuthRequest,
                object: nil,
                userInfo: message
            )

        case .entraIDAuthResult:
            print("Received EntraID auth result")
            if let success = message[WatchMessage.Keys.success] as? Bool {
                let authResult = WatchAuthenticationResult(
                    isSuccess: success,
                    token: message[WatchMessage.Keys.token] as? String,
                    refreshToken: message[WatchMessage.Keys.refreshToken] as? String,
                    expiresAt: {
                        if let timestamp = message[WatchMessage.Keys.expiresAt] as? TimeInterval {
                            return Date(timeIntervalSince1970: timestamp)
                        }
                        return nil
                    }(),
                    errorMessage: message[WatchMessage.Keys.error] as? String,
                    method: "entra_id"
                )

                // Call completion handler if waiting
                authCompletionHandler?(authResult)
                authCompletionHandler = nil

                NotificationCenter.default.post(
                    name: .watchEntraIDAuthResult,
                    object: authResult,
                    userInfo: message
                )
            }

        case .passwordlessAuthRequest:
            print("Received passwordless auth request from Watch")
            NotificationCenter.default.post(
                name: .watchPasswordlessAuthRequest,
                object: nil,
                userInfo: message
            )
        }

        // Handle any error messages
        if let error = message[WatchMessage.Keys.error] as? String {
            self.errorSubject.send(error)
        }
    }

    /// Handle messages from Watch using legacy format (type key)
    private func handleWatchFormatMessage(_ type: String, message: [String: Any]) {
        print("Handling Watch legacy format message: \(type)")

        switch type {
        case "heartPattern":
            if let data = message["data"] as? [Double] {
                print("Received heart pattern data from Watch: \(data.count) samples")
            }

        case "authenticationResult", "auth_result":
            if let success = message["success"] as? Bool {
                let result = WatchAuthenticationResult(
                    isSuccess: success,
                    token: message["token"] as? String,
                    refreshToken: message["refresh_token"] as? String,
                    expiresAt: {
                        if let timestamp = message["expires_at"] as? TimeInterval {
                            return Date(timeIntervalSince1970: timestamp)
                        }
                        return nil
                    }(),
                    errorMessage: message["error"] as? String,
                    method: "entra_id"
                )

                authCompletionHandler?(result)
                authCompletionHandler = nil
            }

        case "enrollmentStatus":
            if let isEnrolled = message["isEnrolled"] as? Bool {
                print("Received enrollment status from Watch: \(isEnrolled)")
                NotificationCenter.default.post(
                    name: .watchEnrollmentComplete,
                    object: nil,
                    userInfo: ["isEnrolled": isEnrolled]
                )
            }

        case "heart_rate_update":
            if let heartRate = message["heart_rate"] as? Int {
                self.lastHeartRate = heartRate
                let timestamp = Date()
                self.lastHeartRateTimestamp = timestamp
                self.heartRateSubject.send((heartRate, timestamp))
            }

        case "sign_out":
            NotificationCenter.default.post(
                name: .init("RemoteSignOut"),
                object: nil
            )

        case "biometric_data_response":
            // Handle Live Biometric Data response from Watch
            handleBiometricDataResponse(message)

        default:
            print("Unknown Watch message type: \(type)")
        }
    }

    // MARK: - Live Biometric Data Handler

    /// Handle biometric data response from Watch for Live Biometric Data display
    /// Watch sends PPG data when actively monitoring, ECG data when not
    private func handleBiometricDataResponse(_ message: [String: Any]) {
        guard let confidence = message["confidence"] as? Double else {
            print("📱 Invalid biometric data response - missing confidence")
            return
        }

        let heartRate = message["heart_rate"] as? Int ?? 0
        let method = message["method"] as? String ?? "unknown"
        let isActive = message["is_active_monitoring"] as? Bool ?? false
        let userName = message["user_name"] as? String ?? ""
        let authenticated = message["authenticated"] as? Bool ?? false

        // Update published properties for Live Biometric Data display
        self.liveBiometricConfidence = confidence
        self.liveBiometricMethod = method
        self.isWatchActivelyMonitoring = isActive
        self.liveBiometricUserName = userName
        self.liveBiometricAuthenticated = authenticated
        self.liveBiometricTimestamp = Date()

        // Also update heart rate if provided
        if heartRate > 0 {
            self.lastHeartRate = heartRate
            self.lastHeartRateTimestamp = Date()
            self.heartRateSubject.send((heartRate, Date()))
        }

        let methodLabel = isActive ? "PPG (active)" : "ECG (last reading)"
        print("📱 Live Biometric Data updated - \(methodLabel): \(Int(confidence * 100))%, HR: \(heartRate) bpm, User: \(userName)")

        // Post notification for UI updates
        NotificationCenter.default.post(
            name: .liveBiometricDataUpdated,
            object: nil,
            userInfo: [
                "confidence": confidence,
                "method": method,
                "isActiveMonitoring": isActive,
                "heartRate": heartRate,
                "userName": userName,
                "authenticated": authenticated
            ]
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let watchEnrollmentComplete = Notification.Name("WatchEnrollmentComplete")
    static let watchEntraIDAuthRequest = Notification.Name("WatchEntraIDAuthRequest")
    static let watchEntraIDAuthResult = Notification.Name("WatchEntraIDAuthResult")
    static let watchPasswordlessAuthRequest = Notification.Name("WatchPasswordlessAuthRequest")
    static let authenticationSucceeded = Notification.Name("AuthenticationSucceeded")
    static let authenticationFailed = Notification.Name("AuthenticationFailed")
    static let liveBiometricDataUpdated = Notification.Name("LiveBiometricDataUpdated")
}
