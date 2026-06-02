// RootView.swift (iOS)
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - RootView (iOS)
// ============================================================================

/// iOS navigation root using `NavigationStack` with a type-erased `NavigationPath`.
///
/// All inter-screen transitions go through `Route` cases. Per-platform UI lives
/// in `Sources-iOS/Screens/`; every `Route` case maps to a concrete destination view.
struct RootView: View {

    @State private var navigationPath = NavigationPath()

    @EnvironmentObject private var appTheme: AppThemeState

    var body: some View {
        NavigationStack(path: $navigationPath) {
            MainScreen(navigationPath: $navigationPath)
                .navigationDestination(for: Route.self) { route in
                    destination(for: route)
                }
        }
        // Inherited default text colour for every Text below this view. Text
        // views that set their own foregroundStyle (semantic colours, the
        // AppBar's white-on-navy title, etc.) override this; everything else
        // — body labels, headings, monospaced addresses, balance amounts —
        // picks up the brand-tinted onSurface tone instead of SwiftUI's
        // neutral Color.primary.
        .foregroundStyle(Color.brandOnSurface)
        .preferredColorScheme(appTheme.mode.preferredColorScheme)
    }

    // -------------------------------------------------------------------------
    // MARK: - Route Mapping
    // -------------------------------------------------------------------------

    // swiftlint:disable cyclomatic_complexity

    /// Maps a `Route` case to its SwiftUI destination view.
    ///
    /// Every `Route` case has a concrete destination; navigation never falls
    /// through to a placeholder view.
    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .main:
            MainScreen(navigationPath: $navigationPath)
        case .walletCreation:
            WalletCreationScreen()
        case .walletConnection:
            WalletConnectionScreen()
        case .transfer:
            TransferScreen()
        case .contextRules:
            ContextRulesScreen(navigationPath: $navigationPath)
        case .contextRuleBuilder:
            ContextRuleBuilderScreen()
        case .contextRuleEditor(let id):
            ContextRuleBuilderScreen(editRuleId: id)
        case .accountSigners:
            KnownSignersScreen()
        case .approve:
            ApproveScreen()
        }
    }
    // swiftlint:enable cyclomatic_complexity
}
