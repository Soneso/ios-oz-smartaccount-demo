// ApproveScreen.swift (iOS)
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ApproveScreen (iOS)
// ============================================================================

/// iOS shell for the token-allowance approve screen.
///
/// Hosts `ApproveScreenCore` and supplies the navigation chrome.
/// `ApproveScreenCore` provides its own native `Form` container, so the shell
/// does not wrap the body in an additional `ScrollView`. The dismiss closure
/// is backed by `@Environment(\.dismiss)` so the standard navigation pop is used.
struct ApproveScreen: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ApproveScreenCore { dismiss() }
            .navigationTitle("Approve")
            .navigationBarTitleDisplayMode(.inline)
    }
}
