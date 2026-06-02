// WalletCreationScreen.swift (macOS)
// SmartAccountDemoMac
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - WalletCreationScreen (macOS)
// ============================================================================

/// macOS shell for the wallet creation screen.
///
/// Hosts `WalletCreationScreenCore`, which owns all form state, passkey
/// orchestration, and result-card presentation. This shell adds the macOS
/// detail-pane chrome (`.macOSContentPane()`, `.toolbarRole(.editor)`,
/// `.navigationTitle`, `.frame(minWidth:)`) and maps sidebar navigation to the
/// Core's `onDismiss` callback.
struct WalletCreationScreen: View {

    @Binding var selectedRoute: Route?

    var body: some View {
        WalletCreationScreenCore(onDismiss: { selectedRoute = .main })
            .macOSContentPane()
            .navigationTitle("Create Wallet")
            .toolbarRole(.editor)
            .frame(minWidth: 420)
    }
}
