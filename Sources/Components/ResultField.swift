// ResultField.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ResultField
// ============================================================================

/// A labeled, copyable field used inside result cards to display wallet
/// creation outcome data such as credential IDs, contract addresses, and
/// transaction hashes.
///
/// Layout:
/// - Small label above the value.
/// - Monospace value text that the user can tap to copy.
/// - "Tap to copy" hint text below the value (hidden from accessibility;
///   the tap gesture announces itself separately).
/// - Tapping the value copies it to the clipboard via the injected
///   `ClipboardService` and signals the provided closure so the parent
///   can show a "Copied" snackbar.
///
/// Shared between iOS and macOS. SwiftUI primitives only — no UIKit or AppKit
/// conditionals in the view body.
public struct ResultField: View {

    // -------------------------------------------------------------------------
    // MARK: - Configuration
    // -------------------------------------------------------------------------

    /// Descriptive label shown above the value (e.g. `"Credential ID"`).
    private let label: String

    /// The value to display and copy (e.g. a contract address).
    private let value: String

    /// Called after the value is written to the clipboard so the parent screen
    /// can show a transient "Copied" snackbar.
    private let onCopied: () -> Void

    // -------------------------------------------------------------------------
    // MARK: - Environment
    // -------------------------------------------------------------------------

    @Environment(\.clipboard) private var clipboard

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates a `ResultField`.
    ///
    /// - Parameters:
    ///   - label: Descriptive label displayed above the value.
    ///   - value: The string to display and copy on tap.
    ///   - onCopied: Called after a successful clipboard write; use to show
    ///     a snackbar at the screen level.
    public init(label: String, value: String, onCopied: @escaping () -> Void) {
        self.label = label
        self.value = value
        self.onCopied = onCopied
    }

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(Color.brandOnSurfaceVariant)
                .accessibilityHidden(true)

            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .onTapGesture(perform: handleCopy)
                .accessibilityLabel("\(label): \(value)")
                // Tailor the hint to the field's label so VoiceOver users hear
                // "Double-tap to copy transaction hash" (or "credential ID",
                // etc.) instead of the generic "Double-tap to copy" verb.
                .accessibilityHint("Double-tap to copy \(label.lowercased())")
                .accessibilityAction(named: "Copy \(label.lowercased())") { handleCopy() }

            Text("Tap to copy")
                .font(Typography.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Copy Action
    // -------------------------------------------------------------------------

    private func handleCopy() {
        clipboard.copy(value, sensitive: false)
        onCopied()
    }
}
