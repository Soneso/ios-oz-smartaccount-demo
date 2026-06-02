// ContextRuleCard.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ContextRuleCard
// ============================================================================

/// Expandable card displaying a single parsed context rule.
///
/// Collapsed state shows:
/// - Rule ID badge (`"#N"`), rule name (with `"Unnamed Rule"` fallback).
/// - Context type label.
/// - Summary badges: signer count (blue), policy count (green), expiry (orange, conditional).
/// - Expand/collapse chevron.
/// - Remove button (disabled with label "Last Rule" when `isLastRule` is true).
///
/// Expanded state adds:
/// - Signers section with type chip + display identifier per signer.
/// - Policies section with "P" badge + truncated address per policy.
///
/// Shared between iOS and macOS. SwiftUI primitives only.
public struct ContextRuleCard: View {

    // -------------------------------------------------------------------------
    // MARK: - Configuration
    // -------------------------------------------------------------------------

    /// The rule this card represents.
    private let rule: ParsedContextRuleInfo

    /// `true` when this is the only rule (disables Remove button).
    private let isLastRule: Bool

    /// `true` while a removal for this rule is in progress.
    private let isRemoving: Bool

    /// `true` while a removal for a different rule on the same screen is in
    /// progress. Disables this card's edit and remove buttons so the user
    /// cannot launch a second authorization flow concurrently.
    private let isAnotherRemovalInFlight: Bool

    /// Whether the card is currently expanded.
    @Binding private var isExpanded: Bool

    /// Called when the user confirms removal.
    private let onRemove: () -> Void

    /// Called when the user taps `Edit Rule`. Optional — when absent the
    /// button is omitted (used by tests that only exercise removal).
    private let onEdit: (() -> Void)?

    // -------------------------------------------------------------------------
    // MARK: - Environment
    // -------------------------------------------------------------------------

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // -------------------------------------------------------------------------
    // MARK: - State
    // -------------------------------------------------------------------------

    @State private var showRemoveDialog: Bool = false

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates a `ContextRuleCard`.
    ///
    /// - Parameters:
    ///   - rule: The parsed context rule to display.
    ///   - isLastRule: `true` when this is the only rule on the account.
    ///   - isRemoving: `true` while the removal transaction for this rule is
    ///     in flight. Drives the inline spinner that replaces the Remove
    ///     button on this row.
    ///   - isAnotherRemovalInFlight: `true` while a removal for a different
    ///     rule on the same screen is in flight. When true the Edit and
    ///     Remove buttons on this card are disabled so the user cannot launch
    ///     a second authorization flow concurrently. Defaults to `false`.
    ///   - isExpanded: Binding controlling collapsed / expanded state.
    ///   - onEdit: Called when the user taps `Edit Rule` in the expanded
    ///     section. Omitted when `nil`.
    ///   - onRemove: Called after the user confirms the removal dialog.
    public init(
        rule: ParsedContextRuleInfo,
        isLastRule: Bool,
        isRemoving: Bool,
        isAnotherRemovalInFlight: Bool = false,
        isExpanded: Binding<Bool>,
        onEdit: (() -> Void)? = nil,
        onRemove: @escaping () -> Void
    ) {
        self.rule = rule
        self.isLastRule = isLastRule
        self.isRemoving = isRemoving
        self.isAnotherRemovalInFlight = isAnotherRemovalInFlight
        self._isExpanded = isExpanded
        self.onEdit = onEdit
        self.onRemove = onRemove
    }

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                Color.brandOutline.opacity(0.6)
                    .frame(height: 1)
                    .padding(.horizontal, Tokens.cardPadding)
                expandedContent
            }
        }
        .sectionCard()
        .confirmationDialog(
            "Remove Context Rule",
            isPresented: $showRemoveDialog,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive, action: onRemove)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(removeMessage)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Header
    // -------------------------------------------------------------------------

    private var header: some View {
        VStack(alignment: .leading, spacing: Tokens.insetPadding) {
            HStack(alignment: .top, spacing: 8) {
                idBadge
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name.isEmpty ? "Unnamed Rule" : rule.name)
                        .font(Typography.sectionHeader)
                        .fontWeight(.semibold)
                    Text(contextTypeLabel(for: rule.contextType))
                        .font(Typography.metadata)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                expandChevron
            }
            summaryBadges
            HStack(spacing: Tokens.insetPadding) {
                editButton
                removeButton
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(headerAccessibilityLabel)
        .accessibilityHint(isExpanded ? "Collapse" : "Expand")
        .accessibilityAddTraits(.isButton)
    }

    private var idBadge: some View {
        Pill(
            "#\(rule.id)",
            background: Color.accentContainerBackground,
            foreground: Color.accentContainerForeground,
            textStyle: .caption.weight(.bold)
        )
    }

    private var expandChevron: some View {
        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(Typography.metadata)
            .foregroundStyle(.tertiary)
            .accessibilityLabel(isExpanded ? "Collapse" : "Expand")
    }

    // -------------------------------------------------------------------------
    // MARK: - Summary badges
    // -------------------------------------------------------------------------

    private var summaryBadges: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            Pill(
                signerCountLabel(rule.signers.count),
                background: .contextRuleSignerBadgeBackground,
                foreground: .contextRuleSignerBadgeForeground,
                textStyle: .caption2.weight(.medium)
            )
            Pill(
                policyCountLabel(rule.policies.count),
                background: .contextRulePolicyBadgeBackground,
                foreground: .contextRulePolicyBadgeForeground,
                textStyle: .caption2.weight(.medium)
            )
            if let ledger = rule.validUntil {
                Pill(
                    "Expires: ledger \(ledger)",
                    background: .contextRuleExpiryBadgeBackground,
                    foreground: .contextRuleExpiryBadgeForeground,
                    textStyle: .caption2.weight(.medium)
                )
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Edit button
    // -------------------------------------------------------------------------

    @ViewBuilder
    private var editButton: some View {
        if let onEdit, !isRemoving {
            LoadingButton("Edit Rule", style: .outlined) { @MainActor in
                onEdit()
            }
            .disabled(isAnotherRemovalInFlight)
            .accessibilityLabel("Edit rule #\(rule.id)")
            .accessibilityHint(isAnotherRemovalInFlight ? "Disabled while another rule is being removed." : "")
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Remove button
    // -------------------------------------------------------------------------

    private var removeButton: some View {
        Group {
            if isRemoving {
                HStack(spacing: Self.removeButtonSpacing) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(width: Tokens.spinnerSize, height: Tokens.spinnerSize)
                        .accessibilityHidden(true)
                    Text("Removing...")
                        .font(Typography.metadata)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Removing rule #\(rule.id). Please wait.")
            } else {
                LoadingButton(
                    isLastRule ? "Last Rule" : "Remove Rule",
                    style: isLastRule ? .outlinedNeutral : .outlinedDestructive
                ) { @MainActor in
                    showRemoveDialog = true
                }
                .disabled(isLastRule || isAnotherRemovalInFlight)
                .accessibilityLabel(removeButtonAccessibilityLabel)
                .accessibilityHint(removeButtonAccessibilityHint)
            }
        }
    }

    private var removeButtonAccessibilityLabel: String {
        if isLastRule { return "Cannot remove: last rule" }
        return "Remove rule #\(rule.id)"
    }

    private var removeButtonAccessibilityHint: String {
        if isLastRule { return "Cannot remove the last context rule." }
        if isAnotherRemovalInFlight { return "Disabled while another rule is being removed." }
        return ""
    }

    // -------------------------------------------------------------------------
    // MARK: - Expanded content
    // -------------------------------------------------------------------------

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            signersSection
            policiesSection
        }
        .padding(16)
    }

    private var signersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Signers")
            // inline data fact inside an expanded card detail — not an empty-state list
            if rule.signers.isEmpty {
                Text("No signers (policy-only rule)")
                    .font(Typography.metadata)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rule.signers, id: \.uniqueKey) { signer in
                    signerRow(for: signer)
                }
            }
        }
    }

    private func signerRow(for signer: any SmartAccountSignerProtocol) -> some View {
        HStack(spacing: 8) {
            Pill(
                signerTypeLabel(for: signer),
                background: Color.accentContainerBackground,
                foreground: Color.accentContainerForeground,
                textStyle: .caption2.weight(.medium)
            )
            Text(signerDisplayIdentifier(for: signer))
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(signerTypeLabel(for: signer)) signer: \(signerDisplayIdentifier(for: signer))")
    }

    private var policiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Policies")
            // inline data fact inside an expanded card detail — not an empty-state list
            if rule.policies.isEmpty {
                Text("No policies (signer-only rule)")
                    .font(Typography.metadata)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rule.policies, id: \.self) { policy in
                    policyRow(for: policy)
                }
            }
        }
    }

    private func policyRow(for address: String) -> some View {
        HStack(spacing: 8) {
            Pill(
                "P",
                background: Color.contextRulePolicyBadgeBackground,
                foreground: Color.contextRulePolicyBadgeForeground,
                padding: EdgeInsets(),
                textStyle: .caption2.weight(.bold)
            )
            .frame(width: Self.policyGlyphSize, height: Self.policyGlyphSize)
            Text(truncateContractAddress(address))
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Policy: \(address)")
    }

    // -------------------------------------------------------------------------
    // MARK: - Helpers
    // -------------------------------------------------------------------------

    private var removeMessage: String {
        let display = rule.name.isEmpty ? "Unnamed Rule" : rule.name
        return "Remove rule #\(rule.id) \"\(display)\"? " +
               "This action requires smart account authorization and cannot be undone."
    }

    private var headerAccessibilityLabel: String {
        let name = rule.name.isEmpty ? "Unnamed Rule" : rule.name
        let ctxLabel = contextTypeLabel(for: rule.contextType)
        return "Rule #\(rule.id): \(name), \(ctxLabel), " +
               "\(signerCountLabel(rule.signers.count)), \(policyCountLabel(rule.policies.count))"
    }

    // -------------------------------------------------------------------------
    // MARK: - Local layout constants
    // -------------------------------------------------------------------------

    /// Horizontal spacing between the inline spinner and the "Removing..."
    /// label rendered in place of the Remove button while a removal for this
    /// rule is in flight.
    private static let removeButtonSpacing: CGFloat = 6

    /// Side length of the fixed-square "P" glyph badge rendered next to each
    /// attached policy address in the expanded view. The glyph occupies a
    /// uniform tile so policy rows align with neighbouring signer rows.
    private static let policyGlyphSize: CGFloat = 20
}
