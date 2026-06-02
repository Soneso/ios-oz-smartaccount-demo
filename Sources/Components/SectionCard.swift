// SectionCard.swift
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
// MARK: - SectionCardStyle
// ============================================================================

/// Visual style of a section card.
public enum SectionCardStyle {
    /// Standard card using `Color.cardBackground`.
    case normal
    /// Warning card tinted with `Color.warningContainer` so cautionary content
    /// reads distinctly from both standard cards and terminal-error surfaces.
    case warning
    /// Error card tinted with `Color.errorContainer` so terminal-failure
    /// content (no wallet connected, validation rejection) reads with the
    /// strongest visual weight.
    case error
}

// ============================================================================
// MARK: - SectionCard ViewModifier
// ============================================================================

/// Applies a rounded-rectangle card treatment to a view.
///
/// Padding, background colour, and corner radius are uniform across iOS and macOS.
/// The corner radius defaults to 12 on iOS and 10 on macOS via the platform
/// parameter; call sites may override by passing an explicit value.
///
/// Usage:
/// ```swift
/// VStack { ... }
///     .sectionCard()
///
/// VStack { ... }
///     .sectionCard(style: .warning)
/// ```
public struct SectionCard: ViewModifier {

    let style: SectionCardStyle
    let cornerRadius: CGFloat

    public func body(content: Content) -> some View {
        content
            .padding(Tokens.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var backgroundColor: Color {
        switch style {
        case .normal:
            return Color.brandCardSurface
        case .warning:
            return Color.warningContainer
        case .error:
            return Color.errorContainer
        }
    }
}

public extension View {

    /// Applies the shared section-card treatment with an optional style and corner radius.
    ///
    /// - Parameters:
    ///   - style: `.normal` (default), `.warning` for cautionary surfaces, or
    ///     `.error` for terminal-failure surfaces (e.g. the not-connected guard).
    ///   - cornerRadius: Corner radius in points. Defaults to 12 on iOS and 10 on macOS.
    func sectionCard(
        style: SectionCardStyle = .normal,
        cornerRadius: CGFloat = {
            #if os(iOS)
            return Tokens.cardRadius
            #else
            return Tokens.controlRadius
            #endif
        }()
    ) -> some View {
        modifier(SectionCard(style: style, cornerRadius: cornerRadius))
    }
}

// ============================================================================
// MARK: - SectionHeader
// ============================================================================

/// A bold section title styled as a SwiftUI accessibility header.
///
/// Shared between iOS and macOS. Identical to the former file-private
/// `SectionHeader` / `MacSectionHeader` types that existed in each screen file.
public struct SectionHeader: View {

    private let title: String

    /// Creates a `SectionHeader`.
    ///
    /// - Parameter title: The section title displayed in headline weight.
    public init(title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(Typography.sectionHeader)
            .fontWeight(.semibold)
            .accessibilityAddTraits(.isHeader)
    }
}

// ============================================================================
// MARK: - InlineErrorText
// ============================================================================

/// A caption-sized error message shown inline below a section's action button.
///
/// Announces itself via the platform accessibility announcement API whenever
/// it appears (nil → non-nil transition), so VoiceOver / VoiceControl users
/// are informed without needing to navigate to the error element.
///
/// Shared between iOS and macOS.
public struct InlineErrorText: View {

    private let message: String

    /// Creates an `InlineErrorText`.
    ///
    /// - Parameter message: The human-readable error string to display.
    public init(_ message: String) {
        self.message = message
    }

    public var body: some View {
        Text(message)
            .font(Typography.caption)
            .foregroundStyle(Color.semanticError)
            .accessibilityLabel("Error: \(message)")
            .onAppear {
                postAccessibilityAnnouncement(message)
            }
    }
}
