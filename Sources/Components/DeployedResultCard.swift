// DeployedResultCard.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - DeployedResultCard
// ============================================================================

/// Result card shown in-place on `WalletCreationScreen` when the wallet was
/// successfully created and the contract was deployed on-chain.
///
/// Layout:
/// - "Wallet Created Successfully" title.
/// - `ResultField` rows: Credential ID, Contract Address, Transaction Hash
///   (conditional — shown only when `result.transactionHash` is non-nil),
///   Balance label, XLM balance value (always shown when non-nil), DEMO
///   balance value (conditional).
/// - "Go to Main Screen" button at the bottom.
///
/// Snackbar:
/// The parent (`WalletCreationScreen`) owns the `.snackbar()` overlay. This
/// card writes `SnackbarMessage` values into the provided binding so toasts
/// appear at the screen level, not within the card's own bounds.
///
/// Shared between iOS and macOS. SwiftUI primitives only — no UIKit or AppKit
/// conditionals in the view body.
public struct DeployedResultCard: View {

    // -------------------------------------------------------------------------
    // MARK: - Configuration
    // -------------------------------------------------------------------------

    /// The result of the completed wallet creation and deployment.
    private let result: WalletCreationResult

    /// Binding to the screen-level snackbar message; set when a field is copied.
    @Binding private var snackbarMessage: SnackbarMessage?

    /// Called when the user taps "Go to Main Screen". The parent handles the
    /// platform-appropriate navigation (dismiss on iOS, sidebar switch on macOS).
    private let onGoToMain: () -> Void

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates a `DeployedResultCard`.
    ///
    /// - Parameters:
    ///   - result: The successful wallet creation result.
    ///   - snackbarMessage: Screen-level snackbar binding for copy confirmations.
    ///   - onGoToMain: Action invoked when "Go to Main Screen" is tapped.
    public init(
        result: WalletCreationResult,
        snackbarMessage: Binding<SnackbarMessage?>,
        onGoToMain: @escaping () -> Void
    ) {
        self.result = result
        self._snackbarMessage = snackbarMessage
        self.onGoToMain = onGoToMain
    }

    // -------------------------------------------------------------------------
    // MARK: - Environment
    // -------------------------------------------------------------------------

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            Divider()
                .padding(.bottom, Self.headerDividerBottomPadding)
            fieldsSection
            goToMainButton
        }
        .sectionCard()
    }

    // -------------------------------------------------------------------------
    // MARK: - Subviews
    // -------------------------------------------------------------------------

    private var headerRow: some View {
        HStack(spacing: Self.headerIconLabelSpacing) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.semanticSuccess)
                .font(.title2)
                .symbolEffect(.bounce, value: reduceMotion ? nil : result.contractAddress)
                .accessibilityHidden(true)

            Text("Wallet Created Successfully")
                .font(Typography.sectionHeader)
        }
        .padding(.bottom, Self.headerBottomPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wallet Created Successfully")
        .accessibilityAddTraits(.isHeader)
    }

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: Self.fieldsSpacing) {
            ResultField(label: "Credential ID", value: result.credentialId) {
                snackbarMessage = SnackbarMessage("Copied")
            }

            Divider()

            ResultField(label: "Contract Address", value: result.contractAddress) {
                snackbarMessage = SnackbarMessage("Copied")
            }

            if let hash = result.transactionHash {
                Divider()
                ResultField(label: "Transaction Hash", value: hash) {
                    snackbarMessage = SnackbarMessage("Copied")
                }
            }

            Divider()

            balanceSection
        }
        .padding(.bottom, Self.fieldsBottomPadding)
    }

    @ViewBuilder
    private var balanceSection: some View {
        if result.xlmBalance != nil || result.demoTokenBalance != nil {
            VStack(alignment: .leading, spacing: Self.balanceSpacing) {
                Text("Balance")
                    .font(Typography.metadata)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)

                if let xlm = result.xlmBalance {
                    Text("\(xlm) XLM")
                        .font(Typography.mono)
                        .accessibilityLabel("Balance: \(xlm) XLM")
                }

                if let demo = result.demoTokenBalance {
                    Text("\(demo) DEMO")
                        .font(Typography.mono)
                        .accessibilityLabel("DEMO balance: \(demo)")
                }
            }
        }
    }

    private var goToMainButton: some View {
        LoadingButton("Go to Main Screen", style: .outlined) { @MainActor in
            onGoToMain()
        }
        .accessibilityHint("Returns to the main dashboard.")
    }

    // -------------------------------------------------------------------------
    // MARK: - Local layout constants
    // -------------------------------------------------------------------------

    /// Bottom padding applied to the divider directly below the card header so
    /// the field group breathes from the title.
    private static let headerDividerBottomPadding: CGFloat = 16

    /// Horizontal spacing between the leading success icon and the title text
    /// inside the card header row.
    private static let headerIconLabelSpacing: CGFloat = 10

    /// Bottom padding applied beneath the header row before the divider line
    /// renders.
    private static let headerBottomPadding: CGFloat = 12

    /// Vertical spacing between successive result fields and their separating
    /// dividers inside the fields section.
    private static let fieldsSpacing: CGFloat = 12

    /// Bottom padding applied beneath the fields section before the bottom
    /// "Go to Main Screen" button.
    private static let fieldsBottomPadding: CGFloat = 20

    /// Vertical spacing between the balance heading and each balance value
    /// row inside the balance section.
    private static let balanceSpacing: CGFloat = 6
}
