// SmartAccountDemoApp.swift (macOS)
// SmartAccountDemoMac
//
// Copyright (c) 2026 Soneso. All rights reserved.

import stellarsdk
import SwiftUI

// ============================================================================
// MARK: - SmartAccountDemoMacApp (macOS)
// ============================================================================

/// macOS application entry point for the Smart Account Demo.
///
/// Platform-specific providers are injected into `DemoState` during `init()`
/// before SwiftUI constructs the first view body. macOS 13+ supports passkeys
/// via `ASAuthorizationController`, so the same `AppleWebAuthnProvider` is
/// used as on iOS. The Reown WalletConnect session layer is not available on
/// macOS; external wallet functionality is intentionally absent from the
/// macOS build.
///
/// Window resizability uses `.contentMinSize` so the window respects each
/// detail pane's minimum width but can be stretched freely beyond it. Detail
/// panes cap their content column at `Tokens.cardMaxContentWidth` via
/// `macOSContentPane()`, so additional window width becomes whitespace rather
/// than over-stretched fields.
///
/// Menu-bar commands hosted in the scene's `commands { ... }` block:
/// - File > New Wallet (Cmd+N) — replaces the standard "New" item and navigates
///   the sidebar to the wallet-creation screen via `NavigationIntent`.
///
/// State-object wiring:
/// `DemoState`, `ActivityLogState`, `AppThemeState`, and `NavigationIntent` are
/// constructed as local values, configured (provider injection, logging), and
/// then handed to SwiftUI via `_demoState = StateObject(wrappedValue: ...)`.
/// Mutating `@StateObject` properties through their wrapped accessor inside
/// `init()` does not reliably persist — SwiftUI manages the StateObject
/// lifecycle independently and may discard mutations made before the first body
/// evaluation. The explicit `StateObject(wrappedValue:)` assignment is the
/// supported pattern for pre-configured state objects.
///
/// `AppThemeState` is injected into both the main `WindowGroup` and the
/// `Settings` scene so the Appearance picker in Settings mutates the same
/// shared instance the main window reads for `.preferredColorScheme`.
@main
struct SmartAccountDemoMacApp: App {

    @StateObject private var demoState: DemoState
    @StateObject private var activityLog: ActivityLogState
    @StateObject private var appTheme: AppThemeState
    @StateObject private var navigationIntent: NavigationIntent

    init() {
        // Construct the observable state instances as locals so the provider
        // injection below mutates the exact same objects that SwiftUI binds
        // to the view tree (see type docstring for why this matters).
        let demoState = DemoState()
        let activityLog = ActivityLogState()
        let appTheme = AppThemeState()
        let navigationIntent = NavigationIntent()

        // Inject platform providers before the first view appears.
        // AppleWebAuthnProvider works on macOS 13+ via ASAuthorizationController.
        // A thrown error means the passkey entitlement is misconfigured.
        // The app can still launch; passkey ceremonies will fail at point-of-use.
        // We record the error so the first visible screen can surface it.
        do {
            let provider = try AppleWebAuthnProvider.create(rpId: DemoConfig.defaultRpId, rpName: DemoConfig.rpName)
            // macOS requires an explicit presentation anchor for the system
            // passkey sheet. Without this delegate, ASAuthorizationController
            // fails register() / authenticate() with error 1004
            // ("No presentation anchor provided").
            provider.presentationContextProvider = MacWebAuthnPresentationAnchor()
            demoState.setWebAuthnProvider(provider)
        } catch {
            // Provider init failure is logged to the activity log. Passkey
            // ceremonies will fail at point-of-use with an actionable error.
            activityLog.error("Bootstrap: AppleWebAuthnProvider init failed — \(ActivityLogState.redact(actionableMessage(for: error)))")
        }
        let storage = OZKeychainStorageAdapter()
        demoState.setStorage(storage)

        // The macOS target does not link Reown; inject the no-op connector so
        // shared code that reads `demoState.walletConnector` has a non-nil
        // value with predictable error semantics for the unreachable wallet
        // path.
        demoState.setWalletConnector(NoOpWalletConnector())

        // Hand the pre-configured instances to SwiftUI.
        _demoState = StateObject(wrappedValue: demoState)
        _activityLog = StateObject(wrappedValue: activityLog)
        _appTheme = StateObject(wrappedValue: appTheme)
        _navigationIntent = StateObject(wrappedValue: navigationIntent)
    }

    var body: some Scene {
        WindowGroup {
            RootView(navigationIntent: navigationIntent)
                .environmentObject(demoState)
                .environmentObject(activityLog)
                .environmentObject(appTheme)
                .environment(\.clipboard, AppKitClipboard())
                .tint(Color.brandPrimary)
                .preferredColorScheme(appTheme.mode.preferredColorScheme)
        }
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Wallet…") {
                    navigationIntent.selectedRoute = .walletCreation
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appTheme)
        }
    }
}
