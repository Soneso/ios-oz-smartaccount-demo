// DelegateToAgentScreen.swift (macOS)
// SmartAccountDemoMac
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - DelegateToAgentScreen (macOS)
// ============================================================================

/// macOS detail view for the delegate-to-agent screen.
///
/// Displayed in the `NavigationSplitView` detail pane. Hosts
/// `DelegateToAgentScreenCore`, which supplies its own native `Form` container.
/// The dismiss closure flips `selectedRoute` back to the context rules screen
/// the delegation was launched from.
struct DelegateToAgentScreen: View {

    @Binding var selectedRoute: Route?

    var body: some View {
        DelegateToAgentScreenCore { selectedRoute = .contextRules }
            .macOSContentPane()
            .frame(minWidth: 480)
            .navigationTitle("Delegate to Agent")
            .toolbarRole(.editor)
    }
}
