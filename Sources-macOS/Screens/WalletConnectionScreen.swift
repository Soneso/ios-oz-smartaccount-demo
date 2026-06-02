// WalletConnectionScreen.swift (macOS)
// SmartAccountDemoMac
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - WalletConnectionScreen (macOS)
// ============================================================================

/// macOS shell for the wallet connection screen.
///
/// Hosts `WalletConnectionScreenCore`, which owns all state, flow orchestration,
/// and section layout. This shell adds the macOS detail-pane chrome
/// (`.macOSContentPane()`, `.toolbarRole(.editor)`, `.navigationTitle`,
/// `.frame(minWidth:)`) and maps sidebar navigation to the Core's `onDismiss`
/// callback.
struct WalletConnectionScreen: View {

    @Binding var selectedRoute: Route?

    var body: some View {
        WalletConnectionScreenCore(onDismiss: { selectedRoute = .main })
            .macOSContentPane()
            .frame(minWidth: 480)
            .navigationTitle("Connect Wallet")
            .toolbarRole(.editor)
    }
}
