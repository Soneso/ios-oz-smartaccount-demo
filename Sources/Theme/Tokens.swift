// Tokens.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.
//
// Shared layout constants used across iOS and macOS surfaces. Every numeric
// literal with semantic meaning (padding, radius, surface widths, spinner
// sizing) is declared here so call sites stay free of magic numbers.

import CoreGraphics

// ============================================================================
// MARK: - Tokens
// ============================================================================

/// Layout constants for the demo's shared design system.
///
/// These values are platform-agnostic and resolved at compile time. Call sites
/// must consume these tokens instead of duplicating numeric literals so that a
/// future scale or rhythm change touches a single location.
public enum Tokens {

    /// Outer padding applied to the contents of a `SectionCard`.
    public static let cardPadding: CGFloat = 16

    /// Inset padding used by inline surfaces (banners, list rows, tight stacks).
    public static let insetPadding: CGFloat = 12

    /// Corner radius applied to chip-shaped surfaces (pills, badges).
    public static let chipRadius: CGFloat = 8

    /// Corner radius applied to card-shaped surfaces (`SectionCard`, banners).
    public static let cardRadius: CGFloat = 12

    /// Corner radius applied to control-sized surfaces on macOS (e.g. the
    /// macOS variant of `SectionCard` which uses a tighter radius to match
    /// the platform's window-panel aesthetic).
    public static let controlRadius: CGFloat = 10

    /// Corner radius applied to banner-shaped surfaces (`InlineErrorBanner`,
    /// `PendingCredentialCard`, `UndeployedResultCard` warning stripe). Matches
    /// `controlRadius` numerically but is named separately so a future
    /// per-surface adjustment does not require touching every call site.
    public static let bannerRadius: CGFloat = 10

    /// Upper bound on the rendered width of a content pane on macOS hosts.
    public static let cardMaxContentWidth: CGFloat = 720

    /// Side length of the inline spinner used by `LoadingButton` and friends.
    public static let spinnerSize: CGFloat = 16

    /// Horizontal gap between a leading icon and its adjacent label inside an
    /// inline composite control (e.g. a balance figure preceded by an SF
    /// Symbol, or a chip with a leading glyph).
    public static let iconLabelSpacing: CGFloat = 8

    /// Maximum number of activity log entries rendered inside
    /// `ActivityLogCard`. The full log is retained in `ActivityLogState`; this
    /// cap only bounds the rendered list height so long-running sessions do
    /// not balloon the card. iOS surfaces favour a denser cap to keep the main
    /// screen scrollable on phone-sized canvases; macOS surfaces use a larger
    /// cap because the activity pane has substantially more vertical room.
    #if os(macOS)
    public static let activityLogMaxVisible: Int = 50
    #else
    public static let activityLogMaxVisible: Int = 10
    #endif
}
