// Clipboard.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import SwiftUI

// ============================================================================
// MARK: - ClipboardService Protocol
// ============================================================================

/// Platform-agnostic clipboard write interface.
///
/// Implementations must not store sensitive content beyond the `expirationDate`
/// and must mark it `localOnly` when `sensitive` is true (prevents syncing to
/// Universal Clipboard / Handoff). See PASSKEY_SETUP.md for the full hygiene
/// policy.
///
/// - Note: Reading from the clipboard is intentionally excluded from this
///   protocol. The demo does not read clipboard content programmatically.
public protocol ClipboardService: Sendable {

    /// Copies `text` to the system clipboard.
    ///
    /// - Parameters:
    ///   - text: The string to copy.
    ///   - sensitive: When `true`, the implementation MUST use local-only and
    ///     set a 60-second expiration. When `false`, standard pasteboard
    ///     behaviour applies and expiration is not set.
    func copy(_ text: String, sensitive: Bool)
}

// ============================================================================
// MARK: - SwiftUI Environment Key
// ============================================================================

/// SwiftUI environment key that carries the active `ClipboardService`.
///
/// Platform app entry points set this in `.environment(\.clipboard, ...)` before
/// the root view so every screen gets the correct platform implementation without
/// needing an explicit initializer parameter.
///
/// Defaults to `NoOpClipboard` so views compile and run safely in Previews and
/// in the library targets used by unit tests.
public struct ClipboardKey: EnvironmentKey {
    public static let defaultValue: any ClipboardService = NoOpClipboard()
}

public extension EnvironmentValues {

    /// The active clipboard service for the current platform.
    ///
    /// Set this in the App root with `.environment(\.clipboard, UIKitClipboard())`
    /// (iOS) or `.environment(\.clipboard, AppKitClipboard())` (macOS).
    var clipboard: any ClipboardService {
        get { self[ClipboardKey.self] }
        set { self[ClipboardKey.self] = newValue }
    }
}

// ============================================================================
// MARK: - NoOpClipboard
// ============================================================================

/// Clipboard implementation that discards every write.
///
/// Used as the default environment value so Previews and unit-test library
/// targets compile without a real `UIPasteboard` or `NSPasteboard`.
public struct NoOpClipboard: ClipboardService {
    public init() {}
    public func copy(_ text: String, sensitive: Bool) {
        // Intentionally a no-op — used in Previews and tests only.
    }
}

// ============================================================================
// MARK: - UIKit Implementation (iOS)
// ============================================================================

#if canImport(UIKit)
import UIKit

/// iOS clipboard implementation backed by `UIPasteboard.general`.
///
/// Sensitive items are marked `localOnly = true` (blocks Handoff / Universal
/// Clipboard) and expire in 60 seconds per the security guardrails in
/// PASSKEY_SETUP.md. Public-address copies use no restrictions.
public final class UIKitClipboard: ClipboardService {

    public init() {}

    public func copy(_ text: String, sensitive: Bool) {
        if sensitive {
            let expiration = Date().addingTimeInterval(60)
            // Use the kUTTypeUTF8PlainText UTI string key for the item dictionary.
            // The pasteboard options dictionary uses typed keys from PasteboardOption,
            // not the NSArray / NSString aliases that trip the type checker.
            let key = "public.utf8-plain-text"
            UIPasteboard.general.setItems(
                [[key: text]],
                options: [
                    .localOnly: true,
                    .expirationDate: expiration
                ]
            )
        } else {
            UIPasteboard.general.string = text
        }
    }
}

#endif

// ============================================================================
// MARK: - AppKit Implementation (macOS)
// ============================================================================

#if canImport(AppKit)
import AppKit

/// macOS clipboard implementation backed by `NSPasteboard.general`.
///
/// `NSPasteboard` does not have a built-in expiry or localOnly API equivalent
/// to `UIPasteboard`. For sensitive items we clear the pasteboard on a 60-second
/// background timer to approximate the iOS hygiene guarantee. The clear is
/// best-effort — the user may read or paste before it fires.
public final class AppKitClipboard: ClipboardService {

    public init() {}

    public func copy(_ text: String, sensitive: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        if sensitive {
            // Approximate the iOS 60-second expiry with a best-effort clear.
            // NSPasteboard has no native expiry or localOnly option.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 60) {
                // Only clear if our string is still on the clipboard — do not
                // wipe content the user has manually replaced in the meantime.
                if NSPasteboard.general.string(forType: .string) == text {
                    NSPasteboard.general.clearContents()
                }
            }
        }
    }
}

#endif
