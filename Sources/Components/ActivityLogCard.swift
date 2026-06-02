// ActivityLogCard.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ActivityLogCard
// ============================================================================

/// Displays the most recent activity log entries from `ActivityLogState`.
///
/// Shared between iOS and macOS. SwiftUI primitives only — no UIKit or AppKit
/// conditionals in the view body.
///
/// Layout:
/// - Header row: "Activity Log (N)" showing the full entry count, and a
///   "Clear" outlined button that removes all entries.
/// - Up to `Tokens.activityLogMaxVisible` entries rendered newest-first inside
///   a `LazyVStack`. Each entry shows a short HH:mm:ss timestamp, a level
///   text badge (INFO / OK / ERR), and the message.
/// - Tapping an entry copies its redacted message to the clipboard and shows a
///   "Log message copied to clipboard" snackbar via the provided binding.
///
/// Card chrome:
/// - The card paints its own background, padding, and corner-radius surface.
///   Entries are stacked in a `LazyVStack` so the card composes correctly
///   inside any outer container — including a native `List` row — without
///   the nested-List height-collapse that occurs when a `List` is embedded
///   inside another `List`.
///
/// Empty state:
/// - When the log has no entries, "No activity yet" is shown (no trailing period).
///
/// Accessibility:
/// - Each row is an independent accessibility element with a combined label.
/// - The copy action is exposed as an accessibility action on each row.
public struct ActivityLogCard: View {

    @EnvironmentObject private var activityLog: ActivityLogState

    /// Platform clipboard injected via `ActivityLogCard.clipboardKey`.
    ///
    /// Defaults to `NoOpClipboard` when no concrete clipboard has been placed
    /// in the environment by the host App.
    @Environment(\.clipboard) private var clipboard

    /// Binding for the bottom snackbar overlay owned by the parent screen.
    @Binding var snackbarMessage: SnackbarMessage?

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates an `ActivityLogCard`.
    ///
    /// - Parameter snackbarMessage: Binding to the parent's snackbar state so
    ///   this card can post "Log message copied to clipboard" toasts.
    public init(snackbarMessage: Binding<SnackbarMessage?>) {
        self._snackbarMessage = snackbarMessage
    }

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    public var body: some View {
        VStack(alignment: .leading, spacing: Tokens.insetPadding) {
            headerRow

            Divider()

            if activityLog.entries.isEmpty {
                emptyState
            } else {
                logList
            }
        }
        .padding(Tokens.cardPadding)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.cardRadius))
    }

    // -------------------------------------------------------------------------
    // MARK: - Subviews
    // -------------------------------------------------------------------------

    private var headerRow: some View {
        HStack {
            Text("Activity Log (\(activityLog.entries.count))")
                .font(Typography.sectionHeader)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            if !activityLog.entries.isEmpty {
                Button("Clear") {
                    activityLog.clear()
                }
                .font(Typography.secondary.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("Clear activity log")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Activity Yet",
            systemImage: "text.bubble",
            description: Text("Operations performed on this account will appear here.")
        )
        .symbolRenderingMode(.hierarchical)
    }

    private var logList: some View {
        // The visible row count is bounded by `Tokens.activityLogMaxVisible`
        // (10 on iOS, 50 on macOS). Using a `LazyVStack` lets the card render
        // correctly inside any outer container — including a native `List` row —
        // without the nested-List height-collapse issue.
        let visibleEntries = Array(activityLog.entries.prefix(Tokens.activityLogMaxVisible))
        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { index, entry in
                LogEntryRow(entry: entry, clipboard: clipboard) {
                    snackbarMessage = SnackbarMessage("Log message copied to clipboard")
                }
                .padding(.vertical, Self.rowVerticalInset)

                if index < visibleEntries.count - 1 {
                    Color.brandOutline
                        .opacity(Self.separatorOpacity)
                        .frame(height: Self.separatorHeight)
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Helpers
    // -------------------------------------------------------------------------

    private var cardBackground: some ShapeStyle {
        Color.brandCardSurface
    }

    // -------------------------------------------------------------------------
    // MARK: - Local layout constants
    // -------------------------------------------------------------------------

    /// Vertical inset applied to each list row so successive entries breathe
    /// without introducing the larger default grouped-row padding.
    private static let rowVerticalInset: CGFloat = 11

    /// Height of the hairline separator drawn between successive log rows.
    private static let separatorHeight: CGFloat = 0.5

    /// Opacity applied to `Color.brandOutline` when painting inter-row hairlines
    /// so they recede visually without disappearing on any background.
    private static let separatorOpacity: Double = 0.5

}

// ============================================================================
// MARK: - LogEntryRow
// ============================================================================

/// A single row in the activity log card.
///
/// Tapping the row copies the redacted entry message to the clipboard and
/// notifies the parent via `onCopied` so a snackbar can be shown.
private struct LogEntryRow: View {

    let entry: LogEntry

    /// Platform clipboard used to copy this entry's message.
    let clipboard: any ClipboardService

    /// Called after a successful clipboard copy so the parent can show a toast.
    let onCopied: @MainActor () -> Void

    var body: some View {
        Button(action: copyEntryToClipboard) {
            VStack(alignment: .leading, spacing: Self.lineSpacing) {
                Text(entry.message)
                    .font(Typography.body)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: Tokens.iconLabelSpacing) {
                    Text(formatShortTime(entry.timestamp))
                        .font(Typography.metadata)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Spacer()

                    ActivityLogLevelBadge(level: entry.level)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Double-tap to copy this entry to the clipboard")
        .accessibilityAction(named: "Copy to clipboard") {
            copyEntryToClipboard()
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Helpers
    // -------------------------------------------------------------------------

    private var accessibilityDescription: String {
        let levelName: String
        switch entry.level {
        case .info:    levelName = "Info"
        case .success: levelName = "Success"
        case .error:   levelName = "Error"
        }
        return "\(levelName) at \(formatShortTime(entry.timestamp)): \(entry.message)"
    }

    /// Copies the redacted entry message to the clipboard.
    ///
    /// Messages pass through `ActivityLogState.redact(_:)` before reaching the
    /// clipboard so no signing payloads, session topics, or seed strings
    /// are copied inadvertently.
    private func copyEntryToClipboard() {
        let safeMessage = ActivityLogState.redact(entry.message)
        clipboard.copy(safeMessage, sensitive: false)
        onCopied()
    }

    // -------------------------------------------------------------------------
    // MARK: - Local layout constants
    // -------------------------------------------------------------------------

    /// Vertical gap between the message line and the timestamp + badge metadata
    /// line in the two-line row layout.
    private static let lineSpacing: CGFloat = 5
}

// See Sources/Util/Clipboard.swift.
