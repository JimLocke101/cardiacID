import Foundation
import WatchConnectivity
import Combine
import UIKit

// MARK: - Custom Error Types
enum WatchConnectivityError: Error, LocalizedError {
    case sessionNotActivated
    case watchNotReachable
    case messageSendFailed(String)
    case authenticationFailed(String)
    case invalidData(String)
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .sessionNotActivated:
            return "Watch session is not activated"
        case .watchNotReachable:
            return "Watch is not reachable"
        case .messageSendFailed(let message):
            return "Failed to send message: \(message)"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .invalidData(let message):
            return "Invalid data: \(message)"
        case .timeout:
            return "Operation timed out"
        }
    }
}

// MARK: - Watch Messages
enum WatchMessage: String, CaseIterable {
    case startMonitoring = "start_monitoring"
    case stopMonitoring = "stop_monitoring"
    case heartRateUpdate = "heart_rate_update"
    case authStatusUpdate = "auth_status_update"
    case enrollmentRequest = "enrollment_request"
    case enrollmentComplete = "enrollment_complete"
    
    // EntraID specific messages
    case entraIDAuthRequest = "entra_id_auth_request"
    case entraIDAuthResult = "entra_id_auth_result"
    case passwordlessAuthRequest = "passwordless_auth_request"
    
    // Keys for message dictionary
    struct Keys {
        static let messageType = "message_type"
        static let heartRate = "heart_rate"
        static let timestamp = "timestamp"
        static let authStatus = "auth_status"
        static let enrollmentStatus = "enrollment_status"
        static let deviceId = "device_id"
        static let userId = "user_id"
        static let error = "error"
        
        // EntraID specific keys
        static let success = "success"
        static let token = "token"
        static let method = "method"
        static let heartPattern = "heart_pattern"
        static let expiresAt = "expires_at"
        static let refreshToken = "refresh_token"
        static let scope = "scope"
    }
}

// MARK: - Watch Authentication Result
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
class WatchConnectivityService: NSObject, ObservableObject {
    // Singleton instance
    static let shared = WatchConnectivityService()
    
    // Session
    private let session = WCSession.default
    
    // Publishers
    @Published var isReachable = false
    @Published var isPaired = false
    @Published var isInstalled = false
    @Published var isActivated = false
    @Published var lastHeartRate: Int = 0
    @Published var lastHeartRateTimestamp: Date?
    
    // Subjects for message passing
    private let heartRateSubject = PassthroughSubject<(Int, Date), Never>()
    private let authStatusSubject = PassthroughSubject<String, Never>()
    private let errorSubject = PassthroughSubject<String, Never>()
    
    // Public publishers
    var heartRatePublisher: AnyPublisher<(Int, Date), Never> {
        return heartRateSubject.eraseToAnyPublisher()
    }
    
    var authStatusPublisher: AnyPublisher<String, Never> {
        return authStatusSubject.eraseToAnyPublisher()
    }
    
    var errorPublisher: AnyPublisher<String, Never> {
        return errorSubject.eraseToAnyPublisher()
    }
    
    // Private init for singleton
    private override init() {
        super.init()
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }
    }
    
    // MARK: - Send Messages
    
    func startMonitoring() {
        sendMessage(
            [WatchMessage.Keys.messageType: WatchMessage.startMonitoring.rawValue],
            replyHandler: { reply in
                print("Watch monitoring started: \(reply)")
            },
            errorHandler: { error in
                print("Error starting watch monitoring: \(error.localizedDescription)")
                self.errorSubject.send("Failed to start monitoring: \(error.localizedDescription)")
            }
        )
    }
    
    func stopMonitoring() {
        sendMessage(
            [WatchMessage.Keys.messageType: WatchMessage.stopMonitoring.rawValue],
            replyHandler: { reply in
                print("Watch monitoring stopped: \(reply)")
            },
            errorHandler: { error in
                print("Error stopping watch monitoring: \(error.localizedDescription)")
                self.errorSubject.send("Failed to stop monitoring: \(error.localizedDescription)")
            }
        )
    }
    
    func startEnrollment() {
        sendMessage(
            [WatchMessage.Keys.messageType: WatchMessage.enrollmentRequest.rawValue],
            replyHandler: { reply in
                print("Enrollment request sent: \(reply)")
            },
            errorHandler: { error in
                print("Error requesting enrollment: \(error.localizedDescription)")
                self.errorSubject.send("Failed to start enrollment: \(error.localizedDescription)")
            }
        )
    }
    
    // MARK: - EntraID Methods
    
    /// Initiates EntraID authentication flow on the Watch
    /// - Parameter completion: Callback with authentication result
    func requestEntraIDAuthentication() async -> Result<Void, WatchConnectivityError> {
        let message: [String: Any] = [
            WatchMessage.Keys.messageType: WatchMessage.entraIDAuthRequest.rawValue,
            WatchMessage.Keys.timestamp: Date().timeIntervalSince1970
        ]
        
        return await withCheckedContinuation { continuation in
            sendMessage(
                message,
                replyHandler: { reply in
                    print("✅ EntraID auth request acknowledged: \(reply)")
                    continuation.resume(returning: .success(()))
                },
                errorHandler: { error in
                    print("❌ Error sending EntraID auth request: \(error)")
                    let watchError = WatchConnectivityError.authenticationFailed(error.localizedDescription)
                    self.errorSubject.send(watchError.localizedDescription)
                    continuation.resume(returning: .failure(watchError))
                }
            )
        }
    }
    
    /// Sends EntraID authentication result to the Watch
    /// - Parameters:
    ///   - result: The authentication result containing tokens and status
    func sendEntraIDAuthResult(_ result: WatchAuthenticationResult) async -> Result<Void, WatchConnectivityError> {
        var message: [String: Any] = [
            WatchMessage.Keys.messageType: WatchMessage.entraIDAuthResult.rawValue,
            WatchMessage.Keys.success: result.isSuccess,
            WatchMessage.Keys.timestamp: Date().timeIntervalSince1970
        ]
        
        if let token = result.token {
            message[WatchMessage.Keys.token] = token
        }
        
        if let refreshToken = result.refreshToken {
            message[WatchMessage.Keys.refreshToken] = refreshToken
        }
        
        if let expiresAt = result.expiresAt {
            message[WatchMessage.Keys.expiresAt] = expiresAt.timeIntervalSince1970
        }
        
        if let errorMessage = result.errorMessage {
            message[WatchMessage.Keys.error] = errorMessage
        }
        
        return await withCheckedContinuation { continuation in
            sendMessage(
                message,
                replyHandler: { reply in
                    print("✅ EntraID auth result sent successfully: \(reply)")
                    continuation.resume(returning: .success(()))
                },
                errorHandler: { error in
                    print("❌ Error sending EntraID auth result: \(error)")
                    let watchError = WatchConnectivityError.messageSendFailed(error.localizedDescription)
                    self.errorSubject.send(watchError.localizedDescription)
                    continuation.resume(returning: .failure(watchError))
                }
            )
        }
    }
    
    // MARK: - Passwordless Auth Methods
    
    /// Initiates passwordless authentication using biometric data
    /// - Parameters:
    ///   - method: Authentication method (e.g., "heart_pattern", "biometric")
    ///   - heartPattern: Encrypted heart rate pattern data
    ///   - deviceId: Unique device identifier for security
    func sendPasswordlessAuthRequest(
        method: String, 
        heartPattern: Data, 
        deviceId: String = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    ) async -> Result<Void, WatchConnectivityError> {
        let message: [String: Any] = [
            WatchMessage.Keys.messageType: WatchMessage.passwordlessAuthRequest.rawValue,
            WatchMessage.Keys.method: method,
            WatchMessage.Keys.heartPattern: heartPattern,
            WatchMessage.Keys.deviceId: deviceId,
            WatchMessage.Keys.timestamp: Date().timeIntervalSince1970
        ]
        
        return await withCheckedContinuation { continuation in
            sendMessage(
                message,
                replyHandler: { reply in
                    print("✅ Passwordless auth request sent: \(reply)")
                    continuation.resume(returning: .success(()))
                },
                errorHandler: { error in
                    print("❌ Error sending passwordless auth request: \(error)")
                    let watchError = WatchConnectivityError.authenticationFailed(error.localizedDescription)
                    self.errorSubject.send(watchError.localizedDescription)
                    continuation.resume(returning: .failure(watchError))
                }
            )
        }
    }
    
    // MARK: - Generic Message Sender
    
    /// Sends a message to the Watch with proper error handling and fallback mechanisms
    /// - Parameters:
    ///   - message: Dictionary containing the message data
    ///   - replyHandler: Called when message is successfully sent and acknowledged
    ///   - errorHandler: Called when an error occurs during sending
    private func sendMessage(
        _ message: [String: Any], 
        replyHandler: @escaping ([String: Any]) -> Void, 
        errorHandler: @escaping (Error) -> Void
    ) {
        // Validate session state
        guard session.activationState == .activated else {
            let error = WatchConnectivityError.sessionNotActivated
            print("❌ Session not activated: \(session.activationState.rawValue)")
            errorHandler(error)
            return
        }
        
        // Add metadata to message
        var enrichedMessage = message
        enrichedMessage["_source"] = "iOS"
        enrichedMessage["_version"] = "1.0"
        enrichedMessage["_messageId"] = UUID().uuidString
        
        if session.isReachable {
            // Direct message sending when watch is reachable
            print("📱 → ⌚️ Sending message via direct transfer: \(message[WatchMessage.Keys.messageType] ?? "unknown")")
            session.sendMessage(enrichedMessage, replyHandler: { reply in
                print("✅ Message acknowledged by Watch: \(reply)")
                replyHandler(reply)
            }, errorHandler: { error in
                print("❌ Direct message failed: \(error.localizedDescription)")
                // Attempt fallback to application context
                self.fallbackToApplicationContext(enrichedMessage, replyHandler: replyHandler, errorHandler: errorHandler)
            })
        } else {
            print("📱 → ⌚️ Watch not reachable, using application context fallback")
            fallbackToApplicationContext(enrichedMessage, replyHandler: replyHandler, errorHandler: errorHandler)
        }
    }
    
    /// Fallback mechanism using application context when direct messaging fails
    private func fallbackToApplicationContext(
        _ message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void,
        errorHandler: @escaping (Error) -> Void
    ) {
        do {
            try session.updateApplicationContext(message)
            print("✅ Message queued via application context")
            replyHandler(["status": "queued", "method": "application_context"])
        } catch {
            print("❌ Application context fallback failed: \(error.localizedDescription)")
            errorHandler(WatchConnectivityError.messageSendFailed(error.localizedDescription))
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isActivated = activationState == .activated
            if let error = error {
                print("Watch session activation error: \(error.localizedDescription)")
                self.errorSubject.send("Watch connection error: \(error.localizedDescription)")
            }
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }
    
    // iOS only delegate method
    func sessionDidBecomeInactive(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isActivated = false
        }
    }
    
    // iOS only delegate method
    func sessionDidDeactivate(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isActivated = false
            // Reactivate the session if needed
            WCSession.default.activate()
        }
    }
    
    // iOS only delegate method
    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isPaired = session.isPaired
            self.isInstalled = session.isWatchAppInstalled
        }
    }
    
    // Receive message from watch
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleReceivedMessage(message)
    }
    
    // Receive message with reply from watch
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handleReceivedMessage(message)
        replyHandler(["status": "received"])
    }
    
    // Receive updated application context
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleReceivedMessage(applicationContext)
    }
    
    // MARK: - Message Handling

    private func handleReceivedMessage(_ message: [String: Any]) {
        print("📱 iOS received message from Watch: \(message)")

        // Check for iOS format first (message_type key)
        if let messageTypeRaw = message[WatchMessage.Keys.messageType] as? String,
           let messageType = WatchMessage(rawValue: messageTypeRaw) {
            handleStandardMessage(messageType, message: message)
            return
        }

        // Check for Watch legacy format (type key)
        if let typeString = message["type"] as? String {
            handleWatchFormatMessage(typeString, message: message)
            return
        }

        print("⚠️ iOS: Received message with unknown format")
    }

    /// Handle messages using standard iOS WatchMessage format
    private func handleStandardMessage(_ messageType: WatchMessage, message: [String: Any]) {
        DispatchQueue.main.async {
            switch messageType {
            case .heartRateUpdate:
                if let heartRate = message[WatchMessage.Keys.heartRate] as? Int {
                    self.lastHeartRate = heartRate
                    let timestamp = Date()
                    self.lastHeartRateTimestamp = timestamp
                    self.heartRateSubject.send((heartRate, timestamp))
                    print("❤️ iOS: Received heart rate from Watch: \(heartRate) BPM")
                }

            case .authStatusUpdate:
                // Also extract heart rate from auth status updates
                if let heartRate = message["heart_rate"] as? Int {
                    self.lastHeartRate = heartRate
                    let timestamp = Date()
                    self.lastHeartRateTimestamp = timestamp
                    self.heartRateSubject.send((heartRate, timestamp))
                    print("❤️ iOS: Received heart rate from auth update: \(heartRate) BPM")
                }

                if let status = message[WatchMessage.Keys.authStatus] as? String {
                    self.authStatusSubject.send(status)
                    print("🔐 iOS: Received auth status from Watch: \(status)")
                }

            case .enrollmentComplete:
                if let status = message[WatchMessage.Keys.enrollmentStatus] as? String {
                    print("✅ iOS: Enrollment complete with status: \(status)")
                    // Notify app of enrollment completion
                    NotificationCenter.default.post(
                        name: .init("WatchEnrollmentComplete"),
                        object: nil,
                        userInfo: ["status": status]
                    )
                }
                
            case .entraIDAuthRequest:
                print("🔐 iOS: Received EntraID auth request from Watch")
                // Handle EntraID authentication request from Watch
                NotificationCenter.default.post(
                    name: .init("WatchEntraIDAuthRequest"),
                    object: nil,
                    userInfo: message
                )
                
            case .entraIDAuthResult:
                print("🔐 iOS: Received EntraID auth result from Watch")
                if let success = message[WatchMessage.Keys.success] as? Bool {
                    var authResult = WatchAuthenticationResult(
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
                    
                    // Notify app of EntraID auth result
                    NotificationCenter.default.post(
                        name: .init("WatchEntraIDAuthResult"),
                        object: authResult,
                        userInfo: message
                    )
                }
                
            case .passwordlessAuthRequest:
                print("🔐 iOS: Received passwordless auth request from Watch")
                // Handle passwordless authentication request from Watch
                NotificationCenter.default.post(
                    name: .init("WatchPasswordlessAuthRequest"),
                    object: nil,
                    userInfo: message
                )

            default:
                print("⚠️ iOS: Unhandled message type: \(messageType)")
            }

            // Handle any error messages
            if let error = message[WatchMessage.Keys.error] as? String {
                self.errorSubject.send(error)
            }
        }
    }

    /// Handle messages from Watch using legacy format (type key)
    private func handleWatchFormatMessage(_ type: String, message: [String: Any]) {
        DispatchQueue.main.async {
            print("⌚️ iOS: Handling Watch legacy format message: \(type)")

            switch type {
            case "heartPattern":
                if let data = message["data"] as? [Double] {
                    print("❤️ iOS: Received heart pattern data from Watch: \(data.count) samples")
                    // Could convert to heart rate or store pattern
                }

            case "authenticationResult":
                if let result = message["result"] as? String {
                    print("🔐 iOS: Received auth result from Watch: \(result)")
                    self.authStatusSubject.send(result)
                }

            case "enrollmentStatus":
                if let isEnrolled = message["isEnrolled"] as? Bool {
                    print("✅ iOS: Received enrollment status from Watch: \(isEnrolled)")
                    NotificationCenter.default.post(
                        name: .init("WatchEnrollmentComplete"),
                        object: nil,
                        userInfo: ["isEnrolled": isEnrolled]
                    )
                }

            default:
                print("⚠️ iOS: Unknown Watch message type: \(type)")
            }
        }
    }
}

// MARK: - Convenience Extensions

extension WatchConnectivityService {
    /// Convenience method for modern async/await authentication
    @MainActor
    func authenticateWithEntraID() async -> WatchAuthenticationResult {
        let result = await requestEntraIDAuthentication()
        
        switch result {
        case .success:
            // Wait for the authentication result from the Watch
            // This would typically be handled by listening to NotificationCenter
            return WatchAuthenticationResult(
                isSuccess: false,
                token: nil,
                refreshToken: nil,
                expiresAt: nil,
                errorMessage: "Authentication initiated. Waiting for Watch response.",
                method: "entra_id"
            )
        case .failure(let error):
            return WatchAuthenticationResult(
                isSuccess: false,
                token: nil,
                refreshToken: nil,
                expiresAt: nil,
                errorMessage: error.localizedDescription,
                method: "entra_id"
            )
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let watchEnrollmentComplete = Notification.Name("WatchEnrollmentComplete")
    static let watchEntraIDAuthRequest = Notification.Name("WatchEntraIDAuthRequest")
    static let watchEntraIDAuthResult = Notification.Name("WatchEntraIDAuthResult")
    static let watchPasswordlessAuthRequest = Notification.Name("WatchPasswordlessAuthRequest")
}
