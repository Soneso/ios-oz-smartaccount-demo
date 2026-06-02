// ContextRuleBuilderScreen.swift (macOS)
// SmartAccountDemoMac
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ContextRuleBuilderScreen (macOS)
// ============================================================================

/// macOS detail view for the context rule builder screen.
///
/// Displayed in the `NavigationSplitView` detail pane when "Context Rule
/// Builder" is selected in the sidebar (either directly or via the `+ Add
/// Rule` button on the context rules screen). Hosts
/// `ContextRuleBuilderCore`, which supplies its own native `Form` container.
/// Dismiss returns the sidebar selection to `.contextRules`.
///
/// When `editRuleId` is non-nil the screen loads the matching on-chain rule
/// into the form and dispatches edit-mode submission.
struct ContextRuleBuilderScreen: View {

    @Binding var selectedRoute: Route?

    let editRuleId: UInt32?

    init(selectedRoute: Binding<Route?>, editRuleId: UInt32? = nil) {
        self._selectedRoute = selectedRoute
        self.editRuleId = editRuleId
    }

    var body: some View {
        ContextRuleBuilderCore(editRuleId: editRuleId) {
            selectedRoute = .contextRules
        }
        .macOSContentPane()
        .frame(minWidth: 480)
        .navigationTitle(pageTitle)
        .toolbarRole(.editor)
    }

    private var pageTitle: String {
        guard let editRuleId else { return "Add Context Rule" }
        return "Edit Context Rule #\(editRuleId)"
    }
}
