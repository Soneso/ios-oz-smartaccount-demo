// ExternalSignerManagerAdapter.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - AdapterError
// ============================================================================

/// Errors specific to `ExternalSignerManagerAdapter` operations.
public enum AdapterError: Error, Sendable {

    /// No connected wallet can sign for the requested address.
    ///
    /// Thrown when no active wallet connection matches the given address. The
    /// caller should connect a wallet before retrying, or register an in-memory
    /// keypair via `kit.externalSigners.addFromSecret(secretKey:)`.
    case signerNotFound(address: String)
}

extension AdapterError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .signerNotFound(let address):
            return "No wallet connected for address \(address). " +
                   "Connect a wallet or register a keypair via kit.externalSigners.addFromSecret(secretKey:)."
        }
    }
}

// ============================================================================
// MARK: - ExternalSignerManagerAdapter
// ============================================================================

/// Bridges `WalletConnector` to the SDK's `OZExternalWalletAdapter`.
///
/// The SDK's `OZExternalSignerManager` calls `OZExternalWalletAdapter.signAuthEntry(preimageXdr:options:)`.
/// This adapter:
/// 1. Checks if the active `WalletConnector` is connected for the requested address. If so,
///    forwards to `WalletConnector.signAuthEntry(authEntryXdr:contextRuleIds:)` and returns
///    the wallet's response.
/// 2. If no match, throws `signerNotFound`.
///
/// In-memory keypair registration for Stellar account (delegated) signers is handled
/// by `kit.externalSigners.addFromSecret(secretKey:)` at submission time. This adapter
/// covers only the wallet-connector path.
///
/// Context rule IDs:
/// The adapter stores context rule IDs set via `setContextRuleIds(_:)` and passes them to the
/// wallet connector for informational context (the wallet may display them to the user).
///
/// macOS note:
/// On macOS the `WalletConnector` is always a `NoOpWalletConnector` which returns
/// `notSupportedOnPlatform` from all methods. The macOS UI never presents
/// external-wallet entry points (gated by a platform check), so this adapter's wallet
/// path is unreachable from macOS UI in practice.
// @unchecked-justified: all mutable state (`_walletConnector`, `contextRuleIds`) is
// protected by `stateLock` (NSLock) via computed property accessors and explicit lock
// calls; no mutable state escapes outside the lock.
public final class ExternalSignerManagerAdapter: OZExternalWalletAdapter, @unchecked Sendable {

    // -------------------------------------------------------------------------
    // MARK: - State (protected by stateLock)
    // -------------------------------------------------------------------------

    private let stateLock = NSLock()

    /// Context rule IDs for the current signing session.
    ///
    /// Forwarded to the wallet connector so it can display or bind them during signing.
    private var contextRuleIds: [UInt32] = []

    // -------------------------------------------------------------------------
    // MARK: - Dependencies (protected by stateLock)
    // -------------------------------------------------------------------------

    /// Backing storage for the wallet connector. Guarded by `stateLock`.
    ///
    /// Use the `walletConnector` computed property for all external access.
    private var _walletConnector: (any WalletConnector)?

    /// The active wallet connector. Set from outside when the user pairs a wallet.
    ///
    /// Thread-safe: get and set are both performed inside `stateLock`. Any concurrent
    /// read from `signAuthEntry`, `canSignFor`, `getConnectedWallets`, `getWalletForAddress`,
    /// or `disconnect` sees a fully-initialized reference or nil — never a partial write.
    ///
    /// On macOS this is always a `NoOpWalletConnector`; the wallet path in
    /// `signAuthEntry` is unreachable from macOS UI by design — see class-level comment.
    public var walletConnector: (any WalletConnector)? {
        get { stateLock.withLock { _walletConnector } }
        set { stateLock.withLock { _walletConnector = newValue } }
    }

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates an adapter with an optional wallet connector.
    ///
    /// The connector may be set later via `walletConnector`.
    ///
    /// - Parameter walletConnector: Optional connector for external wallet signing.
    public init(walletConnector: (any WalletConnector)? = nil) {
        self._walletConnector = walletConnector
    }

    // -------------------------------------------------------------------------
    // MARK: - Context rule ID management
    // -------------------------------------------------------------------------

    /// Sets the context rule IDs to pass to the wallet connector during signing.
    ///
    /// Called before each wallet signing request when context rule IDs change.
    /// The transfer flow calls this after building the auth entry so the
    /// wallet connector can display or bind them.
    ///
    /// - Parameter ids: The context rule IDs from the current signing context.
    public func setContextRuleIds(_ ids: [UInt32]) {
        stateLock.withLock { contextRuleIds = ids }
    }

    // -------------------------------------------------------------------------
    // MARK: - OZExternalWalletAdapter
    // -------------------------------------------------------------------------

    /// Not used — wallets are connected through the `WalletConnector` before the adapter is consulted.
    public func connect() async throws -> OZConnectedWallet? {
        return nil
    }

    /// Disconnects the wallet connector.
    ///
    /// Called by `OZExternalSignerManager.removeAll()` or explicit session teardown.
    public func disconnect() async throws {
        // Capture the connector under the lock, then call disconnect() outside it
        // to avoid holding stateLock across an async call.
        let connector = walletConnector
        await connector?.disconnect()
    }

    /// Returns the set of currently connected wallet addresses.
    ///
    /// Only surfaces the active wallet connector's address (if connected).
    public func getConnectedWallets() -> [OZConnectedWallet] {
        let (address, meta) = stateLock.withLock { () -> (String?, WalletMetadata?) in
            guard let connector = _walletConnector else { return (nil, nil) }
            return (connector.connectedAddress, connector.walletMetadata)
        }
        guard let address, let meta else { return [] }
        return [OZConnectedWallet(
            address: address,
            walletId: "reown",
            walletName: meta.name
        )]
    }

    /// Returns true if a connected wallet can sign for the given address.
    public func canSignFor(address: String) -> Bool {
        stateLock.withLock {
            _walletConnector?.connectedAddress == address
        }
    }

    /// Returns wallet connection info for the given address, or nil if not a wallet signer.
    public func getWalletForAddress(address: String) -> OZConnectedWallet? {
        let meta = stateLock.withLock { () -> WalletMetadata? in
            guard let connector = _walletConnector,
                  connector.connectedAddress == address else { return nil }
            return connector.walletMetadata
        }
        guard let meta else { return nil }
        return OZConnectedWallet(address: address, walletId: "reown", walletName: meta.name)
    }

    /// Reconnection is not supported; the wallet must re-pair via `connect()`.
    public func reconnect(walletId: String) async throws -> OZConnectedWallet? {
        return nil
    }

    /// Signs an authorization preimage for the given address via the wallet connector.
    ///
    /// Forwards to `WalletConnector.signAuthEntry(authEntryXdr:contextRuleIds:)` when
    /// the connector's `connectedAddress` matches `options.address`. Throws
    /// `signerNotFound` when no connected wallet matches.
    ///
    /// In-memory keypair signers are handled by `kit.externalSigners` directly and
    /// never reach this adapter.
    ///
    /// - Parameters:
    ///   - preimageXdr: Base64-encoded `HashIDPreimage` XDR.
    ///   - options: `options.address` identifies which signer to use.
    public func signAuthEntry(
        preimageXdr: String,
        options: OZSignAuthEntryOptions?
    ) async throws -> OZSignAuthEntryResult {

        let address = options?.address ?? ""

        let (connector, ruleIds): (any WalletConnector, [UInt32]) = try stateLock.withLock {
            guard let conn = _walletConnector else {
                throw AdapterError.signerNotFound(address: address)
            }
            guard conn.connectedAddress == address else {
                throw AdapterError.signerNotFound(address: address)
            }
            return (conn, contextRuleIds)
        }

        let signed = try await connector.signAuthEntry(
            authEntryXdr: preimageXdr,
            contextRuleIds: ruleIds
        )

        return OZSignAuthEntryResult(
            signedAuthEntry: signed.signedAuthEntry,
            signerAddress: signed.signerAddress
        )
    }
}
