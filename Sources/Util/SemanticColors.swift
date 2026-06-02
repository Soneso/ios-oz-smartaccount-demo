// SemanticColors.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.
//
// Cross-platform semantic colors for shared SwiftUI views. Every token
// resolves through the bundled Asset Catalog, which carries the Light and
// Dark variants in a single source of truth.

import SwiftUI

extension Color {

    /// Background tone for cards rendered against a grouped-list backdrop.
    ///
    /// Approximates `UIColor.secondarySystemGroupedBackground` (iOS) /
    /// `NSColor.underPageBackgroundColor` (macOS) so the same shared
    /// component file reads naturally on both targets in both appearances.
    static var cardBackground: Color {
        Color("cardBackground", bundle: ThemeBundleAnchor.bundle)
    }

    /// Primary container surface used for the Wallet Status card.
    ///
    /// A lightly tinted blue that gives the card a distinct but non-distracting
    /// background against the page backdrop.
    static var primaryContainer: Color {
        Color("primaryContainer", bundle: ThemeBundleAnchor.bundle)
    }

    // -------------------------------------------------------------------------
    // MARK: - Activity Log Level Badge Colors
    // -------------------------------------------------------------------------
    // These fixed values match the canonical specification so badges read
    // identically across platforms. Semantic names keep usage sites clean.
    // The colors are used as accent (border + tint) on a neutral pill background
    // rather than as text fill, so WCAG AA contrast is met via Color.primary
    // text on Color.surfaceContainerHighest.

    /// Activity log info-level badge accent color (blue).
    static var activityLogInfo: Color {
        Color("activityLogInfo", bundle: ThemeBundleAnchor.bundle)
    }

    /// Activity log success-level badge accent color (green).
    static var activityLogSuccess: Color {
        Color("activityLogSuccess", bundle: ThemeBundleAnchor.bundle)
    }

    /// Activity log error-level badge accent color (red).
    static var activityLogError: Color {
        Color("activityLogError", bundle: ThemeBundleAnchor.bundle)
    }

    // -------------------------------------------------------------------------
    // MARK: - Surface containers
    // -------------------------------------------------------------------------

    /// Neutral surface used as the badge pill background.
    ///
    /// Approximates `UIColor.tertiarySystemBackground` (iOS) /
    /// `NSColor.controlBackgroundColor` (macOS). Both provide a sufficiently
    /// light/distinct background so that `Color.primary` text on top passes
    /// WCAG AA at 4.5:1.
    static var surfaceContainerHighest: Color {
        Color("surfaceContainerHighest", bundle: ThemeBundleAnchor.bundle)
    }

    /// Subtly lifted surface that sits one step above the scaffold backdrop.
    ///
    /// Navy-tinted neutral that pairs with the brand palette: a pale
    /// blue-grey in light appearance and a deep navy-grey in dark
    /// appearance. Used by container surfaces that need a gentle lift
    /// without the stronger emphasis of `cardBackground`.
    static var surfaceContainerLow: Color {
        Color("surfaceContainerLow", bundle: ThemeBundleAnchor.bundle)
    }

    // -------------------------------------------------------------------------
    // MARK: - Tonal containers
    // -------------------------------------------------------------------------
    // Brand-secondary-derived warm-peach pairs for tertiary and secondary
    // tonal containers. Each on-* foreground token is calibrated to meet
    // WCAG AA on top of its matching container background.

    /// Warm tonal-container background derived from the brand-secondary
    /// hue. Light: a pale warm peach. Dark: a deep warm brown.
    static var tertiaryContainer: Color {
        Color("tertiaryContainer", bundle: ThemeBundleAnchor.bundle)
    }

    /// Foreground tone that reads on top of `tertiaryContainer`.
    /// Light: a deep terracotta. Dark: a pale peach.
    static var onTertiaryContainer: Color {
        Color("onTertiaryContainer", bundle: ThemeBundleAnchor.bundle)
    }

    /// Warm tonal-container background, sibling to `tertiaryContainer` with a
    /// fractionally deeper saturation. Light: a warm peach. Dark: a deep
    /// warm brown.
    static var secondaryContainer: Color {
        Color("secondaryContainer", bundle: ThemeBundleAnchor.bundle)
    }

    /// Foreground tone that reads on top of `secondaryContainer`.
    /// Light: a deep terracotta. Dark: a pale peach.
    static var onSecondaryContainer: Color {
        Color("onSecondaryContainer", bundle: ThemeBundleAnchor.bundle)
    }

    // -------------------------------------------------------------------------
    // MARK: - Context Rule Badge Colors
    // -------------------------------------------------------------------------
    // Foreground/background pairs used by the context rules card summary
    // badges. Each pair shares its hue with the corresponding `activityLog*`
    // accent so the visual language is consistent across the surfaces that
    // display signer / policy / expiry information.

    /// Foreground tint for the signer-count badge (blue 800).
    static var contextRuleSignerBadgeForeground: Color {
        Color("contextRuleSignerBadgeForeground", bundle: ThemeBundleAnchor.bundle)
    }

    /// Background tint for the signer-count badge — info accent at 15% alpha.
    static var contextRuleSignerBadgeBackground: Color {
        Color("contextRuleSignerBadgeBackground", bundle: ThemeBundleAnchor.bundle)
    }

    /// Foreground tint for the policy-count badge (green 800).
    static var contextRulePolicyBadgeForeground: Color {
        Color("contextRulePolicyBadgeForeground", bundle: ThemeBundleAnchor.bundle)
    }

    /// Background tint for the policy-count badge — success accent at 15% alpha.
    static var contextRulePolicyBadgeBackground: Color {
        Color("contextRulePolicyBadgeBackground", bundle: ThemeBundleAnchor.bundle)
    }

    /// Foreground tint for the expiry badge (orange 900).
    static var contextRuleExpiryBadgeForeground: Color {
        Color("contextRuleExpiryBadgeForeground", bundle: ThemeBundleAnchor.bundle)
    }

    /// Background tint for the expiry badge — orange 500 at 15% alpha.
    static var contextRuleExpiryBadgeBackground: Color {
        Color("contextRuleExpiryBadgeBackground", bundle: ThemeBundleAnchor.bundle)
    }

    // -------------------------------------------------------------------------
    // MARK: - Accent identifier badge
    // -------------------------------------------------------------------------
    // Pair used by short identifier chips (rule id, generic accent-type tag).
    // Baked from the brand-primary navy so the badge reads as "tag" rather
    // than as a status indicator regardless of the surrounding control tint.

    /// Foreground tint applied to text rendered inside an accent identifier badge.
    static var accentContainerForeground: Color {
        Color("accentContainerForeground", bundle: ThemeBundleAnchor.bundle)
    }

    /// Background tint applied to the fill of an accent identifier badge.
    static var accentContainerBackground: Color {
        Color("accentContainerBackground", bundle: ThemeBundleAnchor.bundle)
    }

    // -------------------------------------------------------------------------
    // MARK: - Semantic status colors
    // -------------------------------------------------------------------------
    // Foreground / container pairs that classify a surface as error, warning,
    // or success. The container colors carry a low-saturation tint suitable
    // as a section background; the `on*` foreground variants meet WCAG AA on
    // top of them.

    /// Foreground tint used for error text, icons, and field-error captions.
    static var semanticError: Color {
        Color("semanticError", bundle: ThemeBundleAnchor.bundle)
    }

    /// Foreground tint used for success icons and confirmations.
    static var semanticSuccess: Color {
        Color("semanticSuccess", bundle: ThemeBundleAnchor.bundle)
    }

    /// Tinted background surface for error banners and rejection containers.
    static var errorContainer: Color {
        Color("errorContainer", bundle: ThemeBundleAnchor.bundle)
    }

    /// Foreground tone that reads on top of `errorContainer`.
    static var onErrorContainer: Color {
        Color("onErrorContainer", bundle: ThemeBundleAnchor.bundle)
    }

    /// Tinted background surface for warning banners and cautionary cards.
    ///
    /// Distinct from `errorContainer` — uses an amber/orange family so warnings
    /// (recoverable problems) read differently from errors (terminal failures).
    static var warningContainer: Color {
        Color("warningContainer", bundle: ThemeBundleAnchor.bundle)
    }

    /// Foreground tone that reads on top of `warningContainer`.
    static var onWarningContainer: Color {
        Color("onWarningContainer", bundle: ThemeBundleAnchor.bundle)
    }

    /// Tinted background surface for success banners and confirmation cards.
    /// Light: a pale green. Dark: a deep forest.
    static var successContainer: Color {
        Color("successContainer", bundle: ThemeBundleAnchor.bundle)
    }

    /// Foreground tone that reads on top of `successContainer`.
    /// Light: a deep forest. Dark: a pale green.
    static var onSuccessContainer: Color {
        Color("onSuccessContainer", bundle: ThemeBundleAnchor.bundle)
    }
}
