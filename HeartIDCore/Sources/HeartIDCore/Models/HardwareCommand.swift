//
//  HardwareCommand.swift
//  HeartIDCore
//
//  Hardware command types for HeartID-gated hardware authorization.
//

import Foundation

public struct HardwareCommand: Identifiable, Sendable {
    public let id: UUID
    public let commandType: CommandType
    public let targetDeviceId: String
    public let payload: Data
    public let issuedAt: Date

    public init(id: UUID = UUID(), commandType: CommandType, targetDeviceId: String, payload: Data, issuedAt: Date = Date()) {
        self.id = id
        self.commandType = commandType
        self.targetDeviceId = targetDeviceId
        self.payload = payload
        self.issuedAt = issuedAt
    }

    public enum CommandType: String, CaseIterable, Sendable {
        case unlock    = "unlock"
        case lock      = "lock"
        case configure = "configure"
        case status    = "status"
        case provision = "provision"

        public var displayName: String { rawValue.capitalized }

        public var systemImage: String {
            switch self {
            case .unlock:    return "lock.open.fill"
            case .lock:      return "lock.fill"
            case .configure: return "slider.horizontal.3"
            case .status:    return "antenna.radiowaves.left.and.right"
            case .provision: return "plus.circle.fill"
            }
        }
    }
}

public struct SignedCommandEnvelope: Codable, Sendable {
    public let commandId: UUID
    public let commandType: String
    public let targetDeviceId: String
    public let payload: Data
    public let issuedAt: Date
    public let signedBy: String
    public let signature: Data

    public var isExpired: Bool {
        Date().timeIntervalSince(issuedAt) > 300
    }

    public var signatureHex: String {
        signature.prefix(8).map { String(format: "%02x", $0) }.joined() + "…"
    }

    public init(commandId: UUID, commandType: String, targetDeviceId: String, payload: Data, issuedAt: Date, signedBy: String, signature: Data) {
        self.commandId = commandId
        self.commandType = commandType
        self.targetDeviceId = targetDeviceId
        self.payload = payload
        self.issuedAt = issuedAt
        self.signedBy = signedBy
        self.signature = signature
    }
}
