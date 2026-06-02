// Pill.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - Pill
// ============================================================================

/// A capsule-shaped, tinted label used for status badges, counts, and tags.
///
/// `Pill` is the shared "capsule + tinted text" badge used throughout the
/// demo. The caller controls the colour pair (so context rule signer /
/// policy / expiry badges share one shape but stay visually distinct) and
/// may attach a leading SF Symbol via `icon`.
///
/// Shared between iOS and macOS; SwiftUI primitives only.
///
/// Usage:
/// ```swift
/// Pill(
///     "Active",
///     background: Color.contextRuleSignerBadgeBackground,
///     foreground: Color.contextRuleSignerBadgeForeground
/// )
///
/// Pill(
///     "3 signers",
///     background: Color.contextRuleSignerBadgeBackground,
///     foreground: Color.contextRuleSignerBadgeForeground,
///     icon: Image(systemName: "person.2.fill")
/// )
/// ```
public struct Pill: View {

    // -------------------------------------------------------------------------
    // MARK: - Configuration
    // -------------------------------------------------------------------------

    /// Caption text rendered inside the pill.
    private let label: String

    /// Tint applied to the capsule fill.
    private let background: Color

    /// Tint applied to the icon and text.
    private let foreground: Color

    /// Optional leading icon shown to the left of the label.
    private let icon: Image?

    /// Internal padding around the label / icon stack.
    private let padding: EdgeInsets

    /// Corner radius applied to the capsule. Defaults to `Tokens.chipRadius`.
    private let radius: CGFloat

    /// Font applied to the rendered text.
    private let textStyle: Font

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates a `Pill`.
    ///
    /// - Parameters:
    ///   - label: Caption text rendered inside the pill.
    ///   - background: Tint applied to the capsule fill.
    ///   - foreground: Tint applied to the icon and text.
    ///   - icon: Optional SF Symbol image shown leading the label.
    ///   - padding: Internal padding around the content. Defaults to the
    ///     compact `2 / 8` rhythm used by status badges.
    ///   - radius: Corner radius applied to the capsule. Defaults to
    ///     `Tokens.chipRadius`.
    ///   - textStyle: Font applied to the rendered text. Defaults to
    ///     `caption.weight(.semibold)`.
    public init(
        _ label: String,
        background: Color,
        foreground: Color,
        icon: Image? = nil,
        padding: EdgeInsets = EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8),
        radius: CGFloat = Tokens.chipRadius,
        textStyle: Font = .caption.weight(.semibold)
    ) {
        self.label = label
        self.background = background
        self.foreground = foreground
        self.icon = icon
        self.padding = padding
        self.radius = radius
        self.textStyle = textStyle
    }

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    public var body: some View {
        HStack(spacing: 4) {
            if let icon {
                icon
                    .font(textStyle)
                    .foregroundStyle(foreground)
                    .accessibilityHidden(true)
            }
            Text(label)
                .font(textStyle)
                .foregroundStyle(foreground)
        }
        .padding(padding)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}
