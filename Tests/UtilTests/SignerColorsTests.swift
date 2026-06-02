// SignerColorsTests.swift
// SmartAccountDemoTests
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI
#if canImport(UIKit)
@testable import SmartAccountDemoLib
#else
@testable import SmartAccountDemoMacLib
#endif
import Testing
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// ============================================================================
// MARK: - SignerColorsTests
// ============================================================================

/// Tests for `signerTypeColor(for:)` in `SignerColors.swift`.
///
/// Each known signer type must return a distinct non-default color.
/// Unknown types return the grey fallback. Tests compare the RGB components
/// to the expected literal values documented in `SignerColors.swift`.
@Suite("SignerColors")
struct SignerColorsTests {

    @Test("Passkey (WebAuthn) returns purple color")
    func passkeyReturnsCorrectColor() {
        let color = signerTypeColor(for: "Passkey (WebAuthn)")
        let resolved = resolveColor(color)
        assertApproxEqual(resolved.red, 0.612, label: "red")
        assertApproxEqual(resolved.green, 0.153, label: "green")
        assertApproxEqual(resolved.blue, 0.690, label: "blue")
    }

    @Test("Stellar Account returns blue color")
    func stellarAccountReturnsCorrectColor() {
        let color = signerTypeColor(for: "Stellar Account")
        let resolved = resolveColor(color)
        assertApproxEqual(resolved.red, 0.129, label: "red")
        assertApproxEqual(resolved.green, 0.588, label: "green")
        assertApproxEqual(resolved.blue, 0.953, label: "blue")
    }

    @Test("Ed25519 returns teal color")
    func ed25519ReturnsCorrectColor() {
        let color = signerTypeColor(for: "Ed25519")
        let resolved = resolveColor(color)
        assertApproxEqual(resolved.red, 0.0, label: "red")
        assertApproxEqual(resolved.green, 0.588, label: "green")
        assertApproxEqual(resolved.blue, 0.533, label: "blue")
    }

    @Test("Unknown signer type returns grey fallback color")
    func unknownSignerTypeReturnsGrey() {
        let color = signerTypeColor(for: "SomeUnknownSignerType")
        let resolved = resolveColor(color)
        assertApproxEqual(resolved.red, 0.376, label: "red")
        assertApproxEqual(resolved.green, 0.490, label: "green")
        assertApproxEqual(resolved.blue, 0.545, label: "blue")
    }

    @Test("Empty string returns grey fallback color")
    func emptySignerTypeReturnsGrey() {
        let known = signerTypeColor(for: "SomeUnknownSignerType")
        let empty = signerTypeColor(for: "")
        let knownResolved = resolveColor(known)
        let emptyResolved = resolveColor(empty)
        // Both unknown strings must resolve to the same fallback.
        assertApproxEqual(emptyResolved.red, knownResolved.red, label: "red")
        assertApproxEqual(emptyResolved.green, knownResolved.green, label: "green")
        assertApproxEqual(emptyResolved.blue, knownResolved.blue, label: "blue")
    }

    // -------------------------------------------------------------------------
    // MARK: - Helpers
    // -------------------------------------------------------------------------

    private struct RGBComponents {
        let red: Double
        let green: Double
        let blue: Double
    }

    private func resolveColor(_ color: Color) -> RGBComponents {
        // Resolve to CGColor in the sRGB colour space so we can read the components.
        // The Color(red:green:blue:) initializer uses the sRGB colour space, so the
        // components we read back should match the values we wrote.
        #if canImport(UIKit)
        let cgColor = UIColor(color).cgColor
        #else
        let cgColor = NSColor(color).cgColor
        #endif
        let components = cgColor.components ?? [0, 0, 0, 1]
        return RGBComponents(
            red: Double(components[0]),
            green: Double(components[1]),
            blue: Double(components[2])
        )
    }

    private func assertApproxEqual(_ actual: Double, _ expected: Double, label: String) {
        let tolerance = 0.002
        #expect(
            abs(actual - expected) <= tolerance,
            "\(label): expected \(expected), got \(actual) (tolerance ±\(tolerance))"
        )
    }
}
