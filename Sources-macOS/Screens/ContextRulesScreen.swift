// ContextRulesScreen.swift (macOS)
// SmartAccountDemoMac
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ContextRulesScreen (macOS)
// ============================================================================

/// macOS detail view for the context rules screen.
///
/// Displayed in the `NavigationSplitView` detail pane when "Context Rules" is
/// selected in the sidebar. Hosts `ContextRulesScreenCore`, which supplies
/// its own native `List` container. The `+ Add Rule` callback flips
/// `selectedRoute` to `.contextRuleBuilder` so the sidebar reflects the new
/// detail screen.
struct ContextRulesScreen: View {

    @Binding var selectedRoute: Route?

    var body: some View {
        ContextRulesScreenCore(
            onAddRule: { selectedRoute = .contextRuleBuilder },
            onEditRule: { id in selectedRoute = .contextRuleEditor(id: id) },
            onDelegateToAgent: { selectedRoute = .delegateToAgent }
        )
        .macOSContentPane()
        .frame(minWidth: 480)
        .navigationTitle("Context Rules")
        .toolbarRole(.editor)
    }
}
