// NoOpWalletConnector.swift
// SmartAccountDemo (macOS)
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation

// ============================================================================
// MARK: - NoOpWalletConnector
// ============================================================================

/// Explicit no-wallet implementation of `WalletConnector` for the macOS target.
///
/// External wallet connections via WalletConnect are not supported on macOS because:
/// 1. Reown Swift (`reown-swift`) depends on UIKit deep-link handling
///    (`UIApplication.shared.open(_:)`) for wallet pairing and signing redirects.
///    UIKit is not available on macOS.
/// 2. App Group session storage for relay session persistence is configured around
///    the iOS entitlement shape and is not carried to the macOS target (which has no
///    App Group entitlement).
/// 3. Reown itself is not linked on the macOS target — see `project.yml` where it
///    is a dependency only of `SmartAccountDemo` (iOS) and its library companion,
///    not of `SmartAccountDemoMac`.
///
/// On macOS, the multi-signer flow uses keypair-based delegated signers registered
/// at submission time via `kit.externalSigners.addFromSecret(secretKey:)`.
/// The macOS sidebar omits the external-wallet rows entirely, so this connector
/// and the wallet-connector signing path are unreachable from the production UI.
public final class NoOpWalletConnector: WalletConnector, NoOpWalletConnectorMarker {

    public let connectedAddress: String? = nil
    public let walletMetadata: WalletMetadata? = nil

    public init() {}

    /// Always throws `notSupportedOnPlatform`.
    ///
    /// The macOS UI never presents a "Connect wallet" affordance, so this path is
    /// unreachable in production. It is implemented so that code paths that hold a
    /// `WalletConnector` reference compile and fail explicitly if somehow invoked.
    public func connect() async throws {
        throw WalletConnectorError.notSupportedOnPlatform(
            reason: "External wallet not supported on macOS — see PASSKEY_SETUP.md for the macOS multi-signer approach."
        )
    }

    /// No session exists; nothing to disconnect.
    public func disconnect() async {}

    /// Always throws `notSupportedOnPlatform`.
    public func signAuthEntry(authEntryXdr: String, contextRuleIds: [UInt32]) async throws -> SignedAuthEntry {
        throw WalletConnectorError.notSupportedOnPlatform(
            reason: "External wallet signing not supported on macOS. Use keypair-based multi-signer instead."
        )
    }
}
