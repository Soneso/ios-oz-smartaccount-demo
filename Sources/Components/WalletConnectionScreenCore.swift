// WalletConnectionScreenCore.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

// swiftlint:disable file_length
import SwiftUI

// ============================================================================
// MARK: - WalletConnectionScreenCore
// ============================================================================

/// Shared body for the wallet connection screen, hosted by the iOS and macOS shells.
///
/// Contains all form state, connection logic, pending-credential CRUD, and the
/// ambiguous-picker presentation that are identical across platforms.
/// Platform-specific concerns — navigation chrome, dismiss / navigate-to-main
/// behaviour, and row inset styling — are delegated to the hosting shell via
/// `onDismiss`.
///
/// Layout (four grouped sections inside a native `Form`):
/// - Section A: Auto Connect
/// - Section B: Connect via Indexer
/// - Section C: Connect with Address (live-validated C... input)
/// - Section D: Pending Deployments (conditional; shown when list is non-empty)
///
/// The `ContractPickerSheet` is presented modally when the SDK returns an
/// `.ambiguous` result so the user can select the target contract without
/// re-prompting WebAuthn.
///
/// All SDK interactions are delegated to `WalletConnectionFlow`. This view
/// reads only from observable state objects and calls only into the flow.
public struct WalletConnectionScreenCore: View { // swiftlint:disable:this type_body_length

    // -------------------------------------------------------------------------
    // MARK: - Environment
    // -------------------------------------------------------------------------

    @EnvironmentObject private var demoState: DemoState
    @EnvironmentObject private var activityLog: ActivityLogState

    // -------------------------------------------------------------------------
    // MARK: - Platform callbacks
    // -------------------------------------------------------------------------

    /// Called when a successful connection has been established (sections A–C),
    /// when a pending-credential retry succeeds, or when the platform-specific
    /// "go back / navigate to main" action is required.
    private let onDismiss: () -> Void

    // -------------------------------------------------------------------------
    // MARK: - Flow
    // -------------------------------------------------------------------------

    @State private var flow: WalletConnectionFlow?

    // -------------------------------------------------------------------------
    // MARK: - Connection state
    // -------------------------------------------------------------------------

    /// Which section is currently executing. Nil when idle.
    @State private var activeConnection: ConnectionSection?

    // -------------------------------------------------------------------------
    // MARK: - Inline errors (one per section)
    // -------------------------------------------------------------------------

    @State private var autoError: String?
    @State private var indexerError: String?
    @State private var addressError: String?

    // -------------------------------------------------------------------------
    // MARK: - Section C input
    // -------------------------------------------------------------------------

    @State private var contractAddressInput: String = ""

    // -------------------------------------------------------------------------
    // MARK: - Pending deployments
    // -------------------------------------------------------------------------

    @State private var pendingCredentials: [PendingCredentialInfo] = []

    /// Per-credential inline errors keyed by credential ID.
    @State private var pendingErrors: [String: String] = [:]

    /// Whether any pending-section action is in-flight. Controls per-card
    /// button disabled state so two cards cannot act simultaneously.
    @State private var isPendingActionActive: Bool = false

    // -------------------------------------------------------------------------
    // MARK: - Ambiguous picker
    // -------------------------------------------------------------------------

    @State private var pickerState: WalletConnectionPickerState?

    // -------------------------------------------------------------------------
    // MARK: - Snackbar
    // -------------------------------------------------------------------------

    @State private var snackbarMessage: SnackbarMessage?

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates a `WalletConnectionScreenCore`.
    ///
    /// - Parameter onDismiss: Closure invoked when the screen should navigate
    ///   away — on successful connection, successful pending retry, or explicit
    ///   cancel on the hosting shell.
    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    public var body: some View {
        formContainer
            .task { await loadPending() }
            .sheet(item: $pickerState) { state in
                pickerSheet(for: state)
            }
            .snackbar($snackbarMessage)
    }

    // -------------------------------------------------------------------------
    // MARK: - Form container
    // -------------------------------------------------------------------------

    @ViewBuilder
    private var formContainer: some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            Form { formSections }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .background(Color.brandScaffold)
                .scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            Form { formSections }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .background(Color.brandScaffold)
        }
        #elseif os(macOS)
        Form { formSections }
            .formStyle(.grouped)
        #else
        Form { formSections }
        #endif
    }

    @ViewBuilder
    private var formSections: some View {
        sectionA
        sectionB
        sectionC
        if !pendingCredentials.isEmpty {
            sectionD
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Section A: Auto Connect
    // -------------------------------------------------------------------------

    private var sectionA: some View {
        Section {
            Text(
                "Restores the last connected session if available. " +
                "If no session exists, triggers passkey authentication " +
                "and tries to resolve the contract address automatically via indexer."
            )
            .font(Typography.body)
            .foregroundStyle(.secondary)

            LoadingButton("Auto Connect", loadingLabel: "Connecting...") {
                try await launchAutoConnect()
            } onError: { error in
                handleConnectionError(error) { autoError = $0 }
            }
            .disabled(buttonsDisabled(section: .auto))
            .accessibilityHint(disabledHint(section: .auto))
            #if os(iOS)
            .listRowInsets(Self.actionRowInsets)
            #endif

            if let error = autoError {
                inlineErrorBanner(message: error)
            }
        } header: {
            Text("Auto Connect")
                .font(Typography.sectionHeader)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Section B: Connect via Indexer
    // -------------------------------------------------------------------------

    private var sectionB: some View {
        Section {
            Text(
                "Authenticates with a passkey, then uses the indexer service " +
                "to look up the smart account contract associated with that credential."
            )
            .font(Typography.body)
            .foregroundStyle(.secondary)

            LoadingButton("Connect via Indexer", loadingLabel: "Connecting...") {
                try await launchIndexerConnect()
            } onError: { error in
                handleConnectionError(error) { indexerError = $0 }
            }
            .disabled(buttonsDisabled(section: .indexer))
            .accessibilityHint(disabledHint(section: .indexer))
            #if os(iOS)
            .listRowInsets(Self.actionRowInsets)
            #endif

            if let error = indexerError {
                inlineErrorBanner(message: error)
            }
        } header: {
            Text("Connect via Indexer")
                .font(Typography.sectionHeader)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Section C: Connect with Address
    // -------------------------------------------------------------------------

    /// Live validation message rendered under the C-address input as the user
    /// types. Stays nil while the input is empty so the user is not greeted
    /// with red on first focus; surfaces the format hint once any text has been
    /// entered that does not satisfy the C-address shape.
    private var liveAddressFieldError: String? {
        let trimmed = contractAddressInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if isValidContractAddress(trimmed) { return nil }
        return "Must be a valid Stellar contract address (C...)"
    }

    private var sectionC: some View {
        Section {
            Text(
                "Connect to a smart account using a known contract address. " +
                "Authenticates with a passkey that is registered as a signer on the contract. " +
                "Use this to reconnect with a recovery signer."
            )
            .font(Typography.body)
            .foregroundStyle(.secondary)

            TextField("C...", text: $contractAddressInput)
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                #endif
                .autocorrectionDisabled(true)
                .accessibilityLabel("Contract Address")
                .onChange(of: contractAddressInput) { _ in
                    addressError = nil
                }
                .disabled(activeConnection != nil)

            LoadingButton("Connect", loadingLabel: "Connecting...") {
                try await launchAddressConnect()
            } onError: { error in
                handleConnectionError(error) { addressError = $0 }
            }
            .disabled(buttonsDisabled(section: .address) || !isValidContractAddress(contractAddressInput))
            .accessibilityHint(disabledHint(section: .address))
            #if os(iOS)
            .listRowInsets(Self.actionRowInsets)
            #elseif os(macOS)
            .keyboardShortcut(.defaultAction)
            #endif

            if let error = addressError {
                inlineErrorBanner(message: error)
            }
        } header: {
            Text("Connect with Address")
                .font(Typography.sectionHeader)
                .accessibilityAddTraits(.isHeader)
        } footer: {
            FieldErrorText(error: liveAddressFieldError)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Section D: Pending Deployments
    // -------------------------------------------------------------------------

    private var sectionD: some View {
        Section {
            Text(
                "These credentials were registered but contract deployment " +
                "may not have completed. Retry the deployment or delete the credential."
            )
            .font(Typography.body)
            .foregroundStyle(.secondary)

            ForEach(pendingCredentials, id: \.credentialId) { credential in
                PendingCredentialCard(
                    credential: credential,
                    inlineError: pendingErrors[credential.credentialId],
                    isAnyActionActive: isPendingActionActive,
                    onRetry: { await handlePendingRetry(credential: credential) },
                    onDelete: { await handlePendingDelete(credential: credential) }
                )
                #if os(iOS)
                .listRowInsets(Self.cardRowInsets)
                .listRowBackground(Color.clear)
                #endif
            }
        } header: {
            Text("Pending Deployments (\(pendingCredentials.count))")
                .font(Typography.sectionHeader)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Inline error banner
    // -------------------------------------------------------------------------

    /// Renders an `InlineErrorBanner` with platform-appropriate row insets.
    ///
    /// On iOS the banner row uses explicit insets to align with the grouped
    /// section content area. On macOS the default row chrome is sufficient.
    @ViewBuilder
    private func inlineErrorBanner(message: String) -> some View {
        #if os(iOS)
        InlineErrorBanner(message: message)
            .listRowInsets(Self.bannerRowInsets)
            .listRowBackground(Color.clear)
        #else
        InlineErrorBanner(message: message)
        #endif
    }

    // -------------------------------------------------------------------------
    // MARK: - Picker sheet
    // -------------------------------------------------------------------------

    @ViewBuilder
    private func pickerSheet(for state: WalletConnectionPickerState) -> some View {
        let sheet = ContractPickerSheet(
            candidates: state.candidates,
            onDismiss: {
                pickerState = nil
            },
            onConnect: { chosen in
                pickerState = nil
                launchFinalize(
                    credentialId: state.credentialId,
                    contractAddress: chosen,
                    originatingSection: state.originatingSection
                )
            }
        )
        #if os(iOS)
        sheet.presentationDetents([.medium, .large])
        #else
        sheet
        #endif
    }

    // -------------------------------------------------------------------------
    // MARK: - Launch helpers
    // -------------------------------------------------------------------------

    @MainActor
    private func launchAutoConnect() async throws {
        clearErrors()
        activeConnection = .auto
        defer { activeConnection = nil }
        let result = try await resolvedFlow().autoConnect()
        handleResult(result, from: .auto, noResultError: "No wallet found for this passkey") { autoError = $0 }
    }

    @MainActor
    private func launchIndexerConnect() async throws {
        clearErrors()
        activeConnection = .indexer
        defer { activeConnection = nil }
        let result = try await resolvedFlow().connectViaIndexer()
        handleResult(result, from: .indexer, noResultError: "No contract found for this credential") {
            indexerError = $0
        }
    }

    @MainActor
    private func launchAddressConnect() async throws {
        clearErrors()
        activeConnection = .address
        defer { activeConnection = nil }
        let result = try await resolvedFlow().connectWithAddress(
            contractAddress: contractAddressInput.trimmingCharacters(in: .whitespaces)
        )
        handleResult(
            result,
            from: .address,
            noResultError: "Could not connect to the provided contract address"
        ) { addressError = $0 }
    }

    @MainActor
    private func launchFinalize(
        credentialId: String,
        contractAddress: String,
        originatingSection: ConnectionSection
    ) {
        clearErrors()
        activeConnection = originatingSection
        let setError = errorForSection(originatingSection)
        Task {
            defer { activeConnection = nil }
            do {
                let result = try await resolvedFlow().finalizeAmbiguous(
                    credentialId: credentialId,
                    contractAddress: contractAddress
                )
                handleResult(
                    result,
                    from: originatingSection,
                    noResultError: "Could not connect to the selected wallet"
                ) { setError($0) }
            } catch {
                handleConnectionError(error) { setError($0) }
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Pending actions
    // -------------------------------------------------------------------------

    @MainActor
    private func handlePendingRetry(credential: PendingCredentialInfo) async {
        isPendingActionActive = true
        pendingErrors.removeValue(forKey: credential.credentialId)
        defer { isPendingActionActive = false }
        do {
            _ = try await resolvedFlow().retryPendingDeploy(credentialId: credential.credentialId)
            await loadPending()
            onDismiss()
        } catch {
            let message = ActivityLogState.redact(actionableMessage(for: error))
            pendingErrors[credential.credentialId] = message
            activityLog.error("Retry failed: \(message)")
        }
    }

    @MainActor
    private func handlePendingDelete(credential: PendingCredentialInfo) async {
        isPendingActionActive = true
        pendingErrors.removeValue(forKey: credential.credentialId)
        defer { isPendingActionActive = false }
        let success = await resolvedFlow().deletePendingCredential(credentialId: credential.credentialId)
        if success {
            await loadPending()
        } else {
            pendingErrors[credential.credentialId] = "Delete failed. Please try again."
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Result handling
    // -------------------------------------------------------------------------

    private func handleResult(
        _ result: ConnectionResult?,
        from section: ConnectionSection,
        noResultError: String,
        _ setError: (String) -> Void
    ) {
        switch result {
        case .connected:
            onDismiss()
        case .ambiguous(let credentialId, let candidates):
            pickerState = WalletConnectionPickerState(
                credentialId: credentialId,
                candidates: candidates,
                originatingSection: section
            )
        case nil:
            setError(noResultError)
        }
    }

    private func handleConnectionError(_ error: Error, _ setError: (String) -> Void) {
        if isUserCancellation(error) {
            activityLog.info("Passkey authentication cancelled")
        } else {
            let redacted = ActivityLogState.redact(actionableMessage(for: error))
            setError(redacted)
            activityLog.error("Connection failed: \(redacted)")
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Pending list loader
    // -------------------------------------------------------------------------

    private func loadPending() async {
        do {
            pendingCredentials = try await resolvedFlow().loadPendingCredentials()
        } catch {
            let message = ActivityLogState.redact(actionableMessage(for: error))
            activityLog.error("Failed to load pending credentials: \(message)")
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Guards
    // -------------------------------------------------------------------------

    private func buttonsDisabled(section: ConnectionSection) -> Bool {
        guard demoState.kit != nil else { return true }
        return activeConnection.map { $0 != section } ?? false
    }

    private func clearErrors() {
        autoError = nil
        indexerError = nil
        addressError = nil
    }

    // -------------------------------------------------------------------------
    // MARK: - Error routing
    // -------------------------------------------------------------------------

    private func errorForSection(_ section: ConnectionSection) -> (String) -> Void {
        switch section {
        case .auto:    return { autoError = $0 }
        case .indexer: return { indexerError = $0 }
        case .address: return { addressError = $0 }
        case .pending: return { _ in }
        }
    }

    private func disabledHint(section: ConnectionSection) -> String {
        guard demoState.kit != nil else { return "Kit not initialized yet." }
        guard let active = activeConnection, active != section else { return "" }
        return "Disabled, another connection in progress."
    }

    // -------------------------------------------------------------------------
    // MARK: - Flow resolution
    // -------------------------------------------------------------------------

    @MainActor
    private func resolvedFlow() -> WalletConnectionFlow {
        if let existing = flow { return existing }
        let newFlow = DemoFlowFactory.makeWalletConnectionFlow(
            demoState: demoState,
            activityLog: activityLog
        )
        flow = newFlow
        return newFlow
    }

    // -------------------------------------------------------------------------
    // MARK: - iOS row-inset constants
    // -------------------------------------------------------------------------

    #if os(iOS)
    /// Row insets applied to the primary CTA inside each connection section so
    /// the button's filled background reaches the grouped section's content
    /// inset without being clipped by the default row separator gutter.
    private static let actionRowInsets: EdgeInsets = EdgeInsets(
        top: Self.actionRowVerticalPadding,
        leading: Self.actionRowHorizontalPadding,
        bottom: Self.actionRowVerticalPadding,
        trailing: Self.actionRowHorizontalPadding
    )

    /// Row insets applied to inline error banners so the rounded banner fills
    /// the section width consistently with the action row above.
    private static let bannerRowInsets: EdgeInsets = EdgeInsets(
        top: Self.bannerRowVerticalPadding,
        leading: Self.actionRowHorizontalPadding,
        bottom: Self.bannerRowVerticalPadding,
        trailing: Self.actionRowHorizontalPadding
    )

    /// Row insets applied to pending-credential cards so each card draws its
    /// own rounded surface flush with the grouped section content area.
    private static let cardRowInsets: EdgeInsets = EdgeInsets(
        top: Self.cardRowVerticalPadding,
        leading: Self.actionRowHorizontalPadding,
        bottom: Self.cardRowVerticalPadding,
        trailing: Self.actionRowHorizontalPadding
    )

    private static let actionRowVerticalPadding: CGFloat = 8
    private static let actionRowHorizontalPadding: CGFloat = 16
    private static let bannerRowVerticalPadding: CGFloat = 4
    private static let cardRowVerticalPadding: CGFloat = 6
    #endif
}

// ============================================================================
// MARK: - WalletConnectionPickerState
// ============================================================================

/// Drives the `ContractPickerSheet` presentation from `WalletConnectionScreenCore`.
///
/// `Identifiable` so it can be used with `.sheet(item:)` directly. Carries the
/// originating section so that spinner and inline errors are routed back to the
/// correct card when the picker resolves.
public struct WalletConnectionPickerState: Identifiable {
    public let id: UUID = UUID()
    let credentialId: String
    let candidates: [String]
    /// The section that produced the `.ambiguous` result.
    let originatingSection: ConnectionSection
}
