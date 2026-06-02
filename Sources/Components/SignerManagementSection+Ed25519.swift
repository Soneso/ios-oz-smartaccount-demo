// SignerManagementSection+Ed25519.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - SignerManagementSection: Ed25519 form
// ============================================================================

extension SignerManagementSection {

    @ViewBuilder
    internal var ed25519Form: some View {
        TextField("64 hex characters", text: $ed25519PubKeyHex)
            .font(Typography.mono)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .accessibilityLabel("Ed25519 Public Key (hex)")
            .onChange(of: ed25519PubKeyHex) { _, _ in
                fieldErrors.removeValue(forKey: "ed25519PublicKey")
            }
        FieldErrorText(error: fieldErrors["ed25519PublicKey"])
        Text("Uses verifier: \(truncateAddress(ed25519VerifierAddress, chars: 6))")
            .font(Typography.metadata)
            .foregroundStyle(.tertiary)
        Button(action: addEd25519) {
            Text("Add Ed25519 Signer")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Self.addButtonVerticalPadding)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: Self.addButtonRadius))
        }
        .buttonStyle(.plain)
        .disabled(ed25519PubKeyHex.trimmingCharacters(in: .whitespaces).isEmpty)
        .accessibilityLabel("Add Ed25519 Signer")
    }

    internal func addEd25519() {
        let hex = ed25519PubKeyHex.trimmingCharacters(in: .whitespaces).lowercased()
        if let preError = preCheckEd25519(hex: hex) {
            setError("ed25519PublicKey", preError)
            return
        }
        guard let keyBytes = data(fromHex: hex) else {
            setError("ed25519PublicKey", "Invalid hex characters")
            return
        }
        let newSigner: ExternalSigner
        do {
            newSigner = try ExternalSigner.ed25519(
                verifierAddress: ed25519VerifierAddress,
                publicKey: keyBytes
            )
        } catch {
            let detail = ActivityLogState.redact(actionableMessage(for: error))
            setError("ed25519PublicKey", "Invalid key: \(detail)")
            return
        }
        guard appendNewSigner(newSigner, errorKey: "ed25519PublicKey") else { return }
        ed25519PubKeyHex = ""
        fieldErrors.removeValue(forKey: "ed25519PublicKey")
        fieldErrors.removeValue(forKey: "signers")
        activityLog.info("Added Ed25519 signer: \(ActivityLogState.redact(String(hex.prefix(8))))...")
    }

    /// Appends `newSigner` either to the create-mode signers list or to the
    /// edit-mode entries list, surfacing validation errors via `setError`.
    /// Returns `true` when the append succeeded.
    private func appendNewSigner(
        _ newSigner: any SmartAccountSignerProtocol,
        errorKey: String
    ) -> Bool {
        if isEditing {
            if let validationError = validateAddEdit(newSigner) {
                setError(errorKey, validationError)
                return false
            }
            let entry = EditSignerEntry(
                signer: newSigner,
                onChainId: nil,
                isOriginal: false
            )
            onAddEntry?(entry)
            return true
        }
        if let validationError = validateAdd(newSigner) {
            setError(errorKey, validationError)
            return false
        }
        signers.append(newSigner)
        return true
    }

    private func preCheckEd25519(hex: String) -> String? {
        if hex.isEmpty { return "Public key is required" }
        if hex.count != 64 {
            return "Must be 64 hex characters (32 bytes), got \(hex.count)"
        }
        if !hex.allSatisfy(\.isHexDigit) {
            return "Invalid hex characters"
        }
        return nil
    }
}
