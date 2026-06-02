// KnownSignersScreen.swift (macOS)
// SmartAccountDemoMac
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - KnownSignersScreen (macOS)
// ============================================================================

/// macOS detail view for the Account Signers screen.
///
/// Displayed in the `NavigationSplitView` detail pane when "Account Signers"
/// is selected in the sidebar. Hosts `KnownSignersScreenCore`, which supplies
/// its own native `List` container. The dismiss closure flips
/// `selectedRoute` back to `.main` so the sidebar follows.
struct KnownSignersScreen: View {

    @Binding var selectedRoute: Route?

    var body: some View {
        KnownSignersScreenCore { selectedRoute = .main }
            .macOSContentPane()
            .frame(minWidth: 480)
            .navigationTitle("Account Signers")
            .toolbarRole(.editor)
    }
}
