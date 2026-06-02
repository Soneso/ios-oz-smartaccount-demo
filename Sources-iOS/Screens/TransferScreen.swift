// TransferScreen.swift (iOS)
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - TransferScreen (iOS)
// ============================================================================

/// iOS shell for the token transfer screen.
///
/// Hosts `TransferScreenCore` and supplies:
/// - A `Menu`-style token picker styled to sit naturally inside a grouped
///   `Form` row.
/// - A dismiss closure backed by `@Environment(\.dismiss)`.
struct TransferScreen: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TransferScreenCore(
            onDismiss: { dismiss() },
            tokenPickerContent: { selectedToken, isDisabled, onTokenChange, demoTokenAvailable in
                IOSTokenPicker(
                    selectedToken: selectedToken,
                    isDisabled: isDisabled,
                    onTokenChange: onTokenChange,
                    demoTokenAvailable: demoTokenAvailable
                )
            }
        )
        .navigationTitle("Transfer")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// ============================================================================
// MARK: - iOS token picker
// ============================================================================

/// Menu-style token selector hosted inside the transfer screen's `Form` row.
///
/// Renders as a row-spanning `Menu` whose label mirrors the iOS form-row
/// idiom: a leading "Token" caption and a trailing value with a disclosure
/// glyph that the user taps to surface the menu.
private struct IOSTokenPicker: View {

    @Binding var selectedToken: TokenOption

    let isDisabled: Bool
    let onTokenChange: () -> Void
    let demoTokenAvailable: Bool

    var body: some View {
        Menu {
            ForEach(TokenOption.allCases, id: \.rawValue) { option in
                Button(option.displayLabel) {
                    selectedToken = option
                    onTokenChange()
                }
                .disabled(option == .demo && !demoTokenAvailable)
                .accessibilityLabel("Select \(option.displayLabel)")
            }
        } label: {
            HStack {
                Text(selectedToken.displayLabel)
                    .font(Typography.body)
                    .foregroundStyle(Color.brandOnSurface)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(.tertiary)
                    .font(Typography.metadata)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .disabled(isDisabled)
        .accessibilityLabel("Token: \(selectedToken.displayLabel)")
    }
}
