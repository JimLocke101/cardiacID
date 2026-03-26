//
//  AuditLoggerProtocol.swift
//  HeartIDCore
//
//  Protocol: structured audit logging for HeartID security events.
//

import Foundation

/// Logs SecurityEvent records. Actor-isolated in the implementation.
public protocol AuditLoggerProtocol: Sendable {
    func log(_ event: SecurityEvent) async
}
