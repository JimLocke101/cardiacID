// HardwareAuthorizationService.swift
// CardiacID
//
// HeartID-gated signed hardware command authorization.

import Foundation
import CryptoKit

@MainActor
final class HardwareAuthorizationService: ObservableObject {
    static let shared = HardwareAuthorizationService()

    @Published private(set) var lastSignedEnvelope: SignedCommandEnvelope?
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var errorMessage: String?

    private let keyManager     = SecureKeyManager.shared
    private let policyEngine   = HeartAuthPolicyEngine.shared
    private let identityEngine = HeartIdentityEngine.shared
    private let sessionManager = SessionTrustManager.shared
    private let auditLogger    = AuditLogger.shared

    private init() {}

    func authorizeCommand(
        _ commandType: HardwareCommand.CommandType,
        targetDeviceId: String = "demo-device-01"
    ) async -> SignedCommandEnvelope? {
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        if !sessionManager.satisfiesTrust(for: .authorizeHardwareCommand) {
            let result   = await identityEngine.verify()
            let decision = policyEngine.evaluate(result, for: .authorizeHardwareCommand)
            sessionManager.recordVerification(result)

            guard decision.isAllowed else {
                errorMessage = "HeartID required (score \(String(format: "%.0f%%", result.combinedScore * 100)))."
                auditLogger.logOperational(action: "hardware.authorize", outcome: "denied",
                                           score: result.combinedScore, reasonCode: commandType.rawValue)
                return nil
            }
        }

        let command = HardwareCommand(
            id: UUID(), commandType: commandType,
            targetDeviceId: targetDeviceId,
            payload: Data("\(commandType.rawValue):\(targetDeviceId)".utf8),
            issuedAt: Date()
        )

        do {
            let envelope = try sign(command: command)
            lastSignedEnvelope = envelope
            auditLogger.logOperational(action: "hardware.signed", outcome: "ok", reasonCode: commandType.rawValue)
            return envelope
        } catch {
            errorMessage = "Signing failed: \(error.localizedDescription)"
            auditLogger.logOperational(action: "hardware.sign", outcome: "error", reasonCode: error.localizedDescription)
            return nil
        }
    }

    private func sign(command: HardwareCommand) throws -> SignedCommandEnvelope {
        let canonical: [String: String] = [
            "commandId":    command.id.uuidString,
            "commandType":  command.commandType.rawValue,
            "targetDevice": command.targetDeviceId,
            "issuedAt":     ISO8601DateFormatter().string(from: command.issuedAt)
        ]
        let canonicalData = try JSONSerialization.data(withJSONObject: canonical, options: [.sortedKeys])
        let signingKey    = try keyManager.applicationSigningKey()
        let sig           = try signingKey.signature(for: canonicalData)

        return SignedCommandEnvelope(
            commandId: command.id, commandType: command.commandType.rawValue,
            targetDeviceId: command.targetDeviceId, payload: command.payload,
            issuedAt: command.issuedAt, signedBy: signingKey.label, signature: sig
        )
    }
}
