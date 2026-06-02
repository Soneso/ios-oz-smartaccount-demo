// ContextRuleBuilderCore+EditResult.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ContextRuleBuilderCore: edit-mode result + picker views
// ============================================================================

extension ContextRuleBuilderCore {

    // -------------------------------------------------------------------------
    // MARK: - Edit result section
    // -------------------------------------------------------------------------

    /// Renders the edit-mode result as a grouped `Section`. The `terminal`
    /// parameter distinguishes the full-success terminal screen (which carries
    /// the Done button) from the partial / failure case rendered inline above
    /// the persisted form.
    internal func editResultSection(
        result: ContextRuleEditResult,
        terminal: Bool
    ) -> some View {
        let style = editResultStyle(for: result)
        return Section {
            VStack(alignment: .leading, spacing: Self.editResultSpacing) {
                Text(style.title)
                    .font(Typography.sectionHeader)
                    .fontWeight(.bold)
                    .foregroundStyle(style.titleColor)
                    .accessibilityAddTraits(.isHeader)
                Text("\(result.completedOperations) of \(result.totalOperations) \(result.totalOperations == 1 ? "operation" : "operations") completed")
                    .font(Typography.metadata)
                    .foregroundStyle(.secondary)
                editResultHashes(result: result, color: style.titleColor)
                editResultAuthGuard(result: result)
                editResultError(result: result)
                editResultFailedStep(result: result)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .modifier(
                AccessibilityAnnouncementModifier(
                    text: editAnnouncement(result: result, title: style.title)
                )
            )
            if terminal && style.isFull {
                doneButton
                    .listRowInsets(EdgeInsets(
                        top: ContextRuleBuilderCore.actionRowVerticalPadding,
                        leading: ContextRuleBuilderCore.actionRowHorizontalPadding,
                        bottom: ContextRuleBuilderCore.actionRowVerticalPadding,
                        trailing: ContextRuleBuilderCore.actionRowHorizontalPadding
                    ))
            }
        }
    }

    /// Vertical spacing between the header, metadata, and detail rows inside
    /// the edit-result section.
    fileprivate static let editResultSpacing: CGFloat = 10

    private struct EditResultStyle {
        let title: String
        let titleColor: Color
        let isFull: Bool
    }

    private func editResultStyle(for result: ContextRuleEditResult) -> EditResultStyle {
        let isFull = result.success && !result.partialDueToAuthGuard
        let isPartial = result.success && result.partialDueToAuthGuard
        if isFull {
            return EditResultStyle(
                title: "All Changes Applied",
                titleColor: Color.contextRulePolicyBadgeForeground,
                isFull: true
            )
        }
        if isPartial {
            return EditResultStyle(
                title: "Partial Update",
                titleColor: Color.contextRuleSignerBadgeForeground,
                isFull: false
            )
        }
        return EditResultStyle(
            title: "Update Failed",
            titleColor: Color.semanticError,
            isFull: false
        )
    }

    /// Stroke alpha applied to the outlined inline copy button surrounding
    /// each transaction hash row.
    fileprivate static let copyBorderAlpha: Double = 0.6

    /// Corner radius applied to the outlined inline copy button surrounding
    /// each transaction hash row.
    fileprivate static let copyButtonRadius: CGFloat = 6

    @ViewBuilder
    private func editResultHashes(
        result: ContextRuleEditResult,
        color: Color
    ) -> some View {
        if !result.transactionHashes.isEmpty {
            Text("Transaction Hashes")
                .font(Typography.metadata)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
            ForEach(result.transactionHashes, id: \.self) { hash in
                editHashRow(hash: hash, color: color)
            }
        }
    }

    @ViewBuilder
    private func editResultAuthGuard(result: ContextRuleEditResult) -> some View {
        if let auth = result.authGuardMessage {
            Text(auth)
                .font(Typography.metadata)
                .foregroundStyle(Color.contextRuleSignerBadgeForeground)
        }
    }

    @ViewBuilder
    private func editResultError(result: ContextRuleEditResult) -> some View {
        if let error = result.error {
            Text(error)
                .font(Typography.metadata)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func editResultFailedStep(result: ContextRuleEditResult) -> some View {
        if let step = result.failedStep {
            Text("Failed at: \(step)")
                .font(Typography.metadata)
                .foregroundStyle(Color.semanticError)
        }
    }

    private func editHashRow(hash: String, color: Color) -> some View {
        HStack(spacing: Tokens.iconLabelSpacing) {
            Text(hash)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                copyEditHash(hash)
            } label: {
                Text("Copy")
                    .font(Typography.metadata)
                    .fontWeight(.semibold)
                    .padding(.horizontal, Self.copyButtonHorizontalPadding)
                    .padding(.vertical, Self.copyButtonVerticalPadding)
                    .overlay(
                        RoundedRectangle(cornerRadius: Self.copyButtonRadius)
                            .stroke(color.opacity(Self.copyBorderAlpha), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy transaction hash")
        }
    }

    /// Horizontal padding inside the inline "Copy" button.
    fileprivate static let copyButtonHorizontalPadding: CGFloat = 10

    /// Vertical padding inside the inline "Copy" button.
    fileprivate static let copyButtonVerticalPadding: CGFloat = 6

    private var doneButton: some View {
        LoadingButton("Done", style: .primary) { @MainActor in
            onDismiss()
        }
        .accessibilityLabel("Done")
    }

    private func copyEditHash(_ hash: String) {
        clipboard.copy(hash, sensitive: false)
        snackbarMessage = SnackbarMessage("Hash copied")
    }

    private func editAnnouncement(
        result: ContextRuleEditResult,
        title: String
    ) -> String {
        var parts: [String] = []
        parts.append(
            "\(title). \(result.completedOperations) of \(result.totalOperations) " +
            "\(result.totalOperations == 1 ? "operation" : "operations") completed."
        )
        if let auth = result.authGuardMessage {
            parts.append(auth)
        }
        if let error = result.error {
            parts.append("Error: \(error)")
        }
        if let step = result.failedStep {
            parts.append("Failed at: \(step).")
        }
        return parts.joined(separator: " ")
    }

    // -------------------------------------------------------------------------
    // MARK: - Edit signer picker sheet
    // -------------------------------------------------------------------------

    @ViewBuilder
    internal var editSignerPickerSheet: some View {
        SignerPickerSheet(
            availableSigners: createAvailableSigners,
            connectedCredentialId: demoState.credentialId,
            walletConnector: demoState.walletConnector,
            ed25519Available: demoState.isEd25519Available,
            description: "Choose which signers co-authorize editing this context rule. " +
                         "Enter a secret key or connect a wallet to enable signing for a Stellar account signer.",
            confirmLabel: "Confirm Edit",
            onCancel: { showEditSignerPicker = false },
            onConfirm: { chosenSigners, delegatedSecrets, ed25519Secrets in
                showEditSignerPicker = false
                let collapsed = MultiSignerRegistration.collapseForSinglePasskey(
                    chosenSigners: chosenSigners,
                    delegatedSecrets: delegatedSecrets,
                    ed25519Secrets: ed25519Secrets,
                    connectedCredentialId: demoState.credentialId
                )
                Task {
                    await performEditSubmit(
                        chosenSigners: collapsed.chosen,
                        delegatedSecrets: collapsed.delegatedSecrets,
                        ed25519Secrets: collapsed.ed25519Secrets
                    )
                }
            }
        )
    }
}
