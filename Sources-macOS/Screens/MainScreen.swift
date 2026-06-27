// MainScreen.swift (macOS)
// SmartAccountDemoMac
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - MainScreen (macOS)
// ============================================================================

/// Main dashboard detail view for macOS.
///
/// Displayed in the `NavigationSplitView` detail pane when "Dashboard" is
/// selected in the sidebar.
///
/// Renders one of three state branches driven by `DemoState`:
///
/// - **Not Connected:** Shows a "No wallet connected" placeholder. The macOS
///   sidebar already exposes "Create Wallet" and "Connect Wallet" so no
///   additional CTAs are shown in the detail pane.
///
/// - **Connected + Not Deployed:** Shows `WalletStatusCard` with contract
///   address, credential ID, and an embedded `UndeployedWalletWarningCard`.
///   Also shows the `ActivityLogCard`.
///
/// - **Connected + Deployed:** Shows `WalletStatusCard` with contract address,
///   credential ID, balance, and "Disconnect". Navigation on macOS lives in the
///   sidebar, so no navigation grid is injected into `WalletStatusCard`.
///   Also shows the `ActivityLogCard`.
///
/// All SDK interactions are delegated to `MainScreenFlow`; this view reads only
/// from observable state objects (`DemoState`, `ActivityLogState`) and calls
/// only into the flow.
///
/// Kit initialisation:
/// `flow.initializeKit()` is called from a `.task` modifier once on appear.
/// The flow guards re-entrancy internally.
///
/// Snackbar:
/// A single `SnackbarMessage?` state drives a `.snackbar()` overlay on the
/// root list. Child components write into the same binding.
///
/// macOS layout notes:
/// - Uses a native `List` in the detail pane (sidebar navigation is handled
///   by `RootView`'s `NavigationSplitView`; this pane shows status content).
/// - The list is capped at `Tokens.cardMaxContentWidth` via `macOSContentPane()`
///   so the content column stays readable on wide windows.
/// - `WalletStatusCard` and `ActivityLogCard` are rich content presentations
///   and stay card-shaped surfaces hosted as full-width list rows with edge-to-edge
///   insets so they continue to read as cards rather than form fields.
struct MainScreen: View {

    // -------------------------------------------------------------------------
    // MARK: - Dependencies
    // -------------------------------------------------------------------------

    @EnvironmentObject private var demoState: DemoState
    @EnvironmentObject private var activityLog: ActivityLogState

    /// Invoked by the toolbar inbox bell to navigate to the approval inbox.
    /// `nil` when the screen is constructed without a navigation host (e.g.
    /// previews); the bell is then hidden.
    var onOpenInbox: (() -> Void)?

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
                notConnectedSection
            }
        }
        .listStyle(.automatic)
        .macOSContentPane()
        .frame(minWidth: Self.minDetailPaneWidth)
        .navigationTitle("Stellar Smart Account Demo")
        .navigationSubtitle("Testnet")
        .toolbar {
            if let onOpenInbox {
                ToolbarItem(placement: .primaryAction) {
                    InboxBellButton(onOpen: onOpenInbox)
                }
            }
        }
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
    // MARK: - Not Connected section
    // -------------------------------------------------------------------------

    private var notConnectedSection: some View {
        Section {
            ContentUnavailableView(
                "No Wallet Connected",
                systemImage: "wallet.bifold",
                description: Text("Use the sidebar to create a new wallet or connect an existing smart account.")
            )
            .symbolRenderingMode(.hierarchical)
        }
        .listRowBackground(Color.clear)
    }

    // -------------------------------------------------------------------------
    // MARK: - Connected sections
    // -------------------------------------------------------------------------

    @ViewBuilder
    private var connectedSections: some View {
        walletStatusSection
        activityLogSection
    }

    private var walletStatusSection: some View {
        Section {
            // macOS: no navigation grid — the sidebar handles navigation.
            WalletStatusCard(
                onRefresh: refreshBalances,
                onDisconnect: disconnect,
                onDeploy: deployPending,
                snackbarMessage: $snackbarMessage
            ) {
                EmptyView()
            }
        }
    }

    private var activityLogSection: some View {
        Section {
            ActivityLogCard(snackbarMessage: $snackbarMessage)
        }
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

    /// Refreshes the pending agent-escalation count for the toolbar inbox bell
    /// badge while a wallet is connected.
    ///
    /// Restarted whenever the connected account changes (via `.task(id:)`). Polls
    /// every `pendingPollInterval` seconds and stops when the task is cancelled.
    /// A failed fetch leaves the previous count in place, and is logged once at
    /// info level when the failure first appears (de-duplicated so a sustained
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

    /// Minimum width of the dashboard detail pane in the macOS split view.
    /// Below this width the content column would no longer accommodate the
    /// status card's address rows without truncating mid-identifier.
    private static let minDetailPaneWidth: CGFloat = 480
}
