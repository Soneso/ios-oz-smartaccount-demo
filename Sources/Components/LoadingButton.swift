// LoadingButton.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - LoadingButton
// ============================================================================

/// A primary button that shows an inline spinner and disables itself while an
/// async action is executing.
///
/// Shared between iOS and macOS. SwiftUI primitives only — no UIKit or AppKit
/// conditionals in the view body.
///
/// Behaviour:
/// - Tapping the button calls the provided `action` closure inside a `Task`.
/// - While the task is running, the button label is replaced by a
///   `ProgressView` spinner and the button is disabled so accidental
///   re-taps are ignored.
/// - If the action throws, the error is forwarded to the optional `onError`
///   closure. If `onError` is nil, thrown errors are silently discarded
///   (the caller should prefer always supplying an error handler for user-
///   facing buttons).
///
/// Usage:
/// ```swift
/// LoadingButton("Disconnect") {
///     await flow.disconnect()
/// } onError: { error in
///     activityLog.error(actionableMessage(for: error))
/// }
/// ```
public struct LoadingButton: View {

    // -------------------------------------------------------------------------
    // MARK: - Configuration
    // -------------------------------------------------------------------------

    /// Label text displayed on the button when not loading.
    private let label: String

    /// Label text displayed on the button while loading. When `nil`, the spinner
    /// replaces the label entirely (no text shown while loading).
    private let loadingLabel: String?

    /// Optional SF Symbol name rendered immediately before the idle label. When
    /// `nil`, the label is rendered alone. The icon is hidden while loading so
    /// the spinner / loading caption render without visual collision.
    private let systemImage: String?

    /// Tonal style of the button. Defaults to `.primary` (filled / accent-coloured).
    private let style: ButtonStyle

    /// The async action executed when the button is tapped.
    private let action: @Sendable () async throws -> Void

    /// Optional error handler invoked when `action` throws.
    ///
    /// Annotated `@MainActor` so callers may directly mutate `@Published`
    /// properties (e.g. `activityLog.error(...)`) without wrapping in a
    /// `Task { @MainActor in ... }`.
    private let onError: (@MainActor @Sendable (Error) -> Void)?

    /// Optional binding that supplies a dynamic in-progress label.
    ///
    /// When non-nil and the bound value is non-nil and `isLoading` is `true`,
    /// the bound string is displayed instead of `loadingLabel`. This allows the
    /// caller to update the label in real time (e.g. "Creating wallet..." →
    /// "Deploying demo token...") without rebuilding the button. Accessibility
    /// label mirrors the displayed text so VoiceOver announces each transition.
    /// When `nil` or when the bound value is `nil`, falls back to `loadingLabel`.
    private let progressBinding: Binding<String?>?

    // -------------------------------------------------------------------------
    // MARK: - State
    // -------------------------------------------------------------------------

    /// True while the async action task is in-flight.
    @State private var isLoading: Bool = false

    /// When enabled by the system, the spinner is replaced with a static text
    /// label to avoid motion for users who have requested reduced motion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates a `LoadingButton`.
    ///
    /// - Parameters:
    ///   - label: Text shown on the button in the idle state.
    ///   - loadingLabel: Text shown on the button while loading. When `nil`, only
    ///     the spinner is shown (no label text). Callers that need a descriptive
    ///     in-progress label (e.g. "Deploying...") should pass it here.
    ///   - progressBinding: Optional binding to a `String?` value that overrides
    ///     `loadingLabel` while `isLoading` is `true` and the bound value is
    ///     non-nil. Pass `nil` (the default) to use `loadingLabel` as before.
    ///   - systemImage: Optional SF Symbol rendered immediately before the idle
    ///     label. Hidden while loading.
    ///   - style: Visual style. Use `.destructive` for disconnect / delete actions.
    ///   - action: Async throwing closure executed on tap.
    ///   - onError: Called on the main actor with any error thrown by `action`.
    public init(
        _ label: String,
        loadingLabel: String? = nil,
        progressBinding: Binding<String?>? = nil,
        systemImage: String? = nil,
        style: ButtonStyle = .primary,
        action: @escaping @Sendable () async throws -> Void,
        onError: (@MainActor @Sendable (Error) -> Void)? = nil
    ) {
        self.label = label
        self.loadingLabel = loadingLabel
        self.progressBinding = progressBinding
        self.systemImage = systemImage
        self.style = style
        self.action = action
        self.onError = onError
    }

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    public var body: some View {
        Button(action: handleTap) {
            buttonContent
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(style.backgroundColor)
                .foregroundStyle(style.foregroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(style.strokeColor, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(isLoading ? (effectiveLoadingLabel ?? label) : label)
        .accessibilityHint(isLoading ? "Please wait." : "")
    }

    // -------------------------------------------------------------------------
    // MARK: - Subviews
    // -------------------------------------------------------------------------

    /// The label to display while loading.
    ///
    /// Prefers the value from `progressBinding` when it is non-nil; falls back
    /// to `loadingLabel`. Returns `nil` when neither is set, in which case only
    /// the spinner is shown.
    private var effectiveLoadingLabel: String? {
        progressBinding?.wrappedValue ?? loadingLabel
    }

    @ViewBuilder
    private var buttonContent: some View {
        if isLoading {
            if let effectiveLabel = effectiveLoadingLabel {
                HStack(spacing: 8) {
                    if !reduceMotion {
                        ProgressView()
                            .frame(width: Tokens.spinnerSize, height: Tokens.spinnerSize)
                            .tint(style.foregroundColor)
                            .accessibilityHidden(true)
                    }
                    ButtonLabel(effectiveLabel)
                }
            } else {
                if reduceMotion {
                    ButtonLabel("Loading")
                } else {
                    ProgressView()
                        .frame(width: Tokens.spinnerSize, height: Tokens.spinnerSize)
                        .tint(style.foregroundColor)
                        .accessibilityHidden(true)
                }
            }
        } else {
            if let systemImage {
                HStack(spacing: Tokens.iconLabelSpacing) {
                    Image(systemName: systemImage)
                        .imageScale(.medium)
                        .accessibilityHidden(true)
                    ButtonLabel(label)
                        .layoutPriority(1)
                }
            } else {
                ButtonLabel(label)
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Action
    // -------------------------------------------------------------------------

    private func handleTap() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                try await action()
            } catch {
                onError?(error)
            }
        }
    }
}

// ============================================================================
// MARK: - LoadingButton.ButtonStyle
// ============================================================================

public extension LoadingButton {

    /// Visual style for a `LoadingButton`.
    enum ButtonStyle: Sendable, Equatable {

        /// Standard brand-primary filled button. Use for positive actions.
        case primary

        /// Red destructive button. Use for disconnect / delete actions.
        case destructive

        /// Outlined button with the brand-accent stroke and accent text.
        /// Use when the secondary action should still read as accent-coloured
        /// (e.g. "Go Back" alongside a destructive primary).
        case outlined

        /// Outlined button with a neutral grey stroke and accent text.
        /// Use for secondary navigation CTAs where the accent should be
        /// reserved for the primary action (the "Connect Wallet" alongside
        /// "Create Wallet" on the main screen is the canonical case).
        case outlinedNeutral

        /// Outlined button with a destructive-red stroke and red text. Use
        /// when the destructive action should not dominate the layout the way
        /// a filled `.destructive` button does (the "Remove Rule" button on
        /// each context rule card is the canonical case — paired alongside
        /// an "Edit Rule" `.outlined` button).
        case outlinedDestructive

        var backgroundColor: Color {
            switch self {
            case .primary:             return Color.brandPrimary
            case .destructive:         return Color.red
            case .outlined:            return Color.clear
            case .outlinedNeutral:     return Color.clear
            case .outlinedDestructive: return Color.clear
            }
        }

        var foregroundColor: Color {
            switch self {
            case .primary:             return Color.brandOnPrimary
            case .destructive:         return .white
            case .outlined:            return Color.brandPrimary
            case .outlinedNeutral:     return Color.brandPrimary
            case .outlinedDestructive: return Color.semanticError
            }
        }

        var strokeColor: Color {
            switch self {
            case .primary:             return Color.clear
            case .destructive:         return Color.clear
            case .outlined:            return Color.brandPrimary
            case .outlinedNeutral:     return Color.brandOutline
            case .outlinedDestructive: return Color.semanticError
            }
        }
    }
}
