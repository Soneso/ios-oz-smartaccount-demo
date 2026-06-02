// ThemeModeToggle.swift (iOS)
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ThemeModeToggle (iOS)
// ============================================================================

/// AppBar trailing icon button that cycles the persisted theme mode
/// (`light → dark → system`).
///
/// The icon and accessibility label always reflect the current mode so the
/// active appearance is recognisable at a glance:
///
/// - `light`  → `sun.max`              ("Light mode (tap for dark)")
/// - `dark`   → `moon`                 ("Dark mode (tap for system)")
/// - `system` → `gearshape`            ("System theme (tap for light)")
///
/// Uses `.buttonStyle(.plain)` so the bare icon renders against the AppBar
/// background without picking up iOS 26's tinted Glass button chrome.
struct ThemeModeToggle: View {

    @EnvironmentObject private var appTheme: AppThemeState

    var body: some View {
        Button(action: appTheme.cycle) {
            Image(systemName: iconName)
                .imageScale(.large)
                .symbolRenderingMode(.monochrome)
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    private var iconName: String {
        switch appTheme.mode {
        case .light:  return "sun.max"
        case .dark:   return "moon"
        case .system: return "gearshape"
        }
    }

    private var accessibilityLabel: String {
        switch appTheme.mode {
        case .light:  return "Light mode"
        case .dark:   return "Dark mode"
        case .system: return "System theme"
        }
    }

    private var accessibilityHint: String {
        switch appTheme.mode {
        case .light:  return "Tap to switch to dark mode."
        case .dark:   return "Tap to switch to system theme."
        case .system: return "Tap to switch to light mode."
        }
    }
}
