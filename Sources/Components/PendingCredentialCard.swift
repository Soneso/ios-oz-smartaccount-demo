// PendingCredentialCard.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// ============================================================================
// MARK: - PendingCredentialCard
// ============================================================================

/// A card row representing one pending credential inside the "Pending
/// Deployments" section of the wallet connection screen.
///
/// Displays the truncated credential ID (with optional nickname) and the
/// truncated contract ID (or "Unknown" when nil). Provides two actions:
/// - "Retry Deploy" (primary) — calls `onRetry`, shows "Deploying..." spinner.
/// - "Delete" (outlined) — calls `onDelete` after a confirmation dialog.
///
/// While the parent signals `isAnyActionActive`, both buttons are disabled so
/// concurrent operations across cards are prevented.
///
/// Layout is shared between iOS and macOS. SwiftUI primitives only.
public struct PendingCredentialCard: View {

    // -------------------------------------------------------------------------
    // MARK: - Configuration
    // -------------------------------------------------------------------------

    private let credential: PendingCredentialInfo

    /// Optional inline error shown below the button row when a retry fails.
    private let inlineError: String?

    /// Whether any action on any pending card is currently running.
    ///
    /// When `true`, both buttons are disabled so concurrent actions on the same
    /// or different cards are prevented.
    private let isAnyActionActive: Bool

    /// Called when the user taps "Retry Deploy".
    private let onRetry: @MainActor () async -> Void

    /// Called when the user taps "Delete".
    private let onDelete: @MainActor () async -> Void

    // -------------------------------------------------------------------------
    // MARK: - State
    // -------------------------------------------------------------------------

    @State private var showDeleteConfirm: Bool = false

    /// Holds the continuation awaited by `LoadingButton`'s async action while
    /// the user decides on the delete confirmation dialog. Resumed once with
    /// `true` (Delete) or `false` (Cancel) when the dialog's button fires.
    @State private var deleteContinuation: CheckedContinuation<Bool, Never>?

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates a `PendingCredentialCard`.
    ///
    /// - Parameters:
    ///   - credential: The pending credential view model to display.
    ///   - inlineError: Optional error message shown below the buttons.
    ///   - isAnyActionActive: When `true`, both buttons are disabled.
    ///   - onRetry: Async closure invoked on the main actor when "Retry Deploy" is tapped.
    ///   - onDelete: Async closure invoked on the main actor when "Delete" is tapped.
    public init(
        credential: PendingCredentialInfo,
        inlineError: String?,
        isAnyActionActive: Bool,
        onRetry: @escaping @MainActor () async -> Void,
        onDelete: @escaping @MainActor () async -> Void
    ) {
        self.credential = credential
        self.inlineError = inlineError
        self.isAnyActionActive = isAnyActionActive
        self.onRetry = onRetry
        self.onDelete = onDelete
    }

    // -------------------------------------------------------------------------
    // MARK: - Computed display values
    // -------------------------------------------------------------------------

    /// Truncated credential ID with optional nickname suffix.
    ///
    /// Format: `"<first12>...<last8>"` with an optional `" (<nickname>)"` suffix
    /// when the credential carries a non-nil nickname.
    private var credentialIdDisplay: String {
        let id = credential.credentialId
        let truncated: String
        if id.count > 20 {
            truncated = "\(id.prefix(12))...\(id.suffix(8))"
        } else {
            truncated = id
        }
        if let nickname = credential.nickname, !nickname.isEmpty {
            return "\(truncated) (\(nickname))"
        }
        return truncated
    }

    /// Truncated contract ID or "Unknown" when nil.
    ///
    /// Uses the shared `truncateContractAddress(_:)` helper (12+12 format).
    private var contractIdDisplay: String {
        guard let contractId = credential.contractId else {
            return "Unknown"
        }
        return truncateContractAddress(contractId)
    }

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    public var body: some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            credentialRow
            contractRow
            buttonRow
            if let error = inlineError {
                InlineErrorText(error)
            }
        }
        .padding(Tokens.insetPadding)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Self.cardCornerRadius))
        .onChange(of: inlineError) { _, newError in
            guard let message = newError else { return }
            postAccessibilityAnnouncement(message)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Subviews
    // -------------------------------------------------------------------------

    private var credentialRow: some View {
        VStack(alignment: .leading, spacing: Self.labelValueSpacing) {
            Text("Credential ID:")
                .font(Typography.metadata)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text(credentialIdDisplay)
                .font(Typography.mono)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Credential ID: \(credentialIdDisplay)")
        }
    }

    private var contractRow: some View {
        VStack(alignment: .leading, spacing: Self.labelValueSpacing) {
            Text("Contract ID:")
                .font(Typography.metadata)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text(contractIdDisplay)
                .font(Typography.mono)
                .foregroundStyle(credential.contractId == nil ? .secondary : .primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Contract ID: \(contractIdDisplay)")
        }
    }

    private var buttonRow: some View {
        HStack(spacing: Self.buttonRowSpacing) {
            retryButton
            deleteButton
        }
    }

    private var retryButton: some View {
        LoadingButton("Retry Deploy", loadingLabel: "Deploying...", style: .primary) { @MainActor in
            await onRetry()
        }
        .disabled(isAnyActionActive)
        .accessibilityLabel("Retry deployment for this credential")
    }

    private var deleteButton: some View {
        LoadingButton("Delete", loadingLabel: "Deleting...", style: .destructive) { @MainActor in
            await runDelete()
        }
        .disabled(isAnyActionActive)
        .accessibilityLabel("Delete this pending credential")
        .confirmationDialog(
            "Delete pending credential? This cannot be undone.",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                resumeDeleteContinuation(with: true)
            }
            Button("Cancel", role: .cancel) {
                resumeDeleteContinuation(with: false)
            }
        }
        .onChange(of: showDeleteConfirm) { _, isShown in
            // If the dialog is dismissed without invoking either action button
            // (e.g. tap-outside on macOS), resume the awaiting continuation
            // with `false` so `LoadingButton`'s spinner does not hang forever.
            if !isShown { resumeDeleteContinuation(with: false) }
        }
    }

    /// Presents the confirmation dialog and, if the user confirms, runs the
    /// async delete on the main actor so `LoadingButton` shows its spinner
    /// for the duration of the delete call.
    @MainActor
    private func runDelete() async {
        let confirmed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            deleteContinuation = continuation
            showDeleteConfirm = true
        }
        guard confirmed else { return }
        await onDelete()
    }

    /// Resumes the suspended `runDelete` continuation exactly once. Subsequent
    /// dismissal callbacks become no-ops because the continuation is cleared
    /// after the first resume.
    @MainActor
    private func resumeDeleteContinuation(with confirmed: Bool) {
        guard let continuation = deleteContinuation else { return }
        deleteContinuation = nil
        continuation.resume(returning: confirmed)
    }

    // -------------------------------------------------------------------------
    // MARK: - Local layout constants
    // -------------------------------------------------------------------------

    /// Vertical spacing between the field label and its monospaced value
    /// inside the credential and contract identifier rows.
    private static let labelValueSpacing: CGFloat = 2

    /// Vertical spacing between the credential row, the contract row, the
    /// button row, and the inline error caption inside the card body.
    private static let rowSpacing: CGFloat = 10

    /// Horizontal spacing between the retry and delete action buttons.
    private static let buttonRowSpacing: CGFloat = 10

    /// Corner radius applied to the card's rounded-rectangle surface.
    /// References `Tokens.bannerRadius` so inline card surfaces track the
    /// shared banner-radius token.
    private static let cardCornerRadius: CGFloat = Tokens.bannerRadius
}
