//
//  ProtectedFileVaultView.swift
//  CardiacID
//
//  HeartID-gated file vault UI.
//  Files listed encrypted; tap to unlock via policy engine; auto-relock indicator.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers
#endif

struct ProtectedFileVaultView: View {
    @StateObject private var vault = ProtectedFileVault.shared
    @StateObject private var sessionTrust = DefaultSessionTrustManager()
    @StateObject private var identityEngine = HeartIdentityEngine.shared

    @State private var selectedItem: VaultItem?
    @State private var decryptedData: Data?
    @State private var isUnlocking = false
    @State private var showImport = false
    @State private var alertMessage: String?
    @State private var timerTick = Date()

    private let colors = HeartIDColors()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            colors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                lockBanner
                if vault.items.isEmpty { emptyState } else { fileList }
            }
        }
        .navigationTitle("File Vault")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button(action: { showImport = true }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(colors.accent)
                    }
                    if !vault.isLocked {
                        Button(action: { vault.lock() }) {
                            Image(systemName: "lock.fill")
                                .foregroundColor(colors.warning)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showImport) {
            ImportFileView { name, data in
                Task {
                    _ = try? await vault.addItemAsync(displayName: name, plaintext: data)
                }
                showImport = false
            }
        }
        .sheet(item: $selectedItem) { item in
            DecryptedFileSheet(item: item, data: decryptedData) {
                selectedItem = nil
                decryptedData = nil
            }
        }
        .alert("Vault", isPresented: .init(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(alertMessage ?? "") }
        .onReceive(timer) { timerTick = $0 }
    }

    // MARK: - Lock Banner

    private var lockBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: vault.isLocked ? "lock.fill" : "lock.open.fill")
                .foregroundColor(vault.isLocked ? colors.warning : colors.success)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(vault.isLocked ? "Vault Locked" : "Vault Unlocked")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(colors.text)
                if !vault.isLocked {
                    Text(autoLockCountdown)
                        .font(.caption).foregroundColor(colors.secondary)
                }
            }

            Spacer()

            if vault.isLocked {
                Button(action: unlockVault) {
                    if isUnlocking {
                        ProgressView().progressViewStyle(.circular)
                            .scaleEffect(0.75).tint(.white)
                    } else {
                        Label("Unlock", systemImage: "waveform.path.ecg")
                            .font(.caption).fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(colors.accent)
                .disabled(isUnlocking)
            }
        }
        .padding()
        .background(vault.isLocked ? colors.warning.opacity(0.12) : colors.success.opacity(0.10))
    }

    // MARK: - File List

    private var fileList: some View {
        List {
            ForEach(vault.items) { item in
                VaultItemRow(item: item, isVaultLocked: vault.isLocked, colors: colors) {
                    handleTap(item)
                }
            }
            .onDelete(perform: deleteItems)
            .listRowBackground(colors.card)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.doc")
                .font(.system(size: 56)).foregroundColor(colors.secondary)
            Text("No protected files")
                .font(.headline).foregroundColor(colors.secondary)
            Text("Tap + to import a file to the vault.")
                .font(.caption).foregroundColor(colors.secondary)
            Spacer()
        }
    }

    // MARK: - Auto-Lock Countdown

    private var autoLockCountdown: String {
        // ProtectedFileVault auto-locks after 120s
        guard !vault.isLocked else { return "" }
        // Estimate based on most recent unlock (approximate)
        return "Vault locks automatically in ~2:00"
    }

    // MARK: - Actions

    private func unlockVault() {
        isUnlocking = true
        Task {
            let ok = await vault.unlock()
            isUnlocking = false
            if !ok { alertMessage = vault.errorMessage ?? "Unlock failed." }
        }
    }

    private func handleTap(_ item: VaultItem) {
        if vault.isLocked {
            unlockVault()
            return
        }
        // Policy check is done inside ProtectedFileVault.open → HeartIDFileVault.decryptItem
        do {
            let data = try vault.open(item)
            decryptedData = data
            selectedItem = item
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func deleteItems(offsets: IndexSet) {
        offsets.map { vault.items[$0] }.forEach { vault.deleteItem($0) }
    }
}

// MARK: - Vault Item Row

private struct VaultItemRow: View {
    let item: VaultItem
    let isVaultLocked: Bool
    let colors: HeartIDColors
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: item.isLocked ? "lock.doc.fill" : "doc.text.fill")
                    .font(.title2)
                    .foregroundColor(item.isLocked ? colors.warning : colors.accent)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(colors.text)

                    HStack(spacing: 6) {
                        if let accessed = item.lastAccessedAt {
                            Text("Accessed \(accessed, style: .relative) ago")
                        } else {
                            Text("Never accessed")
                        }
                    }
                    .font(.caption).foregroundColor(colors.secondary)
                }

                Spacer()

                Image(systemName: isVaultLocked ? "lock.fill" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(isVaultLocked ? colors.warning : colors.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Decrypted File Sheet

private struct DecryptedFileSheet: View {
    let item: VaultItem
    let data: Data?
    let onClose: () -> Void

    private let colors = HeartIDColors()

    var body: some View {
        NavigationView {
            ScrollView {
                if let data, let text = String(data: data, encoding: .utf8) {
                    Text(text)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(colors.text)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let data {
                    Text("Binary data — \(data.count) bytes")
                        .foregroundColor(colors.secondary).padding()
                } else {
                    Text("No data").foregroundColor(colors.secondary).padding()
                }
            }
            .background(colors.background)
            .navigationTitle(item.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close", action: onClose)
                }
            }
        }
    }
}

// MARK: - Import File View (document picker bridge)

private struct ImportFileView: View {
    let onImport: (String, Data) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var fileName = ""
    @State private var fileContent = ""

    private let colors = HeartIDColors()

    var body: some View {
        NavigationView {
            Form {
                Section("File Name") {
                    TextField("e.g. Secure Notes.txt", text: $fileName)
                }
                Section("Content (paste or type)") {
                    TextEditor(text: $fileContent)
                        .frame(minHeight: 140)
                }
                // TODO: Add UIDocumentPickerViewController bridge
                // for importing real files from Files app
                Section {
                    Text("Full document picker (UIDocumentPickerViewController) will be added when file import from Files.app is required.")
                        .font(.caption).foregroundColor(colors.secondary)
                }
            }
            .navigationTitle("Import to Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Encrypt & Save") {
                        guard let data = fileContent.data(using: .utf8) else { return }
                        onImport(fileName.isEmpty ? "Untitled.txt" : fileName, data)
                    }
                    .fontWeight(.semibold)
                    .disabled(fileContent.isEmpty)
                }
            }
        }
    }
}
