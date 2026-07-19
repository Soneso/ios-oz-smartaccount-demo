// ContextRuleBuilderCore+Result.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ContextRuleBuilderCore: success / failure sections
// ============================================================================

extension ContextRuleBuilderCore {

    internal func successResultSection(result: ContextRuleResult) -> some View {
        let successText = Color.contextRulePolicyBadgeForeground
        return Section {
            VStack(alignment: .leading, spacing: Self.successSpacing) {
                Text("Transaction Successful")
                    .font(Typography.sectionHeader)
                    .fontWeight(.bold)
                    .foregroundStyle(successText)
                    .accessibilityAddTraits(.isHeader)
                if let hash = result.hash {
                    successHashRow(hash: hash, color: successText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Self.successRowPadding)
            .accessibilityElement(children: .contain)
            .modifier(AccessibilityAnnouncementModifier(text: "Context rule created successfully"))
            goBackButton
                .listRowInsets(EdgeInsets(
                    top: ContextRuleBuilderCore.actionRowVerticalPadding,
                    leading: ContextRuleBuilderCore.actionRowHorizontalPadding,
                    bottom: ContextRuleBuilderCore.actionRowVerticalPadding,
                    trailing: ContextRuleBuilderCore.actionRowHorizontalPadding
                ))
        }
    }

    /// Vertical spacing between the success heading and the hash row.
    fileprivate static let successSpacing: CGFloat = 12

    /// Vertical padding applied to the success result row inside its section.
    fileprivate static let successRowPadding: CGFloat = 4

    private func successHashRow(hash: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                copyHash(hash)
            } label: {
                Text("Hash: \(hash)")
                    .font(.system(.caption, design: .monospaced))
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(color)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Transaction hash, tap to copy")
            Text("Tap to copy")
                .font(Typography.metadata)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    private var goBackButton: some View {
        LoadingButton("Go Back", style: .primary) { @MainActor in
            onDismiss()
        }
        .accessibilityLabel("Go back")
    }

    internal func failureSection(result: ContextRuleResult) -> some View {
        let announcement = result.error.map { "Transaction failed: \($0)" } ?? "Transaction failed"
        return Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Transaction Failed")
                    .font(Typography.sectionHeader)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.semanticError)
                    .accessibilityAddTraits(.isHeader)
                if let err = result.error {
                    Text(err)
                        .font(Typography.metadata)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .modifier(AccessibilityAnnouncementModifier(text: announcement))
            .id(Self.failureCardAnchor)
        }
    }

    internal func copyHash(_ hash: String) {
        clipboard.copy(hash, sensitive: false)
        snackbarMessage = SnackbarMessage("Hash copied to clipboard")
    }
}
