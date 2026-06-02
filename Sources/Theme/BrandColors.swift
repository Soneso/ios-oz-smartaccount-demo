// BrandColors.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.
//
// Brand-aligned tonal palette used by surfaces that must read with a strong
// product identity. Each token resolves through the bundled Asset Catalog so
// the Light and Dark variants are paired in a single source of truth.

import SwiftUI

extension Color {

    /// Primary brand surface used by the application bar, filled CTA buttons,
    /// and accent foreground tints.
    ///
    /// A medium-saturation navy derived from the deep-navy product seed.
    /// The asset name carries the legacy uppercase spelling because
    /// `Resources/LaunchScreen.storyboard` references the colour by that
    /// exact identifier.
    static var brandPrimary: Color {
        Color("BrandPrimary", bundle: ThemeBundleAnchor.bundle)
    }

    /// Foreground that reads on top of `brandPrimary` (pure white).
    static var brandOnPrimary: Color {
        Color("brandOnPrimary", bundle: ThemeBundleAnchor.bundle)
    }

    /// Secondary brand accent used by chips, badges, and selected toggles.
    /// Reserved for non-navigation surfaces.
    static var brandSecondary: Color {
        Color("brandSecondary", bundle: ThemeBundleAnchor.bundle)
    }

    /// Page-level scaffold background that sits behind every card on the main
    /// dashboard. A light blue-gray that lets card surfaces stand out without
    /// pulling focus from the chrome above.
    static var brandScaffold: Color {
        Color("brandScaffold", bundle: ThemeBundleAnchor.bundle)
    }

    /// Surface tone used by cards rendered against `brandScaffold` (such as
    /// the Activity Log card). Slightly darker than the scaffold so the card
    /// edge reads without an explicit border.
    static var brandCardSurface: Color {
        Color("brandCardSurface", bundle: ThemeBundleAnchor.bundle)
    }

    /// Neutral outline tone used by outlined buttons and divider strokes.
    static var brandOutline: Color {
        Color("brandOutline", bundle: ThemeBundleAnchor.bundle)
    }

    // -------------------------------------------------------------------------
    // MARK: - Brand-tinted text palette
    // -------------------------------------------------------------------------
    // Body and label text rendered with these tones picks up a subtle blue
    // tint that visually ties every screen to the navy AppBar. SwiftUI's
    // plain `.primary` and `.secondary` are pure neutral greys and read as
    // colder / less branded next to the navy chrome.

    /// Primary body-text tone — the brand-tinted analogue of SwiftUI's
    /// `Color.primary` (`UIColor.label`).
    ///
    /// Light: dark navy-grey, clearly blue-tinted vs SwiftUI's pure-black label.
    /// Dark: pale navy-grey, clearly blue-tinted vs SwiftUI's pure-white label.
    static var brandOnSurface: Color {
        Color("brandOnSurface", bundle: ThemeBundleAnchor.bundle)
    }

    /// Secondary / muted text tone — the brand-tinted analogue of SwiftUI's
    /// `Color.secondary` (`UIColor.secondaryLabel`).
    ///
    /// Light: slate-blue grey, clearly blue-tinted vs SwiftUI's neutral 60%
    /// black secondary label.
    /// Dark: cool blue-grey, clearly blue-tinted vs SwiftUI's neutral
    /// secondary label.
    static var brandOnSurfaceVariant: Color {
        Color("brandOnSurfaceVariant", bundle: ThemeBundleAnchor.bundle)
    }
}
