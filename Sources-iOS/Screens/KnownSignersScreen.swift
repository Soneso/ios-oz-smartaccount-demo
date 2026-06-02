// KnownSignersScreen.swift (iOS)
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - KnownSignersScreen (iOS)
// ============================================================================

/// iOS shell for the Account Signers screen.
///
/// Hosts `KnownSignersScreenCore` and supplies the navigation chrome.
/// `KnownSignersScreenCore` provides its own `List` container, so the shell
/// does not wrap the body in an additional `ScrollView`. The dismiss closure
/// is backed by `@Environment(\.dismiss)` so the standard navigation pop is used.
struct KnownSignersScreen: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        KnownSignersScreenCore { dismiss() }
            .navigationTitle("Account Signers")
            .navigationBarTitleDisplayMode(.inline)
    }
}
