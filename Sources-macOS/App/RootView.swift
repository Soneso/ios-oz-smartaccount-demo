// RootView.swift (macOS)
// SmartAccountDemoMac
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - NavigationIntent (macOS)
// ============================================================================

/// Shared navigation state for the macOS app.
///
/// Hoisted from `RootView` so the App scene can mutate the selected route in
/// response to menu-bar commands (e.g. File > New Wallet jumps to
/// `Route.walletCreation`). `RootView` continues to bind the sidebar `List`
/// selection to `selectedRoute` directly.
///
/// Lives at the App scene as a `@StateObject` and is passed into `RootView` as
/// an `@ObservedObject` so the same instance is reachable from both the menu
/// commands and the sidebar.
public final class NavigationIntent: ObservableObject {

    /// Currently selected destination in the sidebar. `nil` falls back to the
    /// dashboard in `RootView.detail(for:)`.
    @Published public var selectedRoute: Route? = .main

    public init() {}
}

// ============================================================================
// MARK: - RootView (macOS)
// ============================================================================

/// macOS navigation root using `NavigationSplitView` (sidebar + detail).
///
/// The sidebar lists all available destinations as `Label`-based rows.
/// The detail pane renders the content for the selected destination.
/// Routes that are not supported on macOS (e.g. external wallet pairing
/// which requires Reown, iOS-only) are omitted from the sidebar entirely
/// rather than shown as a sentinel — this makes the macOS UI feel native
/// rather than a warning-banner collection.
struct RootView: View {

    /// Shared navigation state owned by the App scene so menu commands can
    /// drive the sidebar selection.
    @ObservedObject var navigationIntent: NavigationIntent

    var body: some View {
        NavigationSplitView {
            List(selection: $navigationIntent.selectedRoute) {
                Section("Wallet") {
                    Label("Dashboard", systemImage: "house")
                        .tag(Route.main)
                    Label("Create Wallet", systemImage: "plus.circle")
                        .tag(Route.walletCreation)
                    Label("Connect Wallet", systemImage: "link")
                        .tag(Route.walletConnection)
                }

                Section("Operations") {
                    Label("Transfer", systemImage: "arrow.right.arrow.left")
                        .tag(Route.transfer)
                    Label("Context Rules", systemImage: "list.bullet.rectangle")
                        .tag(Route.contextRules)
                    Label("Context Rule Builder", systemImage: "pencil.and.list.clipboard")
                        .tag(Route.contextRuleBuilder)
                }

                Section("Advanced") {
                    Label("Account Signers", systemImage: "person.2")
                        .tag(Route.accountSigners)
                    Label("Approve", systemImage: "checkmark.seal")
                        .tag(Route.approve)
                    Label("Delegate to Agent", systemImage: "person.badge.key")
                        .tag(Route.delegateToAgent)
                    Label("Approval Inbox", systemImage: "bell")
                        .tag(Route.approvalInbox)
                }
            }
            .navigationTitle("Smart Account Demo")
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detail(for: navigationIntent.selectedRoute)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Detail Mapping
    // -------------------------------------------------------------------------

    // swiftlint:disable cyclomatic_complexity

    /// Maps the selected `Route` to its detail view.
    @ViewBuilder
    private func detail(for route: Route?) -> some View {
        switch route {
        case .main, .none:
            MainScreen(onOpenInbox: { navigationIntent.selectedRoute = .approvalInbox })
        case .walletCreation:
            WalletCreationScreen(selectedRoute: $navigationIntent.selectedRoute)
        case .walletConnection:
            WalletConnectionScreen(selectedRoute: $navigationIntent.selectedRoute)
        case .transfer:
            TransferScreen(selectedRoute: $navigationIntent.selectedRoute)
        case .contextRules:
            ContextRulesScreen(selectedRoute: $navigationIntent.selectedRoute)
        case .contextRuleBuilder:
            ContextRuleBuilderScreen(selectedRoute: $navigationIntent.selectedRoute)
        case .contextRuleEditor(let id):
            ContextRuleBuilderScreen(selectedRoute: $navigationIntent.selectedRoute, editRuleId: id)
        case .accountSigners:
            KnownSignersScreen(selectedRoute: $navigationIntent.selectedRoute)
        case .approve:
            ApproveScreen(selectedRoute: $navigationIntent.selectedRoute)
        case .delegateToAgent:
            DelegateToAgentScreen(selectedRoute: $navigationIntent.selectedRoute)
        case .approvalInbox:
            ApprovalInboxScreen()
        }
    }
    // swiftlint:enable cyclomatic_complexity
}
