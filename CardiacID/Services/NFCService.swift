import Foundation
import CoreNFC
import Combine

/// Service for NFC-based authentication and data exchange
@MainActor
class NFCService: NSObject, ObservableObject, HoldableService {
    @Published var isNFCAvailable = false
    @Published var isScanning = false
    @Published var lastScannedTag: NFCTagData?
    @Published var errorMessage: String?
    @Published var isWriting = false
    @Published var serviceState: ServiceState = .available
    @Published var holdInfo: HoldStateInfo?
    @Published var lastError: Error?
    
    // NFC properties
    private var nfcSession: NFCNDEFReaderSession?
    private var nfcTagReaderSession: NFCTagReaderSession?
    
    // Security
    private let encryptionService = EncryptionService.shared
    private let keychain = KeychainService.shared
    private let serviceStateManager = ServiceStateManager.shared
    
    // Publishers
    private let tagScannedSubject = PassthroughSubject<NFCTagData, Never>()
    private let authenticationSubject = PassthroughSubject<NFCAuthResult, Never>()
    
    var tagScannedPublisher: AnyPublisher<NFCTagData, Never> {
        tagScannedSubject.eraseToAnyPublisher()
    }
    
    var authenticationPublisher: AnyPublisher<NFCAuthResult, Never> {
        authenticationSubject.eraseToAnyPublisher()
    }
    }
    
    override init() {
        super.init()
        checkNFCAvailability()
        serviceStateManager.registerService(ServiceStateManager.nfcService, initialState: .available)
    }
    
    // MARK: - NFC Availability
    
    private func checkNFCAvailability() {
        isNFCAvailable = NFCNDEFReaderSession.readingAvailable
        
        if !isNFCAvailable {
            putOnHold(reason: HoldStateInfo(
                reason: "NFC not available on this device",
                suggestedAction: "Use a device with NFC capability",
                canRetry: false,
                estimatedResolution: nil
            ))
        }
    }
    
    // MARK: - NFC Tag Reading
    
    /// Start scanning for NFC tags
    func startScanning() {
        guard serviceState != .hold else {
            errorMessage = "NFC service is on hold"
            return
        }
        
        guard isNFCAvailable else {
            putOnHold(reason: HoldStateInfo(
                reason: "NFC is not available on this device",
                suggestedAction: "Use a device with NFC capability",
                canRetry: false,
                estimatedResolution: nil
            ))
            return
        }
            return
        }
        
        isScanning = true
        nfcSession = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        nfcSession?.alertMessage = "Hold your iPhone near an NFC tag"
        nfcSession?.begin()
    }
    
    /// Stop scanning for NFC tags
    func stopScanning() {
        isScanning = false
        nfcSession?.invalidate()
        nfcTagReaderSession?.invalidate()
    }
    
    /// Read data from an NFC tag
    func readTagData() {
        guard isNFCAvailable else {
            errorMessage = "NFC is not available on this device"
            return
        }
        
        nfcSession = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        nfcSession?.alertMessage = "Hold your iPhone near an NFC tag to read data"
        nfcSession?.begin()
    }
    
    /// Write data to an NFC tag
    func writeTagData(_ data: NFCTagData) {
        guard isNFCAvailable else {
            errorMessage = "NFC is not available on this device"
            return
        }
        
        isWriting = true
        nfcSession = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        nfcSession?.alertMessage = "Hold your iPhone near an NFC tag to write data"
        nfcSession?.begin()
    }
    
    // MARK: - Heart ID Authentication via NFC
    
    /// Authenticate using heart pattern via NFC
    func authenticateWithHeartPattern(_ pattern: HeartPattern, via nfcTag: NFCTagData) {
        Task {
            do {
                // Encode and encrypt heart pattern
                let patternData = try JSONEncoder().encode(pattern)
                let encryptedPattern = try encryptionService.encryptHeartPattern(patternData)

                // Create authentication payload
                let authPayload = NFCAuthPayload(
                    heartPattern: encryptedPattern,
                    timestamp: Date(),
                    deviceId: getDeviceId(),
                    nonce: try encryptionService.generateRandomData(length: 16)
                )

                // Send authentication request via NFC
                let result = try await sendAuthenticationRequest(authPayload, via: nfcTag)

                await MainActor.run {
                    self.authenticationSubject.send(result)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.authenticationSubject.send(NFCAuthResult(success: false, token: nil, expiresAt: nil, permissions: [], error: error.localizedDescription))
                }
            }
        }
    }
    
    /// Send authentication request via NFC
    private func sendAuthenticationRequest(_ payload: NFCAuthPayload, via nfcTag: NFCTagData) async throws -> NFCAuthResult {
        // In a real implementation, this would send the authentication request via NFC
        // For now, we'll simulate the authentication process

        // Simulate network delay
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Simulate authentication success based on pattern quality
        let success = payload.heartPattern.count > 0

        let token: String?
        if success {
            token = (try? encryptionService.generateRandomString(length: 32)) ?? ""
        } else {
            token = nil
        }

        return NFCAuthResult(
            success: success,
            token: token,
            expiresAt: success ? Date().addingTimeInterval(300) : nil, // 5 minutes
            permissions: success ? [.read, .write, .authenticate] : [],
            error: success ? nil : "Authentication failed"
        )
    }
    
    // MARK: - NFC Data Exchange
    
    /// Exchange data with NFC tag
    func exchangeData(_ data: Data, with nfcTag: NFCTagData) -> AnyPublisher<Data?, NFCError> {
        return Future<Data?, NFCError> { promise in
            Task {
                do {
                    // Encrypt data before sending
                    let encryptedData = try self.encryptionService.encrypt(data)

                    // Send data via NFC
                    let response = try await self.sendData(encryptedData, via: nfcTag)

                    // Decrypt response
                    let decryptedResponse: Data?
                    if let responseData = response {
                        decryptedResponse = try self.encryptionService.decrypt(responseData)
                    } else {
                        decryptedResponse = nil
                    }
                    promise(.success(decryptedResponse))
                } catch let error as EncryptionError {
                    promise(.failure(.encryptionFailed))
                } catch {
                    promise(.failure(error as? NFCError ?? .unknown))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    private func sendData(_ data: Data, via nfcTag: NFCTagData) async throws -> Data? {
        // In a real implementation, this would send data via NFC
        // For now, we'll simulate the data exchange

        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // Simulate response data
        return try encryptionService.generateRandomData(length: 32)
    }
    
    // MARK: - NFC Tag Management
    
    /// Create a new NFC tag with Heart ID data
    func createHeartIDTag(with pattern: HeartPattern) -> AnyPublisher<Bool, NFCError> {
        return Future<Bool, NFCError> { promise in
            Task {
                do {
                    // Encode and encrypt heart pattern
                    let patternData = try JSONEncoder().encode(pattern)
                    let encryptedPattern = try self.encryptionService.encryptHeartPattern(patternData)

                    // Create tag data
                    let tagData = NFCTagData(
                        type: .heartID,
                        data: encryptedPattern,
                        timestamp: Date(),
                        deviceId: self.getDeviceId()
                    )

                    // Write to NFC tag
                    let success = try await self.writeTagData(tagData)
                    promise(.success(success))
                } catch {
                    promise(.failure(error as? NFCError ?? .unknown))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// Read Heart ID data from NFC tag
    func readHeartIDTag() -> AnyPublisher<HeartPattern?, NFCError> {
        return Future<HeartPattern?, NFCError> { promise in
            Task {
                do {
                    // Read tag data
                    let tagData = try await self.readTagData()

                    // Decrypt and decode heart pattern
                    let decryptedData = try self.encryptionService.decryptHeartPattern(tagData.data)
                    let heartPattern = try JSONDecoder().decode(HeartPattern.self, from: decryptedData)

                    promise(.success(heartPattern))
                } catch {
                    promise(.failure(error as? NFCError ?? .unknown))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    private func readTagData() async throws -> NFCTagData {
        // In a real implementation, this would read data from NFC tag
        // For now, we'll simulate reading tag data
        
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        // Simulate tag data
        return NFCTagData(
            type: .heartID,
            data: Data(),
            timestamp: Date(),
            deviceId: getDeviceId()
        )
    }
    
    private func writeTagData(_ tagData: NFCTagData) async throws -> Bool {
        // In a real implementation, this would write data to NFC tag
        // For now, we'll simulate writing tag data
        
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Simulate successful write
        return true
    }
    
    // MARK: - Device Management
    
    private func getDeviceId() -> String {
        if let deviceId = keychain.retrieve(forKey: "device_id") {
            return deviceId
        }
        
        let newDeviceId = UUID().uuidString
        keychain.store(newDeviceId, forKey: "device_id")
        return newDeviceId
    }
    
    // MARK: - Error Handling
    
    func clearError() {
        errorMessage = nil
    }
}

// MARK: - NFCNDEFReaderSessionDelegate

extension NFCService: NFCNDEFReaderSessionDelegate {
    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        DispatchQueue.main.async {
            self.isScanning = false
            self.isWriting = false
            
            if let nfcError = error as? NFCReaderError {
                switch nfcError.code {
                case .readerSessionInvalidationErrorUserCanceled:
                    // User cancelled, no error message needed
                    break
                case .readerSessionInvalidationErrorSessionTimeout:
                    self.errorMessage = "NFC session timed out"
                case .readerSessionInvalidationErrorSessionTerminatedUnexpectedly:
                    self.errorMessage = "NFC session terminated unexpectedly"
                default:
                    self.errorMessage = "NFC error: \(error.localizedDescription)"
                }
            } else {
                self.errorMessage = "NFC error: \(error.localizedDescription)"
            }
        }
    }
    
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        DispatchQueue.main.async {
            self.isScanning = false
            self.isWriting = false
            
            // Process NDEF messages
            for message in messages {
                for record in message.records {
                    if let payload = String(data: record.payload, encoding: .utf8) {
                        let tagData = NFCTagData(
                            type: .ndef,
                            data: record.payload,
                            timestamp: Date(),
                            deviceId: self.getDeviceId()
                        )
                        self.tagScannedSubject.send(tagData)
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Types

struct NFCTagData {
    let type: NFCTagType
    let data: Data
    let timestamp: Date
    let deviceId: String
}

enum NFCTagType {
    case heartID
    case ndef
    case iso14443
    case iso15693
    case iso18092
}

struct NFCAuthPayload {
    let heartPattern: Data
    let timestamp: Date
    let deviceId: String
    let nonce: Data
}

struct NFCAuthResult {
    let success: Bool
    let token: String?
    let expiresAt: Date?
    let permissions: [NFCPermission]
    let error: String?
}

enum NFCPermission {
    case read
    case write
    case authenticate
    case admin
}

enum NFCError: Error, LocalizedError {
    case notAvailable
    case encryptionFailed
    case serviceOnHold
    case invalidTag
    case scanningFailed
    
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "NFC not available"
        case .encryptionFailed:
            return "Encryption failed"
        case .serviceOnHold:
            return "NFC service on hold"
        case .invalidTag:
            return "Invalid NFC tag"
        case .scanningFailed:
            return "NFC scanning failed"
        }
    }
}

// MARK: - HoldableService Implementation

extension NFCService {
    func putOnHold(reason: HoldStateInfo) {
        holdInfo = reason
        updateServiceState(.hold)
        errorMessage = reason.reason
        
        // Stop any active scanning
        stopScanning()
    }
    
    func resumeFromHold() async throws {
        guard serviceState == .hold else { return }
        
        holdInfo = nil
        errorMessage = nil
        lastError = nil
        
        // Recheck availability
        checkNFCAvailability()
        
        if isNFCAvailable {
            updateServiceState(.available)
            print("✅ NFC service resumed from hold")
        } else {
            putOnHold(reason: HoldStateInfo(
                reason: "NFC still not available",
                suggestedAction: "Use a device with NFC capability",
                canRetry: false,
                estimatedResolution: nil
            ))
        }
    }
    
    func checkAvailability() async -> Bool {
        return NFCNDEFReaderSession.readingAvailable
    }
    
    private func updateServiceState(_ state: ServiceState) {
        serviceState = state
        serviceStateManager.updateServiceState(
            ServiceStateManager.nfcService,
            to: state,
            holdInfo: holdInfo
        )
    }
}
    case decryptionFailed
    case tagNotSupported
    case writeFailed
    case readFailed
    case authenticationFailed
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "NFC is not available on this device"
        case .encryptionFailed:
            return "Failed to encrypt data"
        case .decryptionFailed:
            return "Failed to decrypt data"
        case .tagNotSupported:
            return "NFC tag is not supported"
        case .writeFailed:
            return "Failed to write to NFC tag"
        case .readFailed:
            return "Failed to read from NFC tag"
        case .authenticationFailed:
            return "NFC authentication failed"
        case .unknown:
            return "Unknown NFC error"
        }
    }
}
