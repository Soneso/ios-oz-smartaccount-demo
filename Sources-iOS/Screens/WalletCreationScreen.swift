// WalletCreationScreen.swift (iOS)
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - WalletCreationScreen (iOS)
// ============================================================================

/// iOS shell for the wallet creation screen.
///
/// Hosts `WalletCreationScreenCore`, which owns all form state, passkey
/// orchestration, and result-card presentation. This shell adds the iOS
/// navigation chrome (title, display-mode) and maps `dismiss()` to the
/// Core's `onDismiss` callback.
struct WalletCreationScreen: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        WalletCreationScreenCore(onDismiss: { dismiss() })
            .navigationTitle("Create Wallet")
            .navigationBarTitleDisplayMode(.inline)
    }
}
