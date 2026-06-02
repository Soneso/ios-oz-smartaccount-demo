// Typography.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.
//
// Semantic font tokens for the demo's typography ladder. Each token is a
// `Font` value built on `Font.TextStyle` so Dynamic Type scales every text
// surface automatically; pair tokens with `.foregroundStyle(.secondary)` /
// `.tertiary` at call sites to layer tone without re-declaring the role.

import SwiftUI

// ============================================================================
// MARK: - Typography
// ============================================================================

// ============================================================================
// MARK: - ThemeBundleAnchor
// ============================================================================

/// Bundle anchor used by colour-set lookups in `BrandColors` and
/// `SemanticColors`. `Bundle(for: ThemeBundleAnchor.self)` resolves to the
/// bundle that compiled this class, which both the host app and the test
/// targets see as a stable, asset-bearing bundle (the framework target ships
/// the Asset Catalog alongside this file). `Bundle.main` is unreliable in a
/// test process because it points at the xctest runner, not the bundle that
/// owns the resources.
@objc public final class ThemeBundleAnchor: NSObject {

    /// Bundle that owns the Asset Catalog colour-set resources used by the
    /// theme tokens. Cached on the class so callers do not pay for repeated
    /// reflective bundle lookups.
    public static let bundle: Bundle = Bundle(for: ThemeBundleAnchor.self)
}

/// Semantic font roles used across iOS and macOS surfaces.
///
/// Each token is a `Font`, not a view modifier — apply with `.font(Typography.body)`
/// at the call site. Tokens are built on Dynamic Type text styles so they scale
/// with the user's preferred content size (including the AX-class sizes).
public enum Typography {

    /// Page-level title displayed on the primary surface of a screen.
    ///
    /// Backed by `.largeTitle` with an explicit `.bold` weight so the title
    /// reads with the same emphasis as a UIKit large title with a heavy weight
    /// override.
    public static let screenTitle: Font = .largeTitle.weight(.bold)

    /// Section-header label used as the title of a grouped `Form` / `List`
    /// section or as the heading of a card-shaped surface.
    public static let sectionHeader: Font = .headline

    /// Default body copy. Matches the system body text style and is the
    /// baseline against which the other roles are scaled.
    public static let body: Font = .body

    /// Secondary supporting text rendered next to a primary value, such as a
    /// row's auxiliary label or a metadata description. Pair with
    /// `.foregroundStyle(.secondary)` at the call site to reduce contrast.
    public static let secondary: Font = .subheadline

    /// Tertiary metadata such as identifier labels, timestamps, or fine-print
    /// captions. Pair with `.foregroundStyle(.tertiary)` at the call site.
    public static let metadata: Font = .footnote

    /// Monospaced-digit body text used for numeric values that must align
    /// vertically across rows (balances, transaction counts). Built on the
    /// body text style so columnar lists keep a consistent rhythm with
    /// adjacent prose.
    public static let mono: Font = .body.monospacedDigit()

    /// Label for primary and secondary action buttons. Pinned to `.subheadline`
    /// (15 pt at the default Dynamic Type size) so the longest grid-cell caption
    /// ("Account Signers") renders at full size in a 2-column layout without
    /// runtime scale-factor reduction. Still responds to the user's Dynamic Type
    /// setting because it is built on a text style, not a fixed point size.
    public static let buttonLabel: Font = .subheadline

    /// Fine-print caption used for chip labels, compact row annotations, and
    /// inline helper text where `metadata` (footnote) would be too prominent.
    public static let caption: Font = .caption

    /// Secondary caption for the smallest inline labels — status chips, "tap to
    /// copy" hints, and sub-captions beneath a primary caption.
    public static let caption2: Font = .caption2

    /// Sub-title level used inside result cards and summary headers that sit
    /// below a `screenTitle` but need more weight than a plain `sectionHeader`.
    public static let title2: Font = .title2

    /// Title3 size for icon-forward controls (e.g. the checkmark in
    /// `CheckmarkToggleStyle`) where the glyph must visually match adjacent
    /// body text with extra presence.
    public static let title3: Font = .title3
}
