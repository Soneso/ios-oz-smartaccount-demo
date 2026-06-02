// SignerManagementSection+List.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - SignerManagementSection: Staged signers list
// ============================================================================

extension SignerManagementSection {

    @ViewBuilder
    internal var currentSignersSection: some View {
        Section {
            currentSignersBody
        } header: {
            Text("Signers")
                .font(Typography.sectionHeader)
                .accessibilityAddTraits(.isHeader)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    "Add signers who can authorize operations matching this context. " +
                    "At least one signer is required. Maximum \(OZSmartAccountConstants.maxSigners)."
                )
                if isEditing {
                    Text("Each signer change requires a separate passkey authentication.")
                        .foregroundStyle(Color.accentColor)
                }
                FieldErrorText(error: fieldErrors["signers"])
            }
            .font(Typography.metadata)
            .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var currentSignersBody: some View {
        if isEditing {
            editSignersListContent
        } else if signers.isEmpty {
            emptySignersRow
        } else {
            signersListContent
        }
    }

    private var emptySignersRow: some View {
        ContentUnavailableView(
            "No Signers Added",
            systemImage: "person.badge.plus",
            description: Text("Add at least one signer using the controls below.")
        )
        .symbolRenderingMode(.hierarchical)
    }

    @ViewBuilder
    private var signersListContent: some View {
        ForEach(
            Array(signers.enumerated()),
            id: \.element.uniqueKey
        ) { index, signer in
            signerRow(signer: signer, index: index)
        }
        Text("\(pluralize(signers.count, "signer", "signers")) added")
            .font(Typography.metadata)
            .foregroundStyle(.tertiary)
    }

    private func signerRow(
        signer: any SmartAccountSignerProtocol,
        index: Int
    ) -> some View {
        let type = signerTypeLabel(for: signer)
        let identifier = signerDisplayIdentifier(for: signer)
        let color = signerTypeColor(for: type)
        return HStack(spacing: Tokens.iconLabelSpacing) {
            signerTypeBadge(type: type, color: color)
            Text(identifier)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityLabel("\(type) signer: \(identifier)")
            Spacer()
            removeButton(signer: signer, index: index, type: type)
        }
        .accessibilityElement(children: .contain)
    }

    private func signerTypeBadge(type: String, color: Color) -> some View {
        Pill(
            type,
            background: color.opacity(Self.typeBadgeBackgroundAlpha),
            foreground: color,
            textStyle: .caption2.weight(.semibold)
        )
    }

    @ViewBuilder
    private func removeButton(
        signer: any SmartAccountSignerProtocol,
        index: Int,
        type: String
    ) -> some View {
        if !isSubmitting {
            Button {
                let key = SmartAccountBuilders.getSignerKey(signer: signer)
                removeSigner(at: index, key: key)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.semanticError)
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(type) signer")
        }
    }

    internal func removeSigner(at index: Int, key: String) {
        signers.remove(at: index)
        signerWeights.removeValue(forKey: key)
        fieldErrors.removeValue(forKey: "signers")
    }

    // -------------------------------------------------------------------------
    // MARK: - Edit-mode rendering
    // -------------------------------------------------------------------------

    @ViewBuilder
    private var editSignersListContent: some View {
        if signerEntries.isEmpty {
            emptySignersRow
        } else {
            ForEach(
                Array(signerEntries.enumerated()),
                id: \.element.signer.uniqueKey
            ) { index, entry in
                editSignerRow(entry: entry, index: index)
            }
            Text("\(pluralize(signerEntries.count, "signer", "signers")) added")
                .font(Typography.metadata)
                .foregroundStyle(.tertiary)
        }
    }

    private func editSignerRow(entry: EditSignerEntry, index: Int) -> some View {
        let type = signerTypeLabel(for: entry.signer)
        let identifier = signerDisplayIdentifier(for: entry.signer)
        let color = signerTypeColor(for: type)
        let isConnected = isConnectedWalletSigner(entry.signer)
        return HStack(spacing: Tokens.iconLabelSpacing) {
            signerTypeBadge(type: type, color: color)
            if entry.isOriginal {
                onChainBadge
            }
            Text(identifier)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityLabel(editSignerAccessibilityLabel(
                    type: type, identifier: identifier, entry: entry
                ))
            Spacer()
            editSignerTrailing(
                entry: entry, index: index, type: type, isConnected: isConnected
            )
        }
        .accessibilityElement(children: .contain)
    }

    private var onChainBadge: some View {
        Pill(
            "(on-chain)",
            background: Color.activityLogSuccess,
            foreground: .white,
            textStyle: .caption2.weight(.semibold)
        )
        .accessibilityLabel("On-chain")
    }

    @ViewBuilder
    private func editSignerTrailing(
        entry: EditSignerEntry,
        index: Int,
        type: String,
        isConnected: Bool
    ) -> some View {
        if isSubmitting {
            EmptyView()
        } else if isConnected {
            Text("You")
                .font(Typography.metadata)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Connected wallet's own signer cannot be removed")
        } else {
            Button {
                onRemoveEntry?(index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.semanticError)
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(type) signer")
        }
    }

    private func editSignerAccessibilityLabel(
        type: String,
        identifier: String,
        entry: EditSignerEntry
    ) -> String {
        if entry.isOriginal {
            return "\(type) signer (on-chain): \(identifier)"
        }
        return "\(type) signer: \(identifier)"
    }

    internal func isConnectedWalletSigner(_ signer: any SmartAccountSignerProtocol) -> Bool {
        guard let connected = connectedCredentialId else { return false }
        guard let credId = SmartAccountBuilders.getCredentialIdStringFromSigner(
            signer: signer
        ) else {
            return false
        }
        return credId == connected
    }

    // -------------------------------------------------------------------------
    // MARK: - Layout constants
    // -------------------------------------------------------------------------

    /// Alpha applied to a signer-type accent color to derive the soft pill
    /// background tint while keeping the same hue for the foreground glyph.
    fileprivate static let typeBadgeBackgroundAlpha: Double = 0.18
}
