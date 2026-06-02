// UndeployedWalletWarningCard.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - UndeployedWalletWarningCard
// ============================================================================

/// A warning sub-card shown inside `WalletStatusCard` when the connected
/// wallet's smart account contract has not yet been deployed to the network.
///
/// Shared between iOS and macOS. SwiftUI primitives only.
///
/// Layout:
/// - Warning-tinted surface backed by `Color.warningContainer`, with foreground
///   text and the leading icon both rendered in `Color.onWarningContainer` so
///   the card reads as a recoverable warning rather than a terminal error.
/// - Title "Wallet Not Deployed".
/// - Body text explaining the situation.
/// - A `LoadingButton` ("Deploy Now" / "Deploying...") that triggers the
///   provided deploy action.
/// - A progress line ("Deploying contract...") visible while the action is
///   running, surfaced via a `isDeploying` binding.
///
/// Error display:
/// - When the deploy action throws, the error message is shown inline below
///   the deploy button in the semantic error tone.
///
/// Accessibility:
/// - The entire card is not collapsed into a single element because the
///   button must remain independently actionable.
public struct UndeployedWalletWarningCard: View {

    // -------------------------------------------------------------------------
    // MARK: - Configuration
    // -------------------------------------------------------------------------

    /// Async action invoked when the user taps "Deploy Now".
    ///
    /// The caller (typically `WalletStatusCard`) is responsible for routing
    /// this to the appropriate flow method.
    let onDeploy: @Sendable () async throws -> Void

    // -------------------------------------------------------------------------
    // MARK: - State
    // -------------------------------------------------------------------------

    @State private var isDeploying: Bool = false
    @State private var deployError: String?

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    public var body: some View {
        VStack(alignment: .leading, spacing: Self.stackSpacing) {
            Label {
                Text("Wallet Not Deployed")
                    .font(Typography.sectionHeader)
                    .foregroundStyle(Color.onWarningContainer)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.onWarningContainer)
                    .accessibilityHidden(true)
            }

            Text(
                "Your passkey is registered but the smart account contract has not been " +
                "deployed to the network. Deploy it to start using your wallet."
            )
            .font(Typography.metadata)
            .foregroundStyle(Color.onWarningContainer)
            .fixedSize(horizontal: false, vertical: true)

            if isDeploying {
                HStack(spacing: Self.progressIconSpacing) {
                    ProgressView()
                        .scaleEffect(Self.progressScale)
                        .accessibilityHidden(true)
                    Text("Deploying contract...")
                        .font(Typography.metadata)
                        .foregroundStyle(Color.onWarningContainer)
                }
            }

            if let error = deployError {
                Text(error)
                    .font(Typography.metadata)
                    .foregroundStyle(Color.semanticError)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Deploy error: \(error)")
            }

            LoadingButton(
                "Deploy Now",
                loadingLabel: "Deploying...",
                action: performDeploy,
                onError: handleDeployError
            )
        }
        .padding(Tokens.insetPadding)
        .background(Color.warningContainer)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.cardRadius))
    }

    // -------------------------------------------------------------------------
    // MARK: - Actions
    // -------------------------------------------------------------------------

    private func performDeploy() async throws {
        guard !isDeploying else { return }
        isDeploying = true
        deployError = nil
        defer { isDeploying = false }
        try await onDeploy()
    }

    @MainActor
    private func handleDeployError(_ error: Error) {
        deployError = actionableMessage(for: error)
    }

    // -------------------------------------------------------------------------
    // MARK: - Local layout constants
    // -------------------------------------------------------------------------

    /// Vertical spacing between rows inside the warning card stack.
    private static let stackSpacing: CGFloat = 10

    /// Horizontal spacing between the in-flight spinner and the
    /// "Deploying contract..." label.
    private static let progressIconSpacing: CGFloat = 6

    /// Scale factor applied to the inline spinner so it reads as a hint
    /// rather than a primary control.
    private static let progressScale: CGFloat = 0.8
}
