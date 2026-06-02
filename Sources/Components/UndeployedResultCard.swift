// UndeployedResultCard.swift
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
// MARK: - UndeployedResultCard
// ============================================================================

/// Result card shown in-place on `WalletCreationScreen` when the passkey was
/// registered but the smart account contract was not deployed (auto-deploy was
/// off).
///
/// Layout:
/// - "Passkey Registered" title.
/// - `ResultField` rows: Credential ID, Contract Address (derived).
/// - Warning banner explaining the undeployed state.
/// - Progress text "Deploying contract..." while deployment is in flight.
/// - "Deploy Now" / "Deploying..." `LoadingButton` that calls
///   `MainScreenFlow.deployPendingAndProvision(credentialId:)`.
/// - Inline monospace error card when the deploy step fails.
/// - On successful deploy: calls `onDeployed` so the parent can swap this
///   card for a `DeployedResultCard`.
/// - "Go to Main Screen" button at the bottom.
///
/// Snackbar:
/// The parent (`WalletCreationScreen`) owns the `.snackbar()` overlay. This
/// card writes `SnackbarMessage` values into the provided binding so toasts
/// appear at the screen level, not within the card's own bounds.
///
/// Shared between iOS and macOS. SwiftUI primitives only — no UIKit or AppKit
/// conditionals in the view body.
public struct UndeployedResultCard: View {

    // -------------------------------------------------------------------------
    // MARK: - Environment
    // -------------------------------------------------------------------------

    @EnvironmentObject private var demoState: DemoState
    @EnvironmentObject private var activityLog: ActivityLogState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // -------------------------------------------------------------------------
    // MARK: - Configuration
    // -------------------------------------------------------------------------

    /// The result from the passkey-registration step (contract not yet deployed).
    private let result: WalletCreationResult

    /// Binding to the screen-level snackbar message; set when a field is copied.
    @Binding private var snackbarMessage: SnackbarMessage?

    /// Called when the deploy step succeeds so the parent can swap this card
    /// for a `DeployedResultCard`.
    private let onDeployed: (WalletCreationResult) -> Void

    /// Called when "Go to Main Screen" is tapped (without deploying). The
    /// parent handles the platform-appropriate navigation.
    private let onGoToMain: () -> Void

    // -------------------------------------------------------------------------
    // MARK: - Deploy State
    // -------------------------------------------------------------------------

    /// `true` while `deployPendingAndProvision(credentialId:)` is running.
    @State private var isDeploying: Bool = false

    /// Inline error message shown when the deploy step fails.
    @State private var deployError: String?

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates an `UndeployedResultCard`.
    ///
    /// - Parameters:
    ///   - result: The wallet creation result (passkey registered, not deployed).
    ///   - snackbarMessage: Screen-level snackbar binding for copy confirmations.
    ///   - onDeployed: Called on successful deployment with the updated result.
    ///   - onGoToMain: Called when the user taps "Go to Main Screen".
    public init(
        result: WalletCreationResult,
        snackbarMessage: Binding<SnackbarMessage?>,
        onDeployed: @escaping (WalletCreationResult) -> Void,
        onGoToMain: @escaping () -> Void
    ) {
        self.result = result
        self._snackbarMessage = snackbarMessage
        self.onDeployed = onDeployed
        self.onGoToMain = onGoToMain
    }

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            Divider()
                .padding(.bottom, Self.headerDividerBottomPadding)
            fieldsSection
            warningBanner
            if isDeploying {
                deployingProgressText
            }
            if let errorText = deployError {
                deployErrorCard(errorText)
                retryGuidanceText
            }
            deployButton
            Divider()
                .padding(.vertical, Self.dividerVerticalPadding)
            goToMainButton
        }
        .sectionCard()
        .onChange(of: isDeploying) { _, deploying in
            if deploying {
                postAccessibilityAnnouncement("Deploying contract")
            }
        }
        .onChange(of: deployError) { _, errorText in
            if let errorText {
                let redacted = ActivityLogState.redact(errorText)
                postAccessibilityAnnouncement("Deploy failed: \(redacted)")
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Subviews
    // -------------------------------------------------------------------------

    private var headerRow: some View {
        HStack(spacing: Self.headerIconLabelSpacing) {
            Image(systemName: "key.fill")
                .foregroundStyle(Color.onWarningContainer)
                .font(.title2)
                .symbolEffect(.pulse, options: .repeat(2), value: reduceMotion ? nil : result.credentialId)
                .accessibilityHidden(true)

            Text("Passkey Registered")
                .font(Typography.sectionHeader)
        }
        .padding(.bottom, Self.headerBottomPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Passkey Registered")
        .accessibilityAddTraits(.isHeader)
    }

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: Self.fieldsSpacing) {
            ResultField(label: "Credential ID", value: result.credentialId) {
                snackbarMessage = SnackbarMessage("Copied")
            }

            Divider()

            ResultField(label: "Contract Address (derived)", value: result.contractAddress) {
                snackbarMessage = SnackbarMessage("Copied")
            }
        }
        .padding(.bottom, Self.fieldsBottomPadding)
    }

    private var warningBanner: some View {
        HStack(alignment: .top, spacing: Self.bannerIconSpacing) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.onWarningContainer)
                .font(Typography.metadata)
                .accessibilityHidden(true)

            Text(
                "The wallet contract has not been deployed to the network yet. " +
                "Deploy it now or later from the Connect Wallet screen."
            )
            .font(Typography.metadata)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Tokens.insetPadding)
        .background(Color.warningContainer)
        .clipShape(RoundedRectangle(cornerRadius: Self.bannerCornerRadius))
        .padding(.bottom, Self.bannerBottomPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Warning: The wallet contract has not been deployed to the network yet. " +
            "Deploy it now or later from the Connect Wallet screen."
        )
    }

    private var deployingProgressText: some View {
        Text("Deploying contract...")
            .font(Typography.metadata)
            .foregroundStyle(.secondary)
            .padding(.bottom, Self.statusBottomPadding)
            .accessibilityLabel("Deploying contract, please wait.")
    }

    private var deployButton: some View {
        LoadingButton("Deploy Now", loadingLabel: "Deploying...") {
            await handleDeployNow()
        }
        .padding(.bottom, Self.statusBottomPadding)
        .disabled(deployError != nil)
        .accessibilityLabel(isDeploying ? "Deploying..." : "Deploy Now")
        .accessibilityHint(
            deployError != nil
                ? "Retry from the Connect Wallet screen."
                : "Deploys the smart account contract to the Stellar network."
        )
    }

    private var goToMainButton: some View {
        LoadingButton("Go to Main Screen", style: .outlined) { @MainActor in
            onGoToMain()
        }
        .accessibilityHint("Returns to the main dashboard without deploying.")
    }

    @ViewBuilder
    private func deployErrorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Self.bannerIconSpacing) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Color.semanticError)
                .font(Typography.metadata)
                .accessibilityHidden(true)

            Text(message)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Color.onErrorContainer)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Tokens.insetPadding)
        .background(Color.errorContainer)
        .clipShape(RoundedRectangle(cornerRadius: Self.bannerCornerRadius))
        .padding(.bottom, Self.errorCardBottomPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Deploy error: \(message)")
    }

    /// Guidance text shown below the deploy error card directing the user to the
    /// recovery path (Connect Wallet screen). Visible only when `deployError` is set.
    private var retryGuidanceText: some View {
        Text("Retry from the Connect Wallet screen.")
            .font(Typography.metadata)
            .foregroundStyle(.secondary)
            .padding(.bottom, Self.statusBottomPadding)
            .accessibilityLabel("Retry from the Connect Wallet screen.")
    }

    // -------------------------------------------------------------------------
    // MARK: - Local layout constants
    // -------------------------------------------------------------------------

    /// Bottom padding applied to the divider below the card header so the
    /// field group breathes from the title.
    private static let headerDividerBottomPadding: CGFloat = 16

    /// Vertical padding wrapped around the divider that separates the deploy
    /// action stack from the bottom "Go to Main Screen" button.
    private static let dividerVerticalPadding: CGFloat = 12

    /// Horizontal spacing between the leading title icon and the title text
    /// inside the card header row.
    private static let headerIconLabelSpacing: CGFloat = 10

    /// Bottom padding applied beneath the header row before the divider line
    /// renders.
    private static let headerBottomPadding: CGFloat = 12

    /// Vertical spacing between successive result fields inside the fields
    /// section.
    private static let fieldsSpacing: CGFloat = 12

    /// Bottom padding applied beneath the fields section before the warning
    /// banner renders.
    private static let fieldsBottomPadding: CGFloat = 16

    /// Horizontal spacing between the leading icon and the message inside
    /// the warning / error banner rows.
    private static let bannerIconSpacing: CGFloat = 10

    /// Corner radius applied to the warning and error banner surfaces.
    /// References `Tokens.bannerRadius` so any future per-surface adjustment
    /// touches a single location.
    private static let bannerCornerRadius: CGFloat = Tokens.bannerRadius

    /// Bottom padding applied below the warning banner before the next
    /// element renders.
    private static let bannerBottomPadding: CGFloat = 12

    /// Bottom padding applied below transient status / button rows so they
    /// breathe from the next element in the deploy stack.
    private static let statusBottomPadding: CGFloat = 8

    /// Bottom padding applied below the deploy error card before the retry
    /// guidance text renders.
    private static let errorCardBottomPadding: CGFloat = 4

    // -------------------------------------------------------------------------
    // MARK: - Deploy Action
    // -------------------------------------------------------------------------

    /// Calls `MainScreenFlow.deployPendingAndProvision(credentialId:)`.
    ///
    /// On success: builds an updated `WalletCreationResult` with the current
    /// balances from `DemoState` and calls `onDeployed(_:)` so the parent
    /// swaps this card for a `DeployedResultCard`.
    ///
    /// On failure: captures the error message into `_deployError` for inline
    /// display so the user can retry without leaving the screen.
    @MainActor
    private func handleDeployNow() async {
        deployError = nil
        isDeploying = true
        defer { isDeploying = false }

        let mainFlow = MainScreenFlow(
            demoState: demoState,
            activityLog: activityLog,
            demoTokenService: makeDemoTokenService(activityLog: activityLog)
        )
        do {
            let txHash = try await mainFlow.deployPendingAndProvision(credentialId: result.credentialId)
            let updated = WalletCreationResult(
                contractAddress: result.contractAddress,
                credentialId: result.credentialId,
                isDeployed: true,
                xlmBalance: demoState.xlmBalance,
                demoTokenBalance: demoState.demoTokenBalance,
                transactionHash: txHash
            )
            onDeployed(updated)
        } catch {
            deployError = ActivityLogState.redact(actionableMessage(for: error))
        }
    }
}
