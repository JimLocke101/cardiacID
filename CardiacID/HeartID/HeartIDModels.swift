// HeartIDModels.swift
// CardiacID
//
// Hardware command types for HeartID-gated hardware authorization.
// All other HeartID models are defined in HeartID/Models/.

import Foundation

// MARK: - Hardware Command

struct HardwareCommand: Identifiable, Sendable {
    let id: UUID
    let commandType: CommandType
    let targetDeviceId: String
    let payload: Data
    let issuedAt: Date

    enum CommandType: String, CaseIterable, Sendable {
        case unlock    = "unlock"
        case lock      = "lock"
        case configure = "configure"
        case status    = "status"
        case provision = "provision"

        var displayName: String { rawValue.capitalized }

        var systemImage: String {
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

struct SignedCommandEnvelope: Codable, Sendable {
    let commandId: UUID
    let commandType: String
    let targetDeviceId: String
    let payload: Data
    let issuedAt: Date
    let signedBy: String
    let signature: Data

    var isExpired: Bool {
        Date().timeIntervalSince(issuedAt) > 300
    }

    var signatureHex: String {
        signature.prefix(8).map { String(format: "%02x", $0) }.joined() + "…"
    }
}
