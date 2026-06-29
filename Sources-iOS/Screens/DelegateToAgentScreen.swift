// DelegateToAgentScreen.swift (iOS)
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - DelegateToAgentScreen (iOS)
// ============================================================================

/// iOS shell for the delegate-to-agent screen.
///
/// Hosts `DelegateToAgentScreenCore`, which supplies its own native `Form`
/// container. The dismiss closure is backed by `@Environment(\.dismiss)` so the
/// standard navigation pop is used.
struct DelegateToAgentScreen: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DelegateToAgentScreenCore { dismiss() }
            .navigationTitle("Delegate to Agent")
            .navigationBarTitleDisplayMode(.inline)
    }
}
