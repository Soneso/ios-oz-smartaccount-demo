// TransferResultCard.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - TransferResultCard
// ============================================================================

/// Result card displayed after a successful token transfer.
///
/// Rich-content surface that retains a bespoke card treatment via the shared
/// `sectionCard()` modifier so the success readout, monospaced transaction
/// hash, and trailing call-to-action stack read as one composed unit. Used as
/// a list-row child inside the transfer screen's `Form` container.
///
/// Layout:
/// - "Transfer Successful" header with checkmark icon.
/// - `ResultField` for "Transaction Hash" (monospaced, tap-to-copy with snackbar).
/// - "Amount Sent" row showing `"<amount> <tokenLabel>"`.
/// - "Recipient" row showing the full recipient address.
/// - "Updated Balance" row showing XLM balance (always) and DEMO balance (conditional).
/// - [New Transfer] and [Go to Main Screen] buttons.
///
/// Shared between iOS and macOS. SwiftUI primitives only.
public struct TransferResultCard: View {

    // -------------------------------------------------------------------------
    // MARK: - Configuration
    // -------------------------------------------------------------------------

    /// The successful transfer result to display.
    private let result: TransferResult

    /// Binding to the screen-level snackbar; set when the hash is copied.
    @Binding private var snackbarMessage: SnackbarMessage?

    /// Called when the user taps "New Transfer". The screen resets the form.
    private let onNewTransfer: () -> Void

    /// Called when the user taps "Go to Main Screen". The parent handles navigation.
    private let onGoToMain: () -> Void

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates a `TransferResultCard`.
    ///
    /// - Parameters:
    ///   - result: The successful transfer result.
    ///   - snackbarMessage: Screen-level snackbar binding for copy confirmations.
    ///   - onNewTransfer: Action invoked when "New Transfer" is tapped.
    ///   - onGoToMain: Action invoked when "Go to Main Screen" is tapped.
    public init(
        result: TransferResult,
        snackbarMessage: Binding<SnackbarMessage?>,
        onNewTransfer: @escaping () -> Void,
        onGoToMain: @escaping () -> Void
    ) {
        self.result = result
        self._snackbarMessage = snackbarMessage
        self.onNewTransfer = onNewTransfer
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
            buttonsSection
        }
        .sectionCard()
    }

    // -------------------------------------------------------------------------
    // MARK: - Subviews
    // -------------------------------------------------------------------------

    private var headerRow: some View {
        HStack(spacing: Tokens.iconLabelSpacing) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.semanticSuccess)
                .font(.title2)
                .symbolEffect(.bounce, value: reduceMotion ? nil : result.transactionHash)
                .accessibilityHidden(true)

            Text("Transfer Successful")
                .font(Typography.sectionHeader)
        }
        .padding(.bottom, Self.headerBottomPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Transfer Successful")
        .accessibilityAddTraits(.isHeader)
    }

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: Self.fieldRowSpacing) {
            ResultField(label: "Transaction Hash", value: result.transactionHash) {
                snackbarMessage = SnackbarMessage("Transaction hash copied")
            }

            Divider()

            amountRow

            Divider()

            recipientRow

            Divider()

            balanceRow
        }
        .padding(.bottom, Self.fieldsBottomPadding)
    }

    private var amountRow: some View {
        VStack(alignment: .leading, spacing: Self.labelValueSpacing) {
            Text("Amount Sent")
                .font(Typography.metadata)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text("\(result.amount) \(result.tokenLabel)")
                .font(Typography.mono)
                .fontWeight(.bold)
                .accessibilityLabel("Amount Sent: \(result.amount) \(result.tokenLabel)")
        }
    }

    private var recipientRow: some View {
        VStack(alignment: .leading, spacing: Self.labelValueSpacing) {
            Text("Recipient")
                .font(Typography.metadata)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text(result.recipient)
                .font(Typography.mono)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Recipient: \(result.recipient)")
        }
    }

    @ViewBuilder
    private var balanceRow: some View {
        VStack(alignment: .leading, spacing: Self.balanceLineSpacing) {
            Text("Updated Balance")
                .font(Typography.metadata)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            let xlmValue = result.xlmBalance ?? "0.0"
            Text("\(xlmValue) XLM")
                .font(Typography.mono)
                .fontWeight(.bold)
                .accessibilityLabel("Updated Balance: \(xlmValue) XLM")

            if let demo = result.demoTokenBalance {
                Text("\(demo) DEMO")
                    .font(Typography.mono)
                    .fontWeight(.bold)
                    .accessibilityLabel("DEMO balance: \(demo)")
            }
        }
    }

    private var buttonsSection: some View {
        VStack(spacing: Self.buttonStackSpacing) {
            Button(action: onNewTransfer) {
                Text("New Transfer")
                    .font(Typography.body)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Self.buttonVerticalPadding)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: Self.buttonCornerRadius))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New Transfer")
            .accessibilityHint("Resets the form to start another transfer.")

            Button(action: onGoToMain) {
                Text("Go to Main Screen")
                    .font(Typography.body)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Self.buttonVerticalPadding)
                    .background(Color.clear)
                    .foregroundStyle(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: Self.buttonCornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Self.buttonCornerRadius)
                            .stroke(Color.accentColor, lineWidth: Self.buttonBorderWidth)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Go to Main Screen")
            .accessibilityHint("Returns to the main dashboard.")
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Layout constants
    // -------------------------------------------------------------------------

    /// Bottom padding applied to the divider beneath the header row so the
    /// fields section reads as a distinct stack.
    private static let headerDividerBottomPadding: CGFloat = 16

    /// Bottom padding applied to the header row above the divider.
    private static let headerBottomPadding: CGFloat = 12

    /// Vertical spacing between the result-field stack rows (hash, amount,
    /// recipient, balance).
    private static let fieldRowSpacing: CGFloat = 12

    /// Bottom padding applied to the fields stack so the action button row
    /// reads as a separate section.
    private static let fieldsBottomPadding: CGFloat = 20

    /// Vertical spacing between a result field's label and its value.
    private static let labelValueSpacing: CGFloat = 2

    /// Vertical spacing between successive balance lines (XLM, DEMO).
    private static let balanceLineSpacing: CGFloat = 6

    /// Vertical spacing between the two stacked action buttons.
    private static let buttonStackSpacing: CGFloat = 10

    /// Vertical padding applied to each action button's content.
    private static let buttonVerticalPadding: CGFloat = 12

    /// Corner radius applied to each action button.
    private static let buttonCornerRadius: CGFloat = 10

    /// Stroke width applied to the outlined "Go to Main Screen" button border.
    private static let buttonBorderWidth: CGFloat = 1.5
}
