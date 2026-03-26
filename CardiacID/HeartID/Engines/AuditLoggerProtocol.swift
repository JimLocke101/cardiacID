//
//  AuditLoggerProtocol.swift
//  CardiacID
//
//  Protocol: structured audit logging for HeartID security events.
//  OSLog only (no persistent storage in v1).
//  Never logs raw biometric confidence values in production.
//  In DEBUG builds, logs full policy decision detail.
//

import Foundation

// MARK: - Protocol

/// Logs SecurityEvent records to OSLog.
/// Actor-isolated in the implementation to serialise writes.
protocol AuditLoggerProtocol: Sendable {
    /// Log a structured security event.
    func log(_ event: SecurityEvent) async
}
