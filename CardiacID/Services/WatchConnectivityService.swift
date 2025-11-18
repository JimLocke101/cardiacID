import Foundation
import WatchConnectivity
import Combine

// MARK: - Watch Messages
enum WatchMessage: String {
    case startMonitoring = "start_monitoring"
    case stopMonitoring = "stop_monitoring"
    case heartRateUpdate = "heart_rate_update"
    case authStatusUpdate = "auth_status_update"
    case enrollmentRequest = "enrollment_request"
    case enrollmentComplete = "enrollment_complete"
    
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
    
    func sendEntraIDAuthRequest() {
        sendMessage(
            [WatchMessage.Keys.messageType: "entra_id_auth_request"],
            replyHandler: { reply in
                print("EntraID auth request sent: \(reply)")
            },
            errorHandler: { error in
                print("Error sending EntraID auth request: \(error.localizedDescription)")
                self.errorSubject.send("Failed to send EntraID auth request: \(error.localizedDescription)")
            }
        )
    }
    
    func sendEntraIDAuthResult(success: Bool, token: String?) {
        var message: [String: Any] = [
            WatchMessage.Keys.messageType: "entra_id_auth_result",
            "success": success
        ]
        
        if let token = token {
            message["token"] = token
        }
        
        sendMessage(
            message,
            replyHandler: { reply in
                print("EntraID auth result sent: \(reply)")
            },
            errorHandler: { error in
                print("Error sending EntraID auth result: \(error.localizedDescription)")
                self.errorSubject.send("Failed to send EntraID auth result: \(error.localizedDescription)")
            }
        )
    }
    
    // MARK: - Passwordless Auth Methods
    
    func sendPasswordlessAuthRequest(method: String, heartPattern: Data) {
        let message: [String: Any] = [
            WatchMessage.Keys.messageType: "passwordless_auth_request",
            "method": method,
            "heart_pattern": heartPattern
        ]
        
        sendMessage(
            message,
            replyHandler: { reply in
                print("Passwordless auth request sent: \(reply)")
            },
            errorHandler: { error in
                print("Error sending passwordless auth request: \(error.localizedDescription)")
                self.errorSubject.send("Failed to send passwordless auth request: \(error.localizedDescription)")
            }
        )
    }
    
    // Generic message sender
    private func sendMessage(_ message: [String: Any], 
                           replyHandler: @escaping ([String: Any]) -> Void, 
                           errorHandler: @escaping (Error) -> Void) {
        guard session.activationState == .activated else {
            errorHandler(NSError(domain: "WatchConnectivity", code: 0, userInfo: [NSLocalizedDescriptionKey: "Watch session not activated"]))
            return
        }
        
        if session.isReachable {
            session.sendMessage(message, replyHandler: replyHandler, errorHandler: errorHandler)
        } else {
            // If watch isn't reachable, try to transfer the message in the background
            do {
                try session.updateApplicationContext(message)
                replyHandler(["status": "queued"])
            } catch {
                errorHandler(error)
            }
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

            default:
                break
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
