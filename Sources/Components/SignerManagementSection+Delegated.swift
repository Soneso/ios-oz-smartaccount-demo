// SignerManagementSection+Delegated.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - SignerManagementSection: Delegated form
// ============================================================================

extension SignerManagementSection {

    @ViewBuilder
    internal var delegatedForm: some View {
        TextField("GABC...", text: $delegatedAddress)
            .font(Typography.mono)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .accessibilityLabel("Stellar Address (G-address)")
            .disabled(isImportingFromWallet)
            .onChange(of: delegatedAddress) { _, _ in
                fieldErrors.removeValue(forKey: "delegatedAddress")
            }
        FieldErrorText(error: fieldErrors["delegatedAddress"])
        importFromWalletButton
        Button(action: addDelegated) {
            Text("Add Delegated Signer")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Self.addButtonVerticalPadding)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: Self.addButtonRadius))
        }
        .buttonStyle(.plain)
        .disabled(
            delegatedAddress.trimmingCharacters(in: .whitespaces).isEmpty
            || isImportingFromWallet
        )
        .accessibilityLabel("Add Delegated Signer")
    }

    /// Outlined button that pairs an external wallet via WalletConnect and
    /// auto-fills its G-address into the delegated-signer input. Visible only
    /// when a real, functional `walletConnector` is wired — both the macOS
    /// `NoOpWalletConnector` and the simulator stub of `ReownWalletHandler`
    /// conform to `NoOpWalletConnectorMarker` and are filtered out, matching
    /// the same gating `SignerPickerSheet` uses for its wallet UI.
    @ViewBuilder
    internal var importFromWalletButton: some View {
        if let connector = walletConnector, !(connector is NoOpWalletConnectorMarker) {
            Button(action: { Task { await importFromWallet() } }) {
                HStack(spacing: 8) {
                    if isImportingFromWallet {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.accentColor)
                    } else {
                        Image(systemName: "wallet.pass")
                            .imageScale(.medium)
                    }
                    Text(isImportingFromWallet ? "Connecting to wallet…" : "Import from Wallet")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Self.addButtonVerticalPadding)
                .foregroundStyle(Color.accentColor)
                .overlay(
                    RoundedRectangle(cornerRadius: Self.addButtonRadius)
                        .stroke(Color.accentColor, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
            .disabled(isImportingFromWallet)
            .accessibilityLabel("Import Address from Wallet")
        }
    }

    /// Vertical padding inside the per-form add-signer CTA button.
    internal static var addButtonVerticalPadding: CGFloat { 10 }

    /// Corner radius applied to the per-form add-signer CTA button.
    internal static var addButtonRadius: CGFloat { 10 }

    internal func addDelegated() {
        let trimmed = delegatedAddress.trimmingCharacters(in: .whitespaces)
        if let preError = preCheckDelegated(trimmed: trimmed) {
            setError("delegatedAddress", preError)
            return
        }
        let newSigner: DelegatedSigner
        do {
            newSigner = try DelegatedSigner(address: trimmed)
        } catch {
            let detail = ActivityLogState.redact(actionableMessage(for: error))
            setError("delegatedAddress", "Invalid address: \(detail)")
            return
        }
        if isEditing {
            if let validationError = validateAddEdit(newSigner) {
                setError("delegatedAddress", validationError)
                return
            }
            let entry = EditSignerEntry(
                signer: newSigner, onChainId: nil, isOriginal: false
            )
            onAddEntry?(entry)
        } else {
            if let validationError = validateAdd(newSigner) {
                setError("delegatedAddress", validationError)
                return
            }
            signers.append(newSigner)
        }
        delegatedAddress = ""
        fieldErrors.removeValue(forKey: "delegatedAddress")
        fieldErrors.removeValue(forKey: "signers")
        activityLog.info("Added delegated signer: \(truncateAddress(trimmed, chars: 6))")
    }

    private func preCheckDelegated(trimmed: String) -> String? {
        if trimmed.isEmpty { return "Address is required" }
        if !trimmed.hasPrefix("G") || trimmed.count != 56 {
            return "Must be a valid G-address (56 characters)"
        }
        return nil
    }

    /// Pairs an external wallet via `walletConnector`, copies its public
    /// G-address into the delegated-address input, and tears the session down
    /// again — the import is ephemeral; the user still has to tap "Add
    /// Delegated Signer" to actually stage it. A silent return (no error
    /// surface) is used when the wallet ceremony is cancelled.
    @MainActor
    internal func importFromWallet() async {
        guard let connector = walletConnector else { return }
        isImportingFromWallet = true
        fieldErrors.removeValue(forKey: "delegatedAddress")
        defer { isImportingFromWallet = false }
        do {
            try await connector.connect()
        } catch {
            let detail = ActivityLogState.redact(actionableMessage(for: error))
            setError("delegatedAddress", "Failed to get address from wallet: \(detail)")
            return
        }
        // Capture the address before disconnecting; the connector clears its
        // `connectedAddress` accessor as part of the disconnect.
        let connected = connector.connectedAddress
        // Ephemeral connection: discard the session so a subsequent signer-pick
        // step (during ContextRule submission, transfer, etc.) starts fresh
        // and is free to pair the same or a different wallet.
        await connector.disconnect()
        guard let address = connected, !address.isEmpty else {
            // User cancelled the wallet's approval prompt — silent return.
            return
        }
        delegatedAddress = address
        fieldErrors.removeValue(forKey: "delegatedAddress")
        activityLog.info("Imported wallet address: \(truncateAddress(address, chars: 6))")
    }
}
