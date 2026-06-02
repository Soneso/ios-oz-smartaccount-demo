// Snackbar.swift
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
// MARK: - SnackbarMessage
// ============================================================================

/// A transient toast message shown at the bottom of the screen.
///
/// Created by call sites and stored in `@State`. Pass to the `.snackbar(_:)`
/// view modifier on the root container for each screen that needs toasts.
public struct SnackbarMessage: Equatable, Sendable {

    /// Unique ID used to distinguish successive messages with identical text
    /// so repeated copies each trigger a fresh animation cycle.
    public let id: UUID

    /// The text to display in the toast.
    public let text: String

    /// Creates a new message with a fresh UUID.
    ///
    /// - Parameter text: The message to display.
    public init(_ text: String) {
        self.id = UUID()
        self.text = text
    }
}

// ============================================================================
// MARK: - SnackbarModifier
// ============================================================================

/// SwiftUI modifier that overlays a bottom toast when `message` is non-nil.
///
/// The toast auto-dismisses after `duration` seconds by setting `message = nil`
/// on the main actor. Each message's UUID is used as the `.task(id:)` value so
/// SwiftUI automatically cancels the in-flight sleep when the view disappears or
/// when a new message replaces the current one before the timer fires.
/// Back-to-back posts each arm an independent, auto-cancelled dismiss task with
/// no manual ID tracking or fire-and-forget `Task { }` escapes.
///
/// Usage:
/// ```swift
/// @State private var snackbarMessage: SnackbarMessage?
///
/// someView
///     .snackbar($snackbarMessage)
/// ```
private struct SnackbarModifier: ViewModifier {

    @Binding var message: SnackbarMessage?

    /// Seconds before the toast auto-dismisses.
    private let duration: Double = 2.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let msg = message {
                    SnackbarToast(text: msg.text)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                )
                        )
                        .id(msg.id)
                        .padding(.bottom, 24)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: message)
            // `.task(id:)` launches a fresh task each time `message?.id` changes
            // and cancels the previous one automatically — no fire-and-forget
            // escapes, no manual ID tracking needed.
            .task(id: message?.id) {
                guard message != nil else { return }
                do {
                    try await Task.sleep(for: .seconds(duration))
                    withAnimation { message = nil }
                } catch {
                    // Task was cancelled (view dismissed or new message arrived) —
                    // do not clear the binding; the cancelling caller manages state.
                }
            }
    }
}

// ============================================================================
// MARK: - SnackbarToast
// ============================================================================

/// The visual toast pill rendered inside `SnackbarModifier`.
private struct SnackbarToast: View {

    let text: String

    var body: some View {
        Text(text)
            .font(Typography.secondary)
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            .accessibilityLabel(text)
            .accessibilityAddTraits(.isStaticText)
            // Post a VoiceOver announcement when the toast appears so screen
            // reader users are informed of the transient message.
            .modifier(AccessibilityAnnouncementModifier(text: text))
    }
}

// ============================================================================
// MARK: - AccessibilityAnnouncementModifier
// ============================================================================

/// Posts a platform-level accessibility announcement when the view first appears.
///
/// On iOS, uses `UIAccessibility.post(notification:argument:)`. On macOS, posts
/// via `NSAccessibility.post(element:notification:)` with the window as element.
/// This approach works on iOS 16+ and macOS 13+, covering the full deployment
/// target range without requiring the `isLiveRegion` trait (available iOS 17+ only).
internal struct AccessibilityAnnouncementModifier: ViewModifier {

    let text: String

    func body(content: Content) -> some View {
        content.onAppear {
            postAccessibilityAnnouncement(text)
        }
    }
}

// ============================================================================
// MARK: - View extension
// ============================================================================

public extension View {

    /// Overlays a bottom auto-dismiss toast driven by a `SnackbarMessage?` binding.
    ///
    /// Set `message` to a new `SnackbarMessage(_:)` to show the toast; the
    /// modifier resets it to `nil` automatically after ~2 s.
    ///
    /// - Parameter message: Binding to the optional message. Set to a new
    ///   `SnackbarMessage` to trigger the toast; `nil` means hidden.
    func snackbar(_ message: Binding<SnackbarMessage?>) -> some View {
        modifier(SnackbarModifier(message: message))
    }
}
