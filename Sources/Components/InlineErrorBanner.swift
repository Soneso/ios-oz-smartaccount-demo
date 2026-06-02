// InlineErrorBanner.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - InlineErrorBanner
// ============================================================================

/// A full-width, capsule-tinted banner used to surface transient validation or
/// flow errors at the top of a screen / section.
///
/// The banner pairs a leading SF Symbol with the message text, tinted on the
/// shared `errorContainer` background so it reads as a recoverable problem
/// rather than a terminal failure. Padding and radius come from the shared
/// `Tokens` so the banner aligns vertically with sibling `SectionCard`s.
///
/// Shared between iOS and macOS; SwiftUI primitives only.
///
/// Usage:
/// ```swift
/// if let message = flow.errorMessage {
///     InlineErrorBanner(message: message)
/// }
/// ```
public struct InlineErrorBanner: View {

    // -------------------------------------------------------------------------
    // MARK: - Configuration
    // -------------------------------------------------------------------------

    /// The human-readable error message displayed inside the banner.
    private let message: String

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates an `InlineErrorBanner`.
    ///
    /// - Parameter message: The error message displayed inside the banner.
    public init(message: String) {
        self.message = message
    }

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.semanticError)
                .accessibilityHidden(true)
            Text(message)
                .foregroundStyle(Color.brandOnSurface)
                .font(Typography.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Tokens.insetPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.errorContainer.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.cardRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }
}
