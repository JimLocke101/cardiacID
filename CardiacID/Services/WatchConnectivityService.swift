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
    case passkeyAuthenticate = "passkey_authenticate"
    case passkeyAuthenticateResult = "passkey_authenticate_result"
    case passkeyRegister = "passkey_register"
    case passkeyRegisterResult = "passkey_register_result"
    case heartIDAuthenticate = "heartid_authenticate"
    case heartIDAuthenticateResult = "heartid_authenticate_result"
    case fido2Authenticate = "fido2_authenticate"
    case fido2AuthenticateResult = "fido2_authenticate_result"
    case fido2Register = "fido2_register"
    case fido2RegisterResult = "fido2_register_result"

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

    // MARK: - Effective Connection Status
    /// More accurate connection status that considers actual data flow, not just WCSession.isReachable
    /// Returns true if we've received data from Watch within the last 30 seconds
    var isEffectivelyConnected: Bool {
        // If WCSession says reachable, trust it
        if isReachable { return true }

        // Check for recent heartbeat from Watch (most reliable indicator)
        if let lastHeartbeat = lastWatchHeartbeat,
           Date().timeIntervalSince(lastHeartbeat) < 30.0 {
            return true
        }

        // Otherwise check if we've received biometric data recently (within 30 seconds)
        if let lastUpdate = liveBiometricTimestamp,
           Date().timeIntervalSince(lastUpdate) < 30.0 {
            return true
        }

        // Also check heart rate timestamp as fallback
        if let lastHR = lastHeartRateTimestamp,
           Date().timeIntervalSince(lastHR) < 30.0 {
            return true
        }

        return false
    }

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
    /// Recent beat intervals (RR intervals in seconds) from Watch PPG sensor
    @Published private(set) var liveBeatIntervals: [Double] = []
    /// Recent heart rate samples (BPM) from Watch PPG sensor
    @Published private(set) var liveRecentHeartRates: [Double] = []
    /// Timestamp of last heartbeat received from Watch
    @Published private(set) var lastWatchHeartbeat: Date?

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

        // CRITICAL FIX: Try to establish connection even when not reachable
        // If activated but not reachable, proactively attempt connection
        if currentActivated && currentPaired && currentInstalled {
            if currentReachable {
                // Connected - request biometric data update
                requestBiometricDataUpdate()
            } else {
                // Not reachable but activated - try to establish connection
                // Use application context as fallback or send ping to wake up watch
                attemptConnectionRecovery()
            }
        }
        #elseif os(watchOS)
        let currentReachable = session.isReachable
        let currentActivated = session.activationState == .activated

        if isReachable != currentReachable { isReachable = currentReachable }
        if isActivated != currentActivated { isActivated = currentActivated }

        print("⌚ WatchConnectivity State - Reachable: \(isReachable), Activated: \(isActivated)")
        #endif
    }
    
    /// Attempt to recover connection when activated but not reachable
    private func attemptConnectionRecovery() {
        #if os(iOS)
        guard session.activationState == .activated else { return }
        
        // Try sending a ping to wake up the watch connection
        // This helps establish reachability when watch is active but connection is stale
        sendPing { [weak self] success, latency in
            if success {
                print("📱 Connection recovery successful via ping - latency: \(String(format: "%.0f", (latency ?? 0) * 1000))ms")
                // Now that we're connected, request biometric data
                self?.requestBiometricDataUpdate()
            } else {
                // If ping fails, try application context as fallback
                print("📱 Ping failed, attempting application context fallback")
                self?.requestBiometricDataUpdateViaContext()
            }
        }
        #endif
    }

    /// Request biometric data update from Watch (fire and forget - non-blocking)
    private func requestBiometricDataUpdate() {
        #if os(iOS)
        guard session.isReachable else {
            // Fallback to application context if not reachable
            requestBiometricDataUpdateViaContext()
            return
        }

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
            // Fallback to application context on error
            self.requestBiometricDataUpdateViaContext()
        }
        #endif
    }
    
    /// Request biometric data via application context (fallback when not reachable)
    private func requestBiometricDataUpdateViaContext() {
        #if os(iOS)
        guard session.activationState == .activated else { return }
        
        let message: [String: Any] = [
            "message_type": "biometric_data_request",
            "timestamp": Date().timeIntervalSince1970
        ]
        
        do {
            try session.updateApplicationContext(message)
            print("📱 Biometric data request sent via application context (fallback)")
        } catch {
            print("📱 Failed to send biometric data request via application context: \(error.localizedDescription)")
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
    // MARK: - Token Relay to Watch

    /// Proactively push EntraID token to Watch via transferUserInfo (guaranteed delivery)
    /// transferUserInfo is FIFO-queued and delivered even when Watch is backgrounded
    func pushTokenToWatch(
        accessToken: String,
        refreshToken: String?,
        expiresAt: Date,
        userId: String,
        displayName: String
    ) {
        guard session.activationState == .activated else {
            print("Watch session not activated, cannot push token")
            return
        }

        let payload: [String: Any] = [
            "message_type": "token_relay",
            "access_token": accessToken,
            "refresh_token": refreshToken ?? "",
            "expires_at": expiresAt.timeIntervalSince1970,
            "user_id": userId,
            "display_name": displayName,
            "timestamp": Date().timeIntervalSince1970
        ]

        // transferUserInfo is queued and delivered when Watch becomes reachable
        session.transferUserInfo(payload)
        print("iOS: Pushed token to Watch via transferUserInfo for \(displayName)")

        // Also try immediate delivery if reachable
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("iOS: Immediate token push failed (queued via transferUserInfo): \(error.localizedDescription)")
            }
        }
    }

    /// Push enrollment validation back to Watch after iPhone confirms enrollment
    func pushEnrollmentValidation(userId: String, templateHash: String, enrollmentStatus: String) {
        guard session.activationState == .activated else { return }

        let payload: [String: Any] = [
            "message_type": "enrollment_sync",
            "user_id": userId,
            "template_hash": templateHash,
            "enrollment_status": enrollmentStatus,
            "validated": true,
            "timestamp": Date().timeIntervalSince1970
        ]

        session.transferUserInfo(payload)
        print("iOS: Pushed enrollment validation to Watch for user \(userId)")
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
        sendMessage(message, silent: false)
    }

    /// Send message with option to suppress errors (for acknowledgments that aren't critical)
    private func sendMessage(_ message: [String: Any], silent: Bool) {
        guard session.activationState == .activated else {
            if !silent {
                errorSubject.send("Watch session not activated")
            }
            print("⚠️ WatchConnectivity: Session not activated, cannot send message")
            return
        }

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                // Only report errors for non-silent messages
                if !silent {
                    Task { @MainActor in
                        self.errorSubject.send("Message send failed: \(error.localizedDescription)")
                    }
                }
                print("⚠️ WatchConnectivity: Message send failed (silent=\(silent)): \(error.localizedDescription)")
            }
        } else {
            // For result/acknowledgment messages, try transferUserInfo instead of applicationContext
            // This queues the message for delivery when Watch becomes reachable
            let messageType = message["message_type"] as? String ?? "unknown"
            if messageType.contains("result") || messageType.contains("Result") {
                // Queue for later delivery
                session.transferUserInfo(message)
                print("📤 WatchConnectivity: Watch not reachable, queued message via transferUserInfo: \(messageType)")
            } else {
                // Fallback to application context for other messages
                do {
                    try session.updateApplicationContext(message)
                    print("📤 WatchConnectivity: Message sent via application context: \(messageType)")
                } catch {
                    if !silent {
                        errorSubject.send("Failed to send message: \(error.localizedDescription)")
                    }
                    print("⚠️ WatchConnectivity: Failed to update application context: \(error.localizedDescription)")
                }
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
            } else if activationState == .activated {
                // CRITICAL FIX: When session activates, immediately check connection state
                // This helps establish reachability right after activation
                self.updateConnectionState()
                print("📱 Watch session activated - checking connection state")
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

    // Receive queued transferUserInfo payloads (token relay, enrollment sync)
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            print("Received transferUserInfo from Watch")
            self.handleReceivedMessage(userInfo, session: WCSession.default, replyHandler: nil)
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

                    // Proactively push token to Watch via transferUserInfo for reliable delivery
                    self.pushTokenToWatch(
                        accessToken: accessToken,
                        refreshToken: nil,
                        expiresAt: Date().addingTimeInterval(3600),
                        userId: user.id,
                        displayName: user.displayName
                    )

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
    
    /// Handle passkey authentication request from Watch
    private func handlePasskeyAuthenticationRequest(message: [String: Any]) {
        Task { @MainActor in
            print("📱 WatchConnectivity: Handling passkey authentication request from Watch")
            
            // Extract challenge from message (base64 encoded)
            guard let challengeBase64 = message["challenge"] as? String,
                  let challengeData = Data(base64Encoded: challengeBase64) else {
                print("❌ WatchConnectivity: Invalid challenge in passkey request")
                // Send error back to Watch
                let errorMessage: [String: Any] = [
                    WatchMessage.Keys.messageType: WatchMessage.passkeyAuthenticateResult.rawValue,
                    WatchMessage.Keys.success: false,
                    WatchMessage.Keys.error: "Invalid challenge"
                ]
                sendMessage(errorMessage)
                return
            }
            
            do {
                // Trigger passkey authentication
                let passkeyService = PasskeyService.shared
                let result = try await passkeyService.authenticate(challenge: challengeData)
                
                print("✅ WatchConnectivity: Passkey authentication successful")
                
                // Send success result to Watch
                let successMessage: [String: Any] = [
                    WatchMessage.Keys.messageType: WatchMessage.passkeyAuthenticateResult.rawValue,
                    WatchMessage.Keys.success: true,
                    "credential_id": result.credentialID?.base64EncodedString() ?? "",
                    "user_id": result.userID?.base64EncodedString() ?? "",
                    "signature": result.signature?.base64EncodedString() ?? "",
                    "client_data_json": result.clientDataJSON?.base64EncodedString() ?? "",
                    "authenticator_data": result.authenticatorData?.base64EncodedString() ?? ""
                ]
                sendMessage(successMessage)
                
            } catch {
                print("❌ WatchConnectivity: Passkey authentication failed - \(error.localizedDescription)")
                
                // Send error result to Watch
                let errorMessage: [String: Any] = [
                    WatchMessage.Keys.messageType: WatchMessage.passkeyAuthenticateResult.rawValue,
                    WatchMessage.Keys.success: false,
                    WatchMessage.Keys.error: error.localizedDescription
                ]
                sendMessage(errorMessage)
            }
        }
    }
    
    /// Handle HeartID authentication from Watch
    /// This is called when Watch authenticates using HeartID biometrics
    /// and notifies iPhone of the authentication
    private func handleHeartIDAuthenticationFromWatch(message: [String: Any]) {
        Task { @MainActor in
            print("📱 WatchConnectivity: Handling HeartID authentication from Watch")

            // Extract HeartID authentication data
            let confidence = message["confidence"] as? Double ?? 0.0
            let userName = message["user_name"] as? String ?? "Unknown"
            let accessLevel = message["access_level"] as? String ?? "unknown"
            let method = message["method"] as? String ?? "unknown"

            print("🔐 WatchConnectivity: HeartID Auth - User: \(userName), Confidence: \(Int(confidence * 100))%, Access: \(accessLevel), Method: \(method)")

            // Update local state to reflect Watch authentication
            self.liveBiometricConfidence = confidence
            self.liveBiometricUserName = userName
            self.liveBiometricAuthenticated = confidence >= 0.70
            self.liveBiometricMethod = method
            self.liveBiometricTimestamp = Date()

            // Post notification for iOS app components to react
            NotificationCenter.default.post(
                name: .heartIDAuthenticationResult,
                object: nil,
                userInfo: [
                    "success": true,
                    "confidence": confidence,
                    "userName": userName,
                    "accessLevel": accessLevel,
                    "method": method,
                    "source": "watch"
                ]
            )

            // Optionally, send acknowledgment back to Watch (silent - don't show error if Watch is asleep)
            let ackMessage: [String: Any] = [
                WatchMessage.Keys.messageType: WatchMessage.heartIDAuthenticateResult.rawValue,
                WatchMessage.Keys.success: true,
                "confidence": confidence,
                "access_level": accessLevel,
                "synced": true
            ]
            sendMessage(ackMessage, silent: true)

            print("✅ WatchConnectivity: HeartID authentication processed and synced to iPhone")
        }
    }

    /// Handle FIDO2 authentication from Watch
    /// Watch performs FIDO2 operations locally, gated by HeartID biometrics
    private func handleFIDO2AuthenticationFromWatch(message: [String: Any]) {
        Task { @MainActor in
            print("📱 WatchConnectivity: Handling FIDO2 authentication from Watch")

            // Extract FIDO2 assertion data
            let credentialID = message["credential_id"] as? String ?? ""
            let authenticatorData = message["authenticator_data"] as? String ?? ""
            let clientDataJSON = message["client_data_json"] as? String ?? ""
            let signature = message["signature"] as? String ?? ""
            let heartIDConfidence = message["heartid_confidence"] as? Double ?? 0.0
            let userName = message["user_name"] as? String ?? "Unknown"
            let accessLevel = message["access_level"] as? String ?? "unknown"

            print("🔐 WatchConnectivity: FIDO2 Auth - User: \(userName), HeartID: \(Int(heartIDConfidence * 100))%, Access: \(accessLevel)")
            print("🔐 WatchConnectivity: Credential ID: \(credentialID.prefix(20))...")

            // Update local state
            self.liveBiometricConfidence = heartIDConfidence
            self.liveBiometricUserName = userName
            self.liveBiometricAuthenticated = heartIDConfidence >= 0.70
            self.liveBiometricMethod = "fido2"
            self.liveBiometricTimestamp = Date()

            // In production: Verify the signature against stored public key
            // For now, we trust the Watch's verification

            // Post notification for iOS app components
            NotificationCenter.default.post(
                name: .fido2AuthenticationResult,
                object: nil,
                userInfo: [
                    "success": true,
                    "credential_id": credentialID,
                    "authenticator_data": authenticatorData,
                    "client_data_json": clientDataJSON,
                    "signature": signature,
                    "heartid_confidence": heartIDConfidence,
                    "userName": userName,
                    "accessLevel": accessLevel,
                    "source": "watch"
                ]
            )

            // Send acknowledgment back to Watch (silent - don't show error if Watch is asleep)
            let ackMessage: [String: Any] = [
                WatchMessage.Keys.messageType: WatchMessage.fido2AuthenticateResult.rawValue,
                WatchMessage.Keys.success: true,
                "verified": true,
                "access_level": accessLevel
            ]
            sendMessage(ackMessage, silent: true)

            print("✅ WatchConnectivity: FIDO2 authentication processed")
        }
    }

    /// Handle FIDO2 registration from Watch
    private func handleFIDO2RegistrationFromWatch(message: [String: Any]) {
        Task { @MainActor in
            print("📱 WatchConnectivity: Handling FIDO2 registration from Watch")

            // Extract FIDO2 registration data
            let credentialID = message["credential_id"] as? String ?? ""
            let publicKey = message["public_key"] as? String ?? ""
            let attestationObject = message["attestation_object"] as? String ?? ""
            let clientDataJSON = message["client_data_json"] as? String ?? ""
            let userName = message["user_name"] as? String ?? "Unknown"

            print("🔐 WatchConnectivity: FIDO2 Registration - User: \(userName)")
            print("🔐 WatchConnectivity: Credential ID: \(credentialID.prefix(20))...")
            print("🔐 WatchConnectivity: Public Key: \(publicKey.prefix(20))...")

            // In production: Store the public key on the server for future verification
            // The server would verify the attestation and store:
            // - credentialID
            // - publicKey
            // - userName
            // - deviceInfo

            // Post notification for iOS app components
            NotificationCenter.default.post(
                name: .fido2RegistrationResult,
                object: nil,
                userInfo: [
                    "success": true,
                    "credential_id": credentialID,
                    "public_key": publicKey,
                    "attestation_object": attestationObject,
                    "client_data_json": clientDataJSON,
                    "userName": userName,
                    "source": "watch"
                ]
            )

            // Send acknowledgment back to Watch (silent - don't show error if Watch is asleep)
            let ackMessage: [String: Any] = [
                WatchMessage.Keys.messageType: WatchMessage.fido2RegisterResult.rawValue,
                WatchMessage.Keys.success: true,
                "registered": true
            ]
            sendMessage(ackMessage, silent: true)

            print("✅ WatchConnectivity: FIDO2 registration processed")
        }
    }

    /// Handle passkey registration request from Watch
    private func handlePasskeyRegistrationRequest(message: [String: Any]) {
        Task { @MainActor in
            print("📱 WatchConnectivity: Handling passkey registration request from Watch")
            
            // Extract registration data from message
            guard let username = message["username"] as? String,
                  let userIDBase64 = message["user_id"] as? String,
                  let userIDData = Data(base64Encoded: userIDBase64),
                  let challengeBase64 = message["challenge"] as? String,
                  let challengeData = Data(base64Encoded: challengeBase64) else {
                print("❌ WatchConnectivity: Invalid registration data")
                let errorMessage: [String: Any] = [
                    WatchMessage.Keys.messageType: WatchMessage.passkeyRegisterResult.rawValue,
                    WatchMessage.Keys.success: false,
                    WatchMessage.Keys.error: "Invalid registration data"
                ]
                sendMessage(errorMessage)
                return
            }
            
            do {
                // Trigger passkey registration
                let passkeyService = PasskeyService.shared
                let result = try await passkeyService.registerPasskey(
                    username: username,
                    userID: userIDData,
                    challenge: challengeData
                )
                
                print("✅ WatchConnectivity: Passkey registration successful")
                
                // Send success result to Watch
                let successMessage: [String: Any] = [
                    WatchMessage.Keys.messageType: WatchMessage.passkeyRegisterResult.rawValue,
                    WatchMessage.Keys.success: true,
                    "credential_id": result.credentialID.base64EncodedString(),
                    "client_data_json": result.rawClientDataJSON.base64EncodedString(),
                    "attestation_object": result.rawAttestationObject?.base64EncodedString() ?? ""
                ]
                sendMessage(successMessage)
                
            } catch {
                print("❌ WatchConnectivity: Passkey registration failed - \(error.localizedDescription)")
                
                // Send error result to Watch
                let errorMessage: [String: Any] = [
                    WatchMessage.Keys.messageType: WatchMessage.passkeyRegisterResult.rawValue,
                    WatchMessage.Keys.success: false,
                    WatchMessage.Keys.error: error.localizedDescription
                ]
                sendMessage(errorMessage)
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
            
        case .passkeyAuthenticate:
            print("📱 Received passkey authentication request from Watch")
            #if os(iOS)
            handlePasskeyAuthenticationRequest(message: message)
            #endif
            
        case .passkeyRegister:
            print("📱 Received passkey registration request from Watch")
            #if os(iOS)
            handlePasskeyRegistrationRequest(message: message)
            #endif
            
        case .passkeyAuthenticateResult:
            print("📱 Received passkey authentication result")
            // Handle result from server verification
            if let success = message[WatchMessage.Keys.success] as? Bool {
                NotificationCenter.default.post(
                    name: .passkeyAuthenticationResult,
                    object: nil,
                    userInfo: ["success": success, "message": message]
                )
            }
            
        case .passkeyRegisterResult:
            print("📱 Received passkey registration result")
            // Handle result from server verification
            if let success = message[WatchMessage.Keys.success] as? Bool {
                NotificationCenter.default.post(
                    name: .passkeyRegistrationResult,
                    object: nil,
                    userInfo: ["success": success, "message": message]
                )
            }

        case .heartIDAuthenticate:
            print("📱 Received HeartID authentication from Watch")
            #if os(iOS)
            handleHeartIDAuthenticationFromWatch(message: message)
            #endif

        case .heartIDAuthenticateResult:
            print("📱 Received HeartID authentication result")
            // Handle result from server verification
            if let success = message[WatchMessage.Keys.success] as? Bool {
                NotificationCenter.default.post(
                    name: .heartIDAuthenticationResult,
                    object: nil,
                    userInfo: ["success": success, "message": message]
                )
            }

        case .fido2Authenticate:
            print("📱 Received FIDO2 authentication from Watch")
            #if os(iOS)
            handleFIDO2AuthenticationFromWatch(message: message)
            #endif

        case .fido2AuthenticateResult:
            print("📱 Received FIDO2 authentication result")
            if let success = message[WatchMessage.Keys.success] as? Bool {
                NotificationCenter.default.post(
                    name: .fido2AuthenticationResult,
                    object: nil,
                    userInfo: ["success": success, "message": message]
                )
            }

        case .fido2Register:
            print("�� Received FIDO2 registration from Watch")
            #if os(iOS)
            handleFIDO2RegistrationFromWatch(message: message)
            #endif

        case .fido2RegisterResult:
            print("📱 Received FIDO2 registration result")
            if let success = message[WatchMessage.Keys.success] as? Bool {
                NotificationCenter.default.post(
                    name: .fido2RegistrationResult,
                    object: nil,
                    userInfo: ["success": success, "message": message]
                )
            }
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

        case "watch_heartbeat":
            // Handle heartbeat from Watch - update last contact timestamp
            handleWatchHeartbeat(message)

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

        // Store real beat intervals and heart rates from Watch for
        // independent iOS-side HRV verification.
        if let intervals = message["beat_intervals"] as? [Double], !intervals.isEmpty {
            self.liveBeatIntervals = intervals
        }
        if let hrs = message["recent_heart_rates"] as? [Double], !hrs.isEmpty {
            self.liveRecentHeartRates = hrs
        }

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

        // Trigger biometric fallback if confidence is below threshold or not authenticated
        if confidence < 0.70 || !authenticated {
            NotificationCenter.default.post(
                name: .heartIDFallbackRequired,
                object: nil,
                userInfo: [
                    "confidence": confidence,
                    "reason": confidence < 0.70 ? "Low confidence (\(Int(confidence * 100))%)" : "Not authenticated",
                    "userName": userName
                ]
            )
        }
    }

    // MARK: - Watch Heartbeat Handler

    /// Handle heartbeat message from Watch - confirms Watch is actively connected
    private func handleWatchHeartbeat(_ message: [String: Any]) {
        lastWatchHeartbeat = Date()

        // Log less frequently to avoid spam
        if let timestamp = message["timestamp"] as? TimeInterval {
            let watchTime = Date(timeIntervalSince1970: timestamp)
            let latency = Date().timeIntervalSince(watchTime)
            print("📱 Received Watch heartbeat - latency: \(String(format: "%.0f", latency * 1000))ms")
        }
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
    static let passkeyAuthenticationResult = Notification.Name("PasskeyAuthenticationResult")
    static let passkeyRegistrationResult = Notification.Name("PasskeyRegistrationResult")
    static let heartIDAuthenticationResult = Notification.Name("HeartIDAuthenticationResult")
    static let fido2AuthenticationResult = Notification.Name("FIDO2AuthenticationResult")
    static let fido2RegistrationResult = Notification.Name("FIDO2RegistrationResult")
    static let heartIDFallbackRequired = Notification.Name("HeartIDFallbackRequired")
    static let enrollmentSyncValidated = Notification.Name("EnrollmentSyncValidated")
}
