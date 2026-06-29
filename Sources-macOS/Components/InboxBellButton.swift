// InboxBellButton.swift (macOS)
// SmartAccountDemoMac
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - InboxBellButton (macOS)
// ============================================================================

/// Toolbar button that opens the approval inbox, badged with the number of
/// pending agent escalations for the connected smart account.
///
/// The pending count is observed from `DemoState`; the main screen keeps it
/// current by polling the coordination server every eight seconds while a wallet
/// is connected. Tapping invokes `onOpen`, which the main screen wires to set
/// the navigation selection to `Route.approvalInbox`.
struct InboxBellButton: View {

    @EnvironmentObject private var demoState: DemoState

    /// Invoked on tap to navigate to the approval inbox.
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Image(systemName: "bell")
                .overlay(alignment: .topTrailing) {
                    if demoState.pendingRequestCount > 0 {
                        badge
                    }
                }
        }
        .help(demoState.inboxAccessibilityLabel)
        .accessibilityLabel(demoState.inboxAccessibilityLabel)
    }

    private var badge: some View {
        Text(demoState.pendingBadgeText)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(Color.red)
            .clipShape(Capsule())
            .offset(x: 5, y: -5)
            .accessibilityHidden(true)
    }
}
