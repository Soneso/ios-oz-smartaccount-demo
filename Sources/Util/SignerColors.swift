// SignerColors.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.
//
// Signer type colours are stored in the shared Asset Catalog as named colorsets
// so Xcode manages Light / Dark variants automatically. Each colorset is loaded
// via `ThemeBundleAnchor.bundle` (the same bundle used by all other colorsets)
// so the lookup works both in the host app and in the test target.
//
// Colorset RGB values (sRGB, alpha 1.0):
//   signerPasskey       — light: (0.612, 0.153, 0.690) purple
//                         dark:  (0.780, 0.400, 0.820) lighter purple
//   signerStellarAccount — light: (0.129, 0.588, 0.953) blue
//                          dark:  (0.380, 0.745, 1.000) lighter blue
//   signerEd25519        — light: (0.000, 0.588, 0.533) teal
//                          dark:  (0.200, 0.780, 0.710) lighter teal
//   signerUnknown        — light: (0.376, 0.490, 0.545) slate grey
//                          dark:  (0.540, 0.640, 0.690) lighter slate grey

import SwiftUI

// ============================================================================
// MARK: - Signer Type Colors
// ============================================================================

/// Returns a SwiftUI `Color` for a signer type identifier string.
///
/// Recognises both the long SDK description form and the short labels returned
/// by `signerTypeLabel(for:)`:
/// - `"Passkey (WebAuthn)"` / `"Passkey"`        → purple
/// - `"Stellar Account"`   / `"G-Address"`       → blue
/// - `"Ed25519"`                                  → teal
/// - anything else                                → grey
///
/// Colors are resolved from the shared Asset Catalog via
/// `ThemeBundleAnchor.bundle` so Light / Dark variants are applied
/// automatically by the system. They carry type meaning, not state meaning.
public func signerTypeColor(for signerType: String) -> Color {
    switch signerType {
    case "Passkey (WebAuthn)", "Passkey":
        return Color("signerPasskey", bundle: ThemeBundleAnchor.bundle)
    case "Stellar Account", "G-Address":
        return Color("signerStellarAccount", bundle: ThemeBundleAnchor.bundle)
    case "Ed25519":
        return Color("signerEd25519", bundle: ThemeBundleAnchor.bundle)
    default:
        return Color("signerUnknown", bundle: ThemeBundleAnchor.bundle)
    }
}
