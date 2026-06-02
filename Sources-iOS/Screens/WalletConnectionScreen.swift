// WalletConnectionScreen.swift (iOS)
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - WalletConnectionScreen (iOS)
// ============================================================================

/// iOS shell for the wallet connection screen.
///
/// Hosts `WalletConnectionScreenCore`, which owns all state, flow orchestration,
/// and section layout. This shell adds the iOS navigation chrome (title,
/// display-mode) and maps `dismiss()` to the Core's `onDismiss` callback.
struct WalletConnectionScreen: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        WalletConnectionScreenCore(onDismiss: { dismiss() })
            .navigationTitle("Connect Wallet")
            .navigationBarTitleDisplayMode(.inline)
    }
}
