// ContextRuleBuilderCore+Picker.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ContextRuleBuilderCore: signer picker presentation
// ============================================================================

extension ContextRuleBuilderCore {

    @ViewBuilder
    internal var signerPickerSheet: some View {
        SignerPickerSheet(
            availableSigners: createAvailableSigners,
            connectedCredentialId: demoState.credentialId,
            walletConnector: demoState.walletConnector,
            ed25519Available: demoState.isEd25519Available,
            description: "Choose which signers co-authorize creating this context rule. " +
                         "Enter a secret key or connect a wallet to enable signing for a Stellar account signer.",
            confirmLabel: "Confirm Create",
            onCancel: { showCreateSignerPicker = false },
            onConfirm: { chosenSigners, delegatedSecrets, ed25519Secrets in
                showCreateSignerPicker = false
                let collapsed = MultiSignerRegistration.collapseForSinglePasskey(
                    chosenSigners: chosenSigners,
                    delegatedSecrets: delegatedSecrets,
                    ed25519Secrets: ed25519Secrets,
                    connectedCredentialId: demoState.credentialId
                )
                Task {
                    await performSubmit(
                        selectedSigners: collapsed.chosen,
                        delegatedSecrets: collapsed.delegatedSecrets,
                        ed25519Secrets: collapsed.ed25519Secrets
                    )
                }
            }
        )
    }

    /// Returns `true` when the loaded available-signers list contains exactly
    /// one entry and that entry is the connected wallet's own passkey. In that
    /// case the multi-signer picker is skipped and the submission goes through
    /// the single-passkey fast-path.
    internal func isSinglePasskeyTransfer(signersFor list: [TransferSignerInfo]) -> Bool {
        guard list.count == 1 else { return false }
        guard let credId = SmartAccountBuilders.getCredentialIdStringFromSigner(
            signer: list[0].signer
        ) else { return false }
        return credId == demoState.credentialId
    }
}
