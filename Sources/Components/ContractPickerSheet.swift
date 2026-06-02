// ContractPickerSheet.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ContractPickerSheet
// ============================================================================

/// A modal sheet that lets the user pick one contract address from a list of
/// candidates returned when a passkey is registered as a signer on more than
/// one smart account.
///
/// Presented when `WalletConnectionFlow` receives a `.ambiguous` result. The
/// user selects a contract and taps "Connect"; the sheet calls `onConnect` with
/// the chosen address. Tapping "Cancel" calls `onDismiss` without selection.
///
/// Layout:
/// - Title: "Select Wallet"
/// - Description: disambiguation prompt
/// - Radio-style native `List` of candidate C-addresses (monospaced, truncated)
/// - "Cancel" (secondary) / "Connect" (primary) button row
///
/// Shared between iOS and macOS. SwiftUI primitives only.
public struct ContractPickerSheet: View {

    // -------------------------------------------------------------------------
    // MARK: - Configuration
    // -------------------------------------------------------------------------

    /// The list of candidate contract addresses to display.
    private let candidates: [String]

    /// Called when the user taps "Cancel" without making a selection.
    private let onDismiss: @MainActor () -> Void

    /// Called with the selected contract address when the user taps "Connect".
    private let onConnect: @MainActor (String) -> Void

    // -------------------------------------------------------------------------
    // MARK: - State
    // -------------------------------------------------------------------------

    /// The currently highlighted candidate. Defaults to the first candidate so
    /// the user always has a valid selection when "Connect" is first enabled.
    @State private var selectedCandidate: String?

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates a `ContractPickerSheet`.
    ///
    /// - Parameters:
    ///   - candidates: Non-empty list of contract C-addresses.
    ///   - onDismiss: Called on the main actor when the user cancels without selecting.
    ///   - onConnect: Called on the main actor with the selected address when confirmed.
    public init(
        candidates: [String],
        onDismiss: @escaping @MainActor () -> Void,
        onConnect: @escaping @MainActor (String) -> Void
    ) {
        self.candidates = candidates
        self.onDismiss = onDismiss
        self.onConnect = onConnect
        self._selectedCandidate = State(initialValue: candidates.first)
    }

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    public var body: some View {
        VStack(alignment: .leading, spacing: Self.outerSpacing) {
            header
            candidateList
            actionButtons
        }
        .padding(Self.outerPadding)
        .frame(maxWidth: Self.sheetMaxWidth)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Self.sheetCornerRadius))
        .shadow(radius: Self.sheetShadowRadius)
        .padding()
    }

    // -------------------------------------------------------------------------
    // MARK: - Subviews
    // -------------------------------------------------------------------------

    private var header: some View {
        VStack(alignment: .leading, spacing: Self.headerSpacing) {
            Text("Select Wallet")
                .font(Typography.sectionHeader)
                .fontWeight(.semibold)
                .accessibilityAddTraits(.isHeader)

            Text("This passkey is a signer on more than one wallet. Pick the one to connect.")
                .font(Typography.secondary)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var candidateList: some View {
        #if os(iOS)
        candidateListContainer
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .frame(minHeight: candidateListMinHeight, maxHeight: candidateListMaxHeight)
        #elseif os(macOS)
        candidateListContainer
            .listStyle(.automatic)
            .frame(minHeight: candidateListMinHeight, maxHeight: candidateListMaxHeight)
        #else
        candidateListContainer
            .frame(minHeight: candidateListMinHeight, maxHeight: candidateListMaxHeight)
        #endif
    }

    private var candidateListContainer: some View {
        List(selection: Binding(
            get: { selectedCandidate },
            set: { newValue in
                if let value = newValue {
                    selectedCandidate = value
                }
            }
        )) {
            ForEach(candidates, id: \.self) { candidate in
                candidateRow(for: candidate)
                    .tag(candidate)
            }
        }
    }

    /// Estimated row height used to size the embedded `List` so the sheet keeps
    /// its compact silhouette regardless of how many candidates are passed in.
    private var candidateListMinHeight: CGFloat {
        let rows = max(1, min(candidates.count, Self.candidateListVisibleRows))
        return CGFloat(rows) * Self.candidateRowEstimatedHeight
    }

    private var candidateListMaxHeight: CGFloat {
        CGFloat(Self.candidateListVisibleRows) * Self.candidateRowEstimatedHeight
    }

    private func candidateRow(for candidate: String) -> some View {
        Button {
            selectedCandidate = candidate
        } label: {
            HStack(spacing: Tokens.insetPadding) {
                Image(systemName: selectedCandidate == candidate
                    ? "largecircle.fill.circle"
                    : "circle")
                    .foregroundStyle(selectedCandidate == candidate ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)

                Text(truncateContractAddress(candidate))
                    .font(Typography.mono)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Wallet contract \(truncateContractAddress(candidate))")
        .accessibilityHint(selectedCandidate == candidate ? "Selected" : "Double-tap to select")
        .accessibilityAddTraits(selectedCandidate == candidate ? .isSelected : [])
    }

    private var actionButtons: some View {
        HStack(spacing: Self.actionButtonSpacing) {
            LoadingButton("Cancel", style: .outlined) { @MainActor in
                onDismiss()
            }

            LoadingButton("Connect", style: .primary) { @MainActor in
                if let chosen = selectedCandidate {
                    onConnect(chosen)
                }
            }
            .disabled(selectedCandidate == nil)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Layout constants
    // -------------------------------------------------------------------------

    /// Vertical spacing between the header, candidate list, and action button
    /// row inside the sheet's main stack.
    private static let outerSpacing: CGFloat = 20

    /// Padding applied around the sheet's main stack inside its card surface.
    private static let outerPadding: CGFloat = 24

    /// Maximum width of the sheet card so it does not stretch across wide
    /// windows on macOS.
    private static let sheetMaxWidth: CGFloat = 480

    /// Corner radius applied to the sheet's card surface.
    private static let sheetCornerRadius: CGFloat = 16

    /// Drop-shadow radius applied to the sheet card so it floats over its
    /// presentation backdrop.
    private static let sheetShadowRadius: CGFloat = 8

    /// Vertical spacing between the sheet header's title and description copy.
    private static let headerSpacing: CGFloat = 8

    /// Horizontal spacing between the Cancel and Connect action buttons.
    private static let actionButtonSpacing: CGFloat = 12

    /// Maximum number of candidate rows shown without scrolling. The list
    /// scrolls past this height; the embedded sheet keeps its compact
    /// silhouette regardless of how many candidates are passed in.
    private static let candidateListVisibleRows: Int = 5

    /// Estimated rendered height of a single candidate row, used to size the
    /// embedded `List` so it does not collapse to zero height inside a
    /// fixed-size sheet container.
    private static let candidateRowEstimatedHeight: CGFloat = 56
}
