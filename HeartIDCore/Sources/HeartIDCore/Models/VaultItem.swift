//
//  VaultItem.swift
//  HeartIDCore
//
//  Metadata record for a single encrypted file in the ProtectedFileVault.
//

import Foundation

/// A single item stored in the HeartID-protected file vault.
///
/// Only metadata is held in memory; the actual ciphertext lives on disk
/// at `<vaultDirectory>/<encryptedDataReference>`.
public struct VaultItem: Codable, Sendable, Equatable, Identifiable {

    public let id: UUID
    public let displayName: String
    public let encryptedDataReference: String
    public let createdAt: Date
    public var lastAccessedAt: Date?
    public var isLocked: Bool

    public var systemImage: String {
        if isLocked { return "lock.doc.fill" }
        return "doc.text.fill"
    }

    public init(
        id: UUID = UUID(),
        displayName: String,
        encryptedDataReference: String,
        createdAt: Date = Date(),
        lastAccessedAt: Date? = nil,
        isLocked: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.encryptedDataReference = encryptedDataReference
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
        self.isLocked = isLocked
    }

    /// Create a new locked vault item with a generated filename reference.
    public static func create(displayName: String) -> VaultItem {
        let ref = UUID().uuidString + ".enc"
        return VaultItem(
            displayName: displayName,
            encryptedDataReference: ref
        )
    }
}
