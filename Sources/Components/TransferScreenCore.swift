// TransferScreenCore.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

// swiftlint:disable file_length
import SwiftUI

// ============================================================================
// MARK: - TransferScreenCore
// ============================================================================

/// Shared body for the token transfer screen, hosted by the iOS and macOS shells.
///
/// Contains all form state, validation, flow orchestration, and sub-views that
/// are identical across platforms. Platform-specific concerns - title presentation,
/// dismiss behaviour, and token picker style - are delegated to the hosting shell
/// via parameters.
///
/// Hosted inside a native `Form { Section }` container so each surface reads as
/// a grouped row with the platform's inset chrome.
///
/// All SDK interactions are delegated to `TransferFlow`. This view never calls
/// SDK types directly.
public struct TransferScreenCore<TokenPickerContent: View & Sendable>: View { // swiftlint:disable:this type_body_length

    // -------------------------------------------------------------------------
    // MARK: - Environment
    // -------------------------------------------------------------------------

    @EnvironmentObject private var demoState: DemoState
    @EnvironmentObject private var activityLog: ActivityLogState

    // -------------------------------------------------------------------------
    // MARK: - Platform callbacks
    // -------------------------------------------------------------------------

    /// Called when the "Go Back" or "Done" action should navigate away from the screen.
    private let onDismiss: () -> Void

    /// Platform-specific token picker view (iOS uses `Menu`, macOS uses `Picker(.menu)`).
    private let tokenPickerContent: (
        _ selectedToken: Binding<TokenOption>,
        _ isDisabled: Bool,
        _ onTokenChange: @escaping () -> Void,
        _ demoTokenAvailable: Bool
    ) -> TokenPickerContent

    // -------------------------------------------------------------------------
    // MARK: - Flow
    // -------------------------------------------------------------------------

    @State private var flow: TransferFlow?

    // -------------------------------------------------------------------------
    // MARK: - Form state
    // -------------------------------------------------------------------------

    @State private var selectedToken: TokenOption = .xlm
    @State private var recipient: String = ""
    @State private var amount: String = ""

    // -------------------------------------------------------------------------
    // MARK: - Signer state
    // -------------------------------------------------------------------------

    @State private var availableSigners: [TransferSignerInfo] = []
    @State private var signersLoaded: Bool = false

    // -------------------------------------------------------------------------
    // MARK: - Operation state
    // -------------------------------------------------------------------------

    @State private var errorMessage: String?
    @State private var transferResult: TransferResult?

    // -------------------------------------------------------------------------
    // MARK: - Sheet state
    // -------------------------------------------------------------------------

    @State private var showSignerPicker: Bool = false

    // -------------------------------------------------------------------------
    // MARK: - Continuation for multi-signer picker flow
    // -------------------------------------------------------------------------

    /// Suspends `handleTransferTap` while the signer-picker is in progress, so
    /// `LoadingButton` stays in its loading state across the entire picker →
    /// execute arc.
    ///
    /// Resumed exactly once per `handleTransferTap` invocation — on picker cancel,
    /// or after `executeTransfer` resolves.
    @State private var pickerContinuation: CheckedContinuation<Void, Never>?

    // -------------------------------------------------------------------------
    // MARK: - Toast state
    // -------------------------------------------------------------------------

    @State private var snackbarMessage: SnackbarMessage?

    // -------------------------------------------------------------------------
    // MARK: - Derived
    // -------------------------------------------------------------------------

    private var tokenContract: String {
        switch selectedToken {
        case .xlm: return DemoConfig.nativeTokenContract
        case .demo: return demoState.demoTokenContractId ?? ""
        }
    }

    private var recipientError: String? {
        validateRecipient(recipient)
    }

    private var amountError: String? {
        validateAmount(amount)
    }

    private var isFormValid: Bool {
        !recipient.trimmingCharacters(in: .whitespaces).isEmpty &&
        !amount.trimmingCharacters(in: .whitespaces).isEmpty &&
        recipientError == nil &&
        amountError == nil &&
        (selectedToken == .xlm || demoState.demoTokenContractId != nil)
    }

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates a `TransferScreenCore`.
    ///
    /// - Parameters:
    ///   - onDismiss: Closure invoked when the screen should navigate away.
    ///   - tokenPickerContent: Platform-provided token picker view builder.
    public init(
        onDismiss: @escaping () -> Void,
        @ViewBuilder tokenPickerContent: @escaping (
            _ selectedToken: Binding<TokenOption>,
            _ isDisabled: Bool,
            _ onTokenChange: @escaping () -> Void,
            _ demoTokenAvailable: Bool
        ) -> TokenPickerContent
    ) {
        self.onDismiss = onDismiss
        self.tokenPickerContent = tokenPickerContent
    }

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    public var body: some View {
        formContainer
            .task { await loadSigners() }
            .sheet(isPresented: $showSignerPicker) {
                signerPickerSheet
            }
            .snackbar($snackbarMessage)
    }

    // -------------------------------------------------------------------------
    // MARK: - Form container
    // -------------------------------------------------------------------------
    // A native `Form` with `.formStyle(.grouped)` supplies the platform's
    // grouped section chrome on both iOS and macOS.

    @ViewBuilder
    private var formContainer: some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            Form {
                sectionContents
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color.brandScaffold)
            .scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            Form {
                sectionContents
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color.brandScaffold)
        }
        #elseif os(macOS)
        Form {
            sectionContents
        }
        .formStyle(.grouped)
        #else
        Form {
            sectionContents
        }
        #endif
    }

    @ViewBuilder
    private var sectionContents: some View {
        if !demoState.isConnected || demoState.kit == nil {
            notConnectedSection
            notConnectedActionSection
        } else if let result = transferResult {
            descriptionSection
            resultSection(result: result)
        } else {
            descriptionSection
            balanceSection
            tokenSection
            recipientSection
            amountSection

            if let error = errorMessage {
                errorSection(message: error)
            }

            transferActionSection
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Not-connected guard
    // -------------------------------------------------------------------------

    private var notConnectedSection: some View {
        // active-flow error banner, not an empty-state; styled as an error banner with a Go Back action
        Section {
            HStack(alignment: .top, spacing: Tokens.iconLabelSpacing) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(Color.semanticError)
                    .accessibilityHidden(true)
                Text("No wallet connected. Please connect a wallet first.")
                    .font(Typography.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("No wallet connected. Please connect a wallet first.")
        }
    }

    private var notConnectedActionSection: some View {
        Section {
            notConnectedGoBackButton
                .listRowInsets(EdgeInsets(
                    top: TransferScreenLayout.actionRowVerticalPadding,
                    leading: TransferScreenLayout.actionRowHorizontalPadding,
                    bottom: TransferScreenLayout.actionRowVerticalPadding,
                    trailing: TransferScreenLayout.actionRowHorizontalPadding
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
            VStack(alignment: .leading, spacing: TransferScreenLayout.descriptionSpacing) {
                Text("Token Transfer")
                    .font(Typography.sectionHeader)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                Text(
                    "Send tokens from your smart account to another Stellar address. " +
                    "This requires passkey authentication to sign the transaction."
                )
                .font(Typography.secondary)
                .foregroundStyle(.secondary)
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Balance section
    // -------------------------------------------------------------------------

    private var balanceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: TransferScreenLayout.balanceRowSpacing) {
                let xlmValue = demoState.xlmBalance ?? "0.0"
                Text("\(xlmValue) XLM")
                    .font(Typography.mono)
                    .fontWeight(.bold)
                    .accessibilityLabel("Balance: \(xlmValue) XLM")

                let demoValue = demoState.demoTokenBalance ?? "0.0"
                Text("\(demoValue) DEMO")
                    .font(Typography.mono)
                    .fontWeight(.bold)
                    .accessibilityLabel("DEMO balance: \(demoValue)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } header: {
            Text("Balance")
                .font(Typography.sectionHeader)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Token section
    // -------------------------------------------------------------------------

    private var tokenSection: some View {
        Section {
            tokenPickerContent(
                $selectedToken,
                transferResult != nil,
                { errorMessage = nil },
                demoState.demoTokenContractId != nil
            )
        } header: {
            Text("Token")
                .font(Typography.sectionHeader)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Recipient section
    // -------------------------------------------------------------------------

    private var recipientSection: some View {
        Section {
            TextField("G... or C... address", text: $recipient)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                #endif
                .accessibilityLabel("Recipient Address")
                .accessibilityValue(recipient.isEmpty ? "empty" : recipient)
                .onChange(of: recipient) { _, _ in errorMessage = nil }
                .disabled(transferResult != nil)
        } header: {
            Text("Recipient Address")
                .font(Typography.sectionHeader)
                .accessibilityAddTraits(.isHeader)
        } footer: {
            recipientFooter
        }
    }

    @ViewBuilder
    private var recipientFooter: some View {
        if let error = recipientError {
            FieldErrorText(error: error)
        } else if recipient.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("Stellar account (G...) or contract (C...) address")
                .font(Typography.metadata)
                .foregroundStyle(.tertiary)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Amount section
    // -------------------------------------------------------------------------

    private var amountSection: some View {
        Section {
            TextField("e.g. 10.0", text: $amount)
                #if os(iOS)
                .keyboardType(.decimalPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                #endif
                .accessibilityLabel("Amount")
                .accessibilityValue(amount.isEmpty ? "empty" : amount)
                .onChange(of: amount) { _, _ in errorMessage = nil }
                .disabled(transferResult != nil)
        } header: {
            Text("Amount")
                .font(Typography.sectionHeader)
                .accessibilityAddTraits(.isHeader)
        } footer: {
            amountFooter
        }
    }

    @ViewBuilder
    private var amountFooter: some View {
        if let error = amountError {
            FieldErrorText(error: error)
        } else if amount.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("Amount to transfer")
                .font(Typography.metadata)
                .foregroundStyle(.tertiary)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Error section
    // -------------------------------------------------------------------------

    private func errorSection(message: String) -> some View {
        Section {
            HStack(alignment: .top, spacing: Tokens.iconLabelSpacing) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.semanticError)
                    .accessibilityHidden(true)
                Text(message)
                    .font(Typography.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Error: \(message)")
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Transfer action section
    // -------------------------------------------------------------------------

    private var transferActionSection: some View {
        Section {
            transferActionButton
                .disabled(!isFormValid || transferResult != nil || demoState.kit == nil || !signersLoaded)
                .listRowInsets(EdgeInsets(
                    top: TransferScreenLayout.actionRowVerticalPadding,
                    leading: TransferScreenLayout.actionRowHorizontalPadding,
                    bottom: TransferScreenLayout.actionRowVerticalPadding,
                    trailing: TransferScreenLayout.actionRowHorizontalPadding
                ))
        } footer: {
            transferActionFooter
        }
    }

    @ViewBuilder
    private var transferActionFooter: some View {
        if !signersLoaded {
            Text("Loading signers...")
                .font(Typography.metadata)
                .foregroundStyle(.tertiary)
        }
    }

    private var transferActionButton: some View {
        let button = LoadingButton(
            "Transfer",
            loadingLabel: "Transferring..."
        ) {
            await handleTransferTap()
        } onError: { error in
            handleTransferError(error)
        }
        #if os(macOS)
        return button.keyboardShortcut(.defaultAction)
        #else
        return button
        #endif
    }

    // -------------------------------------------------------------------------
    // MARK: - Result section
    // -------------------------------------------------------------------------

    private func resultSection(result: TransferResult) -> some View {
        Section {
            TransferResultCard(
                result: result,
                snackbarMessage: $snackbarMessage,
                onNewTransfer: resetForm,
                onGoToMain: onDismiss
            )
            .listRowInsets(EdgeInsets(
                top: TransferScreenLayout.resultRowVerticalPadding,
                leading: TransferScreenLayout.resultRowHorizontalPadding,
                bottom: TransferScreenLayout.resultRowVerticalPadding,
                trailing: TransferScreenLayout.resultRowHorizontalPadding
            ))
            .listRowBackground(Color.clear)
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
            description: "Choose which signers co-authorize this transfer. " +
                         "Enter a secret key or connect a wallet to enable signing for a Stellar account signer.",
            onCancel: {
                showSignerPicker = false
                // User dismissed the picker without choosing — resume so
                // LoadingButton returns to its enabled idle state.
                resumePickerContinuation()
            },
            onConfirm: { chosenSigners, delegatedSecrets, ed25519Secrets in
                showSignerPicker = false
                // Execute the transfer immediately and resume the continuation
                // once it completes so the button returns to idle only after
                // the RPC round-trip finishes.
                Task {
                    await executeTransfer(
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

    private func handleTransferTap() async {
        // Defensive guard: if a previous continuation was somehow left unresumed
        // (e.g. rapid taps while the sheet was being dismissed), resume it now
        // so the old task does not leak before we start a new flow.
        resumePickerContinuation()

        errorMessage = nil
        if shouldUseSingleSignerFastPath {
            await executeSingleSignerTransfer()
        } else {
            // Suspend here so LoadingButton stays in its loading state across
            // the entire picker → execute arc. The continuation is resumed
            // exactly once:
            //   - picker cancelled → resumePickerContinuation() in onCancel
            //   - picker confirmed → resumePickerContinuation() after executeTransfer
            await withCheckedContinuation { continuation in
                pickerContinuation = continuation
                showSignerPicker = true
            }
        }
    }

    /// Whether the single-signer fast path can be used to submit the transfer
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

    private func executeSingleSignerTransfer() async {
        do {
            let result = try await resolvedFlow().transfer(
                tokenContract: tokenContract,
                recipient: recipient.trimmingCharacters(in: .whitespaces),
                amount: amount.trimmingCharacters(in: .whitespaces),
                tokenLabel: selectedToken.tokenLabel
            )
            transferResult = result
        } catch {
            handleTransferError(error)
        }
    }

    @MainActor
    private func executeTransfer(
        chosenSigners: [any SmartAccountSignerProtocol],
        delegatedSecrets: [String: String],
        ed25519Secrets: [Ed25519SecretKey: Data] = [:]
    ) async {
        errorMessage = nil
        let theFlow = resolvedFlow()
        if theFlow.isSinglePasskeyTransfer(chosenSigners) {
            await executeSingleSignerTransfer()
        } else {
            do {
                let result = try await theFlow.multiSignerTransfer(
                    tokenContract: tokenContract,
                    recipient: recipient.trimmingCharacters(in: .whitespaces),
                    amount: amount.trimmingCharacters(in: .whitespaces),
                    tokenLabel: selectedToken.tokenLabel,
                    chosenSigners: chosenSigners,
                    delegatedSecrets: delegatedSecrets,
                    ed25519Secrets: ed25519Secrets
                )
                transferResult = result
            } catch {
                handleTransferError(error)
            }
        }
    }

    @MainActor
    private func handleTransferError(_ error: Error) {
        if isUserCancellation(error) {
            let message = "Passkey authentication cancelled"
            errorMessage = message
            activityLog.info(message)
            postAccessibilityAnnouncement(message)
        } else {
            let msg = ActivityLogState.redact(actionableMessage(for: error))
            let banner = "Transfer failed: \(msg)"
            errorMessage = banner
            activityLog.error(msg)
            postAccessibilityAnnouncement(banner)
        }
    }

    private func resetForm() {
        recipient = ""
        amount = ""
        selectedToken = .xlm
        errorMessage = nil
        transferResult = nil
    }

    // -------------------------------------------------------------------------
    // MARK: - Validation
    // -------------------------------------------------------------------------

    private func validateRecipient(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.isValidEd25519PublicKey() && !isValidContractAddress(trimmed) {
            return "Must be a valid Stellar account (G...) or contract (C...) address"
        }
        if trimmed == demoState.contractId {
            return "Cannot transfer to your own account"
        }
        return nil
    }

    private func validateAmount(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().contains("e") {
            return "Scientific notation is not supported"
        }
        // Normalise the decimal separator to a dot before parsing so that
        // users on comma-decimal-separator locales (e.g. de_DE) who type "10,5"
        // get the same result as en_US_POSIX users who type "10.5".
        let normalised = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let parsed = Decimal(string: normalised) else {
            return "Must be a valid number"
        }
        if parsed <= 0 {
            return "Must be greater than zero"
        }
        return nil
    }

    // -------------------------------------------------------------------------
    // MARK: - Flow resolution
    // -------------------------------------------------------------------------

    @MainActor
    private func resolvedFlow() -> TransferFlow {
        if let existing = flow { return existing }
        let newFlow = DemoFlowFactory.makeTransferFlow(
            demoState: demoState,
            activityLog: activityLog
        )
        flow = newFlow
        return newFlow
    }

}

// ============================================================================
// MARK: - TransferScreenLayout
// ============================================================================

/// Layout constants for `TransferScreenCore`. Lifted to a file-level namespace
/// because `TransferScreenCore` is generic over its token-picker view type, and
/// Swift does not permit static stored properties inside a generic type.
private enum TransferScreenLayout {

    /// Vertical spacing between the heading and the body copy in the
    /// description section at the top of the screen.
    static let descriptionSpacing: CGFloat = 6

    /// Vertical spacing between the two balance readout lines inside the
    /// balance section.
    static let balanceRowSpacing: CGFloat = 6

    /// Vertical padding applied to action rows (Go Back, Transfer) inside
    /// their grouped sections so the button's stroke is not clipped by the
    /// row's default separator inset.
    static let actionRowVerticalPadding: CGFloat = 8

    /// Horizontal padding applied to action rows (Go Back, Transfer) so they
    /// align with the grouped section's content area on both platforms.
    static let actionRowHorizontalPadding: CGFloat = 16

    /// Vertical padding applied to the result-card row inside its section so
    /// the rich-content card surface breathes inside the grouped list chrome.
    static let resultRowVerticalPadding: CGFloat = 4

    /// Horizontal padding applied to the result-card row so the card aligns
    /// with the surrounding content area on both platforms.
    static let resultRowHorizontalPadding: CGFloat = 0
}

// ============================================================================
// MARK: - TokenOption
// ============================================================================

/// Token options available in the transfer form.
///
/// Shared by `TransferScreenCore` and its platform shells for the token picker.
public enum TokenOption: String, CaseIterable {

    /// XLM native token via Stellar Asset Contract.
    case xlm

    /// Demo token deployed by `DemoTokenService`.
    case demo

    /// Label shown in the token picker UI.
    public var displayLabel: String {
        switch self {
        case .xlm: return "XLM (Native)"
        case .demo: return "Demo Token (DEMO)"
        }
    }

    /// Short token symbol shown in transfer summaries and result cards.
    public var tokenLabel: String {
        switch self {
        case .xlm: return "XLM"
        case .demo: return "DEMO"
        }
    }
}
