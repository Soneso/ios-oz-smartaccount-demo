// KeyValueRow.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - KeyValueRow (generic value)
// ============================================================================

/// A horizontal "label : value" row with a fixed-width label gutter.
///
/// The label sits left-aligned in a fixed gutter so multiple rows stack into a
/// visually aligned column. The value occupies the remaining width and is
/// pushed against the trailing edge by a `Spacer`.
///
/// Two overloads are provided:
///
/// 1. The generic `KeyValueRow(label:labelWidth:content:)` accepts any view as
///    the value (e.g. a `Pill`, an icon button, or a layout).
/// 2. The convenience `KeyValueRow(label:value:labelWidth:monospace:emphasised:)`
///    initializer renders a plain-text value with optional monospaced /
///    emphasised styling.
///
/// Shared between iOS and macOS; SwiftUI primitives only.
public struct KeyValueRow<Content: View>: View {

    // -------------------------------------------------------------------------
    // MARK: - Configuration
    // -------------------------------------------------------------------------

    private let label: String
    private let labelWidth: CGFloat
    private let content: () -> Content

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates a `KeyValueRow` whose value is any custom view.
    ///
    /// - Parameters:
    ///   - label: Caption shown in the left gutter.
    ///   - labelWidth: Width allocated to the label gutter. Defaults to 110pt.
    ///   - content: Trailing view-builder rendering the value.
    public init(
        label: String,
        labelWidth: CGFloat = 110,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.label = label
        self.labelWidth = labelWidth
        self.content = content
    }

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(Typography.caption.weight(.semibold))
                .foregroundStyle(Color.brandOnSurfaceVariant)
                .frame(width: labelWidth, alignment: .leading)
            Spacer(minLength: 0)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// ============================================================================
// MARK: - KeyValueRow (plain-text value convenience)
// ============================================================================

public extension KeyValueRow where Content == KeyValueRowText {

    /// Creates a `KeyValueRow` whose value is a plain text string.
    ///
    /// - Parameters:
    ///   - label: Caption shown in the left gutter.
    ///   - value: Text rendered as the value.
    ///   - labelWidth: Width allocated to the label gutter. Defaults to 110pt.
    ///   - monospace: When `true`, the value is rendered with the platform's
    ///     monospaced design — useful for hashes, addresses, or amounts.
    ///   - emphasised: When `true`, the value is rendered bold and with
    ///     monospaced digit alignment.
    init(
        label: String,
        value: String,
        labelWidth: CGFloat = 110,
        monospace: Bool = false,
        emphasised: Bool = false
    ) {
        self.init(label: label, labelWidth: labelWidth) {
            KeyValueRowText(
                value: value,
                monospace: monospace,
                emphasised: emphasised
            )
        }
    }
}

// ============================================================================
// MARK: - KeyValueRowText
// ============================================================================

/// Plain-text value renderer used by the convenience `KeyValueRow` initializer.
///
/// Exposed publicly only because it is the resolved `Content` type of the
/// convenience overload; call sites should construct `KeyValueRow` directly
/// rather than instantiating this view themselves.
public struct KeyValueRowText: View {

    private let value: String
    private let monospace: Bool
    private let emphasised: Bool

    public init(value: String, monospace: Bool, emphasised: Bool) {
        self.value = value
        self.monospace = monospace
        self.emphasised = emphasised
    }

    public var body: some View {
        let text = Text(value)
        if emphasised {
            text.font(Typography.body.weight(.bold).monospacedDigit())
        } else if monospace {
            text.font(Typography.body.monospaced())
        } else {
            text.font(Typography.body)
        }
    }
}
