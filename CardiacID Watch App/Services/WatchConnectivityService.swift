import Foundation
import WatchConnectivity
import Combine

/// Service for handling communication between watchOS and iOS apps
class WatchConnectivityService: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var lastMessage: [String: Any]?
    @Published var connectionStatus: String = "Not Connected"
    
    private var session: WCSession?
    
    override init() {
        super.init()
        setupWatchConnectivity()
        setupNotificationObservers()
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
            if let resultRawValue = notification.userInfo?["result"] as? String,
               let result = AuthenticationResult(rawValue: resultRawValue) {
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
    
    /// Send message to iOS companion app
    func sendMessage(_ message: [String: Any], completion: @escaping (Bool) -> Void = { _ in }) {
        guard let session = session, session.isReachable else {
            connectionStatus = "iOS App Not Reachable"
            completion(false)
            return
        }
        
        session.sendMessage(message, replyHandler: { response in
            DispatchQueue.main.async {
                self.lastMessage = response
                completion(true)
            }
        }, errorHandler: { error in
            DispatchQueue.main.async {
                self.connectionStatus = "Error: \(error.localizedDescription)"
                completion(false)
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
        let message: [String: Any] = [
            "type": "authenticationResult",
            "result": result.rawValue,
            "timestamp": Date().timeIntervalSince1970
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
    
    /// Request data from iOS app
    func requestData(_ dataType: String, completion: @escaping (Bool) -> Void = { _ in }) {
        let message: [String: Any] = [
            "type": "requestData",
            "dataType": dataType,
            "timestamp": Date().timeIntervalSince1970
        ]
        sendMessage(message, completion: completion)
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            switch activationState {
            case .activated:
                self.isConnected = session.isReachable
                self.connectionStatus = session.isReachable ? "Connected to iOS" : "iOS App Not Reachable"
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
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isConnected = session.isReachable
            self.connectionStatus = session.isReachable ? "Connected to iOS" : "iOS App Not Reachable"
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            self.lastMessage = message
            self.handleReceivedMessage(message)
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        DispatchQueue.main.async {
            self.lastMessage = message
            self.handleReceivedMessage(message)
            
            // Send acknowledgment
            replyHandler(["status": "received"])
        }
    }
    
    private func handleReceivedMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        
        switch type {
        case "heartPatternRequest":
            // iOS app is requesting heart pattern data
            // This would trigger the watch to start capturing heart data
            NotificationCenter.default.post(name: .heartPatternRequest, object: nil)
            
        case "authenticationRequest":
            // iOS app is requesting authentication
            NotificationCenter.default.post(name: .authenticationRequest, object: nil)
            
        case "enrollmentRequest":
            // iOS app is requesting enrollment
            NotificationCenter.default.post(name: .enrollmentRequest, object: nil)
            
        case "settingsUpdate":
            // iOS app is updating settings
            if let settings = message["settings"] as? [String: Any] {
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
