// ContextRuleBuilderCore.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ContextTypeOption
// ============================================================================

/// Options exposed in the "Context Type" dropdown of the builder.
public enum ContextTypeOption: String, CaseIterable, Sendable {

    /// Default fallback rule that matches any operation.
    case defaultRule

    /// Rule matching invocations of a specific contract address.
    case callContract

    /// Rule matching contract deployments using a specific WASM hash.
    case createContract

    /// Human-readable label shown in the dropdown header and selected row.
    public var displayName: String {
        switch self {
        case .defaultRule:    return "Default (Any Operation)"
        case .callContract:   return "Call Contract"
        case .createContract: return "Create Contract"
        }
    }

    /// One-sentence sub-label shown below the option in the dropdown menu.
    public var description: String {
        switch self {
        case .defaultRule:
            return "Matches any operation that does not match a more specific rule"
        case .callContract:
            return "Matches invocations to a specific contract address"
        case .createContract:
            return "Matches contract deployments using a specific WASM hash"
        }
    }
}

// ============================================================================
// MARK: - ContextRuleBuilderCore
// ============================================================================

/// Shared body for the context rule builder screen, hosted by the iOS and
/// macOS shells.
///
/// Owns the entire form state (rule name, context type, expiry, signers,
/// policies) and orchestrates submission via the injected `ContextRuleFlow`.
/// Platform-specific concerns — navigation chrome, dismiss behaviour — are
/// delegated to the hosting shell via parameters.
///
/// The view body is a native `Form { Section }` on both iOS and macOS; the
/// inset-grouped chrome is supplied automatically. Each visual cluster (rule
/// name, context type, expiry, signers, policies, submit) is its own
/// `Section` so the keyboard focus order and VoiceOver rotor match the user's
/// reading order.
public struct ContextRuleBuilderCore: View {

    // -------------------------------------------------------------------------
    // MARK: - Environment
    // -------------------------------------------------------------------------

    @EnvironmentObject internal var demoState: DemoState
    @EnvironmentObject internal var activityLog: ActivityLogState
    @Environment(\.clipboard) internal var clipboard: any ClipboardService

    // -------------------------------------------------------------------------
    // MARK: - Platform callbacks
    // -------------------------------------------------------------------------

    internal let onDismiss: () -> Void

    // -------------------------------------------------------------------------
    // MARK: - Mode
    // -------------------------------------------------------------------------

    /// On-chain rule identifier when the screen was entered in edit mode.
    /// `nil` means the screen runs in create mode.
    public let editRuleId: UInt32?

    internal var isEditing: Bool { editRuleId != nil }

    // -------------------------------------------------------------------------
    // MARK: - Flow
    // -------------------------------------------------------------------------

    @State internal var flow: ContextRuleFlow?

    // -------------------------------------------------------------------------
    // MARK: - Rule configuration state
    // -------------------------------------------------------------------------

    @State internal var ruleName: String = ""
    @State internal var contextTypeOption: ContextTypeOption = .defaultRule
    @State internal var contractAddress: String = ""
    @State internal var wasmHashHex: String = ""
    @State internal var hasExpiry: Bool = false
    @State internal var expiryLedger: String = ""

    // -------------------------------------------------------------------------
    // MARK: - Signers and policies state
    // -------------------------------------------------------------------------

    @State internal var signers: [any SmartAccountSignerProtocol] = []
    @State internal var policies: [StagedPolicy] = []
    @State internal var signerWeights: [String: String] = [:]

    // -------------------------------------------------------------------------
    // MARK: - Spending-limit decimals state
    // -------------------------------------------------------------------------

    /// Decimal scale used when converting a spending-limit amount to base units.
    ///
    /// Resolved from the guarded token (the call-contract target): native XLM
    /// and non-token rules use ``nativeTokenDecimals``; a custom guarded token's
    /// own `decimals()` value is fetched and stored here. The spending-limit
    /// forms read this value so the conversion matches the token's scale.
    @State internal var spendingLimitDecimals: Int = nativeTokenDecimals

    /// Set when the token-decimals fetch for the guarded token fails. While
    /// non-nil the spending-limit "Add" button is disabled and the error is
    /// shown, so an amount is never converted with the wrong scale.
    @State internal var spendingLimitDecimalsError: String?

    // -------------------------------------------------------------------------
    // MARK: - Submission state
    // -------------------------------------------------------------------------

    @State internal var fieldErrors: [String: String] = [:]
    @State internal var errorMessage: String?
    @State internal var isSubmitting: Bool = false
    @State internal var submissionResult: ContextRuleResult?
    @State internal var snackbarMessage: SnackbarMessage?

    // -------------------------------------------------------------------------
    // MARK: - Scroll-into-view state
    // -------------------------------------------------------------------------

    /// Row identity to scroll into the visible area. Set when content appears
    /// outside the viewport (a failure/edit-result card, or a newly staged
    /// signer/policy row, whose list renders above the add controls); the
    /// scroll handler consumes and resets it.
    @State internal var scrollTarget: String?

    /// Anchor identity of the create-mode failure card row.
    internal static let failureCardAnchor = "context-rule-failure-card"

    /// Anchor identity of the edit-mode result card row.
    internal static let editResultCardAnchor = "context-rule-edit-result-card"

    /// Anchor identity of the general error banner row near the top of the
    /// form. Pre-submit rejections (field validation, empty edit diff) scroll
    /// here rather than to the first field error, so a user with several
    /// validation errors starts from the summary and scans down through all
    /// of them.
    internal static let errorBannerAnchor = "context-rule-error-banner"

    /// Gates the staged-row scroll triggers to genuine user staging actions.
    /// The signer/policy collections are also rewritten wholesale by the
    /// edit-mode initial load and by the post-failure on-chain reload; both
    /// run while one of these flags is set and must not move the viewport.
    internal var stagingScrollEnabled: Bool {
        !isSubmitting && !editSubmitting && !isLoadingRule
    }

    // -------------------------------------------------------------------------
    // MARK: - Multi-signer state
    // -------------------------------------------------------------------------

    @State internal var createAvailableSigners: [TransferSignerInfo] = []
    @State internal var createSignersLoaded: Bool = false
    @State internal var showCreateSignerPicker: Bool = false

    // -------------------------------------------------------------------------
    // MARK: - Edit-mode state
    // -------------------------------------------------------------------------

    @State internal var signerEntries: [EditSignerEntry] = []
    @State internal var originalSignerEntries: [EditSignerEntry] = []
    @State internal var policyEntries: [EditPolicyEntry] = []
    @State internal var originalPolicyEntries: [EditPolicyEntry] = []
    @State internal var originalName: String = ""
    @State internal var existingExpiryLedger: UInt32?
    @State internal var expiryModified: Bool = false
    @State internal var allOnChainSigners: [any SmartAccountSignerProtocol] = []
    @State internal var isLoadingRule: Bool = false
    @State internal var editResult: ContextRuleEditResult?
    @State internal var editProgressMessage: String = ""
    @State internal var editSubmitting: Bool = false
    @State internal var showEditSignerPicker: Bool = false

    // -------------------------------------------------------------------------
    // MARK: - Computed
    // -------------------------------------------------------------------------

    internal var createdSuccessfully: Bool {
        submissionResult?.success == true
    }

    /// Full-success edit run (excludes partial-due-to-auth-guard, which keeps
    /// the form visible so the user can retry the skipped operations).
    internal var editFullySucceeded: Bool {
        guard let editResult else { return false }
        return editResult.success && !editResult.partialDueToAuthGuard
    }

    internal var submitEnabled: Bool {
        if isEditing {
            let diff = currentEditDiff
            return demoState.isConnected &&
                !isSubmitting &&
                !ruleName.trimmingCharacters(in: .whitespaces).isEmpty &&
                !editFullySucceeded &&
                !(diff?.isEmpty ?? true)
        }
        return demoState.isConnected &&
            !isSubmitting &&
            !ruleName.trimmingCharacters(in: .whitespaces).isEmpty &&
            !signers.isEmpty &&
            !createdSuccessfully
    }

    /// Diff between the original on-chain state and the current edit form.
    ///
    /// Recomputed on every read from the current `@State` form values; pure
    /// function call, no caching layer. The diff is small (signer / policy
    /// counts are bounded by `OZSmartAccountConstants.maxSigners` / `maxPolicies`), so
    /// re-running the diff on each body evaluation is cheap. `nil` in create mode.
    internal var currentEditDiff: ContextRuleEditDiff? {
        guard let editRuleId else { return nil }
        return computeEditDiff(ruleId: editRuleId)
    }

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    public init(editRuleId: UInt32? = nil, onDismiss: @escaping () -> Void) {
        self.editRuleId = editRuleId
        self.onDismiss = onDismiss
    }

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    public var body: some View {
        ScrollViewReader { proxy in
            formContainer
                .task { @MainActor in
                    if flow == nil { _ = resolvedFlow() }
                }
                .task { await loadAvailableSigners() }
                .task(id: editRuleId) { await loadRuleIfNeeded() }
                .task(id: spendingLimitGuardedToken) { await resolveSpendingLimitDecimals() }
                .sheet(isPresented: $showCreateSignerPicker) {
                    signerPickerSheet
                }
                .sheet(isPresented: $showEditSignerPicker) {
                    editSignerPickerSheet
                }
                .snackbar($snackbarMessage)
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    // Deferred one runloop so a row inserted in the same state
                    // transaction is laid out before the scroll runs.
                    Task { @MainActor in
                        withAnimation { proxy.scrollTo(target, anchor: .center) }
                        scrollTarget = nil
                    }
                }
                .onChange(of: submissionResult) { _, result in
                    if let result, !result.success {
                        scrollTarget = Self.failureCardAnchor
                    }
                }
                .onChange(of: editSubmitting) { wasSubmitting, isSubmittingNow in
                    if wasSubmitting, !isSubmittingNow, editResult != nil, !editFullySucceeded {
                        scrollTarget = Self.editResultCardAnchor
                    }
                }
                .onChange(of: signers.count) { oldCount, newCount in
                    if stagingScrollEnabled, newCount > oldCount {
                        scrollTarget = SignerManagementSection.stagedSignersCaptionAnchor
                    }
                }
                .onChange(of: policies.count) { oldCount, newCount in
                    if stagingScrollEnabled, newCount > oldCount, let added = policies.last {
                        scrollTarget = added.id
                    }
                }
                .onChange(of: signerEntries.count) { oldCount, newCount in
                    if stagingScrollEnabled, newCount > oldCount {
                        scrollTarget = SignerManagementSection.stagedSignersCaptionAnchor
                    }
                }
                .onChange(of: policyEntries.count) { oldCount, newCount in
                    if stagingScrollEnabled, newCount > oldCount, let added = policyEntries.last {
                        scrollTarget = added.address
                    }
                }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Form container
    // -------------------------------------------------------------------------

    @ViewBuilder
    private var formContainer: some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            Form {
                contentBody
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color.brandScaffold)
            .scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            Form {
                contentBody
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color.brandScaffold)
        }
        #elseif os(macOS)
        Form {
            contentBody
        }
        .formStyle(.grouped)
        #else
        Form {
            contentBody
        }
        #endif
    }

    @ViewBuilder
    private var contentBody: some View {
        if !demoState.isConnected {
            notConnectedSection
        } else if isLoadingRule {
            loadingRuleSection
        } else if let result = submissionResult, result.success {
            successResultSection(result: result)
        } else if editFullySucceeded, let result = editResult {
            editResultSection(result: result, terminal: true)
        } else {
            mainForm
        }
    }

    private var loadingRuleSection: some View {
        Section {
            HStack(spacing: Tokens.iconLabelSpacing) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.accentColor)
                Text("Loading rule...")
                    .font(Typography.secondary)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Self.loadingRowVerticalPadding)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Loading rule")
            .modifier(AccessibilityAnnouncementModifier(text: "Loading rule..."))
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Main form
    // -------------------------------------------------------------------------

    @ViewBuilder
    private var mainForm: some View {
        descriptionSection
        errorBannerSection
        failureSectionIfNeeded
        editResultSectionIfNeeded
        ruleNameSection
        contextTypeSection
        expirySection
        signerSection
        policySection
        if isEditing {
            editOperationSummarySection
        }
        submitSection
    }

    @ViewBuilder
    private var errorBannerSection: some View {
        if let msg = errorMessage {
            Section {
                InlineErrorText(msg)
                    .id(Self.errorBannerAnchor)
            }
        }
    }

    @ViewBuilder
    private var failureSectionIfNeeded: some View {
        if let result = submissionResult, !result.success {
            failureSection(result: result)
        }
    }

    @ViewBuilder
    private var editResultSectionIfNeeded: some View {
        if isEditing, let result = editResult, !editFullySucceeded {
            editResultSection(result: result, terminal: false)
        }
    }

    /// Inline progress + submit button section. Keeps create-mode and
    /// edit-mode feedback in the same slot:
    /// - Create mode: a single status caption with a leading spinner above
    ///   the submit button.
    /// - Edit mode: the per-step progress card driven by ``editProgressMessage``.
    private var submitSection: some View {
        Section {
            if isEditing {
                editProgressRow
            } else if isSubmitting {
                createProgressRow
            }
            submitButton
                .listRowInsets(EdgeInsets(
                    top: Self.actionRowVerticalPadding,
                    leading: Self.actionRowHorizontalPadding,
                    bottom: Self.actionRowVerticalPadding,
                    trailing: Self.actionRowHorizontalPadding
                ))
        }
    }

    @ViewBuilder
    private var createProgressRow: some View {
        HStack(spacing: Tokens.iconLabelSpacing) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.8)
            Text("Transaction in progress...")
                .font(Typography.secondary)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Transaction in progress")
        .modifier(AccessibilityAnnouncementModifier(text: "Transaction in progress"))
    }

    @ViewBuilder
    private var signerSection: some View {
        if let flow {
            SignerManagementSection(
                signers: $signers,
                signerWeights: $signerWeights,
                fieldErrors: $fieldErrors,
                isSubmitting: isSubmitting,
                flow: flow,
                connectedCredentialId: demoState.credentialId,
                ed25519VerifierAddress: DemoConfig.ed25519VerifierAddress,
                isEditing: isEditing,
                existingSigners: allOnChainSigners,
                signerEntries: signerEntries,
                onAddEntry: { entry in appendSignerEntry(entry) },
                onRemoveEntry: { index in removeSignerEntry(at: index) },
                walletConnector: demoState.walletConnector
            )
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        }
    }

    private var policySection: some View {
        PolicyManagementSection(
            policies: $policies,
            signerWeights: $signerWeights,
            fieldErrors: $fieldErrors,
            signers: effectiveSigners,
            isSubmitting: isSubmitting,
            spendingLimitDecimals: spendingLimitDecimals,
            spendingLimitDecimalsError: spendingLimitDecimalsError,
            isEditing: isEditing,
            policyEntries: policyEntries,
            onAddEntry: { entry in appendPolicyEntry(entry) },
            onRemoveEntry: { index in removePolicyEntry(at: index) },
            onUpdateEntry: { index, updated in updatePolicyEntry(at: index, with: updated) }
        )
    }

    private var effectiveSigners: [any SmartAccountSignerProtocol] {
        isEditing ? signerEntries.map(\.signer) : signers
    }

    // -------------------------------------------------------------------------
    // MARK: - Static sections
    // -------------------------------------------------------------------------

    private var notConnectedSection: some View {
        // active-flow guard section with heading and description, not an empty list state
        Section {
            VStack(alignment: .leading, spacing: Self.descriptionSpacing) {
                Text("No wallet connected")
                    .font(Typography.sectionHeader)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                Text("Connect a wallet to create or edit context rules.")
                    .font(Typography.secondary)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "No wallet connected. Connect a wallet to create or edit context rules."
            )
        }
    }

    private var descriptionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Self.descriptionSpacing) {
                Text("Rule Configuration")
                    .font(Typography.sectionHeader)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                Text("Define the context type and basic settings for this rule.")
                    .font(Typography.secondary)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Rule name
    // -------------------------------------------------------------------------

    private var ruleNameSection: some View {
        Section {
            TextField("e.g., DefaultRule, TokenTransfers", text: $ruleName)
                .font(Typography.mono)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .accessibilityLabel("Rule Name")
                .onChange(of: ruleName) { _, _ in
                    fieldErrors.removeValue(forKey: "ruleName")
                }
            FieldErrorText(error: fieldErrors["ruleName"])
        } header: {
            Text("Rule Name")
                .font(Typography.sectionHeader)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Flow resolution
    // -------------------------------------------------------------------------

    @MainActor
    internal func resolvedFlow() -> ContextRuleFlow {
        if let existing = flow { return existing }
        let newFlow = DemoFlowFactory.makeContextRuleBuilderFlow(
            demoState: demoState,
            activityLog: activityLog
        )
        flow = newFlow
        return newFlow
    }

    @MainActor
    internal func loadAvailableSigners() async {
        guard demoState.isConnected else { return }
        createAvailableSigners = await resolvedFlow().loadAvailableSigners()
        createSignersLoaded = true
    }

    // -------------------------------------------------------------------------
    // MARK: - Local layout constants
    // -------------------------------------------------------------------------

    /// Vertical spacing between the heading and the body copy in a leading
    /// status section (description, not-connected, etc.).
    private static let descriptionSpacing: CGFloat = 6

    /// Vertical padding applied to the loading section so the spinner stack
    /// reads as a distinct surface inside its grouped section.
    private static let loadingRowVerticalPadding: CGFloat = 12

    /// Vertical padding applied to action rows (submit) inside their
    /// list section so the button's stroke is not clipped by the row's default
    /// separator inset.
    internal static let actionRowVerticalPadding: CGFloat = 8

    /// Horizontal padding applied to action rows (submit) so they align with
    /// the grouped section's content area on both platforms.
    internal static let actionRowHorizontalPadding: CGFloat = 16
}
