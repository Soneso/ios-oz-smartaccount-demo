// SmartAccountDemoApp.swift (iOS)
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import stellarsdk
import SwiftUI
import UIKit

// ============================================================================
// MARK: - SmartAccountDemoApp (iOS)
// ============================================================================

/// iOS application entry point for the Smart Account Demo.
///
/// Platform-specific providers are injected into `DemoState` during `init()`
/// before SwiftUI constructs the first view body. This ordering is required
/// because `MainScreenFlow` reads the providers from `DemoState` when
/// initialising the kit; any delay would surface a nil-provider error at kit
/// creation time.
///
/// State-object wiring:
/// `DemoState`, `ActivityLogState`, and `AppThemeState` are constructed as
/// local values, configured (provider injection, logging), and then handed to
/// SwiftUI via `_demoState = StateObject(wrappedValue: ...)`. Mutating
/// `@StateObject` properties through their wrapped accessor inside `init()`
/// does not reliably persist — SwiftUI manages the StateObject lifecycle
/// independently and may discard mutations made before the first body
/// evaluation. The explicit `StateObject(wrappedValue:)` assignment is the
/// supported pattern for pre-configured state objects.
@main
struct SmartAccountDemoApp: App {

    @StateObject private var demoState: DemoState
    @StateObject private var activityLog: ActivityLogState
    @StateObject private var appTheme: AppThemeState

    init() {
        // Brand the platform navigation bar used by child screens
        // (WalletCreationScreen, ContextRulesScreen, etc.) so their nav-bar
        // chrome reads with the same opaque navy treatment as the main screen's
        // custom AppBar. MainScreen itself hides the platform nav bar and
        // renders the AppBar directly; this appearance therefore only applies
        // to screens pushed onto the navigation stack.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.brandPrimary)
        let titleFont = UIFontMetrics.default.scaledFont(
            for: UIFont.systemFont(ofSize: 17, weight: .semibold)
        )
        let largeTitleFont = UIFontMetrics.default.scaledFont(
            for: UIFont.systemFont(ofSize: 28, weight: .semibold)
        )
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: titleFont,
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: largeTitleFont,
        ]
        appearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactScrollEdgeAppearance = appearance
        UINavigationBar.appearance().tintColor = .white

        // Construct the observable state instances as locals so the provider
        // injection below mutates the exact same objects that SwiftUI binds
        // to the view tree (see type docstring for why this matters).
        let demoState = DemoState()
        let activityLog = ActivityLogState()
        let appTheme = AppThemeState()

        // Inject platform providers before the first view appears.
        // A thrown error means the passkey entitlement is misconfigured.
        // The app can still launch; passkey ceremonies will fail at point-of-use.
        // We record the error so the first visible screen can surface it.
        do {
            let provider = try AppleWebAuthnProvider.create(rpId: DemoConfig.defaultRpId, rpName: DemoConfig.rpName)
            demoState.setWebAuthnProvider(provider)
        } catch {
            // Provider init failure is logged to the activity log. Passkey
            // ceremonies will fail at point-of-use with an actionable error.
            activityLog.error("Bootstrap: AppleWebAuthnProvider init failed — \(ActivityLogState.redact(actionableMessage(for: error)))")
        }
        let storage = OZKeychainStorageAdapter()
        demoState.setStorage(storage)

        // External-wallet connect requires a Reown project ID. When none is
        // configured, the Reown SDK is never initialised and a no-op connector
        // is injected so the "Connect Wallet" UI hides via the same path used on
        // the simulator and macOS. Register a free project ID at reown.com and
        // set `DemoConfig.reownProjectId` to enable external-wallet connect.
        if DemoConfig.reownProjectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            demoState.setWalletConnector(UnconfiguredWalletConnector())
        } else {
            // Configure Reown's networking stack once before constructing the
            // handler. `configureOnce()` is idempotent because Reown's own
            // `Networking/Pair/Sign.configure` calls are themselves single-shot.
            ReownWalletHandler.configureOnce()
            demoState.setWalletConnector(ReownWalletHandler())
        }

        // Hand the pre-configured instances to SwiftUI.
        _demoState = StateObject(wrappedValue: demoState)
        _activityLog = StateObject(wrappedValue: activityLog)
        _appTheme = StateObject(wrappedValue: appTheme)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(demoState)
                .environmentObject(activityLog)
                .environmentObject(appTheme)
                .environment(\.clipboard, UIKitClipboard())
                .tint(Color.brandPrimary)
                .onOpenURL { url in
                    // Wallets paired via Reown return session-settle and
                    // signing-response envelopes by opening the dApp with a
                    // `stellar-smartaccount-ios://?wc_ev=…` URL. Forward each
                    // one into the Sign client so the matching `connect()` or
                    // `signAuthEntry()` continuation resolves immediately
                    // (instead of relying on the slower relay-websocket path,
                    // which on link-mode wallets like Freighter never arrives).
                    //
                    // Skipped entirely when no Reown project ID is configured:
                    // the Reown SDK was never initialised, so no wallet pairing
                    // can occur and no such redirect can arrive.
                    guard !DemoConfig.reownProjectId
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    ReownWalletHandler.handleOpenURL(url)
                }
        }
    }
}
