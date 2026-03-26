//
//  DefaultAuditLogger.swift
//  CardiacID
//
//  Production implementation of AuditLoggerProtocol.
//  Actor-isolated for thread-safe serialised writes.
//
//  Rules:
//    - Uses OSLog subsystem "com.heartid.audit" category "security"
//    - Never logs raw matchConfidence values in production
//      (only logs pass/fail/stepup + action + reason code)
//    - In DEBUG builds, logs full policy decision detail
//    - No persistent storage in v1 — OSLog only
//

import Foundation
import OSLog

actor DefaultAuditLogger: AuditLoggerProtocol {

    private let logger = Logger(subsystem: "com.heartid.audit", category: "security")

    // MARK: - AuditLoggerProtocol

    func log(_ event: SecurityEvent) {
        let action   = event.action.rawValue
        let decision = event.decision.rawValue
        let session  = event.sessionStateAtTime.rawValue
        let reason   = event.reasonCode

        #if DEBUG
        // Full detail in debug builds (never ships)
        logger.info("""
        [AUDIT] action=\(action, privacy: .public) \
        decision=\(decision, privacy: .public) \
        session=\(session, privacy: .public) \
        reason=\(reason, privacy: .public) \
        ts=\(event.timestamp.ISO8601Format(), privacy: .public)
        """)
        #else
        // Production: action + decision + reason only. No scores.
        logger.info("""
        [AUDIT] action=\(action, privacy: .public) \
        decision=\(decision, privacy: .public) \
        reason=\(reason, privacy: .public)
        """)
        #endif
    }
}
