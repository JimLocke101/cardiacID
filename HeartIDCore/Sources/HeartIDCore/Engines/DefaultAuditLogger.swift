//
//  DefaultAuditLogger.swift
//  HeartIDCore
//
//  Production implementation of AuditLoggerProtocol.
//  Actor-isolated for thread-safe serialised writes.
//
//  Rules:
//    - Never logs raw matchConfidence values in production
//    - In DEBUG builds, logs full policy decision detail
//

import Foundation
import OSLog

public actor DefaultAuditLogger: AuditLoggerProtocol {

    private let logger = Logger(subsystem: "com.heartid.audit", category: "security")

    public init() {}

    public func log(_ event: SecurityEvent) {
        let action   = event.action.rawValue
        let decision = event.decision.rawValue
        let session  = event.sessionStateAtTime.rawValue
        let reason   = event.reasonCode

        #if DEBUG
        logger.info("""
        [AUDIT] action=\(action, privacy: .public) \
        decision=\(decision, privacy: .public) \
        session=\(session, privacy: .public) \
        reason=\(reason, privacy: .public) \
        ts=\(event.timestamp.ISO8601Format(), privacy: .public)
        """)
        #else
        logger.info("""
        [AUDIT] action=\(action, privacy: .public) \
        decision=\(decision, privacy: .public) \
        reason=\(reason, privacy: .public)
        """)
        #endif
    }
}
