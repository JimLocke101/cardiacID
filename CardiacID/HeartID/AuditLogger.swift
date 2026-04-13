// AuditLogger.swift
// CardiacID
//
// OSLog-based structured audit logging for the HeartID security layer.
// Two logging modes:
//   1. Structured SecurityEvent records (formal policy decisions)
//   2. Operational log entries (freeform diagnostic messages)
// Never logs raw biometric signal data or cryptographic key material.

import Foundation
import OSLog

final class AuditLogger: Sendable {
    static let shared = AuditLogger()

    private let logger = Logger(subsystem: "com.argos.cardiacid", category: "SecurityAudit")
    private let queue  = DispatchQueue(label: "com.argos.cardiacid.auditLogger", qos: .utility)

    // Internal operational log entries (lightweight, circular buffer)
    private struct OperationalEntry: Sendable {
        let timestamp: Date
        let action: String
        let outcome: String
        let score: Double?
        let reasonCode: String?
    }

    private var _operationalEntries: [OperationalEntry] = []
    private var _securityEvents: [SecurityEvent] = []
    private let maxEntries = 200

    private init() {}

    // MARK: - Structured policy event logging

    func log(_ event: SecurityEvent) {
        logger.info("[\(event.action.rawValue, privacy: .public)] decision=\(event.decision.rawValue, privacy: .public) session=\(event.sessionStateAtTime.rawValue, privacy: .public) reason=\(event.reasonCode, privacy: .public)")

        queue.async { [weak self] in
            guard let self else { return }
            self._securityEvents.append(event)
            if self._securityEvents.count > self.maxEntries {
                self._securityEvents.removeFirst()
            }
        }
    }

    // MARK: - Operational (freeform) logging

    func logOperational(action: String, outcome: String, score: Double? = nil, reasonCode: String? = nil) {
        let scoreStr = score.map { String(format: "%.2f", $0) } ?? "n/a"
        let reason   = reasonCode ?? "none"
        logger.info("[\(action, privacy: .public)] outcome=\(outcome, privacy: .public) score=\(scoreStr, privacy: .public) reason=\(reason, privacy: .public)")

        let entry = OperationalEntry(timestamp: Date(), action: action, outcome: outcome, score: score, reasonCode: reasonCode)
        queue.async { [weak self] in
            guard let self else { return }
            self._operationalEntries.append(entry)
            if self._operationalEntries.count > self.maxEntries {
                self._operationalEntries.removeFirst()
            }
        }
    }

    // MARK: - Read

    func recentSecurityEvents() -> [SecurityEvent] {
        queue.sync { _securityEvents }
    }

    /// Returns all operational log entries for the Activity Log.
    /// Each entry contains action, outcome, score, reasonCode, and timestamp.
    func recentOperationalEntries() -> [(timestamp: Date, action: String, outcome: String, score: Double?, reasonCode: String?)] {
        queue.sync {
            _operationalEntries.map { ($0.timestamp, $0.action, $0.outcome, $0.score, $0.reasonCode) }
        }
    }

    func recentOperationalCount() -> Int {
        queue.sync { _operationalEntries.count }
    }

    func clear() {
        queue.async { [weak self] in
            self?._operationalEntries = []
            self?._securityEvents = []
        }
    }
}
