// DelegateToAgentScreenCore.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - Form option enums
// ============================================================================

/// Spending-limit rolling-window presets, in ledgers.
///
/// One ledger is approximately five seconds on Stellar testnet.
public enum DelegatePeriodOption: CaseIterable, Sendable {
    case oneHour
    case oneDay
    case sevenDays
    case thirtyDays

    /// Human-readable label shown in the dropdown.
    public var label: String {
        switch self {
        case .oneHour: return "Per hour"
        case .oneDay: return "Per day"
        case .sevenDays: return "Per 7 days"
        case .thirtyDays: return "Per 30 days"
        }
    }

    /// Rolling-window length in ledgers.
    public var ledgers: UInt32 {
        switch self {
        case .oneHour: return UInt32(StellarProtocol.ledgersPerHour)
        case .oneDay: return UInt32(StellarProtocol.ledgersPerDay)
        case .sevenDays: return UInt32(StellarProtocol.ledgersPerDay * 7)
        case .thirtyDays: return UInt32(StellarProtocol.ledgersPerDay * 30)
        }
    }
}

/// Rule-expiry (`validUntil`) presets, expressed as a ledger offset from the
/// current ledger.
public enum DelegateExpiryOption: CaseIterable, Sendable {
    case oneDay
    case threeDays
    case sevenDays
    case thirtyDays

    /// Human-readable label shown in the dropdown.
    public var label: String {
        switch self {
        case .oneDay: return "1 day (~24h)"
        case .threeDays: return "3 days"
        case .sevenDays: return "7 days"
        case .thirtyDays: return "30 days"
        }
    }

    /// Ledger offset from "now" at which the rule expires.
    public var offset: UInt32 {
        switch self {
        case .oneDay: return UInt32(StellarProtocol.ledgersPerDay)
        case .threeDays: return UInt32(StellarProtocol.ledgersPerDay * 3)
        case .sevenDays: return UInt32(StellarProtocol.ledgersPerDay * 7)
        case .thirtyDays: return UInt32(StellarProtocol.ledgersPerDay * 30)
        }
    }
}

// ============================================================================
// MARK: - DelegateToAgentScreenCore
// ============================================================================

/// Shared body for the delegate-to-agent screen (step 2 of the agent-signer
/// flow), hosted by the iOS and macOS shells.
///
/// Grants an autonomous agent a scoped, spend-capped, time-bounded authority on
/// the connected smart account by composing ONE `addContextRule` call:
/// `CallContract(token)` scope + an Ed25519 external signer (the agent's pasted
/// public key) + a spending-limit policy + a `validUntil` bound. The agent owns
/// the matching secret; only its public key is entered here.
///
/// All SDK interactions are delegated to ``DelegateToAgentFlow`` (via
/// ``ContextRuleFlow``). This view never calls SDK types directly.
public struct DelegateToAgentScreenCore: View {

    // -------------------------------------------------------------------------
    // MARK: - Environment
    // -------------------------------------------------------------------------

    @EnvironmentObject private var demoState: DemoState
    @EnvironmentObject private var activityLog: ActivityLogState

    // -------------------------------------------------------------------------
    // MARK: - Flow
    // -------------------------------------------------------------------------

    @State private var flow: DelegateToAgentFlow?

    // -------------------------------------------------------------------------
    // MARK: - Form state
    // -------------------------------------------------------------------------

    @State private var agentKey: String = ""
    @State private var tokenContract: String = ""
    @State private var amount: String = ""
    @State private var period: DelegatePeriodOption = .oneDay
    @State private var expiry: DelegateExpiryOption = .oneDay

    @State private var agentKeyError: String?
    @State private var tokenError: String?
    @State private var amountError: String?

    /// Resolved decimal scale of the scoped token; defaults to the demo token's
    /// scale until a custom token's `decimals()` is fetched.
    @State private var tokenDecimals: Int = Int(DemoConfig.demoTokenDecimals)

    /// Set when the `decimals()` fetch for a non-native scoped token fails. While
    /// non-nil the error is shown beneath the token field and the submit button
    /// is disabled, so the spend cap is never encoded at the wrong scale.
    @State private var tokenDecimalsError: String?

    /// Monotonic token guarding against a stale late decimals response
    /// overwriting a newer resolution.
    @State private var decimalsRequestToken: Int = 0

    @State private var tokenPrefilled: Bool = false

    // -------------------------------------------------------------------------
    // MARK: - Operation state
    // -------------------------------------------------------------------------

    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?
    @State private var result: DelegationResult?
    @State private var resultExpiry: DelegateExpiryOption = .oneDay

    /// Screen-level snackbar binding for copy confirmations on the result card.
    @State private var snackbarMessage: SnackbarMessage?

    // -------------------------------------------------------------------------
    // MARK: - Dismiss
    // -------------------------------------------------------------------------

    private let onDone: () -> Void

    /// Creates a `DelegateToAgentScreenCore`.
    ///
    /// - Parameter onDone: Invoked when the user taps "Done" or "Go Back".
    public init(onDone: @escaping () -> Void) {
        self.onDone = onDone
    }

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    public var body: some View {
        Form {
            if !demoState.isConnected {
                notConnectedSection
            } else if let result, result.success {
                resultSection(result)
            } else {
                descriptionSection
                formSection
                if let errorMessage {
                    Section { InlineErrorBanner(message: errorMessage) }
                        .listRowBackground(Color.clear)
                }
                submitSection
            }
        }
        .onAppear { prefillToken() }
        .task(id: tokenContract) { await resolveTokenDecimals() }
        .snackbar($snackbarMessage)
    }

    // -------------------------------------------------------------------------
    // MARK: - Description section
    // -------------------------------------------------------------------------

    private var descriptionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Delegate to an Agent")
                Text(
                    "Register an agent as an Ed25519 external signer in one context rule: " +
                    "scoped to a single token contract, capped by a spending limit, and expiring " +
                    "after a set time. The agent holds its own secret; paste only its public key " +
                    "(64-char hex)."
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
            VStack(alignment: .leading, spacing: 10) {
                Text("No wallet connected. Connect a wallet to delegate to an agent.")
                    .font(Typography.body)
                LoadingButton("Go Back", style: .outlinedNeutral) {
                    await MainActor.run { onDone() }
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Form section
    // -------------------------------------------------------------------------

    private var formSection: some View {
        Section {
            agentKeyField
            tokenField
            amountField
            periodPicker
            expiryPicker
        } header: {
            Text("Delegation").font(Typography.sectionHeader).accessibilityAddTraits(.isHeader)
        }
    }

    private var agentKeyField: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("64 hex characters", text: $agentKey)
                .font(Typography.mono)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .disabled(isSubmitting)
                .accessibilityLabel("Agent Ed25519 Public Key (hex)")
                .onChange(of: agentKey) { _, newValue in
                    agentKeyError = newValue.isEmpty ? nil : resolvedFlow().validateAgentPublicKey(newValue)
                    errorMessage = nil
                }
            if let agentKeyError {
                FieldErrorText(error: agentKeyError)
            } else {
                Text("The agent's Ed25519 public key in hex (printed on its startup line)")
                    .font(Typography.metadata)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var tokenField: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("C...", text: $tokenContract)
                .font(Typography.mono)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .disabled(isSubmitting)
                .accessibilityLabel("Token Contract")
                .onChange(of: tokenContract) { _, newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                    tokenError = trimmed.isEmpty || isValidContractAddress(trimmed)
                        ? nil
                        : "Must be a valid Stellar contract (C...) address"
                    errorMessage = nil
                }
            if let tokenError {
                FieldErrorText(error: tokenError)
            } else {
                Text("The only token the agent may call (defaults to the demo token)")
                    .font(Typography.metadata)
                    .foregroundStyle(.tertiary)
            }
            if let tokenDecimalsError {
                FieldErrorText(error: tokenDecimalsError)
            }
        }
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("e.g. 100.0", text: $amount)
                .font(Typography.mono)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.decimalPad)
                #endif
                .disabled(isSubmitting)
                .accessibilityLabel("Spending Limit")
                .onChange(of: amount) { _, newValue in
                    amountError = newValue.isEmpty ? nil : DelegateToAgentFlow.validateAmount(newValue)
                    errorMessage = nil
                }
            if let amountError {
                FieldErrorText(error: amountError)
            } else {
                Text("Maximum the agent may spend per period")
                    .font(Typography.metadata)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var periodPicker: some View {
        Picker("Spending Limit Period", selection: $period) {
            ForEach(DelegatePeriodOption.allCases, id: \.self) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.menu)
        .disabled(isSubmitting)
    }

    private var expiryPicker: some View {
        Picker("Rule Expires In", selection: $expiry) {
            ForEach(DelegateExpiryOption.allCases, id: \.self) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.menu)
        .disabled(isSubmitting)
    }

    // -------------------------------------------------------------------------
    // MARK: - Submit section
    // -------------------------------------------------------------------------

    private var submitSection: some View {
        Section {
            LoadingButton(
                "Delegate to Agent",
                loadingLabel: "Submitting (requires authorization)...",
                style: .primary
            ) {
                await handleSubmit()
            }
            .disabled(!isFormValid || isSubmitting)
        }
        .listRowBackground(Color.clear)
    }

    // -------------------------------------------------------------------------
    // MARK: - Result section
    // -------------------------------------------------------------------------

    @ViewBuilder
    private func resultSection(_ result: DelegationResult) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Agent Authorised")
                Text(
                    "The agent can now sign calls to the scoped token, up to the spending cap, " +
                    "until the rule expires."
                )
                .font(Typography.secondary)
                .foregroundStyle(.secondary)

                if let summary = result.summary {
                    summaryRows(summary)
                }
                KeyValueRow(label: "Tx Hash") {
                    CopyableValue(
                        value: result.hash ?? "",
                        copyConfirmation: "Transaction hash copied",
                        snackbarMessage: $snackbarMessage
                    )
                }

                LoadingButton("Done", style: .outlinedNeutral) {
                    await MainActor.run { onDone() }
                }
                .padding(.top, 4)
            }
            .sectionCard()
            .accessibilityElement(children: .contain)
        }
        .listRowBackground(Color.clear)
    }

    /// The authorised-delegation rows on the confirmation card.
    ///
    /// Mirrors the cross-platform demo: the agent key, the scoped token contract,
    /// and the transaction hash are copyable so they can be handed to the
    /// reference agent (the token contract is `AGENT_TOKEN_CONTRACT`). The cap
    /// period is rendered from the rule's on-chain `periodLedgers` (via
    /// ``delegatePeriodLabel(forLedgers:)``) rather than the live picker
    /// selection, so the card reflects the rolling window written on-chain.
    @ViewBuilder
    private func summaryRows(_ summary: DelegationSummary) -> some View {
        KeyValueRow(label: "Agent Key") {
            CopyableValue(
                value: summary.agentPublicKey,
                copyConfirmation: "Agent key copied",
                snackbarMessage: $snackbarMessage
            )
        }
        KeyValueRow(label: "Scope", value: "CallContract")
        KeyValueRow(label: "Token Contract") {
            CopyableValue(
                value: summary.tokenContract,
                copyConfirmation: "Token contract address copied",
                snackbarMessage: $snackbarMessage
            )
        }
        Text("Start the reference agent with this token contract (AGENT_TOKEN_CONTRACT).")
            .font(Typography.secondary)
            .foregroundStyle(.secondary)
        KeyValueRow(
            label: "Cap",
            value: "\(summary.amount) \(delegatePeriodLabel(forLedgers: summary.periodLedgers))",
            emphasised: true
        )
        KeyValueRow(
            label: "Expires",
            value: summary.validUntilLedger.map { "Ledger \($0) (\(resultExpiry.label))" } ?? "Never"
        )
        KeyValueRow(
            label: "Verifier",
            value: truncateAddress(summary.verifierAddress),
            monospace: true
        )
        KeyValueRow(
            label: "Policy",
            value: truncateAddress(summary.spendingLimitPolicyAddress),
            monospace: true
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - Validation
    // -------------------------------------------------------------------------

    private var isFormValid: Bool {
        guard !agentKey.trimmingCharacters(in: .whitespaces).isEmpty, agentKeyError == nil else { return false }
        guard !tokenContract.trimmingCharacters(in: .whitespaces).isEmpty, tokenError == nil else { return false }
        guard !amount.trimmingCharacters(in: .whitespaces).isEmpty, amountError == nil else { return false }
        // Fail closed: a non-native scoped token whose `decimals()` could not be
        // resolved blocks submission so the cap is never encoded at the wrong scale.
        guard tokenDecimalsError == nil else { return false }
        return true
    }

    // -------------------------------------------------------------------------
    // MARK: - Actions
    // -------------------------------------------------------------------------

    private func prefillToken() {
        guard !tokenPrefilled else { return }
        tokenPrefilled = true
        if tokenContract.isEmpty {
            tokenContract = demoState.demoTokenContractId
                ?? (try? DemoTokenService.deriveContractAddress())
                ?? DemoConfig.nativeTokenContract
        }
    }

    /// Resolves the scoped token's decimal scale for the cap conversion.
    ///
    /// The native token resolves to ``nativeTokenDecimals`` without a network
    /// call; a custom token's `decimals()` is fetched on-chain. A monotonic token
    /// guards against a stale late response overwriting a newer resolution.
    ///
    /// Fails closed: when a non-native custom token's `decimals()` cannot be
    /// read, ``tokenDecimalsError`` is set (surfaced beneath the token field) and
    /// the previous scale is left unchanged so the disabled submit button never
    /// encodes the cap at the wrong scale. The scale is not silently kept as the
    /// demo token's default for an unresolved custom token.
    private func resolveTokenDecimals() async {
        let token = tokenContract.trimmingCharacters(in: .whitespaces)
        tokenDecimalsError = nil
        guard !token.isEmpty else { return }

        // The native token has a fixed scale; resolve it without a round trip.
        guard token != DemoConfig.nativeTokenContract else {
            tokenDecimals = nativeTokenDecimals
            return
        }

        // A malformed address is already reported by the token field validation,
        // which blocks submit on its own; do not fetch or flag a decimals error
        // for it so a later valid entry re-triggers resolution cleanly.
        guard isValidContractAddress(token) else { return }

        decimalsRequestToken += 1
        let requestToken = decimalsRequestToken
        do {
            let resolved = try await resolvedFlow().resolveTokenDecimals(token)
            guard requestToken == decimalsRequestToken else { return }
            tokenDecimals = resolved
        } catch {
            guard requestToken == decimalsRequestToken else { return }
            let msg = ActivityLogState.redact(actionableMessage(for: error))
            tokenDecimalsError =
                "Could not read token decimals for the scoped contract: \(msg)"
            activityLog.error("Could not read token decimals: \(msg)")
        }
    }

    private func handleSubmit() async {
        let flow = resolvedFlow()
        let keyError = flow.validateAgentPublicKey(agentKey)
        let amtError = DelegateToAgentFlow.validateAmount(amount)
        let trimmedToken = tokenContract.trimmingCharacters(in: .whitespaces)
        let tokError: String? = trimmedToken.isEmpty
            ? "Token contract is required"
            : (isValidContractAddress(trimmedToken) ? nil : "Must be a valid Stellar contract (C...) address")

        if keyError != nil || amtError != nil || tokError != nil {
            agentKeyError = keyError
            amountError = amtError
            tokenError = tokError
            return
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let submitted = await flow.delegateToAgent(
            agentPublicKey: agentKey,
            tokenContract: trimmedToken,
            amount: amount.trimmingCharacters(in: .whitespaces),
            periodLedgers: period.ledgers,
            validUntilOffsetLedgers: expiry.offset,
            tokenDecimals: tokenDecimals
        )

        if submitted.success {
            resultExpiry = expiry
            result = submitted
            postAccessibilityAnnouncement("Agent authorised")
        } else {
            errorMessage = submitted.error ?? "Delegation failed."
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Flow resolution
    // -------------------------------------------------------------------------

    @MainActor
    private func resolvedFlow() -> DelegateToAgentFlow {
        if let flow { return flow }
        let newFlow = DemoFlowFactory.makeDelegateToAgentFlow(
            demoState: demoState,
            activityLog: activityLog
        )
        flow = newFlow
        return newFlow
    }
}

// ============================================================================
// MARK: - Period formatting
// ============================================================================

/// Human-readable spending-cap period derived from a rule's on-chain
/// `periodLedgers` rather than a live picker selection.
///
/// Recognises whole-hour and whole-day windows (covering every delegate preset)
/// and falls back to the raw ledger count for any other value, so the label
/// always reflects the rolling window actually written on-chain.
private func delegatePeriodLabel(forLedgers ledgers: UInt32) -> String {
    let perDay = UInt32(StellarProtocol.ledgersPerDay)
    let perHour = UInt32(StellarProtocol.ledgersPerHour)
    if ledgers >= perDay, ledgers.isMultiple(of: perDay) {
        let days = ledgers / perDay
        return days == 1 ? "per day" : "per \(days) days"
    }
    if ledgers >= perHour, ledgers.isMultiple(of: perHour) {
        let hours = ledgers / perHour
        return hours == 1 ? "per hour" : "per \(hours) hours"
    }
    return "per \(ledgers) ledgers"
}

// ============================================================================
// MARK: - CopyableValue
// ============================================================================

/// A compact, copyable monospace value for the result card: middle-truncated to
/// a single line and paired with a copy button that writes the full value to the
/// clipboard and confirms via the screen snackbar.
private struct CopyableValue: View {

    let value: String
    let copyConfirmation: String
    @Binding var snackbarMessage: SnackbarMessage?

    @Environment(\.clipboard) private var clipboard

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value)
                .font(Typography.body.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .accessibilityLabel(value)
            Button {
                clipboard.copy(value, sensitive: false)
                snackbarMessage = SnackbarMessage(copyConfirmation)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.brandPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy")
            .accessibilityHint(copyConfirmation)
        }
    }
}
