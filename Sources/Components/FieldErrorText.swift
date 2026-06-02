// FieldErrorText.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - FieldErrorText
// ============================================================================

/// A caption-sized error message rendered beneath a form field.
///
/// Returns `EmptyView` when `error` is `nil`, so callers can unconditionally
/// place a `FieldErrorText` after each field without managing visibility
/// themselves. When an error is present, the message is rendered with the
/// `semanticError` tint and flagged as static-text for assistive technologies.
///
/// Shared between iOS and macOS; SwiftUI primitives only.
///
/// Usage:
/// ```swift
/// VStack(alignment: .leading) {
///     TextField("Name", text: $name)
///     FieldErrorText(error: validation.nameError)
/// }
/// ```
public struct FieldErrorText: View {

    // -------------------------------------------------------------------------
    // MARK: - Configuration
    // -------------------------------------------------------------------------

    /// The error message to render. When `nil`, the view collapses to nothing.
    private let error: String?

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates a `FieldErrorText`.
    ///
    /// - Parameter error: Error message string, or `nil` to render nothing.
    public init(error: String?) {
        self.error = error
    }

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    @ViewBuilder
    public var body: some View {
        if let error {
            Text(error)
                .font(Typography.caption)
                .foregroundStyle(Color.semanticError)
                .accessibilityAddTraits(.isStaticText)
        } else {
            EmptyView()
        }
    }
}
