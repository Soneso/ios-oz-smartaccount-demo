// AccessibilityAnnounce.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// ============================================================================
// MARK: - postAccessibilityAnnouncement
// ============================================================================

/// Posts an accessibility announcement to the platform screen reader.
///
/// On iOS, calls `UIAccessibility.post(notification: .announcement, argument:)`.
/// On macOS, calls `NSAccessibility.post(element:notification:userInfo:)` against
/// the key window with the `.announcementRequested` notification and a userInfo
/// dictionary containing both the message text and a `.high` priority level.
/// The `userInfo` payload is required for macOS VoiceOver to actually speak the
/// announcement — posting `.announcementRequested` without `userInfo` is a no-op.
///
/// - Parameter message: The string VoiceOver / VoiceControl should speak.
public func postAccessibilityAnnouncement(_ message: String) {
    #if os(iOS)
    UIAccessibility.post(notification: .announcement, argument: message)
    #elseif os(macOS)
    if let window = NSApp.keyWindow {
        NSAccessibility.post(
            element: window,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }
    #endif
}
