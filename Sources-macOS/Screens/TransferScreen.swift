// TransferScreen.swift (macOS)
// SmartAccountDemoMac
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - TransferScreen (macOS)
// ============================================================================

/// macOS shell for the token transfer screen.
///
/// Hosts `TransferScreenCore` and supplies:
/// - A `Picker(.menu)` token selector sized for a grouped `Form` row.
/// - A dismiss closure that sets `selectedRoute = .main` for sidebar navigation.
struct TransferScreen: View {

    @Binding var selectedRoute: Route?

    var body: some View {
        TransferScreenCore(
            onDismiss: { selectedRoute = .main },
            tokenPickerContent: { selectedToken, isDisabled, onTokenChange, _ in
                MacOSTokenPicker(
                    selectedToken: selectedToken,
                    isDisabled: isDisabled,
                    onTokenChange: onTokenChange
                )
            }
        )
        .macOSContentPane()
        .frame(minWidth: 480)
        .navigationTitle("Transfer")
        .toolbarRole(.editor)
    }
}

// ============================================================================
// MARK: - macOS token picker
// ============================================================================

/// Menu-style `Picker` token selector hosted inside the transfer screen's
/// `Form` row.
private struct MacOSTokenPicker: View {

    @Binding var selectedToken: TokenOption

    let isDisabled: Bool
    let onTokenChange: () -> Void

    var body: some View {
        Picker("Token", selection: $selectedToken) {
            ForEach(TokenOption.allCases, id: \.rawValue) { option in
                Text(option.displayLabel).tag(option)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .onChange(of: selectedToken) { _, _ in onTokenChange() }
        .disabled(isDisabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
