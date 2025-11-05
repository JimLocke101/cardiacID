import Foundation
import Combine
import CryptoKit
import LocalAuthentication
import CoreNFC

/// Service for enhanced passwordless authentication protocols (FIDO2, WebAuthn, etc.)
class PasswordlessAuthService: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var availableMethods: [PasswordlessMethod] = []
    @Published var errorMessage: String?
    @Published var isEnrolling = false
    
    // Security
    private let encryptionService = EncryptionService.shared
    private let keychain = KeychainService.shared
    private let localAuthContext = LAContext()
    
    // Publishers
    private let authResultSubject = PassthroughSubject<PasswordlessAuthResult, Never>()
    private let enrollmentSubject = PassthroughSubject<PasswordlessEnrollmentResult, Never>()
    
    var authResultPublisher: AnyPublisher<PasswordlessAuthResult, Never> {
        authResultSubject.eraseToAnyPublisher()
    }
    
    var enrollmentPublisher: AnyPublisher<PasswordlessEnrollmentResult, Never> {
        enrollmentSubject.eraseToAnyPublisher()
    }
    
    override init() {
        super.init()
        loadAvailableMethods()
    }
    
    // MARK: - Method Discovery
    
    private func loadAvailableMethods() {
        var methods: [PasswordlessMethod] = []
        
        // Check for Face ID / Touch ID
        if localAuthContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
            methods.append(PasswordlessMethod(
                type: .biometric,
                name: "Face ID / Touch ID",
                isAvailable: true,
                isEnrolled: false
            ))
        }
        
        // Check for FIDO2 / WebAuthn
        if isFIDO2Supported() {
            methods.append(PasswordlessMethod(
                type: .fido2,
                name: "FIDO2 / WebAuthn",
                isAvailable: true,
                isEnrolled: false
            ))
        }
        
        // Check for NFC
        if NFCNDEFReaderSession.readingAvailable {
            methods.append(PasswordlessMethod(
                type: .nfc,
                name: "NFC",
                isAvailable: true,
                isEnrolled: false
            ))
        }
        
        // Check for Bluetooth
        methods.append(PasswordlessMethod(
            type: .bluetooth,
            name: "Bluetooth",
            isAvailable: true,
            isEnrolled: false
        ))
        
        // Check for Heart ID
        methods.append(PasswordlessMethod(
            type: .heartID,
            name: "Heart ID",
            isAvailable: true,
            isEnrolled: false
        ))
        
        availableMethods = methods
    }
    
    // MARK: - Enrollment
    
    /// Enroll in a passwordless authentication method
    func enroll(method: PasswordlessMethod, with heartPattern: HeartPattern? = nil) {
        isEnrolling = true
        
        Task {
            do {
                let result = try await performEnrollment(method: method, heartPattern: heartPattern)
                
                await MainActor.run {
                    self.isEnrolling = false
                    self.enrollmentSubject.send(result)
                }
            } catch {
                await MainActor.run {
                    self.isEnrolling = false
                    self.errorMessage = error.localizedDescription
                    self.enrollmentSubject.send(PasswordlessEnrollmentResult(
                        success: false,
                        method: method,
                        error: error.localizedDescription
                    ))
                }
            }
        }
    }
    
    private func performEnrollment(method: PasswordlessMethod, heartPattern: HeartPattern?) async throws -> PasswordlessEnrollmentResult {
        switch method.type {
        case .biometric:
            return try await enrollBiometric()
        case .fido2:
            return try await enrollFIDO2()
        case .nfc:
            return try await enrollNFC()
        case .bluetooth:
            return try await enrollBluetooth()
        case .heartID:
            return try await enrollHeartID(heartPattern: heartPattern)
        }
    }
    
    private func enrollBiometric() async throws -> PasswordlessEnrollmentResult {
        // Biometric enrollment is handled by the system
        // We just need to verify it's available
        guard localAuthContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            throw PasswordlessAuthError.biometricNotAvailable
        }
        
        // Store enrollment status
        keychain.store("enrolled", forKey: "biometric_enrollment")
        
        return PasswordlessEnrollmentResult(
            success: true,
            method: PasswordlessMethod(type: .biometric, name: "Face ID / Touch ID", isAvailable: true, isEnrolled: true),
            error: nil
        )
    }
    
    private func enrollFIDO2() async throws -> PasswordlessEnrollmentResult {
        // In a real implementation, this would create FIDO2 credentials
        // For now, we'll simulate the enrollment process
        
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Generate FIDO2 key pair
        let keyPair = try generateFIDO2KeyPair()
        
        // Store credentials
        keychain.store(keyPair.privateKey, forKey: "fido2_private_key")
        keychain.store(keyPair.publicKey, forKey: "fido2_public_key")
        keychain.store("enrolled", forKey: "fido2_enrollment")
        
        return PasswordlessEnrollmentResult(
            success: true,
            method: PasswordlessMethod(type: .fido2, name: "FIDO2 / WebAuthn", isAvailable: true, isEnrolled: true),
            error: nil
        )
    }
    
    private func enrollNFC() async throws -> PasswordlessEnrollmentResult {
        // NFC enrollment would involve writing credentials to an NFC tag
        // For now, we'll simulate the enrollment process
        
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        // Store enrollment status
        keychain.store("enrolled", forKey: "nfc_enrollment")
        
        return PasswordlessEnrollmentResult(
            success: true,
            method: PasswordlessMethod(type: .nfc, name: "NFC", isAvailable: true, isEnrolled: true),
            error: nil
        )
    }
    
    private func enrollBluetooth() async throws -> PasswordlessEnrollmentResult {
        // Bluetooth enrollment would involve pairing with devices
        // For now, we'll simulate the enrollment process
        
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Store enrollment status
        keychain.store("enrolled", forKey: "bluetooth_enrollment")
        
        return PasswordlessEnrollmentResult(
            success: true,
            method: PasswordlessMethod(type: .bluetooth, name: "Bluetooth", isAvailable: true, isEnrolled: true),
            error: nil
        )
    }
    
    private func enrollHeartID(heartPattern: HeartPattern?) async throws -> PasswordlessEnrollmentResult {
        guard let pattern = heartPattern else {
            throw PasswordlessAuthError.invalidHeartPattern
        }
        
        // Encrypt and store heart pattern
        guard let encryptedPattern = encryptionService.encryptHeartPattern(pattern) else {
            throw PasswordlessAuthError.encryptionFailed
        }
        
        keychain.store(encryptedPattern, forKey: "heart_id_pattern")
        keychain.store("enrolled", forKey: "heart_id_enrollment")
        
        return PasswordlessEnrollmentResult(
            success: true,
            method: PasswordlessMethod(type: .heartID, name: "Heart ID", isAvailable: true, isEnrolled: true),
            error: nil
        )
    }
    
    // MARK: - Authentication
    
    /// Authenticate using a passwordless method
    func authenticate(method: PasswordlessMethod, with heartPattern: HeartPattern? = nil) {
        Task {
            do {
                let result = try await performAuthentication(method: method, heartPattern: heartPattern)
                
                await MainActor.run {
                    self.isAuthenticated = result.success
                    self.authResultSubject.send(result)
                }
            } catch {
                await MainActor.run {
                    self.isAuthenticated = false
                    self.errorMessage = error.localizedDescription
                    self.authResultSubject.send(PasswordlessAuthResult(
                        success: false,
                        method: method,
                        error: error.localizedDescription
                    ))
                }
            }
        }
    }
    
    private func performAuthentication(method: PasswordlessMethod, heartPattern: HeartPattern?) async throws -> PasswordlessAuthResult {
        switch method.type {
        case .biometric:
            return try await authenticateBiometric()
        case .fido2:
            return try await authenticateFIDO2()
        case .nfc:
            return try await authenticateNFC()
        case .bluetooth:
            return try await authenticateBluetooth()
        case .heartID:
            return try await authenticateHeartID(heartPattern: heartPattern)
        }
    }
    
    private func authenticateBiometric() async throws -> PasswordlessAuthResult {
        return try await withCheckedThrowingContinuation { continuation in
            localAuthContext.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Authenticate with biometrics"
            ) { success, error in
                if success {
                    continuation.resume(returning: PasswordlessAuthResult(
                        success: true,
                        method: PasswordlessMethod(type: .biometric, name: "Face ID / Touch ID", isAvailable: true, isEnrolled: true),
                        error: nil
                    ))
                } else {
                    continuation.resume(throwing: error ?? PasswordlessAuthError.authenticationFailed)
                }
            }
        }
    }
    
    private func authenticateFIDO2() async throws -> PasswordlessAuthResult {
        // In a real implementation, this would perform FIDO2 authentication
        // For now, we'll simulate the authentication process
        
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Check if FIDO2 is enrolled
        guard keychain.retrieve(forKey: "fido2_enrollment") != nil else {
            throw PasswordlessAuthError.notEnrolled
        }
        
        // Simulate FIDO2 authentication
        let success = true // In real implementation, this would verify the signature
        
        return PasswordlessAuthResult(
            success: success,
            method: PasswordlessMethod(type: .fido2, name: "FIDO2 / WebAuthn", isAvailable: true, isEnrolled: true),
            error: nil
        )
    }
    
    private func authenticateNFC() async throws -> PasswordlessAuthResult {
        // In a real implementation, this would perform NFC authentication
        // For now, we'll simulate the authentication process
        
        try await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds
        
        // Check if NFC is enrolled
        guard keychain.retrieve(forKey: "nfc_enrollment") != nil else {
            throw PasswordlessAuthError.notEnrolled
        }
        
        // Simulate NFC authentication
        let success = true // In real implementation, this would verify the NFC tag
        
        return PasswordlessAuthResult(
            success: success,
            method: PasswordlessMethod(type: .nfc, name: "NFC", isAvailable: true, isEnrolled: true),
            error: nil
        )
    }
    
    private func authenticateBluetooth() async throws -> PasswordlessAuthResult {
        // In a real implementation, this would perform Bluetooth authentication
        // For now, we'll simulate the authentication process
        
        try await Task.sleep(nanoseconds: 600_000_000) // 0.6 seconds
        
        // Check if Bluetooth is enrolled
        guard keychain.retrieve(forKey: "bluetooth_enrollment") != nil else {
            throw PasswordlessAuthError.notEnrolled
        }
        
        // Simulate Bluetooth authentication
        let success = true // In real implementation, this would verify the Bluetooth device
        
        return PasswordlessAuthResult(
            success: success,
            method: PasswordlessMethod(type: .bluetooth, name: "Bluetooth", isAvailable: true, isEnrolled: true),
            error: nil
        )
    }
    
    private func authenticateHeartID(heartPattern: HeartPattern?) async throws -> PasswordlessAuthResult {
        guard let pattern = heartPattern else {
            throw PasswordlessAuthError.invalidHeartPattern
        }
        
        // Check if Heart ID is enrolled
        guard let storedPatternData = keychain.retrieveData(forKey: "heart_id_pattern"),
              let storedPattern = encryptionService.decryptHeartPattern(storedPatternData) else {
            throw PasswordlessAuthError.notEnrolled
        }
        
        // Compare patterns (simplified comparison)
        let similarity = compareHeartPatterns(storedPattern, pattern)
        let success = similarity > 0.8 // 80% similarity threshold
        
        return PasswordlessAuthResult(
            success: success,
            method: PasswordlessMethod(type: .heartID, name: "Heart ID", isAvailable: true, isEnrolled: true),
            error: nil
        )
    }
    
    // MARK: - FIDO2 Support
    
    private func isFIDO2Supported() -> Bool {
        // In a real implementation, this would check for FIDO2 support
        // For now, we'll assume it's supported on iOS 14+
        if #available(iOS 14.0, *) {
            return true
        }
        return false
    }
    
    private func generateFIDO2KeyPair() throws -> FIDO2KeyPair {
        // In a real implementation, this would generate actual FIDO2 key pairs
        // For now, we'll generate a simple key pair
        
        let privateKey = encryptionService.generateRandomData(length: 32) ?? Data()
        let publicKey = encryptionService.generateRandomData(length: 64) ?? Data()
        
        return FIDO2KeyPair(privateKey: privateKey, publicKey: publicKey)
    }
    
    // MARK: - Heart Pattern Comparison
    
    private func compareHeartPatterns(_ pattern1: HeartPattern, _ pattern2: HeartPattern) -> Double {
        // Simplified pattern comparison
        // In a real implementation, this would use sophisticated algorithms
        
        guard pattern1.heartRateData.count == pattern2.heartRateData.count else {
            return 0.0
        }
        
        var totalDifference: Double = 0
        for i in 0..<pattern1.heartRateData.count {
            totalDifference += abs(pattern1.heartRateData[i] - pattern2.heartRateData[i])
        }
        
        let averageDifference = totalDifference / Double(pattern1.heartRateData.count)
        let maxDifference = 50.0 // Maximum expected difference
        
        return max(0, 1.0 - (averageDifference / maxDifference))
    }
    
    // MARK: - Method Management
    
    /// Get enrolled methods
    func getEnrolledMethods() -> [PasswordlessMethod] {
        return availableMethods.filter { method in
            switch method.type {
            case .biometric:
                return keychain.retrieve(forKey: "biometric_enrollment") != nil
            case .fido2:
                return keychain.retrieve(forKey: "fido2_enrollment") != nil
            case .nfc:
                return keychain.retrieve(forKey: "nfc_enrollment") != nil
            case .bluetooth:
                return keychain.retrieve(forKey: "bluetooth_enrollment") != nil
            case .heartID:
                return keychain.retrieve(forKey: "heart_id_enrollment") != nil
            }
        }
    }
    
    /// Remove enrollment for a method
    func removeEnrollment(method: PasswordlessMethod) {
        switch method.type {
        case .biometric:
            keychain.delete(forKey: "biometric_enrollment")
        case .fido2:
            keychain.delete(forKey: "fido2_enrollment")
            keychain.delete(forKey: "fido2_private_key")
            keychain.delete(forKey: "fido2_public_key")
        case .nfc:
            keychain.delete(forKey: "nfc_enrollment")
        case .bluetooth:
            keychain.delete(forKey: "bluetooth_enrollment")
        case .heartID:
            keychain.delete(forKey: "heart_id_enrollment")
            keychain.delete(forKey: "heart_id_pattern")
        }
        
        loadAvailableMethods()
    }
    
    // MARK: - Error Handling
    
    func clearError() {
        errorMessage = nil
    }
}

// MARK: - Supporting Types

struct PasswordlessMethod: Identifiable, Codable {
    let id = UUID()
    let type: PasswordlessMethodType
    let name: String
    let isAvailable: Bool
    let isEnrolled: Bool
}

enum PasswordlessMethodType: String, Codable, CaseIterable {
    case biometric = "biometric"
    case fido2 = "fido2"
    case nfc = "nfc"
    case bluetooth = "bluetooth"
    case heartID = "heart_id"
}

struct PasswordlessAuthResult {
    let success: Bool
    let method: PasswordlessMethod
    let error: String?
}

struct PasswordlessEnrollmentResult {
    let success: Bool
    let method: PasswordlessMethod
    let error: String?
}

struct FIDO2KeyPair {
    let privateKey: Data
    let publicKey: Data
}

enum PasswordlessAuthError: Error, LocalizedError {
    case biometricNotAvailable
    case fido2NotSupported
    case nfcNotAvailable
    case bluetoothNotAvailable
    case heartIDNotAvailable
    case notEnrolled
    case authenticationFailed
    case enrollmentFailed
    case encryptionFailed
    case decryptionFailed
    case invalidHeartPattern
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .biometricNotAvailable:
            return "Biometric authentication is not available"
        case .fido2NotSupported:
            return "FIDO2 is not supported on this device"
        case .nfcNotAvailable:
            return "NFC is not available on this device"
        case .bluetoothNotAvailable:
            return "Bluetooth is not available"
        case .heartIDNotAvailable:
            return "Heart ID is not available"
        case .notEnrolled:
            return "Method is not enrolled"
        case .authenticationFailed:
            return "Authentication failed"
        case .enrollmentFailed:
            return "Enrollment failed"
        case .encryptionFailed:
            return "Encryption failed"
        case .decryptionFailed:
            return "Decryption failed"
        case .invalidHeartPattern:
            return "Invalid heart pattern"
        case .unknown:
            return "Unknown error"
        }
    }
}
