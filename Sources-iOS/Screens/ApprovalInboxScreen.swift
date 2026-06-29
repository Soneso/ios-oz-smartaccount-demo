// ApprovalInboxScreen.swift (iOS)
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ApprovalInboxScreen (iOS)
// ============================================================================

/// iOS shell for the approval inbox screen.
///
/// Hosts `ApprovalInboxScreenCore`, which supplies its own native `List`
/// container and load/refresh handling. The shell installs the navigation
/// chrome.
struct ApprovalInboxScreen: View {

    var body: some View {
        ApprovalInboxScreenCore()
            .navigationTitle("Approval Inbox")
            .navigationBarTitleDisplayMode(.inline)
    }
}
