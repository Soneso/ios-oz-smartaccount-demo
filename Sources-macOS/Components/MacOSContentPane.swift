// MacOSContentPane.swift (macOS)
// SmartAccountDemoMac
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - MacOSContentPane
// ============================================================================

/// View modifier that caps the horizontal width of macOS detail-pane content
/// to `Tokens.cardMaxContentWidth` while keeping it left-aligned inside the
/// available pane width.
///
/// Applied to the top-level content container of each macOS screen (the inner
/// `VStack` for `ScrollView`-hosted screens, the `Group` for `Form`-hosted
/// screens). On wide windows the content column stays at a readable width and
/// the remaining horizontal space is left as whitespace, rather than the form
/// fields and cards stretching across the entire window.
///
/// Use:
/// ```
/// ScrollView {
///     VStack { ... }
///         .padding()
///         .macOSContentPane()
/// }
/// .frame(minWidth: 480)
/// ```
private struct MacOSContentPane: ViewModifier {

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: Tokens.cardMaxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {

    /// Applies `MacOSContentPane`: caps the view's width at
    /// `Tokens.cardMaxContentWidth` and left-aligns it inside any wider parent.
    func macOSContentPane() -> some View {
        modifier(MacOSContentPane())
    }
}
