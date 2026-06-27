// MainScreen.swift (iOS)
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - MainScreen (iOS)
// ============================================================================

/// Main dashboard screen for iOS.
///
/// Renders one of three state branches driven by `DemoState`:
///
/// - **Not Connected:** Shows a "No wallet connected" placeholder with
///   "Create Wallet" and "Connect Wallet" primary call-to-action buttons.
///   Balance, activity log, and navigation are hidden.
///
/// - **Connected + Not Deployed:** Shows `WalletStatusCard` containing the
///   contract address, credential ID, and an embedded `UndeployedWalletWarningCard`
///   with a "Deploy Now" button. Also shows the `ActivityLogCard`.
///
/// - **Connected + Deployed:** Shows `WalletStatusCard` with contract address,
///   credential ID, balance row, feature navigation grid, and the "Disconnect"
///   button. Also shows the `ActivityLogCard`.
///
/// All SDK interactions are delegated to `MainScreenFlow`; this view reads only
/// from observable state objects (`DemoState`, `ActivityLogState`) and calls
/// only into the flow.
///
/// Kit initialisation:
/// `flow.initializeKit()` is called from a `.task` modifier once on appear.
/// The flow guards re-entrancy internally so the kit is never built twice.
///
/// Snackbar:
/// A single `SnackbarMessage?` state drives a `.snackbar()` overlay on the
/// root list. Child components (`WalletStatusCard`, `ActivityLogCard`) write
/// into the same binding so all toasts surface at screen level.
///
/// Container:
/// The screen body is a native `List` with the inset-grouped style so each
/// content surface (status card, activity log card, navigation rows) reads as
/// a distinct grouped section while keeping platform-managed row chrome.
/// `WalletStatusCard` and `ActivityLogCard` are rich content presentations and
/// remain card-shaped surfaces hosted as full-width list rows with edge-to-edge
/// insets so they continue to read as cards rather than form fields.
///
/// App bar:
/// `AppBar` is placed in the top safe-area inset and the platform navigation
/// bar is hidden via `.toolbar(.hidden, for: .navigationBar)`. The bar's
/// brand-primary background extends through the status bar so the status-bar
/// glyphs render on top of the brand colour, giving the main screen the
/// canonical two-line app-bar moment.
struct MainScreen: View {

    // -------------------------------------------------------------------------
    // MARK: - Dependencies
    // -------------------------------------------------------------------------

    @EnvironmentObject private var demoState: DemoState
    @EnvironmentObject private var activityLog: ActivityLogState

    /// Navigation stack owned by `RootView`. Mutated here so primary CTAs
    /// can push destinations the parent `NavigationStack` will then render
    /// via its `.navigationDestination(for: Route.self)` modifier.
    @Binding var navigationPath: NavigationPath

    @State private var flow: MainScreenFlow?

    // -------------------------------------------------------------------------
    // MARK: - Toast state
    // -------------------------------------------------------------------------

    @State private var snackbarMessage: SnackbarMessage?

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    var body: some View {
        List {
            if demoState.isConnected {
                connectedSections
            } else {
                notConnectedSections
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.brandScaffold.ignoresSafeArea())
        .refreshable {
            if demoState.isConnected {
                await resolvedFlow().refreshBalances()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            AppBar(title: "Stellar Smart Account Demo", subtitle: "Testnet") {
                HStack(spacing: Tokens.cardPadding) {
                    InboxBellButton(navigationPath: $navigationPath)
                    ThemeModeToggle()
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await resolvedFlow().initializeKit()
        }
        .task(id: demoState.contractId) {
            await pollPendingRequestCount()
        }
        .onChange(of: demoState.kit != nil) { _, hasKit in
            if hasKit {
                Task { await resolvedFlow().refreshBalances() }
            }
        }
        .snackbar($snackbarMessage)
    }

    // -------------------------------------------------------------------------
    // MARK: - Not Connected sections
    // -------------------------------------------------------------------------

    @ViewBuilder
    private var notConnectedSections: some View {
        emptyPlaceholderSection
        createWalletSection
        connectWalletSection
        activityLogSection
    }

    private var emptyPlaceholderSection: some View {
        Section {
            ContentUnavailableView(
                "No Wallet Connected",
                systemImage: "wallet.bifold",
                description: Text("Create a new wallet or connect an existing smart account to get started.")
            )
            .symbolRenderingMode(.hierarchical)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets())
    }

    private var createWalletSection: some View {
        Section {
            navigationButton(
                title: "Create Wallet",
                hint: "Register a passkey and deploy a smart account",
                style: .primary,
                route: .walletCreation
            )
            .listRowInsets(Self.fullBleedRowInsets)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var connectWalletSection: some View {
        Section {
            navigationButton(
                title: "Connect Wallet",
                hint: "Reconnect to an existing smart account",
                style: .outlinedNeutral,
                route: .walletConnection
            )
            .listRowInsets(Self.fullBleedRowInsets)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Connected sections (deployed + not-deployed)
    // -------------------------------------------------------------------------

    @ViewBuilder
    private var connectedSections: some View {
        walletStatusSection
        activityLogSection
    }

    private var walletStatusSection: some View {
        Section {
            WalletStatusCard(
                onRefresh: refreshBalances,
                onDisconnect: disconnect,
                onDeploy: deployPending,
                snackbarMessage: $snackbarMessage
            ) {
                navigationGrid.padding(.top, Self.navigationGridTopPadding)
            }
            .listRowInsets(Self.fullBleedRowInsets)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Activity log section
    // -------------------------------------------------------------------------

    private var activityLogSection: some View {
        Section {
            ActivityLogCard(snackbarMessage: $snackbarMessage)
                .listRowInsets(Self.fullBleedRowInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Navigation Grid (injected into WalletStatusCard when deployed)
    // -------------------------------------------------------------------------

    private var navigationGrid: some View {
        VStack(spacing: Tokens.insetPadding) {
            HStack(spacing: Tokens.insetPadding) {
                navigationButton(
                    title: "Context Rules",
                    hint: "View and manage signing rules",
                    style: .primary,
                    route: .contextRules
                )
                .disabled(!demoState.isDeployed)

                navigationButton(
                    title: "Transfer",
                    hint: "Send XLM or DEMO tokens",
                    style: .primary,
                    route: .transfer
                )
                .disabled(!demoState.isDeployed)
            }

            HStack(spacing: Tokens.insetPadding) {
                navigationButton(
                    title: "Approve",
                    hint: "Set a token spending allowance",
                    style: .primary,
                    route: .approve
                )
                .disabled(!demoState.isDeployed)

                navigationButton(
                    title: "Account Signers",
                    hint: "View all signing credentials",
                    style: .primary,
                    route: .accountSigners
                )
                .disabled(!demoState.isDeployed)
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Navigation Button Builder
    // -------------------------------------------------------------------------

    /// Builds a full-width navigation button that appends `route` to the
    /// parent navigation path when tapped.
    ///
    /// Delegates to ``LoadingButton`` so the visual treatment (filled primary,
    /// outlined neutral, single-line shrink-to-fit label) stays consistent
    /// with every other button in the demo.
    private func navigationButton(
        title: String,
        hint: String,
        style: LoadingButton.ButtonStyle,
        route: Route
    ) -> some View {
        LoadingButton(title, style: style) {
            await MainActor.run {
                navigationPath.append(route)
            }
        }
        .accessibilityHint(hint)
    }

    // -------------------------------------------------------------------------
    // MARK: - Flow actions
    // -------------------------------------------------------------------------

    private func refreshBalances() async {
        await resolvedFlow().refreshBalances()
    }

    private func deployPending() async throws {
        guard let credentialId = demoState.credentialId else { return }
        try await resolvedFlow().deployPendingAndProvision(credentialId: credentialId)
    }

    private func disconnect() async {
        await resolvedFlow().disconnect()
    }

    // -------------------------------------------------------------------------
    // MARK: - Inbox bell poller
    // -------------------------------------------------------------------------

    /// Refreshes the pending agent-escalation count for the inbox bell badge
    /// while a wallet is connected.
    ///
    /// Restarted whenever the connected account changes (via `.task(id:)`). Polls
    /// every `pendingPollInterval` seconds and stops when the task is cancelled
    /// (screen disappears or the account changes). A failed fetch leaves the
    /// previous count in place rather than clearing the badge, and is logged once
    /// at info level when the failure first appears (de-duplicated so a sustained
    /// outage does not flood the activity log every interval).
    private func pollPendingRequestCount() async {
        guard demoState.isConnected else {
            demoState.setPendingRequestCount(0)
            return
        }
        let inbox = DemoFlowFactory.makeApprovalInboxFlow(
            demoState: demoState,
            activityLog: activityLog
        )
        var lastLoggedError: String?
        while !Task.isCancelled {
            do {
                let count = try await inbox.pendingCount()
                demoState.setPendingRequestCount(count)
                lastLoggedError = nil
            } catch {
                // The badge is best-effort: keep the previous count and keep
                // polling. Surface the failure at info level, de-duplicated, so a
                // transient blip is visible without spamming the log every poll.
                let message = ActivityLogState.redact(actionableMessage(for: error))
                if message != lastLoggedError {
                    activityLog.info("Inbox badge refresh paused: \(message)")
                    lastLoggedError = message
                }
            }
            do {
                try await Task.sleep(for: .seconds(Self.pendingPollInterval))
            } catch {
                return
            }
        }
    }

    /// Seconds between inbox pending-count polls.
    private static let pendingPollInterval: Double = 8

    // -------------------------------------------------------------------------
    // MARK: - Flow Resolution
    // -------------------------------------------------------------------------

    /// Returns the existing flow or creates one bound to the current environment.
    @MainActor
    private func resolvedFlow() -> MainScreenFlow {
        if let existing = flow {
            return existing
        }
        let newFlow = MainScreenFlow(
            demoState: demoState,
            activityLog: activityLog,
            demoTokenService: makeDemoTokenService(activityLog: activityLog)
        )
        flow = newFlow
        return newFlow
    }

    // -------------------------------------------------------------------------
    // MARK: - Local layout constants
    // -------------------------------------------------------------------------

    /// Edge insets applied to list rows that host full-bleed content surfaces
    /// (the status card, the activity log card, the primary CTA buttons in the
    /// not-connected branch). The horizontal inset matches the inset-grouped
    /// list section's natural content margin; the vertical inset gives each
    /// surface breathing room without adding the row's default separator gutter.
    private static let fullBleedRowInsets = EdgeInsets(
        top: 8,
        leading: 16,
        bottom: 8,
        trailing: 16
    )

    /// Top padding applied between the wallet-status content and the
    /// navigation grid that the iOS shell injects into the status card.
    private static let navigationGridTopPadding: CGFloat = 8
}
