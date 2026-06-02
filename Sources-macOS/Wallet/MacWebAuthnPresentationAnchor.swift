// MacWebAuthnPresentationAnchor.swift (macOS)
// SmartAccountDemoMac
//
// Copyright (c) 2026 Soneso. All rights reserved.

import AppKit
import AuthenticationServices

// ============================================================================
// MARK: - MacWebAuthnPresentationAnchor
// ============================================================================

/// Presentation-anchor provider that `AppleWebAuthnProvider` requires on
/// macOS in order to host the passkey ceremony UI.
///
/// `ASAuthorizationController` on macOS does not surface its own host window —
/// the integrator must hand it back the `NSWindow` that should anchor the
/// system passkey sheet. Without this delegate, the controller fails the
/// `register(...)` / `authenticate(...)` request with error code 1004
/// ("No presentation anchor provided").
///
/// The provider is held by the active `AppleWebAuthnProvider` instance via
/// its strong `presentationContextProvider` property, so creating one
/// instance at app start-up is sufficient for the app's lifetime.
///
/// Window resolution:
/// Returns `NSApplication.shared.keyWindow` when one is available (the
/// expected case once the user has interacted with the app). Falls back to a
/// fresh `NSWindow` if no key window exists — typically when the passkey
/// request fires before the main scene is fully connected. The fallback
/// window is not displayed; the system still finds and uses the app's
/// frontmost window for sheet attachment.
final class MacWebAuthnPresentationAnchor: NSObject, ASAuthorizationControllerPresentationContextProviding {

    func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        return NSApplication.shared.keyWindow ?? NSWindow()
    }
}
