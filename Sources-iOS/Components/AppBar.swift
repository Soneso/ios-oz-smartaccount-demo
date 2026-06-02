// AppBar.swift (iOS)
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - AppBar (iOS)
// ============================================================================

/// Edge-to-edge application bar — solid brand-primary background that
/// extends through the status bar, left-aligned two-line title, and an
/// optional trailing accessory.
///
/// Used by the main screen as a replacement for the platform navigation bar.
/// SwiftUI's standard toolbar pipeline (a single-line title bar with a tinted
/// background) does not match the canonical two-line AppBar appearance the
/// main screen requires as a brand moment, so the main screen hides the
/// platform nav bar and places this view in the top safe-area inset instead.
///
/// Usage:
/// ```swift
/// ScrollView { ... }
///     .safeAreaInset(edge: .top, spacing: 0) {
///         AppBar(title: "...", subtitle: "...") { ThemeModeToggle() }
///     }
///     .toolbar(.hidden, for: .navigationBar)
/// ```
struct AppBar<Trailing: View>: View {

    // -------------------------------------------------------------------------
    // MARK: - Configuration
    // -------------------------------------------------------------------------

    private let title: String
    private let subtitle: String?
    private let trailing: () -> Trailing

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates an `AppBar`.
    ///
    /// - Parameters:
    ///   - title: Bold primary caption rendered in the bar.
    ///   - subtitle: Optional secondary caption rendered immediately below
    ///     the title in a muted tone.
    ///   - trailing: Trailing accessory view (typically `ThemeModeToggle`).
    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    var body: some View {
        HStack(alignment: .center, spacing: Tokens.cardPadding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.sectionHeader)
                    .foregroundStyle(Color.brandOnPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let subtitle {
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(Color.brandOnPrimary.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(subtitle.map { "\(title) — \($0)" } ?? title)

            Spacer(minLength: Tokens.iconLabelSpacing)

            trailing()
                .foregroundStyle(Color.brandOnPrimary)
        }
        .padding(.horizontal, Tokens.cardPadding)
        .padding(.vertical, Tokens.insetPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.brandPrimary.ignoresSafeArea(edges: .top))
    }
}

