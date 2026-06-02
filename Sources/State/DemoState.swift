// DemoState.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Combine
import Foundation
import stellarsdk

// ============================================================================
// MARK: - ConnectionState
// ============================================================================

/// Describes the current wallet connection status.
///
/// Transitions: `.disconnected` → `.connected` on successful wallet load;
/// `.connected` → `.disconnected` on explicit disconnect or session expiry.
public enum ConnectionState: Sendable {
    case disconnected
    case connected(contractId: String, credentialId: String, isDeployed: Bool)
}

// ============================================================================
// MARK: - DemoState
// ============================================================================

/// Shared observable state for the Smart Account Demo.
///
/// Acts as the single source of truth that all screens observe. Uses
/// `ObservableObject` with `@Published` for iOS 16 compatibility
/// (`@Observable` requires iOS 17+). Mutation methods are public so that
/// Flow classes (which own business logic) can update state without direct
/// property access. UI screens must never mutate DemoState directly — only
/// Flows may call the setters.
///
/// Platform entry points (SmartAccountDemoApp for iOS, SmartAccountDemoMacApp
/// for macOS) inject the platform-specific providers into DemoState during
/// `init()`, before SwiftUI constructs the first view body.
@MainActor
public final class DemoState: ObservableObject {

    // -------------------------------------------------------------------------
    // MARK: - Kit
    // -------------------------------------------------------------------------

    /// The OZSmartAccountKit instance, nil until the kit is initialised.
    ///
    /// Kit initialisation is deferred to the first screen that needs it
    /// (MainScreenFlow) rather than at app launch, because creating the kit
    /// requires platform providers that must already be injected.
    @Published public private(set) var kit: OZSmartAccountKit?

    // -------------------------------------------------------------------------
    // MARK: - Platform Providers
    // -------------------------------------------------------------------------

    /// Apple-platform WebAuthn provider (AuthenticationServices).
    ///
    /// Set once during app init before any view is shown. macOS 13+ supports
    /// passkeys via the same ASAuthorizationController API as iOS.
    public private(set) var webAuthnProvider: WebAuthnProvider?

    /// Keychain-backed persistent storage adapter.
    ///
    /// Injected at app startup. Never UserDefaults — those are not encrypted
    /// at rest. See PASSKEY_SETUP.md for the iOS/macOS storage security model.
    public private(set) var storage: StorageAdapter?

    /// Platform external wallet connector.
    ///
    /// Injected at app startup. On iOS this is a `ReownWalletHandler` that
    /// pairs Stellar wallets via WalletConnect. On macOS this is a
    /// `NoOpWalletConnector` whose `connect()` always throws — the macOS UI
    /// hides any external-wallet entry point so the no-op path is unreachable
    /// from production code.
    ///
    /// `nil` only in the brief window before the platform entry point runs, or
    /// in unit tests that intentionally exercise the "no connector" branch.
    public private(set) var walletConnector: (any WalletConnector)?

    // -------------------------------------------------------------------------
    // MARK: - Connection
    // -------------------------------------------------------------------------

    /// Current wallet connection state.
    ///
    /// Screens observe this value to render connected / disconnected UI.
    @Published public private(set) var connectionState: ConnectionState = .disconnected

    // -------------------------------------------------------------------------
    // MARK: - Balances
    // -------------------------------------------------------------------------

    /// XLM balance display string for the connected wallet, nil if disconnected
    /// or not yet fetched.
    @Published public private(set) var xlmBalance: String?

    /// DEMO token balance display string for the connected wallet, nil if
    /// disconnected or the DEMO contract has not been deployed yet.
    @Published public private(set) var demoTokenBalance: String?

    /// DEMO token contract ID (C-address), nil if not yet deployed.
    @Published public private(set) var demoTokenContractId: String?

    // -------------------------------------------------------------------------
    // MARK: - External Signer Adapter
    // -------------------------------------------------------------------------

    /// The shared ``ExternalSignerManagerAdapter`` configured as the wallet adapter
    /// in `OZSmartAccountConfig`. Multi-signer flows register delegated keypairs via
    /// `kit.externalSigners.addFromSecret(secretKey:)` at runtime, and the
    /// wallet-connector path routes through this adapter at signing time.
    ///
    /// Set by the kit-init pathway (`MainScreenFlow.initializeKit`) alongside
    /// kit creation. `nil` until the kit is initialised.
    @Published public private(set) var externalSignerAdapter: ExternalSignerManagerAdapter?

    /// Demo Ed25519 adapter that demonstrates the ``OZExternalEd25519SignerAdapter``
    /// callback path.
    ///
    /// Created by `MainScreenFlow.initializeKit` and wired into the kit via
    /// `OZSmartAccountConfig.externalEd25519Adapter`. The same instance is stored
    /// here so the approve flow can register verified Ed25519 secrets on it via
    /// ``DemoEd25519Adapter/add(_:seedBytes:)`` before submission and clear them
    /// via ``DemoEd25519Adapter/clearAll()`` afterward. The kit consults this
    /// adapter (via ``DemoEd25519Adapter/canSignFor(verifierAddress:publicKey:)``)
    /// ahead of its in-process keypair registry, so secrets registered here route
    /// through the adapter custody path. The transfer and context-rule flows use
    /// the in-process path
    /// (``OZExternalSignerManager/addEd25519FromRawKey(secretKeyBytes:verifierAddress:)``)
    /// instead, for which this adapter holds no secret.
    ///
    /// `nil` until the kit is initialised.
    @Published public private(set) var demoEd25519Adapter: DemoEd25519Adapter?

    /// Test-injection seam for the kit's external signer manager.
    ///
    /// Production code leaves this `nil`; the ``externalSigners`` accessor then
    /// resolves to `kit?.externalSigners`. Unit tests inject a real
    /// ``OZExternalSignerManager`` (constructed standalone via its public
    /// initialiser) so the multi-signer registration / cleanup paths can be
    /// exercised against the real actor without standing up a full kit.
    private var injectedExternalSigners: OZExternalSignerManager?

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates an empty state.
    ///
    /// Platform entry points call the setter methods immediately after init to
    /// inject providers before the first view appears.
    public init() {}

    // -------------------------------------------------------------------------
    // MARK: - Setters (called by Flows and platform init only)
    // -------------------------------------------------------------------------

    /// Stores the initialised kit.
    ///
    /// Called by MainScreenFlow after a successful OZSmartAccountKit.create(...).
    public func setKit(_ kit: OZSmartAccountKit?) {
        self.kit = kit
    }

    /// Sets the platform WebAuthn provider.
    ///
    /// Must be called once, in the App entry point's init(), before any view body runs.
    public func setWebAuthnProvider(_ provider: WebAuthnProvider?) {
        webAuthnProvider = provider
    }

    /// Sets the platform storage adapter.
    ///
    /// Must be called once, in the App entry point's init(), before any view body runs.
    public func setStorage(_ adapter: StorageAdapter?) {
        storage = adapter
    }

    /// Sets the platform external wallet connector.
    ///
    /// Called once at app startup with the platform-appropriate implementation
    /// (`ReownWalletHandler` on iOS, `NoOpWalletConnector` on macOS). May also
    /// be called from tests to inject a mock connector.
    public func setWalletConnector(_ connector: (any WalletConnector)?) {
        walletConnector = connector
    }

    /// Transitions to the connected state, recording the contract and credential IDs.
    ///
    /// Resets balance fields so stale values from a previous session are never shown.
    public func setConnected(contractId: String, credentialId: String, isDeployed: Bool) {
        connectionState = .connected(
            contractId: contractId,
            credentialId: credentialId,
            isDeployed: isDeployed
        )
        xlmBalance = nil
        demoTokenBalance = nil
    }

    /// Updates the deployed flag for the connected wallet.
    ///
    /// A no-op when called in `.disconnected` state — there is no contract to mark deployed.
    public func setDeployed(_ deployed: Bool) {
        guard case .connected(let contractId, let credentialId, _) = connectionState else {
            return
        }
        connectionState = .connected(
            contractId: contractId,
            credentialId: credentialId,
            isDeployed: deployed
        )
    }

    /// Stores the shared ``ExternalSignerManagerAdapter`` after kit initialisation.
    ///
    /// Called by `MainScreenFlow.initializeKit` alongside kit creation. The adapter
    /// covers the wallet-connector signing path. In-memory delegated keypair
    /// registration is handled by `kit.externalSigners.addFromSecret(secretKey:)` at
    /// multi-signer submit time.
    public func setExternalSignerAdapter(_ adapter: ExternalSignerManagerAdapter?) {
        externalSignerAdapter = adapter
    }

    /// Stores the ``DemoEd25519Adapter`` after kit initialisation.
    ///
    /// Called by `MainScreenFlow.initializeKit` with the same adapter instance
    /// that was wired into `OZSmartAccountConfig.externalEd25519Adapter`. The
    /// approve flow registers verified Ed25519 secrets on it and clears them
    /// after submission.
    public func setDemoEd25519Adapter(_ adapter: DemoEd25519Adapter?) {
        demoEd25519Adapter = adapter
    }

    /// Injects an external signer manager for unit tests.
    ///
    /// When set, ``externalSigners`` returns this instance instead of the kit's.
    /// Production code never calls this; the production path resolves through
    /// `kit?.externalSigners`.
    public func setInjectedExternalSigners(_ manager: OZExternalSignerManager?) {
        injectedExternalSigners = manager
    }

    /// Transitions to the disconnected state and clears session-scoped data.
    ///
    /// The kit instance and kit event subscription remain in place so the next
    /// connect flow can run without re-initialising the SDK. Only the connection
    /// metadata and balance display fields are cleared. `demoTokenContractId` is
    /// preserved because it is a deterministic value owned by the kit lifetime,
    /// not the session.
    public func setDisconnected() {
        connectionState = .disconnected
        xlmBalance = nil
        demoTokenBalance = nil
    }

    /// Updates the XLM balance display string.
    ///
    /// Pass nil to clear the displayed balance (e.g. when refreshing).
    public func setXlmBalance(_ balance: String?) {
        xlmBalance = balance
    }

    /// Updates the DEMO token balance display string.
    ///
    /// Pass nil to clear the displayed balance.
    public func setDemoTokenBalance(_ balance: String?) {
        demoTokenBalance = balance
    }

    /// Stores the DEMO token contract ID after deployment.
    public func setDemoTokenContractId(_ contractId: String?) {
        demoTokenContractId = contractId
    }
}

// ============================================================================
// MARK: - Convenience Accessors
// ============================================================================

public extension DemoState {

    /// Returns the connected wallet's contract ID, or nil if disconnected.
    var contractId: String? {
        if case .connected(let id, _, _) = connectionState { return id }
        return nil
    }

    /// Returns the connected wallet's credential ID, or nil if disconnected.
    var credentialId: String? {
        if case .connected(_, let id, _) = connectionState { return id }
        return nil
    }

    /// Returns true if the connected wallet's contract has been deployed on-chain.
    var isDeployed: Bool {
        if case .connected(_, _, let deployed) = connectionState { return deployed }
        return false
    }

    /// Returns true if a wallet is currently connected.
    var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    /// The external signer manager that multi-signer flows register delegated
    /// and Ed25519 keypairs on.
    ///
    /// Resolves to the test-injected manager when one was set via
    /// ``setInjectedExternalSigners(_:)``; otherwise to the kit's
    /// `externalSigners`. `nil` only before the kit is initialised in production
    /// (and never injected).
    var externalSigners: OZExternalSignerManager? {
        injectedExternalSigners ?? kit?.externalSigners
    }

    /// Returns true when the kit is initialised and Ed25519 external signing is
    /// available via `kit.externalSigners`.
    ///
    /// Components use this to enable the "Enter Key" affordance for Ed25519 signer
    /// rows in the picker.
    var isEd25519Available: Bool {
        kit != nil
    }

    /// Returns true when an external wallet connector is configured and is a real
    /// (non-no-op) wallet connector.
    ///
    /// Components use this to show or hide the "Connect Wallet" affordance in the
    /// signer picker. On macOS this always returns `false` because the macOS
    /// target injects a `NoOpWalletConnector`.
    var hasWalletAdapter: Bool {
        guard let connector = externalSignerAdapter?.walletConnector else { return false }
        return !(connector is NoOpWalletConnectorMarker)
    }
}
