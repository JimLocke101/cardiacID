//
//  VaultItem.swift
//  CardiacID
//
//  Metadata record for a single encrypted file in the ProtectedFileVault.
//  Pure value type — no UIKit, no SwiftUI, no dependencies on unwritten code.
//

import Foundation

/// A single item stored in the HeartID-protected file vault.
///
/// Only metadata is held in memory; the actual ciphertext lives on disk
/// at `<vaultDirectory>/<encryptedDataReference>`.
struct VaultItem: Codable, Sendable, Equatable, Identifiable {

    let id: UUID

    /// Human-readable name shown in the vault list.
    let displayName: String

    /// Filename of the encrypted blob on disk (e.g. "8F3A…B1.enc").
    /// Never contains a full path — the vault service resolves the directory.
    let encryptedDataReference: String

    /// When this item was first encrypted and added to the vault.
    let createdAt: Date

    /// When the plaintext was last decrypted/viewed. Nil if never opened.
    var lastAccessedAt: Date?

    /// True while the item's vault is locked and the plaintext is inaccessible.
    var isLocked: Bool

    // MARK: - Derived display

    var systemImage: String {
        if isLocked { return "lock.doc.fill" }
        return "doc.text.fill"
    }

    // MARK: - Factory

    /// Create a new locked vault item with a generated filename reference.
    static func create(displayName: String) -> VaultItem {
        let ref = UUID().uuidString + ".enc"
        return VaultItem(
            id: UUID(),
            displayName: displayName,
            encryptedDataReference: ref,
            createdAt: Date(),
            lastAccessedAt: nil,
            isLocked: true
        )
    }
}
