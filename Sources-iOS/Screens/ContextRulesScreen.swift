// ContextRulesScreen.swift (iOS)
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ContextRulesScreen (iOS)
// ============================================================================

/// iOS shell for the context rules screen.
///
/// Hosts `ContextRulesScreenCore`, which supplies its own native `List`
/// container. The shell installs the navigation chrome. The `+ Add Rule`
/// callback pushes the builder route onto the navigation path managed by
/// `RootView`, keeping all navigation transitions driven by `Route` values
/// (the same path that handles every other inter-screen push).
struct ContextRulesScreen: View {

    /// Navigation path managed by `RootView`. The `+ Add Rule` callback appends
    /// `Route.contextRuleBuilder` to this path so `NavigationStack` pushes the
    /// builder via the registered `navigationDestination(for: Route.self)`.
    @Binding var navigationPath: NavigationPath

    var body: some View {
        ContextRulesScreenCore(
            onAddRule: { navigationPath.append(Route.contextRuleBuilder) },
            onEditRule: { id in
                navigationPath.append(Route.contextRuleEditor(id: id))
            },
            onDelegateToAgent: { navigationPath.append(Route.delegateToAgent) }
        )
        .navigationTitle("Context Rules")
        .navigationBarTitleDisplayMode(.inline)
    }
}
