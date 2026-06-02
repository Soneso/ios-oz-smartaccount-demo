// WalletStatusCard.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - WalletStatusCard
// ============================================================================

/// Primary surface on the main dashboard that presents the connected wallet's
/// identity, balances, and the disconnect action.
///
/// Shared between iOS and macOS. SwiftUI primitives only — no UIKit or AppKit
/// conditionals in the view body.
///
/// Layout (deployed, no navigation slot):
/// - "Wallet Status" header.
/// - Contract Address row: truncated value + "Copy" button (posts toast via
///   `snackbarMessage` binding).
/// - Credential ID row.
/// - Divider.
/// - Balance: "Balance:" label, XLM value, optional DEMO value, "Refresh" button.
/// - Optional injected navigation content (iOS passes a `NavigationGrid`;
///   macOS omits it because the sidebar handles navigation).
/// - Outlined "Disconnect" button.
///
/// When the wallet is connected but not yet deployed, the balance row and any
/// injected navigation are replaced by `UndeployedWalletWarningCard`, and the
/// "Disconnect" button is still shown.
///
/// Snackbar:
/// The parent (MainScreen) owns the `.snackbar()` overlay. This card writes
/// `SnackbarMessage` values into the provided binding so toasts appear at the
/// screen level, not inside the card's own bounds.
public struct WalletStatusCard<NavContent: View>: View {

    // -------------------------------------------------------------------------
    // MARK: - Dependencies
    // -------------------------------------------------------------------------

    @EnvironmentObject private var demoState: DemoState

    /// Platform clipboard used for the contract-address copy action.
    @Environment(\.clipboard) private var clipboard

    // -------------------------------------------------------------------------
    // MARK: - Callbacks
    // -------------------------------------------------------------------------

    /// Called when the user taps "Refresh". The card shows "Refreshing..." while
    /// this is in flight.
    let onRefresh: @Sendable () async -> Void

    /// Called when the user taps "Disconnect".
    ///
    /// Non-throwing because `MainScreenFlow.disconnect()` swallows SDK teardown
    /// errors internally, logging them to the activity log. The button therefore
    /// needs no error handler.
    let onDisconnect: @Sendable () async -> Void

    /// Called when the user taps "Deploy Now" in the undeployed warning card.
    let onDeploy: @Sendable () async throws -> Void

    /// Binding for the bottom snackbar. The parent owns the overlay.
    @Binding var snackbarMessage: SnackbarMessage?

    /// Optional navigation content injected by the parent.
    ///
    /// iOS passes a nav grid; macOS passes `EmptyView()` because the sidebar
    /// owns navigation.
    private let navContent: NavContent

    // -------------------------------------------------------------------------
    // MARK: - State
    // -------------------------------------------------------------------------

    @State private var isRefreshing: Bool = false

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates a `WalletStatusCard`.
    ///
    /// - Parameters:
    ///   - onRefresh: Called when the user taps "Refresh".
    ///   - onDisconnect: Called when the user taps "Disconnect".
    ///   - onDeploy: Called when the user taps "Deploy Now".
    ///   - snackbarMessage: Binding to the parent's snackbar state.
    ///   - navContent: Optional navigation grid content. Pass `EmptyView()` on macOS.
    public init(
        onRefresh: @escaping @Sendable () async -> Void,
        onDisconnect: @escaping @Sendable () async -> Void,
        onDeploy: @escaping @Sendable () async throws -> Void,
        snackbarMessage: Binding<SnackbarMessage?>,
        @ViewBuilder _ content: () -> NavContent
    ) {
        self.onRefresh = onRefresh
        self.onDisconnect = onDisconnect
        self.onDeploy = onDeploy
        self._snackbarMessage = snackbarMessage
        self.navContent = content()
    }

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Wallet Status")
                .font(Typography.sectionHeader)
                .accessibilityAddTraits(.isHeader)

            Divider()
                .padding(.vertical, Self.headerDividerVerticalPadding)

            addressSection

            if demoState.isDeployed {
                Divider()
                    .padding(.vertical, Self.balanceDividerVerticalPadding)

                balanceSection

                navContent

                outlinedDisconnectButton
                    .padding(.top, Self.disconnectTopSpacingDeployed)
            } else {
                UndeployedWalletWarningCard(onDeploy: onDeploy)
                .padding(.top, Self.warningCardTopSpacing)

                outlinedDisconnectButton
                    .padding(.top, Self.disconnectTopSpacingUndeployed)
            }
        }
        .padding(Tokens.cardPadding)
        .background(Color.primaryContainer)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.cardRadius))
    }

    // -------------------------------------------------------------------------
    // MARK: - Address section
    // -------------------------------------------------------------------------

    private var addressSection: some View {
        VStack(alignment: .leading, spacing: Self.addressRowSpacing) {
            HStack(alignment: .center, spacing: Tokens.iconLabelSpacing) {
                Text("Contract Address:")
                    .font(Typography.metadata)
                    .foregroundStyle(Color.brandOnSurfaceVariant)

                Spacer()

                Text(truncatedContractAddress)
                    .font(Typography.metadata.monospaced())
                    .lineLimit(1)

                Button(action: copyContractAddress) {
                    Image(systemName: "doc.on.doc")
                        .imageScale(.medium)
                        .accessibilityHidden(true)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.brandOnSurfaceVariant)
                .accessibilityLabel("Copy contract address")
                .accessibilityHint("Copies the contract address to the clipboard")
            }

            HStack(alignment: .top, spacing: Tokens.iconLabelSpacing) {
                Text("Credential ID:")
                    .font(Typography.metadata)
                    .foregroundStyle(Color.brandOnSurfaceVariant)
                    .fixedSize()

                Spacer()

                Text(demoState.credentialId ?? "—")
                    .font(Typography.metadata.monospaced())
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.bottom, Self.addressSectionBottomPadding)
    }

    // -------------------------------------------------------------------------
    // MARK: - Balance section
    // -------------------------------------------------------------------------

    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: Self.balanceRowSpacing) {
            Text("Balance:")
                .font(Typography.metadata)
                .foregroundStyle(Color.brandOnSurfaceVariant)

            HStack(alignment: .center, spacing: Tokens.iconLabelSpacing) {
                Text("\(demoState.xlmBalance ?? "Loading...") XLM")
                    .font(Typography.body)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityLabel("XLM balance: \(demoState.xlmBalance ?? "loading")")

                Spacer()

                Button {
                    Task {
                        guard !isRefreshing else { return }
                        isRefreshing = true
                        defer { isRefreshing = false }
                        await onRefresh()
                    }
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .imageScale(.medium)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.brandOnSurfaceVariant)
                .disabled(isRefreshing)
                .accessibilityLabel(isRefreshing ? "Refreshing balance" : "Refresh balance")
            }

            if let demo = demoState.demoTokenBalance {
                Text("\(demo) DEMO")
                    .font(Typography.metadata)
                    .foregroundStyle(Color.brandOnSurfaceVariant)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityLabel("DEMO token balance: \(demo)")
            }
        }
        .padding(.bottom, Self.balanceSectionBottomPadding)
    }

    // -------------------------------------------------------------------------
    // MARK: - Disconnect button
    // -------------------------------------------------------------------------

    private var outlinedDisconnectButton: some View {
        LoadingButton(
            "Disconnect",
            loadingLabel: "Disconnecting...",
            style: .outlined,
            action: onDisconnect
        )
        .accessibilityLabel("Disconnect the current wallet session")
    }

    // -------------------------------------------------------------------------
    // MARK: - Helpers
    // -------------------------------------------------------------------------

    /// Contract address formatted as `"take(12)...takeLast(12)"` per the UI spec.
    private var truncatedContractAddress: String {
        guard let addr = demoState.contractId else { return "—" }
        return truncateAddress(addr, chars: 12)
    }

    private func copyContractAddress() {
        guard let addr = demoState.contractId else { return }
        clipboard.copy(addr, sensitive: false)
        snackbarMessage = SnackbarMessage("Contract address copied")
    }

    // -------------------------------------------------------------------------
    // MARK: - Local layout constants
    // -------------------------------------------------------------------------

    /// Vertical padding applied to the divider that separates the header from
    /// the address section.
    private static var headerDividerVerticalPadding: CGFloat { WalletStatusCardConstants.headerDividerVerticalPadding }

    /// Vertical padding applied to the divider that separates the address
    /// section from the balance section in the deployed branch.
    private static var balanceDividerVerticalPadding: CGFloat { WalletStatusCardConstants.balanceDividerVerticalPadding }

    /// Top spacing applied to the outlined Disconnect button when the wallet
    /// is connected and deployed.
    private static var disconnectTopSpacingDeployed: CGFloat { WalletStatusCardConstants.disconnectTopSpacingDeployed }

    /// Top spacing applied to the outlined Disconnect button when the wallet
    /// is connected but not yet deployed.
    private static var disconnectTopSpacingUndeployed: CGFloat { WalletStatusCardConstants.disconnectTopSpacingUndeployed }

    /// Top spacing applied to the embedded `UndeployedWalletWarningCard` so it
    /// breathes below the address rows.
    private static var warningCardTopSpacing: CGFloat { WalletStatusCardConstants.warningCardTopSpacing }

    /// Vertical spacing between the contract-address row and the credential-id
    /// row inside the address section.
    private static var addressRowSpacing: CGFloat { WalletStatusCardConstants.addressRowSpacing }

    /// Bottom padding applied to the address section so it does not abut the
    /// trailing divider.
    private static var addressSectionBottomPadding: CGFloat { WalletStatusCardConstants.addressSectionBottomPadding }

    /// Vertical spacing between the "Balance:" caption, the XLM amount row,
    /// and the optional DEMO token row inside the balance section.
    private static var balanceRowSpacing: CGFloat { WalletStatusCardConstants.balanceRowSpacing }

    /// Bottom padding applied to the balance section so the disconnect button
    /// has visual breathing room below.
    private static var balanceSectionBottomPadding: CGFloat { WalletStatusCardConstants.balanceSectionBottomPadding }
}

// ============================================================================
// MARK: - WalletStatusCardConstants
// ============================================================================

/// Concrete numeric tokens consumed by `WalletStatusCard`'s body. Lifted to a
/// non-generic enum so the values remain accessible from the generic view's
/// static accessors without violating Swift's restriction on static stored
/// properties inside generic types.
private enum WalletStatusCardConstants {

    static let headerDividerVerticalPadding: CGFloat = 10

    static let balanceDividerVerticalPadding: CGFloat = 6

    static let disconnectTopSpacingDeployed: CGFloat = 10

    static let disconnectTopSpacingUndeployed: CGFloat = 12

    static let warningCardTopSpacing: CGFloat = 4

    static let addressRowSpacing: CGFloat = 8

    static let addressSectionBottomPadding: CGFloat = 4

    static let balanceRowSpacing: CGFloat = 4

    static let balanceSectionBottomPadding: CGFloat = 4
}
