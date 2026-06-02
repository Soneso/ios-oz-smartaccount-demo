// WalletCreationScreenCore.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - WalletCreationScreenCore
// ============================================================================

/// Shared body for the wallet creation screen, hosted by the iOS and macOS shells.
///
/// Contains all form state, validation, flow orchestration, and sub-views that
/// are identical across platforms. Platform-specific concerns — navigation chrome,
/// dismiss / navigate-to-main behaviour, text field styling, and result layout —
/// are handled via `#if os(...)` compile-time guards inside the body, keeping the
/// shell files thin.
///
/// The result surface is platform-split: on iOS it is shown as Form sections
/// in-place; on macOS it is shown in a `ScrollView + LazyVStack` pane that
/// replaces the form.
///
/// All SDK interactions are delegated to `WalletCreationFlow`. This view reads
/// only from observable state objects and calls only into the flow.
public struct WalletCreationScreenCore: View { // swiftlint:disable:this type_body_length

    // -------------------------------------------------------------------------
    // MARK: - Environment
    // -------------------------------------------------------------------------

    @EnvironmentObject private var demoState: DemoState
    @EnvironmentObject private var activityLog: ActivityLogState

    // -------------------------------------------------------------------------
    // MARK: - Platform callbacks
    // -------------------------------------------------------------------------

    /// Called when the screen should navigate away — after "Go to Main Screen"
    /// on the result cards, or on any other platform-specific dismiss action.
    private let onDismiss: () -> Void

    // -------------------------------------------------------------------------
    // MARK: - Form state
    // -------------------------------------------------------------------------

    /// Display name for the new passkey credential.
    @State private var username: String = ""

    /// When `true`, the SDK deploys the contract immediately after passkey
    /// registration.
    @State private var autoSubmit: Bool = true

    /// `true` once the passkey-name field has lost focus at least once. Suppresses
    /// the inline validation footer on first appearance so the user is not greeted
    /// with an error before interacting.
    @State private var usernameTouched: Bool = false

    /// Keyboard focus state for the passkey-name field.
    @FocusState private var usernameFieldFocused: Bool

    // -------------------------------------------------------------------------
    // MARK: - UI state
    // -------------------------------------------------------------------------

    /// `true` while `WalletCreationFlow.createWallet(...)` is executing.
    @State private var isCreating: Bool = false

    /// Short status string shown in the Create Wallet button label while
    /// creation is in progress. `nil` when idle or when no progress message
    /// has been emitted yet (button falls back to its static `loadingLabel`).
    @State private var creationProgress: String? = nil

    /// Inline error message shown below the form for hard failures.
    /// Cleared when the user edits the username or re-taps Create.
    @State private var errorMessage: String?

    /// Neutral info message shown for user-cancellation events (not an error).
    @State private var cancelledMessage: String?

    /// Set on success; drives the result-card branch.
    @State private var createResult: WalletCreationResult?

    /// Screen-level snackbar message for copy confirmations from result cards.
    @State private var snackbarMessage: SnackbarMessage?

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates a `WalletCreationScreenCore`.
    ///
    /// - Parameter onDismiss: Closure invoked when the screen should navigate
    ///   away — on "Go to Main Screen" from any result card, or when the hosting
    ///   shell provides a cancel / back action.
    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    public var body: some View {
        platformBody
            .snackbar($snackbarMessage)
    }

    // -------------------------------------------------------------------------
    // MARK: - Platform body
    // -------------------------------------------------------------------------

    @ViewBuilder
    private var platformBody: some View {
        #if os(iOS)
        iOSFormContainer
        #elseif os(macOS)
        macOSContainer
        #else
        Form { formSections }
        #endif
    }

    // -------------------------------------------------------------------------
    // MARK: - iOS form container
    // -------------------------------------------------------------------------

    #if os(iOS)
    @ViewBuilder
    private var iOSFormContainer: some View {
        if #available(iOS 26.0, *) {
            Form { iOSFormSections }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .background(Color.brandScaffold)
                .scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            Form { iOSFormSections }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .background(Color.brandScaffold)
        }
    }

    @ViewBuilder
    private var iOSFormSections: some View {
        if let result = createResult {
            iOSResultSection(result)
        } else {
            infoSection
            passkeyNameSection
            autoDeploySection
            if let message = errorMessage {
                iOSErrorSection(message: message)
            }
            if let message = cancelledMessage {
                iOSCancelledSection(message: message)
            }
            iOSActionSection
        }
    }
    #endif

    // -------------------------------------------------------------------------
    // MARK: - macOS container
    // -------------------------------------------------------------------------

    #if os(macOS)
    @ViewBuilder
    private var macOSContainer: some View {
        if createResult != nil {
            macOSResultPane
        } else {
            macOSFormPane
        }
    }

    private var macOSFormPane: some View {
        Form {
            infoSection
            passkeyNameSection
            autoDeploySection
            macOSActionSection
            if let message = errorMessage {
                macOSErrorSection(message: message)
            }
            if let message = cancelledMessage {
                macOSCancelledSection(message: message)
            }
        }
        .formStyle(.grouped)
    }
    #endif

    // -------------------------------------------------------------------------
    // MARK: - Shared sections
    // -------------------------------------------------------------------------

    private var infoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Self.descriptionSpacing) {
                Text("Wallet Creation")
                    .font(Typography.sectionHeader)
                    .accessibilityAddTraits(.isHeader)

                Text(
                    "Creating a wallet will register a passkey with your device and deploy a " +
                    "smart account contract to the Stellar network. The passkey is used to " +
                    "authenticate and sign transactions."
                )
                .font(Typography.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var passkeyNameSection: some View {
        Section {
            TextField("Passkey name", text: $username)
                .font(Typography.body)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #elseif os(macOS)
                .textFieldStyle(.roundedBorder)
                #endif
                .autocorrectionDisabled(true)
                #if os(iOS)
                .submitLabel(.done)
                #endif
                .focused($usernameFieldFocused)
                .accessibilityLabel("Passkey name")
                .onChange(of: username) { _, _ in
                    errorMessage = nil
                    cancelledMessage = nil
                }
                .onChange(of: usernameFieldFocused) { _, isFocused in
                    if !isFocused {
                        usernameTouched = true
                    }
                }
        } header: {
            Text("Passkey Name")
                .font(Typography.sectionHeader)
                .accessibilityAddTraits(.isHeader)
        } footer: {
            FieldErrorText(error: usernameFooterError)
        }
        .disabled(isCreating)
    }

    /// Validation message displayed beneath the passkey-name field once the
    /// field has been touched and is still empty. Nil while the user has not
    /// yet interacted with the field, or while the value is non-empty, so the
    /// section renders no footer until the user has had a chance to type.
    private var usernameFooterError: String? {
        guard usernameTouched else { return nil }
        guard username.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return "Username must not be empty."
    }

    private var autoDeploySection: some View {
        Section {
            Toggle(isOn: $autoSubmit) {
                Text("Auto-deploy after passkey registration")
                    .font(Typography.body)
                    .fontWeight(.medium)
            }
            .accessibilityLabel("Auto-deploy after passkey registration")
            .accessibilityHint(
                autoSubmit
                    ? "On. The contract will be deployed immediately after passkey creation."
                    : "Off. The deploy transaction will be prepared but not submitted."
            )
        } footer: {
            #if os(iOS)
            Text(
                "Submit the deployment transaction immediately after passkey " +
                "creation. Disable to deploy later from the Connect Wallet screen."
            )
            .font(Typography.metadata)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
            #endif
        }
        .disabled(isCreating)
    }

    // -------------------------------------------------------------------------
    // MARK: - iOS-specific sections
    // -------------------------------------------------------------------------

    #if os(iOS)
    private var iOSActionSection: some View {
        Section {
            if isCreating {
                ProgressCard(statusText: creationProgress ?? "Creating...")
                    .listRowInsets(EdgeInsets(
                        top: Self.bannerRowVerticalPadding,
                        leading: Self.bannerRowHorizontalPadding,
                        bottom: Self.bannerRowVerticalPadding,
                        trailing: Self.bannerRowHorizontalPadding
                    ))
            } else {
                LoadingButton(
                    "Create Wallet",
                    loadingLabel: "Creating...",
                    progressBinding: $creationProgress
                ) {
                    try await handleCreateWallet()
                } onError: { error in
                    handleCreationError(error)
                }
                .accessibilityLabel("Create Wallet")
                .accessibilityHint("Starts passkey registration and smart account deployment.")
                .listRowInsets(EdgeInsets(
                    top: Self.actionRowVerticalPadding,
                    leading: Self.actionRowHorizontalPadding,
                    bottom: Self.actionRowVerticalPadding,
                    trailing: Self.actionRowHorizontalPadding
                ))
            }
        }
    }

    private func iOSErrorSection(message: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Self.bannerInnerSpacing) {
                HStack(alignment: .top, spacing: Tokens.iconLabelSpacing) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.semanticError)
                        .accessibilityHidden(true)

                    Text(message)
                        .font(Typography.metadata)
                        .foregroundStyle(Color.onErrorContainer)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(
                    "If a passkey was registered before the failure, go to Connect Wallet " +
                    "and check Pending Deployments to retry the deployment."
                )
                .font(Typography.metadata)
                .foregroundStyle(Color.onErrorContainer)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Tokens.insetPadding)
            .background(Color.errorContainer)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.cardRadius))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Error: \(message). If a passkey was registered before the failure, " +
                "go to Connect Wallet and check Pending Deployments to retry the deployment."
            )
            .listRowInsets(EdgeInsets(
                top: Self.bannerRowVerticalPadding,
                leading: Self.bannerRowHorizontalPadding,
                bottom: Self.bannerRowVerticalPadding,
                trailing: Self.bannerRowHorizontalPadding
            ))
        }
    }

    private func iOSCancelledSection(message: String) -> some View {
        Section {
            HStack(alignment: .top, spacing: Tokens.iconLabelSpacing) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text(message)
                    .font(Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Tokens.insetPadding)
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.cardRadius)
                    .stroke(
                        Color.brandOutline.opacity(Self.cancelledBorderAlpha),
                        lineWidth: Self.cancelledBorderWidth
                    )
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Notice: \(message)")
            .listRowInsets(EdgeInsets(
                top: Self.bannerRowVerticalPadding,
                leading: Self.bannerRowHorizontalPadding,
                bottom: Self.bannerRowVerticalPadding,
                trailing: Self.bannerRowHorizontalPadding
            ))
        }
    }

    @ViewBuilder
    private func iOSResultSection(_ result: WalletCreationResult) -> some View {
        Section {
            if result.isDeployed {
                DeployedResultCard(result: result, snackbarMessage: $snackbarMessage) {
                    onDismiss()
                }
            } else {
                UndeployedResultCard(
                    result: result,
                    snackbarMessage: $snackbarMessage,
                    onDeployed: { updated in createResult = updated },
                    onGoToMain: { onDismiss() }
                )
            }
        }
        .listRowInsets(EdgeInsets(
            top: Self.resultRowVerticalPadding,
            leading: Self.resultRowHorizontalPadding,
            bottom: Self.resultRowVerticalPadding,
            trailing: Self.resultRowHorizontalPadding
        ))
        .listRowBackground(Color.clear)
    }
    #endif

    // -------------------------------------------------------------------------
    // MARK: - macOS-specific sections
    // -------------------------------------------------------------------------

    #if os(macOS)
    private var macOSActionSection: some View {
        Section {
            if isCreating {
                ProgressCard(statusText: creationProgress ?? "Creating...")
            } else {
                macOSCreateWalletButton
            }
        }
    }

    /// Primary "Create Wallet" button with `.defaultAction` keyboard shortcut
    /// so Return submits the form from anywhere on the macOS pane.
    private var macOSCreateWalletButton: some View {
        LoadingButton(
            "Create Wallet",
            loadingLabel: "Creating...",
            progressBinding: $creationProgress
        ) {
            try await handleCreateWallet()
        } onError: { error in
            handleCreationError(error)
        }
        .accessibilityLabel("Create Wallet")
        .accessibilityHint("Starts passkey registration and smart account deployment.")
        .keyboardShortcut(.defaultAction)
    }

    private func macOSErrorSection(message: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Self.bannerInnerSpacing) {
                HStack(alignment: .top, spacing: Self.bannerIconSpacing) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.semanticError)
                        .accessibilityHidden(true)
                    Text(message)
                        .font(Typography.metadata)
                        .foregroundStyle(Color.brandOnSurface)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(
                    "If a passkey was registered before the failure, go to Connect Wallet " +
                    "and check Pending Deployments to retry the deployment."
                )
                .font(Typography.metadata)
                .foregroundStyle(Color.brandOnSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Error: \(message). If a passkey was registered before the failure, " +
                "go to Connect Wallet and check Pending Deployments to retry the deployment."
            )
        }
    }

    private func macOSCancelledSection(message: String) -> some View {
        Section {
            HStack(alignment: .top, spacing: Self.bannerIconSpacing) {
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.brandOnSurfaceVariant)
                    .accessibilityHidden(true)
                Text(message)
                    .font(Typography.metadata)
                    .foregroundStyle(Color.brandOnSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Notice: \(message)")
        }
    }

    private var macOSResultPane: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Self.resultPaneSpacing) {
                if let result = createResult {
                    if result.isDeployed {
                        DeployedResultCard(result: result, snackbarMessage: $snackbarMessage) {
                            onDismiss()
                        }
                    } else {
                        UndeployedResultCard(
                            result: result,
                            snackbarMessage: $snackbarMessage,
                            onDeployed: { updated in createResult = updated },
                            onGoToMain: { onDismiss() }
                        )
                    }
                }
            }
            .padding()
        }
    }
    #endif

    // -------------------------------------------------------------------------
    // MARK: - Action
    // -------------------------------------------------------------------------

    /// Resolves the flow dependencies and calls `createWallet`.
    ///
    /// On success: `createResult` is set, which drives the result-card branch.
    /// On error: `handleCreationError` is called by `LoadingButton.onError`.
    private func handleCreateWallet() async throws {
        errorMessage = nil
        cancelledMessage = nil
        creationProgress = nil
        isCreating = true
        defer {
            isCreating = false
            creationProgress = nil
        }

        guard let creationFlow = DemoFlowFactory.makeWalletCreationFlow(
            demoState: demoState,
            activityLog: activityLog
        ) else {
            throw WalletCreationError.creationFailed(
                underlying: PlainError(Self.kitNotInitialisedMessage)
            )
        }

        let result = try await creationFlow.createWallet(
            username: username,
            autoSubmit: autoSubmit,
            onProgress: { creationProgress = $0 }
        )

        createResult = result
    }

    /// Handles errors thrown by the `createWallet` task.
    @MainActor
    private func handleCreationError(_ error: Error) {
        if let walletErr = error as? WalletCreationError {
            switch walletErr {
            case .userCanceled:
                cancelledMessage = "Passkey registration cancelled by user"
                errorMessage = nil
            case .invalidUsername(let reason):
                errorMessage = "Failed to create wallet: \(ActivityLogState.redact(reason))"
                cancelledMessage = nil
            default:
                let desc = ActivityLogState.redact(
                    walletErr.errorDescription ?? actionableMessage(for: error)
                )
                errorMessage = "Failed to create wallet: \(desc)"
                cancelledMessage = nil
            }
        } else {
            errorMessage = "Failed to create wallet: \(ActivityLogState.redact(actionableMessage(for: error)))"
            cancelledMessage = nil
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Platform-specific kit-error message
    // -------------------------------------------------------------------------

    /// Error message injected when `demoState.kit` is nil at the time the user
    /// taps "Create Wallet". The text differs by platform so the user receives
    /// actionable guidance for their context.
    private static let kitNotInitialisedMessage: String = {
        #if os(iOS)
        return "Kit not initialised. Return to the main screen and try again."
        #elseif os(macOS)
        return "Kit not initialised. Select Dashboard and wait for initialisation."
        #else
        return "Kit not initialised. Return to the main screen and try again."
        #endif
    }()

    // -------------------------------------------------------------------------
    // MARK: - Layout constants
    // -------------------------------------------------------------------------

    /// Vertical spacing between the heading and body copy inside the info section.
    private static let descriptionSpacing: CGFloat = 6

    /// Vertical spacing between the icon-prefixed message row and the follow-up
    /// recovery hint inside inline error banners.
    private static let bannerInnerSpacing: CGFloat = 8

    #if os(iOS)
    /// Vertical padding applied to banner / progress rows so rounded surfaces do
    /// not collide with the grouped section separator.
    private static let bannerRowVerticalPadding: CGFloat = 8

    /// Horizontal padding applied to banner / progress rows so they align with
    /// the surrounding grouped form content area.
    private static let bannerRowHorizontalPadding: CGFloat = 16

    /// Vertical padding applied to the primary action row so the `LoadingButton`
    /// stroke is not clipped by the row separator inset.
    private static let actionRowVerticalPadding: CGFloat = 8

    /// Horizontal padding applied to the primary action row so the button aligns
    /// with the surrounding grouped form content area.
    private static let actionRowHorizontalPadding: CGFloat = 16

    /// Vertical padding applied to the result-card row so the card's own padding
    /// remains the dominant inset.
    private static let resultRowVerticalPadding: CGFloat = 0

    /// Horizontal padding applied to the result-card row so the card's own
    /// padding remains the dominant inset.
    private static let resultRowHorizontalPadding: CGFloat = 0

    /// Opacity applied to the outline stroke of the neutral cancellation banner.
    private static let cancelledBorderAlpha: Double = 0.4

    /// Stroke width applied to the cancellation banner outline.
    private static let cancelledBorderWidth: CGFloat = 1
    #endif

    #if os(macOS)
    /// Horizontal spacing between the leading icon and the label inside the inline
    /// error and cancellation banners on macOS.
    private static let bannerIconSpacing: CGFloat = 10

    /// Vertical spacing between cards stacked inside the macOS result pane.
    private static let resultPaneSpacing: CGFloat = 20
    #endif
}
