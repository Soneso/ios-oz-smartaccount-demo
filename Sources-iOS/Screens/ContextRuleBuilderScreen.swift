// ContextRuleBuilderScreen.swift (iOS)
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ContextRuleBuilderScreen (iOS)
// ============================================================================

/// iOS shell for the context rule builder screen.
///
/// Hosts `ContextRuleBuilderCore`, which supplies its own native `Form`
/// container. The shell installs the navigation chrome. Dismiss returns to the
/// previous screen via `@Environment(\.dismiss)`.
///
/// When `editRuleId` is non-nil the screen loads the matching on-chain rule
/// into the form and dispatches edit-mode submission.
struct ContextRuleBuilderScreen: View {

    @Environment(\.dismiss) private var dismiss

    let editRuleId: UInt32?

    init(editRuleId: UInt32? = nil) {
        self.editRuleId = editRuleId
    }

    private var screenTitle: String {
        editRuleId == nil ? "Add Context Rule" : "Edit Context Rule"
    }

    var body: some View {
        ContextRuleBuilderCore(editRuleId: editRuleId) { dismiss() }
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
    }
}
