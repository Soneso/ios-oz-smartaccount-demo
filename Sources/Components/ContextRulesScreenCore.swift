// ContextRulesScreenCore.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ContextRulesScreenCore
// ============================================================================

/// Shared body for the context rules screen, hosted by the iOS and macOS shells.
///
/// Contains all flow orchestration, screen state, and sub-views that are
/// identical across platforms. Platform-specific concerns — navigation chrome,
/// dismiss behaviour, and the outer scroll container — are owned by the hosting
/// shell.
///
/// The rule list is potentially large (a smart account can register many
/// context rules), so the screen is hosted by a native `List` rather than a
/// heterogeneous `Form`. `List` virtualises its rows and supplies the
/// platform's grouped-section chrome on both iOS and macOS.
///
/// In the rule list, the card whose rule matches `removingRuleId` renders an
/// inline spinner in place of its Remove button; other cards' Edit and Remove
/// buttons are disabled until the removal completes.
///
/// All SDK interactions are delegated to `ContextRuleFlow`. This view never
/// calls SDK types directly.
public struct ContextRulesScreenCore: View {

    // -------------------------------------------------------------------------
    // MARK: - Environment
    // -------------------------------------------------------------------------

    @EnvironmentObject private var demoState: DemoState
    @EnvironmentObject private var activityLog: ActivityLogState

    // -------------------------------------------------------------------------
    // MARK: - Flow
    // -------------------------------------------------------------------------

    @State private var flow: ContextRuleFlow?

    // -------------------------------------------------------------------------
    // MARK: - Screen state
    // -------------------------------------------------------------------------

    @State private var rules: [ParsedContextRuleInfo] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var expandedRuleId: UInt32?

    /// Active remove-rule ceremony state. Non-nil presents the signer picker
    /// sheet via `.sheet(item:)`; the rule and loaded signer list travel as
    /// one payload so the sheet content reads them from its closure parameter
    /// instead of through `self.@State`.
    @State private var activeRemoval: RemovalContext?

    /// Identifier of the rule currently being removed, or `nil` when no
    /// removal is in flight. Drives the per-row spinner on the matching
    /// `ContextRuleCard` and disables the Refresh / Add Rule buttons plus
    /// the action buttons on every other card while a removal is pending.
    @State private var removingRuleId: UInt32?

    /// Anchor identity of the error section row, used to scroll a removal
    /// failure into the visible area.
    private static let errorAnchor = "context-rules-error"

    // -------------------------------------------------------------------------
    // MARK: - RemovalContext
    // -------------------------------------------------------------------------

    /// Payload presented by `.sheet(item:)` when the remove-rule ceremony
    /// needs a multi-signer authorization. Carries the rule under removal
    /// and the available signers in one value so the sheet does not need to
    /// read screen-level `@State`.
    fileprivate struct RemovalContext: Identifiable {
        let rule: ParsedContextRuleInfo
        let signers: [TransferSignerInfo]
        var id: UInt32 { rule.id }
    }

    // -------------------------------------------------------------------------
    // MARK: - Platform callbacks
    // -------------------------------------------------------------------------

    /// Called when the user taps the `+ Add Rule` button. The hosting shell
    /// navigates to the `ContextRuleBuilderScreen` via its preferred mechanism
    /// (push on iOS, sidebar selection on macOS).
    private let onAddRule: () -> Void

    /// Called when the user taps `Edit Rule` on a `ContextRuleCard`. Carries
    /// the on-chain rule identifier so the hosting shell can navigate to the
    /// builder in edit mode. Defaults to a no-op.
    private let onEditRule: (UInt32) -> Void

    /// Called when the user taps `Delegate to Agent`. The hosting shell
    /// navigates to the `DelegateToAgentScreen`. Defaults to a no-op.
    private let onDelegateToAgent: () -> Void

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates a `ContextRulesScreenCore`.
    ///
    /// - Parameters:
    ///   - onAddRule: Closure invoked when the user taps `+ Add Rule`.
    ///   - onEditRule: Closure invoked when the user taps `Edit Rule` on a
    ///     `ContextRuleCard`. Receives the on-chain rule identifier.
    public init(
        onAddRule: @escaping () -> Void = {},
        onEditRule: @escaping (UInt32) -> Void = { _ in },
        onDelegateToAgent: @escaping () -> Void = {}
    ) {
        self.onAddRule = onAddRule
        self.onEditRule = onEditRule
        self.onDelegateToAgent = onDelegateToAgent
    }

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    public var body: some View {
        ScrollViewReader { proxy in
            listContainer
                .task { await loadRules() }
                .sheet(item: $activeRemoval) { ctx in
                    signerPickerSheet(for: ctx)
                }
                .onChange(of: errorMessage) { _, message in
                    guard message != nil else { return }
                    // The error section renders above the rule list; a removal
                    // failure on a rule far down the list would otherwise land
                    // outside the viewport. Deferred one runloop so the row is
                    // laid out before the scroll runs.
                    Task { @MainActor in
                        withAnimation { proxy.scrollTo(Self.errorAnchor, anchor: .center) }
                    }
                }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - List container
    // -------------------------------------------------------------------------

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
        } else if isLoading {
            loadingSection
        } else {
            if let msg = errorMessage {
                errorSection(message: msg)
            }
            actionSection
            ruleListSection
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Description section
    // -------------------------------------------------------------------------

    private var descriptionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Self.descriptionSpacing) {
                Text("On-Chain Authorization Rules")
                    .font(Typography.sectionHeader)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                Text(
                    "Context rules define who can authorize what operations on this smart account. " +
                    "Each rule specifies signers and policies that control access for a given context type."
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
        // active-flow guard section with heading and description, not an empty list state
        Section {
            VStack(alignment: .leading, spacing: Self.descriptionSpacing) {
                Text("No wallet connected")
                    .font(Typography.sectionHeader)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                Text("Connect a wallet to view context rules.")
                    .font(Typography.secondary)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("No wallet connected. Connect a wallet to view context rules.")
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
                Text("Loading context rules...")
                    .font(Typography.secondary)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Self.loadingRowVerticalPadding)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Loading context rules")
            .modifier(AccessibilityAnnouncementModifier(text: "Loading context rules"))
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Error section
    // -------------------------------------------------------------------------

    private func errorSection(message: String) -> some View {
        Section {
            InlineErrorText(message)
                .id(Self.errorAnchor)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Action section (Refresh, Add Rule)
    // -------------------------------------------------------------------------

    private var actionSection: some View {
        Section {
            refreshButton
                .listRowInsets(EdgeInsets(
                    top: Self.actionRowVerticalPadding,
                    leading: Self.actionRowHorizontalPadding,
                    bottom: Self.actionRowVerticalPadding,
                    trailing: Self.actionRowHorizontalPadding
                ))
            addRuleButton
                .listRowInsets(EdgeInsets(
                    top: Self.actionRowVerticalPadding,
                    leading: Self.actionRowHorizontalPadding,
                    bottom: Self.actionRowVerticalPadding,
                    trailing: Self.actionRowHorizontalPadding
                ))
            delegateToAgentButton
                .listRowInsets(EdgeInsets(
                    top: Self.actionRowVerticalPadding,
                    leading: Self.actionRowHorizontalPadding,
                    bottom: Self.actionRowVerticalPadding,
                    trailing: Self.actionRowHorizontalPadding
                ))
        }
    }

    private var delegateToAgentButton: some View {
        LoadingButton("Delegate to Agent", style: .outlined) { @MainActor in
            onDelegateToAgent()
        }
        .disabled(isLoading || removingRuleId != nil)
        .accessibilityLabel("Delegate to agent")
        .accessibilityHint("Opens the delegate-to-agent screen to authorise an autonomous agent signer.")
    }

    private var addRuleButton: some View {
        LoadingButton("+ Add Rule", style: .primary) { @MainActor in
            onAddRule()
        }
        .disabled(isLoading || removingRuleId != nil)
        .accessibilityLabel("Add context rule")
        .accessibilityHint("Opens the context rule builder.")
        #if os(macOS)
        .keyboardShortcut(.defaultAction)
        #endif
    }

    private var refreshButton: some View {
        LoadingButton(
            isLoading ? "Loading..." : "Refresh",
            loadingLabel: "Loading...",
            style: .outlined
        ) {
            await loadRules()
        } onError: { error in
            // Refresh is single-flight (see `loadRules`'s in-flight guard); the
            // only errors that reach this closure are the awaited body throwing,
            // which `loadRules` already catches internally. The guard prevents
            // a stale refresh from racing a fresh one and writing both error
            // messages.
            errorMessage = ActivityLogState.redact(actionableMessage(for: error))
        }
        .disabled(isLoading || removingRuleId != nil)
    }

    // -------------------------------------------------------------------------
    // MARK: - Rule list section
    // -------------------------------------------------------------------------

    @ViewBuilder
    private var ruleListSection: some View {
        if rules.isEmpty {
            emptySection
        } else {
            Section {
                ForEach(rules, id: \.id) { rule in
                    let isExpanded = Binding<Bool>(
                        get: { expandedRuleId == rule.id },
                        set: { expanded in expandedRuleId = expanded ? rule.id : nil }
                    )
                    ContextRuleCard(
                        rule: rule,
                        isLastRule: rules.count == 1,
                        isRemoving: removingRuleId == rule.id,
                        isAnotherRemovalInFlight: removingRuleId != nil && removingRuleId != rule.id,
                        isExpanded: isExpanded,
                        onEdit: { onEditRule(rule.id) },
                        onRemove: { initiateRemoval(of: rule) }
                    )
                }
            } header: {
                Text("\(pluralize(rules.count, "context rule", "context rules")) loaded")
                    .font(Typography.sectionHeader)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }

    private var emptySection: some View {
        Section {
            ContentUnavailableView {
                Label("No Context Rules Found", systemImage: "list.bullet.clipboard")
            } description: {
                Text("This wallet has no context rules. Add a rule to configure access control.")
            } actions: {
                Button("+ Add Rule") {
                    onAddRule()
                }
                .disabled(removingRuleId != nil)
            }
            .symbolRenderingMode(.hierarchical)
        }
        .listRowBackground(Color.clear)
    }

    // -------------------------------------------------------------------------
    // MARK: - Signer picker sheet
    // -------------------------------------------------------------------------

    @ViewBuilder
    private func signerPickerSheet(for ctx: RemovalContext) -> some View {
        SignerPickerSheet(
            availableSigners: ctx.signers,
            connectedCredentialId: demoState.credentialId,
            walletConnector: demoState.walletConnector,
            ed25519Available: demoState.isEd25519Available,
            description: "Choose which signers co-authorize removing this context rule. " +
                         "Enter a secret key or connect a wallet to enable signing for a Stellar account signer.",
            confirmLabel: "Confirm Remove",
            onCancel: { activeRemoval = nil },
            onConfirm: { chosenSigners, delegatedSecrets, ed25519Secrets in
                activeRemoval = nil
                let collapsed = MultiSignerRegistration.collapseForSinglePasskey(
                    chosenSigners: chosenSigners,
                    delegatedSecrets: delegatedSecrets,
                    ed25519Secrets: ed25519Secrets,
                    connectedCredentialId: demoState.credentialId
                )
                Task {
                    await performRemoval(
                        rule: ctx.rule,
                        chosenSigners: collapsed.chosen,
                        delegatedSecrets: collapsed.delegatedSecrets,
                        ed25519Secrets: collapsed.ed25519Secrets
                    )
                }
            }
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - Actions
    // -------------------------------------------------------------------------

    private func loadRules() async {
        guard demoState.isConnected else { return }
        // Single-flight guard: if a refresh is already in flight, the user-
        // facing refresh button is disabled, but a stray concurrent caller
        // would otherwise produce duplicate activity-log entries and could
        // race the error-message write. Skip the duplicate call early.
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            rules = try await resolvedFlow().listContextRules()
        } catch {
            if !isUserCancellation(error) {
                errorMessage = ActivityLogState.redact(actionableMessage(for: error))
            }
        }
        isLoading = false
    }

    private func initiateRemoval(of rule: ParsedContextRuleInfo) {
        if rules.count == 1 { return }
        Task {
            // Brief delay so the `.confirmationDialog` triggered by the
            // rule card's Remove button has time to fully dismiss before
            // the picker sheet is presented.
            try? await Task.sleep(for: .milliseconds(350))
            let signers = await resolvedFlow().loadAvailableSigners()
            if signers.count > 1 {
                activeRemoval = RemovalContext(rule: rule, signers: signers)
            } else {
                await performRemoval(rule: rule, chosenSigners: [], delegatedSecrets: [:])
            }
        }
    }

    private func performRemoval(
        rule: ParsedContextRuleInfo,
        chosenSigners: [any SmartAccountSignerProtocol],
        delegatedSecrets: [String: String],
        ed25519Secrets: [Ed25519SecretKey: Data] = [:]
    ) async {
        removingRuleId = rule.id
        errorMessage = nil
        do {
            _ = try await resolvedFlow().removeContextRule(
                ruleId: rule.id,
                ruleName: rule.name,
                totalRuleCount: rules.count,
                selectedSigners: chosenSigners,
                delegatedSecrets: delegatedSecrets,
                ed25519Secrets: ed25519Secrets
            )
            activeRemoval = nil
            rules = try await resolvedFlow().listContextRules()
        } catch {
            if isUserCancellation(error) {
                activityLog.info("Passkey authentication cancelled")
            } else {
                errorMessage = ActivityLogState.redact(actionableMessage(for: error))
            }
        }
        removingRuleId = nil
    }

    // -------------------------------------------------------------------------
    // MARK: - Flow resolution
    // -------------------------------------------------------------------------

    @MainActor
    private func resolvedFlow() -> ContextRuleFlow {
        if let existing = flow { return existing }
        let newFlow = DemoFlowFactory.makeContextRuleListFlow(
            demoState: demoState,
            activityLog: activityLog
        )
        flow = newFlow
        return newFlow
    }

    // -------------------------------------------------------------------------
    // MARK: - Local layout constants
    // -------------------------------------------------------------------------

    /// Vertical spacing between the heading and the body copy of a leading
    /// status section (description, not-connected, empty-state).
    private static let descriptionSpacing: CGFloat = 6

    /// Vertical padding applied to the loading row so the spinner stack reads
    /// as a distinct surface inside its grouped section.
    private static let loadingRowVerticalPadding: CGFloat = 12

    /// Vertical padding applied to action rows (Refresh, Add Rule) inside their
    /// list section so the button's stroke is not clipped by the row's default
    /// separator inset.
    private static let actionRowVerticalPadding: CGFloat = 8

    /// Horizontal padding applied to action rows (Refresh, Add Rule) so they
    /// align with the grouped section's content area on both platforms.
    private static let actionRowHorizontalPadding: CGFloat = 16
}
