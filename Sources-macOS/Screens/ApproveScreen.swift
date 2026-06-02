// ApproveScreen.swift (macOS)
// SmartAccountDemoMac
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ApproveScreen (macOS)
// ============================================================================

/// macOS detail view for the token-allowance approve screen.
///
/// Displayed in the `NavigationSplitView` detail pane when "Approve" is
/// selected in the sidebar. Hosts `ApproveScreenCore`, which supplies its
/// own native `Form` container. The dismiss closure flips `selectedRoute`
/// back to `.main` so the sidebar follows.
struct ApproveScreen: View {

    @Binding var selectedRoute: Route?

    var body: some View {
        ApproveScreenCore { selectedRoute = .main }
            .macOSContentPane()
            .frame(minWidth: 480)
            .navigationTitle("Approve")
            .toolbarRole(.editor)
    }
}
