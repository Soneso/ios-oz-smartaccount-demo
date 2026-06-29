// InboxBellButton.swift (iOS)
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - InboxBellButton (iOS)
// ============================================================================

/// AppBar trailing icon button that opens the approval inbox, badged with the
/// number of pending agent escalations for the connected smart account.
///
/// The pending count is observed from `DemoState`; the main screen keeps it
/// current by polling the coordination server every eight seconds while a wallet
/// is connected. Tapping appends `Route.approvalInbox` to the navigation path
/// owned by `RootView`.
///
/// Uses `.buttonStyle(.plain)` so the bare icon renders against the AppBar
/// background without picking up iOS 26's tinted Glass button chrome.
struct InboxBellButton: View {

    @EnvironmentObject private var demoState: DemoState

    /// Navigation path owned by `RootView`; appended with `Route.approvalInbox`
    /// on tap.
    @Binding var navigationPath: NavigationPath

    var body: some View {
        Button {
            navigationPath.append(Route.approvalInbox)
        } label: {
            Image(systemName: "bell")
                .imageScale(.large)
                .symbolRenderingMode(.monochrome)
                .overlay(alignment: .topTrailing) {
                    if demoState.pendingRequestCount > 0 {
                        badge
                    }
                }
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(demoState.inboxAccessibilityLabel)
        .accessibilityHint("Opens the approval inbox.")
    }

    private var badge: some View {
        Text(demoState.pendingBadgeText)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.red)
            .clipShape(Capsule())
            .offset(x: 6, y: -6)
            .accessibilityHidden(true)
    }
}
