// ActivityLogLevelBadge.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ActivityLogLevelBadge
// ============================================================================

/// A small pill badge that renders the textual level label for an activity log
/// entry: `"INFO"`, `"OK"`, or `"ERR"`.
///
/// Shared between iOS and macOS. SwiftUI primitives only.
///
/// Visual design:
/// - Background: `Color.surfaceContainerHighest` (neutral adaptive surface).
/// - Border: level accent color (`activityLogInfo` / `activityLogSuccess` /
///   `activityLogError`) stroked at `Self.borderWidth`.
/// - Text: `Color.primary` (system label color, AA-safe on the neutral surface).
///
/// The accent colors are preserved as the visual cue (border stroke) so the
/// recognisable palette is maintained while WCAG AA contrast (4.5:1) is achieved
/// for the text via `Color.primary` on the neutral background.
///
/// The badge is rendered at a fixed width so all entries in a log list align
/// the message text that follows. Width is `Self.fixedWidth` so three-character
/// labels do not shift the layout between entries.
public struct ActivityLogLevelBadge: View {

    /// The log level to render.
    let level: LogLevel

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    public var body: some View {
        Pill(
            labelText,
            background: Color.surfaceContainerHighest,
            foreground: .primary,
            padding: EdgeInsets(top: 2, leading: 5, bottom: 2, trailing: 5),
            radius: Self.cornerRadius,
            textStyle: .caption2.weight(.bold).monospaced()
        )
        .frame(minWidth: Self.minWidth, alignment: .center)
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .strokeBorder(accentColor, lineWidth: Self.borderWidth)
        )
        .accessibilityLabel(accessibilityText)
    }

    // -------------------------------------------------------------------------
    // MARK: - Helpers
    // -------------------------------------------------------------------------

    private var labelText: String {
        switch level {
        case .info:    return "INFO"
        case .success: return "OK"
        case .error:   return "ERR"
        }
    }

    private var accentColor: Color {
        switch level {
        case .info:    return .activityLogInfo
        case .success: return .activityLogSuccess
        case .error:   return .activityLogError
        }
    }

    private var accessibilityText: String {
        switch level {
        case .info:    return "Info"
        case .success: return "Success"
        case .error:   return "Error"
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Local layout constants
    // -------------------------------------------------------------------------

    /// Minimum rendered width that keeps the badge column aligned across all
    /// three label variants in a vertical activity log list. The badge expands
    /// beyond this value at larger Dynamic Type sizes.
    private static let minWidth: CGFloat = 38

    /// Corner radius applied to both the underlying pill fill and the stroked
    /// accent border so the two shapes register exactly.
    private static let cornerRadius: CGFloat = 4

    /// Stroke width of the level-coloured border that frames the pill.
    private static let borderWidth: CGFloat = 1.5
}
