// AppThemeState.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import SwiftUI

// ============================================================================
// MARK: - AppThemeMode
// ============================================================================

/// Tri-state appearance preference exposed to the user via the navigation-bar
/// theme toggle.
///
/// Encodes to a stable string (`"light" | "dark" | "system"`) so the persisted
/// payload uses well-known, human-readable values.
public enum AppThemeMode: String, CaseIterable, Sendable {

    /// Force light appearance regardless of the host's setting.
    case light

    /// Force dark appearance regardless of the host's setting.
    case dark

    /// Follow the host operating system's appearance.
    case system

    /// SwiftUI override the application applies to its root view hierarchy.
    /// `nil` defers to the system appearance.
    public var preferredColorScheme: ColorScheme? {
        switch self {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }

    /// Returns the next mode in the cycle order (`light → dark → system → light`).
    public func next() -> AppThemeMode {
        switch self {
        case .light:  return .dark
        case .dark:   return .system
        case .system: return .light
        }
    }
}

// ============================================================================
// MARK: - AppThemeState
// ============================================================================

/// Observable state holding the user's chosen appearance and persisting it
/// across launches.
///
/// The persisted key (`theme_mode`) and the encoded payload (`"light"`,
/// `"dark"`, `"system"`) follow the cross-platform demo convention so the
/// same user choice survives platform switching during demos.
@MainActor
public final class AppThemeState: ObservableObject {

    /// User-default key under which the active mode is persisted.
    private static let storageKey = "theme_mode"

    /// Current appearance preference. Mutating this property writes the new
    /// value to `UserDefaults` immediately so the choice survives launches.
    @Published public var mode: AppThemeMode {
        didSet {
            guard oldValue != mode else { return }
            UserDefaults.standard.set(mode.rawValue, forKey: Self.storageKey)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        if let raw = defaults.string(forKey: Self.storageKey),
           let restored = AppThemeMode(rawValue: raw) {
            self.mode = restored
        } else {
            self.mode = .system
        }
    }

    /// Advances `mode` to the next entry in the cycle order.
    public func cycle() {
        mode = mode.next()
    }
}
