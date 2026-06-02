// ProgressCard.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ProgressCard
// ============================================================================

/// An inline card that communicates an in-flight async operation.
///
/// Displays a `ProgressView` spinner alongside a status message. Shown while
/// `WalletCreationFlow.createWallet(...)` is executing so the user knows the
/// operation is in progress before the passkey ceremony prompt appears or while
/// network operations complete.
///
/// Shared between iOS and macOS. SwiftUI primitives only — no UIKit or AppKit
/// conditionals in the view body.
public struct ProgressCard: View {

    // -------------------------------------------------------------------------
    // MARK: - Configuration
    // -------------------------------------------------------------------------

    /// Status message displayed next to the spinner.
    ///
    /// Defaults to `"Creating..."` at the call site when no specific message
    /// is available from the flow.
    private let statusText: String

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates a `ProgressCard`.
    ///
    /// - Parameter statusText: The message to display alongside the spinner.
    ///   Defaults to `"Creating..."`.
    public init(statusText: String = "Creating...") {
        self.statusText = statusText
    }

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    public var body: some View {
        HStack(spacing: Tokens.iconLabelSpacing) {
            ProgressView()
                .progressViewStyle(.circular)
                .frame(width: Tokens.spinnerSize, height: Tokens.spinnerSize)
                .accessibilityHidden(true)

            Text(statusText)
                .font(Typography.secondary)
                .foregroundStyle(Color.brandOnSurfaceVariant)
        }
        .padding(Tokens.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.cardRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusText)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
