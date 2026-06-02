// KnownSignersScreenCore.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// ============================================================================
// MARK: - KnownSignersScreenCore
// ============================================================================

/// Shared body for the Account Signers screen, hosted by the iOS and macOS shells.
///
/// Reads every context rule from the connected smart account via
/// `AccountSignersFlow`, deduplicates the union of their signers, and renders
/// a non-interactive list grouped by unique signer. Each row stacks the
/// signer-type badge, the full identifier line, and the per-rule chip group
/// vertically so long passkey credential ids never get middle-truncated on
/// narrow widths.
///
/// Sections (top to bottom):
/// - Description section explaining the screen's purpose.
/// - Not-connected guard section if the wallet is not connected.
/// - Refresh action section (single-flight guard).
/// - Loading / error / empty / signers-list section, mutually exclusive.
/// - Navigation section containing the Go Back action.
///
/// All SDK interactions are delegated to `AccountSignersFlow`. This view
/// never calls SDK types directly.
public struct KnownSignersScreenCore: View {

    // -------------------------------------------------------------------------
    // MARK: - Environment
    // -------------------------------------------------------------------------

    @EnvironmentObject private var demoState: DemoState
    @EnvironmentObject private var activityLog: ActivityLogState

    // -------------------------------------------------------------------------
    // MARK: - Flow
    // -------------------------------------------------------------------------

    @State private var flow: AccountSignersFlow?

    // -------------------------------------------------------------------------
    // MARK: - Screen state
    // -------------------------------------------------------------------------

    @State private var signerEntries: [SignerEntry] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var initialLoadStarted: Bool = false

    // -------------------------------------------------------------------------
    // MARK: - Platform callbacks
    // -------------------------------------------------------------------------

    /// Called when the user taps the bottom "Go Back" button. The hosting
    /// shell dismisses the screen (push back on iOS, sidebar selection on macOS).
    private let onDismiss: () -> Void

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates a `KnownSignersScreenCore`.
    ///
    /// - Parameter onDismiss: Closure invoked when the screen should navigate away.
    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    public var body: some View {
        listContainer
            .task {
                guard !initialLoadStarted else { return }
                initialLoadStarted = true
                await loadSigners()
            }
    }

    // -------------------------------------------------------------------------
    // MARK: - List container
    // -------------------------------------------------------------------------
    // The signer list is potentially large (a smart account can register many
    // delegated signers across its context rules), so the screen is hosted by
    // a native `List` rather than a heterogeneous `Form`. `List` virtualises
    // its rows and supplies the platform's grouped-section chrome on both
    // iOS and macOS.

    @ViewBuilder
    private var listContainer: some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            List {
                sectionContents
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.brandScaffold)
            .scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            List {
                sectionContents
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.brandScaffold)
        }
        #elseif os(macOS)
        List {
            sectionContents
        }
        .listStyle(.automatic)
        #else
        List {
            sectionContents
        }
        #endif
    }

    @ViewBuilder
    private var sectionContents: some View {
        descriptionSection

        if !demoState.isConnected {
            notConnectedSection
        } else {
            refreshSection

            if isLoading && signerEntries.isEmpty {
                loadingSection
            } else if let msg = errorMessage {
                errorSection(message: msg)
            } else if signerEntries.isEmpty {
                emptySection
            } else {
                signersListSection
            }
        }

        goBackSection
    }

    // -------------------------------------------------------------------------
    // MARK: - Description section
    // -------------------------------------------------------------------------

    private var descriptionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Self.descriptionSpacing) {
                Text("Account Signers")
                    .font(Typography.sectionHeader)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                Text(
                    "All signers registered on this smart account across all context rules."
                )
                .font(Typography.secondary)
                .foregroundStyle(.secondary)
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Not-connected section
    // -------------------------------------------------------------------------

    private var notConnectedSection: some View {
        Section {
            HStack(alignment: .top, spacing: Tokens.iconLabelSpacing) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.semanticError)
                    .accessibilityHidden(true)
                Text("Connect a wallet to view account signers")
                    .font(Typography.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Connect a wallet to view account signers")
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Refresh section
    // -------------------------------------------------------------------------

    private var refreshSection: some View {
        Section {
            LoadingButton(
                "Refresh",
                loadingLabel: "Loading...",
                style: .outlined
            ) {
                await loadSigners()
            } onError: { error in
                errorMessage = ActivityLogState.redact(actionableMessage(for: error))
            }
            .accessibilityHint("Reloads the list of account signers from the network.")
            #if os(macOS)
            .keyboardShortcut("r", modifiers: .command)
            #endif
            .listRowInsets(EdgeInsets(
                top: Self.actionRowVerticalPadding,
                leading: Self.actionRowHorizontalPadding,
                bottom: Self.actionRowVerticalPadding,
                trailing: Self.actionRowHorizontalPadding
            ))
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Loading section
    // -------------------------------------------------------------------------

    private var loadingSection: some View {
        Section {
            HStack(spacing: Tokens.iconLabelSpacing) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text("Loading signers...")
                    .font(Typography.secondary)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Self.loadingRowVerticalPadding)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Loading signers")
            .modifier(AccessibilityAnnouncementModifier(text: "Loading signers"))
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Error section
    // -------------------------------------------------------------------------

    private func errorSection(message: String) -> some View {
        Section {
            HStack(alignment: .top, spacing: Tokens.iconLabelSpacing) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(Color.semanticError)
                    .accessibilityHidden(true)
                Text("Failed to load signers: \(message)")
                    .font(Typography.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Failed to load signers: \(message)")
            .modifier(AccessibilityAnnouncementModifier(text: "Failed to load signers: \(message)"))
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Empty section
    // -------------------------------------------------------------------------

    private var emptySection: some View {
        Section {
            ContentUnavailableView(
                "No Signers Found",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text("This account has no registered signers across any context rule.")
            )
            .symbolRenderingMode(.hierarchical)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Signers list section
    // -------------------------------------------------------------------------

    private var signersListSection: some View {
        Section {
            ForEach(signerEntries, id: \.signer.uniqueKey) { entry in
                signerRow(entry: entry)
            }
        } header: {
            Text(signerCountLabel(signerEntries.count))
                .font(Typography.sectionHeader)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Per-signer row
    // -------------------------------------------------------------------------

    private func signerRow(entry: SignerEntry) -> some View {
        let typeLabel = signerTypeLabel(for: entry.signer)
        let identifier = signerDisplayIdentifier(for: entry.signer)
        let typeColor = signerTypeColor(for: typeLabel)
        let accessibilityIdentifier: String = {
            if typeLabel == "Passkey" {
                return ActivityLogState.redactCredentialId(identifier)
            }
            return identifier
        }()
        return VStack(alignment: .leading, spacing: Self.signerRowSpacing) {
            HStack(spacing: Self.badgeRowSpacing) {
                Pill(
                    typeLabel,
                    background: typeColor,
                    foreground: .white,
                    padding: EdgeInsets(
                        top: Self.badgePillVerticalPadding,
                        leading: Self.badgePillHorizontalPadding,
                        bottom: Self.badgePillVerticalPadding,
                        trailing: Self.badgePillHorizontalPadding
                    )
                )
                .accessibilityLabel("Signer type: \(typeLabel)")

                Spacer(minLength: 0)
            }

            Text(identifier)
                .font(Typography.mono)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Signer identifier: \(accessibilityIdentifier)")

            ruleMembershipChips(rules: entry.contextRules)
        }
        .padding(.vertical, Self.signerRowVerticalPadding)
    }

    @ViewBuilder
    private func ruleMembershipChips(rules: [ParsedContextRuleInfo]) -> some View {
        VStack(alignment: .leading, spacing: Self.ruleRowSpacing) {
            ForEach(rules, id: \.id) { rule in
                ruleMembershipRow(rule: rule)
            }
        }
    }

    private func ruleMembershipRow(rule: ParsedContextRuleInfo) -> some View {
        let displayName = rule.name.isEmpty ? "Unnamed Rule" : rule.name
        let contextLabel = contextTypeLabel(for: rule.contextType)
        return VStack(alignment: .leading, spacing: Self.ruleChipRowSpacing) {
            HStack(spacing: Self.ruleChipSpacing) {
                Pill(
                    "#\(rule.id)",
                    background: Color.accentContainerBackground,
                    foreground: Color.accentContainerForeground
                )
                Pill(
                    contextLabel,
                    background: Color.accentContainerBackground.opacity(Self.contextChipBackgroundAlpha),
                    foreground: Color.accentContainerForeground
                )
                Spacer(minLength: 0)
            }

            Text(displayName)
                .font(Typography.metadata)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rule \(rule.id), \(displayName), \(contextLabel)")
    }

    // -------------------------------------------------------------------------
    // MARK: - Go Back section
    // -------------------------------------------------------------------------

    private var goBackSection: some View {
        Section {
            Button(action: onDismiss) {
                ButtonLabel("Go Back")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Self.goBackVerticalPadding)
                    .foregroundStyle(Color.accentColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: Self.goBackCornerRadius)
                            .stroke(Color.accentColor, lineWidth: Self.goBackBorderWidth)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Returns to the previous screen.")
            .listRowInsets(EdgeInsets(
                top: Self.actionRowVerticalPadding,
                leading: Self.actionRowHorizontalPadding,
                bottom: Self.actionRowVerticalPadding,
                trailing: Self.actionRowHorizontalPadding
            ))
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Actions
    // -------------------------------------------------------------------------

    private func loadSigners() async {
        guard demoState.isConnected else { return }
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            signerEntries = try await resolvedFlow().loadAccountSigners()
        } catch {
            // The account-signers read is a pure context-rule RPC fetch with
            // no passkey ceremony, so there is no user-cancellation branch
            // to suppress. Any thrown error is surfaced as a sanitised
            // error card and logged.
            let redacted = ActivityLogState.redact(actionableMessage(for: error))
            errorMessage = redacted
            activityLog.error("Failed to load signers: \(redacted)")
        }
        isLoading = false
    }

    // -------------------------------------------------------------------------
    // MARK: - Flow resolution
    // -------------------------------------------------------------------------

    @MainActor
    private func resolvedFlow() -> AccountSignersFlow {
        if let existing = flow { return existing }
        let newFlow = DemoFlowFactory.makeAccountSignersFlow(
            demoState: demoState,
            activityLog: activityLog
        )
        flow = newFlow
        return newFlow
    }

    // -------------------------------------------------------------------------
    // MARK: - Local layout constants
    // -------------------------------------------------------------------------

    /// Vertical spacing between the heading and the body copy in the
    /// description section at the top of the screen.
    private static let descriptionSpacing: CGFloat = 6

    /// Vertical padding applied to the loading row so the spinner stack reads
    /// as a distinct surface inside its grouped section.
    private static let loadingRowVerticalPadding: CGFloat = 12

    /// Vertical spacing between the badge row, the identifier line, and the
    /// rule-membership chip group within a single signer entry.
    private static let signerRowSpacing: CGFloat = 8

    /// Vertical padding applied to each signer row so adjacent rows breathe
    /// inside the inset-grouped list section.
    private static let signerRowVerticalPadding: CGFloat = 4

    /// Horizontal spacing between the leading signer-type pill and any
    /// trailing space inside the badge row.
    private static let badgeRowSpacing: CGFloat = 8

    /// Vertical padding applied to the signer-type pill so it reads as a
    /// prominent badge above the monospaced identifier line.
    private static let badgePillVerticalPadding: CGFloat = 4

    /// Horizontal padding applied to the signer-type pill.
    private static let badgePillHorizontalPadding: CGFloat = 8

    /// Vertical spacing between successive rule-membership rows within a
    /// signer entry.
    private static let ruleRowSpacing: CGFloat = 6

    /// Vertical spacing between the chip row and the rule-name line within a
    /// single rule-membership row.
    private static let ruleChipRowSpacing: CGFloat = 4

    /// Horizontal spacing between adjacent chips on the rule-membership chip row.
    private static let ruleChipSpacing: CGFloat = 6

    /// Alpha applied to the accent-container background of the context-type
    /// chip so it reads as a softer companion to the leading rule-id chip.
    private static let contextChipBackgroundAlpha: Double = 0.6

    /// Vertical padding applied inside the bottom Go Back outlined button.
    private static let goBackVerticalPadding: CGFloat = 12

    /// Corner radius applied to the bottom Go Back outlined button.
    private static let goBackCornerRadius: CGFloat = 10

    /// Stroke width applied to the bottom Go Back outlined button border.
    private static let goBackBorderWidth: CGFloat = 1.5

    /// Vertical padding applied to action rows (Refresh, Go Back) inside their
    /// list sections so the button's stroke is not clipped by the row's
    /// default separator inset.
    private static let actionRowVerticalPadding: CGFloat = 8

    /// Horizontal padding applied to action rows (Refresh, Go Back) so they
    /// align with the grouped section's content area on both platforms.
    private static let actionRowHorizontalPadding: CGFloat = 16
}
