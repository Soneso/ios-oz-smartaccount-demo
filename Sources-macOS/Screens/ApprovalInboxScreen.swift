// ApprovalInboxScreen.swift (macOS)
// SmartAccountDemoMac
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ApprovalInboxScreen (macOS)
// ============================================================================

/// macOS detail view for the approval inbox screen.
///
/// Displayed in the `NavigationSplitView` detail pane when "Approval Inbox" is
/// selected in the sidebar or the toolbar bell is tapped. Hosts
/// `ApprovalInboxScreenCore`, which supplies its own native `List` container and
/// load/refresh handling.
struct ApprovalInboxScreen: View {

    var body: some View {
        ApprovalInboxScreenCore()
            .macOSContentPane()
            .frame(minWidth: 480)
            .navigationTitle("Approval Inbox")
            .toolbarRole(.editor)
    }
}
