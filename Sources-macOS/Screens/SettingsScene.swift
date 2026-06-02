// SettingsScene.swift (macOS)
// SmartAccountDemoMac
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - SettingsView
// ============================================================================

/// Root view for the macOS Settings window (Cmd+,).
///
/// Hosts a two-tab layout: General and Network. The tab bar adopts the native
/// macOS preferences-pane visual chrome automatically when placed inside a
/// `Settings { }` scene.
///
/// Minimum dimensions are sized so both tabs have enough room for their content
/// without scrolling under normal Dynamic Type sizes.
struct SettingsView: View {

    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                GeneralSettingsTab()
            }
            Tab("Network", systemImage: "network") {
                NetworkSettingsTab()
            }
        }
        .frame(
            minWidth: SettingsView.minWidth,
            minHeight: SettingsView.minHeight
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - Layout constants
    // -------------------------------------------------------------------------

    /// Minimum width of the Settings window. Wide enough to accommodate the
    /// tab bar labels and the General tab content without horizontal clipping.
    private static let minWidth: CGFloat = 480

    /// Minimum height of the Settings window. Accommodates the General tab's
    /// picker and the Network tab's read-only content without vertical
    /// compression.
    private static let minHeight: CGFloat = 320
}

// ============================================================================
// MARK: - GeneralSettingsTab
// ============================================================================

/// General settings tab hosting appearance preferences.
///
/// The theme picker cycles through `AppThemeMode` cases and mutates the shared
/// `AppThemeState` environment object. Because `AppThemeState` is the same
/// instance injected into both the main `WindowGroup` and the `Settings`
/// scene, toggling here immediately updates the main window's appearance.
struct GeneralSettingsTab: View {

    @EnvironmentObject private var appTheme: AppThemeState

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appTheme.mode) {
                    ForEach(AppThemeMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Appearance")
                    .font(Typography.sectionHeader)
            }
        }
        .formStyle(.grouped)
        .padding(Tokens.cardPadding)
    }
}

// ============================================================================
// MARK: - NetworkSettingsTab
// ============================================================================

/// Network settings tab showing the active network in read-only form.
///
/// The demo targets Testnet exclusively. The actual network selection for
/// transactions is embedded within each operation flow. This tab surfaces the
/// active network as informational context only.
struct NetworkSettingsTab: View {

    var body: some View {
        Form {
            Section {
                LabeledContent("Active Network") {
                    Text("Testnet")
                        .foregroundStyle(.secondary)
                        .font(Typography.body)
                }
                LabeledContent("Horizon URL") {
                    Text("https://horizon-testnet.stellar.org")
                        .foregroundStyle(.tertiary)
                        .font(Typography.metadata)
                        .textSelection(.enabled)
                }
                LabeledContent("Soroban RPC URL") {
                    Text("https://soroban-testnet.stellar.org")
                        .foregroundStyle(.tertiary)
                        .font(Typography.metadata)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Network")
                    .font(Typography.sectionHeader)
            } footer: {
                Text("The network used for all transactions is configured in each operation flow.")
                    .font(Typography.metadata)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(Tokens.cardPadding)
    }
}

// ============================================================================
// MARK: - AppThemeMode + label
// ============================================================================

private extension AppThemeMode {

    /// Human-readable label shown in the segmented Appearance picker.
    var label: String {
        switch self {
        case .light:  return "Light"
        case .dark:   return "Dark"
        case .system: return "System"
        }
    }
}
