// ButtonLabel.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ButtonLabel
// ============================================================================

/// A single-line text label suitable as a button's child view.
///
/// `ButtonLabel` uses `Typography.buttonLabel` (`.subheadline`, 15 pt at the
/// default Dynamic Type size) so the longest grid-cell caption fits naturally
/// in a 2-column layout without runtime scale-factor reduction. All buttons
/// therefore render at the same visual size regardless of whether they occupy
/// a narrow grid cell or the full screen width.
///
/// The font is a Dynamic Type text style, so it still scales with the user's
/// preferred content size.
///
/// Shared between iOS and macOS; SwiftUI primitives only.
///
/// Usage:
/// ```swift
/// Button { ... } label: { ButtonLabel("Disconnect Wallet") }
/// ```
public struct ButtonLabel: View {

    // -------------------------------------------------------------------------
    // MARK: - Configuration
    // -------------------------------------------------------------------------

    /// The text rendered by the button.
    private let label: String

    /// Font weight applied to the rendered text. Defaults to `.semibold` to match
    /// the demo's primary / destructive button typography.
    private let weight: Font.Weight

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates a `ButtonLabel`.
    ///
    /// - Parameters:
    ///   - label: The caption displayed inside the button.
    ///   - weight: Font weight applied to the rendered text. Defaults to `.semibold`.
    public init(_ label: String, weight: Font.Weight = .semibold) {
        self.label = label
        self.weight = weight
    }

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    public var body: some View {
        Text(label)
            .font(Typography.buttonLabel)
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .fontWeight(weight)
    }
}
