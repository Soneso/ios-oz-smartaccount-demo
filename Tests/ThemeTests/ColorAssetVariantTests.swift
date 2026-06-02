// ColorAssetVariantTests.swift
// SmartAccountDemoTests
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import SwiftUI
#if canImport(UIKit)
@testable import SmartAccountDemoLib
import UIKit
#else
@testable import SmartAccountDemoMacLib
import AppKit
#endif
import Testing

// ============================================================================
// MARK: - ColorAssetVariantTests
// ============================================================================

/// Resolves every brand and semantic colour token in both the light and dark
/// appearances and verifies the expected sRGB component values.
///
/// The Asset Catalog stores Light and Dark variants in a single colour-set
/// entry. The tests guard against silent dark-variant drift by reading the
/// resolved component values back through the platform's appearance APIs
/// and comparing to the expected three-decimal values.
@Suite("ColorAssetVariants")
struct ColorAssetVariantTests {

    // -------------------------------------------------------------------------
    // MARK: - Brand palette — dynamic tokens
    // -------------------------------------------------------------------------

    @Test("brandOnSurface resolves the documented light and dark variants")
    func brandOnSurfaceVariants() {
        assertVariants(
            assetName: "brandOnSurface",
            light: RGBA(red: 0.122, green: 0.165, blue: 0.239, alpha: 1.000),
            dark: RGBA(red: 0.847, green: 0.863, blue: 0.910, alpha: 1.000)
        )
    }

    @Test("brandOnSurfaceVariant resolves the documented light and dark variants")
    func brandOnSurfaceVariantVariants() {
        assertVariants(
            assetName: "brandOnSurfaceVariant",
            light: RGBA(red: 0.361, green: 0.412, blue: 0.510, alpha: 1.000),
            dark: RGBA(red: 0.714, green: 0.729, blue: 0.788, alpha: 1.000)
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - Semantic status — dynamic tokens
    // -------------------------------------------------------------------------

    @Test("semanticError resolves the documented light and dark variants")
    func semanticErrorVariants() {
        assertVariants(
            assetName: "semanticError",
            light: RGBA(red: 0.720, green: 0.110, blue: 0.110, alpha: 1.000),
            dark: RGBA(red: 1.000, green: 0.550, blue: 0.550, alpha: 1.000)
        )
    }

    @Test("semanticSuccess resolves the documented light and dark variants")
    func semanticSuccessVariants() {
        assertVariants(
            assetName: "semanticSuccess",
            light: RGBA(red: 0.180, green: 0.490, blue: 0.200, alpha: 1.000),
            dark: RGBA(red: 0.510, green: 0.780, blue: 0.520, alpha: 1.000)
        )
    }

    @Test("errorContainer resolves the documented light and dark variants")
    func errorContainerVariants() {
        assertVariants(
            assetName: "errorContainer",
            light: RGBA(red: 1.000, green: 0.910, blue: 0.910, alpha: 1.000),
            dark: RGBA(red: 0.360, green: 0.100, blue: 0.100, alpha: 1.000)
        )
    }

    @Test("onErrorContainer resolves the documented light and dark variants")
    func onErrorContainerVariants() {
        assertVariants(
            assetName: "onErrorContainer",
            light: RGBA(red: 0.410, green: 0.000, blue: 0.050, alpha: 1.000),
            dark: RGBA(red: 1.000, green: 0.850, blue: 0.850, alpha: 1.000)
        )
    }

    @Test("warningContainer resolves the documented light and dark variants")
    func warningContainerVariants() {
        assertVariants(
            assetName: "warningContainer",
            light: RGBA(red: 1.000, green: 0.950, blue: 0.800, alpha: 1.000),
            dark: RGBA(red: 0.360, green: 0.270, blue: 0.000, alpha: 1.000)
        )
    }

    @Test("onWarningContainer resolves the documented light and dark variants")
    func onWarningContainerVariants() {
        assertVariants(
            assetName: "onWarningContainer",
            light: RGBA(red: 0.400, green: 0.270, blue: 0.000, alpha: 1.000),
            dark: RGBA(red: 1.000, green: 0.880, blue: 0.550, alpha: 1.000)
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - Surface tokens — dynamic (real light/dark pairs)
    // -------------------------------------------------------------------------

    @Test("brandScaffold resolves the documented light and dark variants")
    func brandScaffoldVariants() {
        assertVariants(
            assetName: "brandScaffold",
            light: RGBA(red: 0.945, green: 0.953, blue: 0.973, alpha: 1.000),
            dark:  RGBA(red: 0.071, green: 0.090, blue: 0.122, alpha: 1.000)
        )
    }

    @Test("brandCardSurface resolves the documented light and dark variants")
    func brandCardSurfaceVariants() {
        assertVariants(
            assetName: "brandCardSurface",
            light: RGBA(red: 0.910, green: 0.918, blue: 0.941, alpha: 1.000),
            dark:  RGBA(red: 0.110, green: 0.133, blue: 0.169, alpha: 1.000)
        )
    }

    @Test("primaryContainer resolves the documented light and dark variants")
    func primaryContainerVariants() {
        assertVariants(
            assetName: "primaryContainer",
            light: RGBA(red: 0.910, green: 0.945, blue: 1.000, alpha: 1.000),
            dark:  RGBA(red: 0.137, green: 0.196, blue: 0.314, alpha: 1.000)
        )
    }

    @Test("brandOutline resolves the documented light and dark variants")
    func brandOutlineVariants() {
        assertVariants(
            assetName: "brandOutline",
            light: RGBA(red: 0.475, green: 0.455, blue: 0.494, alpha: 1.000),
            dark:  RGBA(red: 0.388, green: 0.388, blue: 0.439, alpha: 1.000)
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - Badge foreground tokens — dynamic (real light/dark pairs)
    // -------------------------------------------------------------------------

    @Test("contextRuleSignerBadgeForeground resolves the documented light and dark variants")
    func contextRuleSignerBadgeForegroundVariants() {
        assertVariants(
            assetName: "contextRuleSignerBadgeForeground",
            light: RGBA(red: 0.082, green: 0.396, blue: 0.753, alpha: 1.000),
            dark:  RGBA(red: 0.565, green: 0.792, blue: 0.976, alpha: 1.000)
        )
    }

    @Test("contextRulePolicyBadgeForeground resolves the documented light and dark variants")
    func contextRulePolicyBadgeForegroundVariants() {
        assertVariants(
            assetName: "contextRulePolicyBadgeForeground",
            light: RGBA(red: 0.180, green: 0.490, blue: 0.196, alpha: 1.000),
            dark:  RGBA(red: 0.620, green: 0.878, blue: 0.627, alpha: 1.000)
        )
    }

    @Test("contextRuleExpiryBadgeForeground resolves the documented light and dark variants")
    func contextRuleExpiryBadgeForegroundVariants() {
        assertVariants(
            assetName: "contextRuleExpiryBadgeForeground",
            light: RGBA(red: 0.902, green: 0.318, blue: 0.000, alpha: 1.000),
            dark:  RGBA(red: 1.000, green: 0.878, blue: 0.502, alpha: 1.000)
        )
    }

    @Test("accentContainerForeground resolves the documented light and dark variants")
    func accentContainerForegroundVariants() {
        assertVariants(
            assetName: "accentContainerForeground",
            light: RGBA(red: 0.239, green: 0.361, blue: 0.549, alpha: 1.000),
            dark:  RGBA(red: 0.722, green: 0.804, blue: 0.933, alpha: 1.000)
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - Fixed brand-identity tokens — resolve without crashing
    // -------------------------------------------------------------------------

    @Test("Fixed brand-identity tokens resolve in both appearances")
    func staticTokensResolve() {
        // Tokens with intentionally identical light and dark values — fixed
        // brand-identity colors that do not adapt to appearance.
        let staticTokens = [
            "BrandPrimary",
            "brandOnPrimary",
            "brandSecondary",
            "activityLogInfo",
            "activityLogSuccess",
            "activityLogError",
            "contextRuleSignerBadgeBackground",
            "contextRulePolicyBadgeBackground",
            "contextRuleExpiryBadgeBackground",
            "accentContainerBackground",
        ]
        for name in staticTokens {
            let light = resolveColor(named: name, isDark: false)
            let dark = resolveColor(named: name, isDark: true)
            #expect(light != nil, "Light variant for \(name) failed to resolve")
            #expect(dark != nil, "Dark variant for \(name) failed to resolve")
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Brand-new tokens — resolve without crashing
    // -------------------------------------------------------------------------

    @Test("New tonal tokens resolve in both appearances")
    func newTokensResolve() {
        let newTokens = [
            "tertiaryContainer",
            "onTertiaryContainer",
            "secondaryContainer",
            "onSecondaryContainer",
            "surfaceContainerLow",
            "successContainer",
            "onSuccessContainer",
            "cardBackground",
            "surfaceContainerHighest",
        ]
        for name in newTokens {
            let light = resolveColor(named: name, isDark: false)
            let dark = resolveColor(named: name, isDark: true)
            #expect(light != nil, "Light variant for \(name) failed to resolve")
            #expect(dark != nil, "Dark variant for \(name) failed to resolve")
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Helpers
    // -------------------------------------------------------------------------

    private struct RGBA {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

    /// Tolerance used when comparing component values. The Asset Catalog
    /// re-quantises stored values when resolving through the platform
    /// rendering pipeline, so a small slack absorbs the rounding noise
    /// without masking a wrong variant.
    private static let tolerance: Double = 0.005

    /// Asserts that the asset resolves to `light` in light appearance and
    /// `dark` in dark appearance. Each channel is compared with `tolerance`.
    private func assertVariants(assetName: String, light: RGBA, dark: RGBA) {
        guard let resolvedLight = resolveColor(named: assetName, isDark: false) else {
            Issue.record("Asset \(assetName) did not resolve in light appearance")
            return
        }
        guard let resolvedDark = resolveColor(named: assetName, isDark: true) else {
            Issue.record("Asset \(assetName) did not resolve in dark appearance")
            return
        }
        assertApproxEqual(resolvedLight, light, asset: assetName, appearance: "light")
        assertApproxEqual(resolvedDark, dark, asset: assetName, appearance: "dark")
    }

    private func assertApproxEqual(_ actual: RGBA, _ expected: RGBA, asset: String, appearance: String) {
        let tolerance = Self.tolerance
        #expect(
            abs(actual.red - expected.red) <= tolerance,
            "\(asset) [\(appearance)] red: expected \(expected.red), got \(actual.red) (tolerance \(tolerance))"
        )
        #expect(
            abs(actual.green - expected.green) <= tolerance,
            "\(asset) [\(appearance)] green: expected \(expected.green), got \(actual.green) (tolerance \(tolerance))"
        )
        #expect(
            abs(actual.blue - expected.blue) <= tolerance,
            "\(asset) [\(appearance)] blue: expected \(expected.blue), got \(actual.blue) (tolerance \(tolerance))"
        )
        #expect(
            abs(actual.alpha - expected.alpha) <= tolerance,
            "\(asset) [\(appearance)] alpha: expected \(expected.alpha), got \(actual.alpha) (tolerance \(tolerance))"
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - Platform-specific resolution
    // -------------------------------------------------------------------------

    /// The bundle whose Asset Catalog carries the colour-set resources used
    /// by the tests. Matches the bundle that the production code uses for
    /// the same lookups, so the test exercises the same code path the app
    /// runs at launch.
    private static let resourceBundle = ThemeBundleAnchor.bundle

    #if canImport(UIKit)

    /// Resolves a named Asset Catalog colour in the requested appearance using
    /// the iOS / iPadOS / tvOS trait-collection API.
    private func resolveColor(named name: String, isDark: Bool) -> RGBA? {
        guard let uiColor = UIColor(named: name, in: Self.resourceBundle, compatibleWith: nil) else {
            return nil
        }
        let style: UIUserInterfaceStyle = isDark ? .dark : .light
        let traits = UITraitCollection(userInterfaceStyle: style)
        let resolved = uiColor.resolvedColor(with: traits)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        return RGBA(red: Double(red), green: Double(green), blue: Double(blue), alpha: Double(alpha))
    }

    #elseif canImport(AppKit)

    /// Resolves a named Asset Catalog colour in the requested appearance using
    /// the macOS `NSAppearance` performAsCurrentDrawingAppearance API
    /// (available macOS 11+).
    private func resolveColor(named name: String, isDark: Bool) -> RGBA? {
        guard let nsColor = NSColor(named: NSColor.Name(name), bundle: Self.resourceBundle) else {
            return nil
        }
        let appearanceName: NSAppearance.Name = isDark ? .darkAqua : .aqua
        guard let appearance = NSAppearance(named: appearanceName) else {
            return nil
        }
        var captured: RGBA?
        appearance.performAsCurrentDrawingAppearance {
            guard let srgb = nsColor.usingColorSpace(.sRGB) else { return }
            captured = RGBA(
                red: Double(srgb.redComponent),
                green: Double(srgb.greenComponent),
                blue: Double(srgb.blueComponent),
                alpha: Double(srgb.alphaComponent)
            )
        }
        return captured
    }

    #endif
}

