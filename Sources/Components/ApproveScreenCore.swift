// ApproveScreenCore.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

// swiftlint:disable file_length
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// ============================================================================
// MARK: - ApproveExpirationOption
// ============================================================================

/// Allowance expiration choices exposed in the expiration dropdown.
///
/// Each value carries the ledger-offset that is added to the network's
/// current ledger to produce the absolute `expiration_ledger` argument
/// passed to the token contract's `approve(...)` function.
public enum ApproveExpirationOption: CaseIterable, Sendable {
    case oneDay
    case tenDays
    case thirtyDays

    /// Human-readable label shown in the dropdown.
    public var displayLabel: String {
        switch self {
        case .oneDay: return "1 day"
        case .tenDays: return "10 days"
        case .thirtyDays: return "30 days"
        }
    }

    /// Number of ledgers from "now" used to compute the absolute expiration.
    public var ledgerOffset: UInt32 {
        switch self {
        case .oneDay: return UInt32(StellarProtocol.ledgersPerDay)
        case .tenDays: return UInt32(StellarProtocol.ledgersPerDay * 10)
        case .thirtyDays: return UInt32(StellarProtocol.ledgersPerDay * 30)
        }
    }
}

// ============================================================================
// MARK: - ApproveScreenCore
// ============================================================================

/// Shared body for the token-allowance approve screen, hosted by the iOS and
/// macOS shells.
///
/// Contains the form state, validation, flow orchestration, and sub-views
/// that are identical across platforms. Platform-specific concerns — title
/// presentation and dismiss behaviour — are delegated to the hosting shell
/// via parameters.
///
/// The screen is hosted by a native `Form { Section }` container because it
/// is a heterogeneous entry shape (description, balance, three input rows,
/// optional error banner, primary CTA, and a rich success surface). The
/// success card and any conditional error banner retain the rounded
/// `sectionCard()` chrome so they read as distinct presentation surfaces
/// inside the grouped form, matching the treatment used elsewhere for
/// terminal result content.
///
/// All SDK interactions are delegated to `ApproveFlow`. This view never
/// calls SDK types directly.
public struct ApproveScreenCore: View { // swiftlint:disable:this type_body_length

    // -------------------------------------------------------------------------
    // MARK: - Environment
    // -------------------------------------------------------------------------

    @EnvironmentObject private var demoState: DemoState
    @EnvironmentObject private var activityLog: ActivityLogState

    // -------------------------------------------------------------------------
    // MARK: - Flow
    // -------------------------------------------------------------------------

    @State private var flow: ApproveFlow?
    @State private var ledgerSource: (any LatestLedgerSource)?

    // -------------------------------------------------------------------------
    // MARK: - Form state
    // -------------------------------------------------------------------------

    @State private var spender: String = ""
    @State private var amount: String = ""
    @State private var expiration: ApproveExpirationOption = .oneDay

    // -------------------------------------------------------------------------
    // MARK: - Signer state
    // -------------------------------------------------------------------------

    @State private var availableSigners: [TransferSignerInfo] = []
    @State private var signersLoaded: Bool = false
    @State private var showSignerPicker: Bool = false

    // -------------------------------------------------------------------------
    // MARK: - Continuation for multi-signer picker flow
    // -------------------------------------------------------------------------

    /// Suspends `handleApproveTap` while the signer-picker is in progress, so
    /// `LoadingButton` stays in its loading state across the entire picker →
    /// execute arc.
    ///
    /// Resumed exactly once per `handleApproveTap` invocation — on picker
    /// cancel or after the final `executeAfterPicker` call resolves.
    @State private var pickerContinuation: CheckedContinuation<Void, Never>?

    // -------------------------------------------------------------------------
    // MARK: - Operation state
    // -------------------------------------------------------------------------

    @State private var errorMessage: String?
    @State private var approveResult: ApproveResult?
    @State private var resultAmount: String = ""
    @State private var resultSpender: String = ""
    @State private var allowanceText: String?
    @State private var allowanceLoading: Bool = false
    /// Background allowance-read task launched after a successful approval.
    ///
    /// Held in `@State` so the screen can cancel the work when it is dismissed
    /// before completion or when the user taps "New Approve" to reset the form.
    @State private var allowanceTask: Task<Void, Never>?

    // -------------------------------------------------------------------------
    // MARK: - Focus
    // -------------------------------------------------------------------------

    /// Posted with `UIAccessibility.post(.screenChanged, ...)` after the user
    /// taps "New Approve" so VoiceOver moves focus back to the top of the
    /// form. The accessibility announcement is the shipped focus-restore
    /// mechanism because the spender row is hosted inside a `Form` and the
    /// `@FocusState` binding for the native `TextField` lives at row scope.
    @State private var resetFocusRequest: UUID = UUID()

    // -------------------------------------------------------------------------
    // MARK: - Toast state
    // -------------------------------------------------------------------------

    @State private var snackbarMessage: SnackbarMessage?

    // -------------------------------------------------------------------------
    // MARK: - Derived
    // -------------------------------------------------------------------------

    private var tokenContract: String? { demoState.demoTokenContractId }

    private var spenderError: String? { validateSpender(spender) }
    private var amountError: String? { validateAmount(amount) }

    private var isFormValid: Bool {
        !spender.trimmingCharacters(in: .whitespaces).isEmpty &&
        !amount.trimmingCharacters(in: .whitespaces).isEmpty &&
        spenderError == nil &&
        amountError == nil &&
        demoState.demoTokenContractId != nil
    }

    // -------------------------------------------------------------------------
    // MARK: - Platform callbacks
    // -------------------------------------------------------------------------

    /// Called when the user taps "Go Back" (not-connected) or "Go to Main
    /// Screen" (success card). The hosting shell dismisses the screen.
    private let onDismiss: () -> Void

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates an `ApproveScreenCore`.
    ///
    /// - Parameter onDismiss: Closure invoked when the screen should navigate away.
    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    public var body: some View {
        formContainer
            .task { await loadSigners() }
            .onDisappear {
                allowanceTask?.cancel()
                allowanceTask = nil
            }
            .sheet(isPresented: $showSignerPicker) {
                signerPickerSheet
            }
            .snackbar($snackbarMessage)
    }

    // -------------------------------------------------------------------------
    // MARK: - Form container
    // -------------------------------------------------------------------------
    // Hosted by a native `Form { Section }`; the scaffold-coloured background
    // tints the form on iOS so the grouped sections read against the same
    // scaffold tone as the rest of the app.

    @ViewBuilder
    private var formContainer: some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            Form {
                sectionContents
            }
            .scrollContentBackground(.hidden)
            .background(Color.brandScaffold)
            .scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            Form {
                sectionContents
            }
            .scrollContentBackground(.hidden)
            .background(Color.brandScaffold)
        }
        #else
        Form {
            sectionContents
        }
        .formStyle(.grouped)
        #endif
    }

    @ViewBuilder
    private var sectionContents: some View {
        if !demoState.isConnected || demoState.kit == nil {
            notConnectedSection
            notConnectedActionSection
        } else {
            descriptionSection
            balanceSection

            if approveResult == nil {
                formInputSection

                if let error = errorMessage {
                    errorSection(message: error)
                }

                approveActionSection
            } else if let result = approveResult, result.success {
                successSection(hash: result.hash ?? "")
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Not-connected guard
    // -------------------------------------------------------------------------

    private var notConnectedSection: some View {
        // active-flow error banner, not an empty-state; styled as an error card with a Go Back action
        Section {
            Text("No wallet connected. Please connect a wallet first.")
                .font(Typography.body)
                .foregroundStyle(Color.onErrorContainer)
                .frame(maxWidth: .infinity, alignment: .leading)
                .sectionCard(style: .error)
                .listRowInsets(EdgeInsets(
                    top: Self.cardRowVerticalPadding,
                    leading: Self.cardRowHorizontalPadding,
                    bottom: Self.cardRowVerticalPadding,
                    trailing: Self.cardRowHorizontalPadding
                ))
                .listRowBackground(Color.clear)
        }
    }

    private var notConnectedActionSection: some View {
        Section {
            notConnectedGoBackButton
                .listRowInsets(EdgeInsets(
                    top: Self.actionRowVerticalPadding,
                    leading: Self.actionRowHorizontalPadding,
                    bottom: Self.actionRowVerticalPadding,
                    trailing: Self.actionRowHorizontalPadding
                ))
        }
    }

    private var notConnectedGoBackButton: some View {
        let button = LoadingButton("Go Back") {
            await MainActor.run { onDismiss() }
        }
        #if os(macOS)
        return button.keyboardShortcut(.defaultAction)
        #else
        return button
        #endif
    }

    // -------------------------------------------------------------------------
    // MARK: - Description section
    // -------------------------------------------------------------------------

    private var descriptionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Self.descriptionSpacing) {
                Text("Token Allowance")
                    .font(Typography.sectionHeader)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                Text(
                    "Approve a token spending allowance for another address. " +
                    "The spender can transfer up to the approved amount from your " +
                    "smart account until the allowance expires."
                )
                .font(Typography.secondary)
                .foregroundStyle(.secondary)

                tokenContractRow
            }
        }
    }

    /// Inline "Token Contract" row rendered inside the description section.
    @ViewBuilder
    private var tokenContractRow: some View {
        VStack(alignment: .leading, spacing: Self.metadataLabelSpacing) {
            Text("Token Contract")
                .font(Typography.metadata)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            if let contract = tokenContract {
                Text("DEMO (\(contract))")
                    .font(Typography.metadata.monospaced())
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .accessibilityLabel("Token contract: DEMO, \(contract)")
            } else {
                Text("DEMO token not deployed")
                    .font(Typography.secondary)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Token contract: DEMO token not deployed")
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Balance section
    // -------------------------------------------------------------------------

    private var balanceSection: some View {
        Section {
            LabeledContent {
                HStack(spacing: Tokens.iconLabelSpacing) {
                    Image(systemName: "creditcard.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(Typography.secondary)
                        .accessibilityHidden(true)

                    Text("\(demoState.demoTokenBalance ?? "0.0") DEMO")
                        .font(Typography.secondary)
                        .fontWeight(.bold)
                }
                .accessibilityLabel("DEMO balance: \(demoState.demoTokenBalance ?? "0.0")")
            } label: {
                Text("DEMO Balance")
                    .font(Typography.metadata)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Form input section
    // -------------------------------------------------------------------------

    @ViewBuilder
    private var formInputSection: some View {
        Section {
            spenderRow
            amountRow
            expirationRow
        } header: {
            Text("Allowance Details")
                .font(Typography.sectionHeader)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Spender row
    // -------------------------------------------------------------------------

    private var spenderRow: some View {
        VStack(alignment: .leading, spacing: Self.fieldRowSpacing) {
            Text("Spender Address")
                .font(Typography.metadata)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            TextField("G... or C...", text: $spender, axis: .vertical)
                .lineLimit(Self.spenderLineLimit, reservesSpace: false)
                .textFieldStyle(.plain)
                .font(Typography.body.monospaced())
                .accessibilityLabel("Spender Address")
                .accessibilityIdentifier(Self.spenderFieldIdentifier)
                .disabled(approveResult != nil)
                .onChange(of: spender) { _, _ in errorMessage = nil }
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                #endif

            FieldErrorText(error: spenderError)

            if spender.trimmingCharacters(in: .whitespaces).isEmpty && spenderError == nil {
                Text("Address to grant the allowance to")
                    .font(Typography.metadata)
                    .foregroundStyle(.tertiary)
            }
        }
        .id(resetFocusRequest)
    }

    // -------------------------------------------------------------------------
    // MARK: - Amount row
    // -------------------------------------------------------------------------

    private var amountRow: some View {
        VStack(alignment: .leading, spacing: Self.fieldRowSpacing) {
            Text("Amount")
                .font(Typography.metadata)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            TextField("e.g. 10.0", text: $amount)
                .textFieldStyle(.plain)
                .font(Typography.body.monospacedDigit())
                .accessibilityLabel("Amount")
                .disabled(approveResult != nil)
                .onChange(of: amount) { _, _ in errorMessage = nil }
                #if os(iOS)
                .keyboardType(.decimalPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                #endif

            FieldErrorText(error: amountError)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Expiration row
    // -------------------------------------------------------------------------

    private var expirationRow: some View {
        Picker(selection: $expiration) {
            ForEach(ApproveExpirationOption.allCases, id: \.displayLabel) { option in
                Text(option.displayLabel).tag(option)
            }
        } label: {
            Text("Expiration")
                .font(Typography.body)
        }
        #if os(iOS)
        .pickerStyle(.menu)
        #else
        .pickerStyle(.menu)
        #endif
        .disabled(approveResult != nil)
        .accessibilityLabel("Expiration: \(expiration.displayLabel)")
    }

    // -------------------------------------------------------------------------
    // MARK: - Error section
    // -------------------------------------------------------------------------

    private func errorSection(message: String) -> some View {
        Section {
            Text(message)
                .font(Typography.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .sectionCard(style: .warning)
                .accessibilityLabel("Error: \(message)")
                .listRowInsets(EdgeInsets(
                    top: Self.cardRowVerticalPadding,
                    leading: Self.cardRowHorizontalPadding,
                    bottom: Self.cardRowVerticalPadding,
                    trailing: Self.cardRowHorizontalPadding
                ))
                .listRowBackground(Color.clear)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Approve action section
    // -------------------------------------------------------------------------

    private var approveActionSection: some View {
        Section {
            VStack(spacing: Self.actionStackSpacing) {
                approveActionButton
                    .disabled(
                        !isFormValid ||
                        approveResult != nil ||
                        demoState.kit == nil ||
                        !signersLoaded
                    )
                    .accessibilityHint(
                        isFormValid && signersLoaded
                            ? "Submits the allowance approval."
                            : "Disabled until the form is valid."
                    )

                if !signersLoaded {
                    Text("Loading signers...")
                        .font(Typography.metadata)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .listRowInsets(EdgeInsets(
                top: Self.actionRowVerticalPadding,
                leading: Self.actionRowHorizontalPadding,
                bottom: Self.actionRowVerticalPadding,
                trailing: Self.actionRowHorizontalPadding
            ))
        }
    }

    private var approveActionButton: some View {
        let button = LoadingButton(
            "Approve",
            loadingLabel: "Approving..."
        ) {
            await handleApproveTap()
        } onError: { error in
            handleApproveError(error)
        }
        #if os(macOS)
        return button.keyboardShortcut(.defaultAction)
        #else
        return button
        #endif
    }

    // -------------------------------------------------------------------------
    // MARK: - Success section
    // -------------------------------------------------------------------------

    private func successSection(hash: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Self.successCardSpacing) {
                approveSuccessHeader
                Divider()
                ResultField(label: "Transaction Hash", value: hash) {
                    snackbarMessage = SnackbarMessage("Transaction hash copied")
                }
                Divider()
                resultRow(label: "Amount Approved", value: "\(resultAmount) DEMO")
                Divider()
                resultRow(label: "Spender", value: resultSpender, monospaced: true)
                Divider()
                allowanceResultRow
                approveResultButtons
            }
            .padding(Self.successCardPadding)
            .background(Color.accentColor.opacity(Self.successCardBackgroundAlpha))
            .clipShape(RoundedRectangle(cornerRadius: Self.successCardCornerRadius))
            .modifier(AccessibilityAnnouncementModifier(text: "Approve successful"))
            .listRowInsets(EdgeInsets(
                top: Self.cardRowVerticalPadding,
                leading: Self.cardRowHorizontalPadding,
                bottom: Self.cardRowVerticalPadding,
                trailing: Self.cardRowHorizontalPadding
            ))
            .listRowBackground(Color.clear)
        }
    }

    private var approveSuccessHeader: some View {
        HStack(spacing: Self.successHeaderSpacing) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.semanticSuccess)
                .font(Typography.title2)
                .accessibilityHidden(true)
            Text("Approve Successful")
                .font(Typography.sectionHeader)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var approveResultButtons: some View {
        VStack(spacing: Self.successButtonSpacing) {
            Button(action: resetForm) {
                Text("New Approve")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Self.successButtonVerticalPadding)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: Self.successButtonCornerRadius))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New Approve")
            .accessibilityHint("Resets the form for another approval.")

            Button(action: onDismiss) {
                Text("Go to Main Screen")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Self.successButtonVerticalPadding)
                    .background(Color.clear)
                    .foregroundStyle(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: Self.successButtonCornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Self.successButtonCornerRadius)
                            .stroke(Color.accentColor, lineWidth: Self.successButtonStrokeWidth)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Go to Main Screen")
            .accessibilityHint("Returns to the main dashboard.")
        }
        .padding(.top, Self.successButtonStackTopPadding)
    }

    private func resultRow(label: String, value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Self.metadataLabelSpacing) {
            Text(label)
                .font(Typography.metadata)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Group {
                if monospaced {
                    Text(value)
                        .font(.system(.footnote, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(value)
                        .font(.system(.footnote, design: .monospaced))
                        .fontWeight(.bold)
                }
            }
            .accessibilityLabel("\(label): \(value)")
        }
    }

    private var allowanceValueText: String {
        if allowanceLoading {
            return "Loading..."
        }
        if let text = allowanceText {
            return "\(text) DEMO"
        }
        return "Unable to fetch"
    }

    @ViewBuilder
    private var allowanceResultRow: some View {
        let valueText = allowanceValueText
        VStack(alignment: .leading, spacing: Self.metadataLabelSpacing) {
            Text("Current Allowance")
                .font(Typography.metadata)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text(valueText)
                .font(.system(.footnote, design: .monospaced))
                .fontWeight(.bold)
                .accessibilityLabel("Current Allowance: \(valueText)")
        }
        // Live-announce transitions of the allowance row so VoiceOver users
        // hear when the background read replaces "Loading..." with the
        // fetched value (or with "Unable to fetch" on a fetch failure).
        .onChange(of: valueText) { _, newValue in
            postAccessibilityAnnouncement("Current Allowance: \(newValue)")
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Signer picker sheet
    // -------------------------------------------------------------------------

    private var signerPickerSheet: some View {
        SignerPickerSheet(
            availableSigners: availableSigners,
            connectedCredentialId: demoState.credentialId,
            walletConnector: demoState.walletConnector,
            ed25519Available: demoState.isEd25519Available,
            description: "Choose which signers co-authorize this approval. " +
                         "Enter a secret key or connect a wallet to enable signing for a Stellar account signer.",
            confirmLabel: "Approve",
            onCancel: {
                showSignerPicker = false
                // User dismissed the picker without choosing — resume so
                // LoadingButton returns to its enabled idle state.
                resumePickerContinuation()
            },
            onConfirm: { chosenSigners, delegatedSecrets, ed25519Secrets in
                showSignerPicker = false
                // Execute the approve inline and resume the continuation once
                // it completes so the button returns to idle only after the
                // RPC round-trip finishes.
                Task {
                    await executeAfterPicker(
                        chosenSigners: chosenSigners,
                        delegatedSecrets: delegatedSecrets,
                        ed25519Secrets: ed25519Secrets
                    )
                    resumePickerContinuation()
                }
            }
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - Actions
    // -------------------------------------------------------------------------

    private func loadSigners() async {
        availableSigners = await resolvedFlow().loadAvailableSigners()
        signersLoaded = true
    }

    private func handleApproveTap() async {
        // Defensive guard: if a previous continuation was somehow left unresumed
        // (e.g. rapid taps while the sheet was being dismissed), resume it now
        // so the old task does not leak before we start a new flow.
        resumePickerContinuation()

        errorMessage = nil
        if shouldUseSingleSignerFastPath {
            await executeSingleSignerApprove()
        } else {
            // Suspend here so LoadingButton stays in its loading state across
            // the entire picker → execute arc. The continuation is resumed
            // exactly once:
            //   - picker cancelled  → resumePickerContinuation() in onCancel
            //   - picker confirmed  → resumePickerContinuation() after executeAfterPicker
            await withCheckedContinuation { continuation in
                pickerContinuation = continuation
                showSignerPicker = true
            }
        }
    }

    /// Whether the single-signer fast path can be used to submit the approval
    /// without showing the signer picker.
    ///
    /// Eligible when: signers have not yet loaded (the SDK auto-resolves the
    /// signer), there are no signers extracted from context rules (same), or the
    /// only available signer is ready to sign right now. A single signer with
    /// `canSign == false` (e.g. a wallet-backed delegated signer with no active
    /// WalletConnect session) must instead go through the picker so the user
    /// can explicitly connect the wallet — without that interaction, the SDK
    /// rejects submission with "No signer available for address …" because
    /// the external wallet adapter cannot sign for that address.
    private var shouldUseSingleSignerFastPath: Bool {
        if !signersLoaded || availableSigners.isEmpty { return true }
        if availableSigners.count == 1 { return availableSigners[0].canSign }
        return false
    }

    /// Resumes the pending picker continuation, if any, and clears it.
    ///
    /// Safe to call from any context that is already on the main actor (all
    /// call sites are SwiftUI closures or `@MainActor`-annotated functions).
    /// Calling when `pickerContinuation` is `nil` is a no-op.
    private func resumePickerContinuation() {
        pickerContinuation?.resume()
        pickerContinuation = nil
    }

    @MainActor
    private func executeSingleSignerApprove() async {
        guard let tokenContract else {
            errorMessage = "DEMO token contract is not available."
            return
        }
        let trimmedSpender = spender.trimmingCharacters(in: .whitespaces)
        let trimmedAmount = amount.trimmingCharacters(in: .whitespaces)
        activityLog.info(
            "Approving \(trimmedAmount) DEMO for \(spenderPrefix(trimmedSpender))..."
        )
        do {
            let absoluteLedger = try await resolveAbsoluteLedger()
            let result = try await resolvedFlow().approveAllowance(
                tokenContract: tokenContract,
                spenderAddress: trimmedSpender,
                amount: trimmedAmount,
                expirationLedger: absoluteLedger
            )
            await handleApproveOutcome(
                result: result,
                tokenContract: tokenContract,
                spender: trimmedSpender,
                amount: trimmedAmount
            )
        } catch {
            handleApproveError(error)
        }
    }

    @MainActor
    private func executeAfterPicker(
        chosenSigners: [any SmartAccountSignerProtocol],
        delegatedSecrets: [String: String],
        ed25519Secrets: [Ed25519SecretKey: Data] = [:]
    ) async {
        guard let tokenContract else {
            errorMessage = "DEMO token contract is not available."
            return
        }
        let trimmedSpender = spender.trimmingCharacters(in: .whitespaces)
        let trimmedAmount = amount.trimmingCharacters(in: .whitespaces)
        let theFlow = resolvedFlow()
        if theFlow.isSinglePasskeyApproval(chosenSigners) {
            await executeSingleSignerApprove()
            return
        }
        activityLog.info(
            "Multi-signer approve: \(trimmedAmount) DEMO for " +
            "\(spenderPrefix(trimmedSpender))... (\(signerCountLabel(chosenSigners.count)))"
        )
        do {
            let absoluteLedger = try await resolveAbsoluteLedger()
            let result = try await theFlow.multiSignerApproveAllowanceWithChosenSigners(
                tokenContract: tokenContract,
                spenderAddress: trimmedSpender,
                amount: trimmedAmount,
                expirationLedger: absoluteLedger,
                chosenSigners: chosenSigners,
                delegatedSecrets: delegatedSecrets,
                ed25519Secrets: ed25519Secrets
            )
            await handleApproveOutcome(
                result: result,
                tokenContract: tokenContract,
                spender: trimmedSpender,
                amount: trimmedAmount
            )
        } catch {
            handleApproveError(error)
        }
    }

    @MainActor
    private func handleApproveOutcome(
        result: ApproveResult,
        tokenContract: String,
        spender: String,
        amount: String
    ) async {
        if result.success {
            approveResult = result
            resultAmount = amount
            resultSpender = spender
            allowanceLoading = true
            allowanceText = nil
            // Background allowance read — does not block the primary success surface.
            allowanceTask?.cancel()
            let captureTokenContract = tokenContract
            let captureSpender = spender
            let theFlow = resolvedFlow()
            allowanceTask = Task { @MainActor in
                let fetched = await theFlow.fetchAllowance(
                    tokenContract: captureTokenContract,
                    spenderAddress: captureSpender
                )
                guard !Task.isCancelled else { return }
                allowanceText = fetched
                allowanceLoading = false
            }
        } else if let msg = result.error {
            errorMessage = msg
        }
    }

    @MainActor
    private func handleApproveError(_ error: Error) {
        if isUserCancellation(error) {
            let message = "Passkey authentication cancelled"
            errorMessage = message
            activityLog.info(message)
            postAccessibilityAnnouncement(message)
        } else {
            let msg = ActivityLogState.redact(actionableMessage(for: error))
            errorMessage = "Approve failed: \(msg)"
            activityLog.error("Approve failed: \(msg)")
            postAccessibilityAnnouncement("Approve failed: \(msg)")
        }
    }

    private func resetForm() {
        // Cancel any in-flight allowance read so its trailing assignments do
        // not clobber the freshly reset state after the user taps "New
        // Approve".
        allowanceTask?.cancel()
        allowanceTask = nil
        spender = ""
        amount = ""
        expiration = .oneDay
        errorMessage = nil
        approveResult = nil
        resultAmount = ""
        resultSpender = ""
        allowanceText = nil
        allowanceLoading = false
        // Refresh the focus-restore token so the spender field receives
        // VoiceOver focus on the next layout pass.
        resetFocusRequest = UUID()
        postScreenChangedFocus()
    }

    /// Posts an accessibility "screen changed" notification anchoring focus
    /// to the form region after a reset. On iOS this returns VoiceOver
    /// focus to the top of the form (where the spender field sits); on
    /// macOS the equivalent NSAccessibility notification is posted against
    /// the key window so VoiceOver re-reads the visible focus target.
    private func postScreenChangedFocus() {
        #if os(iOS)
        UIAccessibility.post(notification: .screenChanged, argument: nil)
        #elseif os(macOS)
        if let window = NSApp.keyWindow {
            NSAccessibility.post(element: window, notification: .focusedUIElementChanged)
        }
        #endif
    }

    private func spenderPrefix(_ value: String) -> String {
        value.count > 8 ? String(value.prefix(8)) : value
    }

    // -------------------------------------------------------------------------
    // MARK: - Validation
    // -------------------------------------------------------------------------

    private func validateSpender(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.isValidEd25519PublicKey() && !isValidContractAddress(trimmed) {
            return "Must be a valid Stellar account (G...) or contract (C...) address"
        }
        return nil
    }

    private func validateAmount(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().contains("e") {
            return "Scientific notation is not supported"
        }
        // Stellar 7-decimal cap regex.
        let pattern = #"^\d+(\.\d{1,7})?$"#
        if trimmed.range(of: pattern, options: .regularExpression) == nil {
            return "Must be a valid number"
        }
        guard let parsed = Decimal(string: trimmed) else {
            return "Must be a valid number"
        }
        if parsed <= 0 {
            return "Must be greater than zero"
        }
        return nil
    }

    // -------------------------------------------------------------------------
    // MARK: - Ledger resolution
    // -------------------------------------------------------------------------

    /// Resolves the relative expiration ledger offset to an absolute ledger
    /// using the kit's Soroban RPC.
    @MainActor
    private func resolveAbsoluteLedger() async throws -> UInt32 {
        guard demoState.kit != nil else {
            throw WalletError.NotConnected(message: "No wallet connected.")
        }
        let source: any LatestLedgerSource
        if let existing = ledgerSource {
            source = existing
        } else {
            guard let created = DemoFlowFactory.makeLedgerSource(demoState: demoState) else {
                throw WalletError.NotConnected(message: "No wallet connected.")
            }
            ledgerSource = created
            source = created
        }
        let current = try await source.latestLedgerSequence()
        return current &+ expiration.ledgerOffset
    }

    // -------------------------------------------------------------------------
    // MARK: - Flow resolution
    // -------------------------------------------------------------------------

    @MainActor
    private func resolvedFlow() -> ApproveFlow {
        if let existing = flow { return existing }
        let newFlow = DemoFlowFactory.makeApproveFlow(
            demoState: demoState,
            activityLog: activityLog
        )
        flow = newFlow
        return newFlow
    }

    // -------------------------------------------------------------------------
    // MARK: - Local layout constants
    // -------------------------------------------------------------------------

    /// Vertical spacing between the description heading, the body copy, and
    /// the inline token-contract row in the description section.
    private static let descriptionSpacing: CGFloat = 8

    /// Vertical spacing between a metadata caption (e.g. "DEMO Balance",
    /// "Token Contract") and the line of text below it.
    private static let metadataLabelSpacing: CGFloat = 4

    /// Vertical spacing between a field's caption, its `TextField`, and the
    /// `FieldErrorText` / placeholder hint that follows.
    private static let fieldRowSpacing: CGFloat = 6

    /// Maximum number of visual lines reserved by the spender field. Stellar
    /// `C-` addresses are 56 characters and can wrap onto a second line on
    /// narrow iPhone widths; the wrap is permitted but the field collapses
    /// back to its natural height once the entered value fits.
    private static let spenderLineLimit: Int = 2

    /// Accessibility identifier applied to the spender text field so UI
    /// tests can resolve the input deterministically.
    private static let spenderFieldIdentifier: String = "ApproveScreen.SpenderField"

    /// Vertical padding applied to action rows (Approve, Go Back) inside
    /// their grouped sections so the button's stroke is not clipped by the
    /// row's default separator inset.
    private static let actionRowVerticalPadding: CGFloat = 8

    /// Horizontal padding applied to action rows (Approve, Go Back) so they
    /// align with the surrounding grouped section's content area.
    private static let actionRowHorizontalPadding: CGFloat = 16

    /// Vertical padding applied to card-shaped rows (error banner, success
    /// surface, not-connected error) so the rounded card surface clears the
    /// row's default separator inset.
    private static let cardRowVerticalPadding: CGFloat = 8

    /// Horizontal padding applied to card-shaped rows so the rounded card
    /// surface aligns with the grouped section's content area.
    private static let cardRowHorizontalPadding: CGFloat = 16

    /// Vertical spacing between the action button and the supporting
    /// "Loading signers..." caption inside the approve action section.
    private static let actionStackSpacing: CGFloat = 6

    /// Vertical spacing between the stacked elements of the success surface
    /// (header, divider, result rows, action buttons).
    private static let successCardSpacing: CGFloat = 16

    /// Outer padding applied to the success surface so its inner content
    /// clears the rounded background.
    private static let successCardPadding: CGFloat = 16

    /// Alpha applied to the accent-tinted background of the success surface
    /// so the contained content remains legible against the form scaffold.
    private static let successCardBackgroundAlpha: Double = 0.12

    /// Corner radius applied to the success surface so it reads as a
    /// distinct card inside the grouped form.
    private static let successCardCornerRadius: CGFloat = 12

    /// Horizontal spacing between the success-header icon and its title.
    private static let successHeaderSpacing: CGFloat = 10

    /// Vertical spacing between the two stacked buttons in the success
    /// surface ([New Approve] above [Go to Main Screen]).
    private static let successButtonSpacing: CGFloat = 10

    /// Vertical padding applied inside each stacked success button so the
    /// label has comfortable tap height.
    private static let successButtonVerticalPadding: CGFloat = 12

    /// Corner radius applied to each stacked success button.
    private static let successButtonCornerRadius: CGFloat = 10

    /// Stroke width applied to the outlined success button border.
    private static let successButtonStrokeWidth: CGFloat = 1.5

    /// Top padding applied to the stacked success button column so it reads
    /// as a distinct action footer below the result-detail rows.
    private static let successButtonStackTopPadding: CGFloat = 4
}

