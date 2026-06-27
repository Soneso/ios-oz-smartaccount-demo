// MainScreenFlow.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - MainScreenFlow
// ============================================================================

/// Business logic for the main dashboard screen.
///
/// This is the single entry point for kit initialisation, balance refresh, and
/// session teardown on the main screen. The iOS and macOS `MainScreen` views
/// delegate every SDK interaction here; views must not call into the SDK
/// directly.
///
/// Thread safety:
/// `MainScreenFlow` is annotated `@MainActor` because it mutates `DemoState`
/// (an `ObservableObject` whose `@Published` properties must be written on the
/// main actor). All public methods are therefore `async` and must be awaited
/// from a `Task` or `.task` modifier.
///
/// Re-entrancy guard:
/// `initializeKit()` uses a boolean flag to prevent a second concurrent call
/// from constructing a duplicate kit instance. Any call that arrives while an
/// init is already in flight returns immediately.
///
/// Failure modes (per method):
/// - `initializeKit()` — logs to the activity log at error level; never
///   propagates the error out to the caller (the screen observes the activity log).
/// - `refreshBalances()` — catches all errors and logs them; never propagates;
///   stale balance labels remain visible while the error is shown in the log.
/// - `disconnect()` — best-effort; errors during SDK teardown are logged but
///   the demo state is always cleared regardless (so the user is never stuck).
@MainActor
public final class MainScreenFlow {

    // -------------------------------------------------------------------------
    // MARK: - Dependencies
    // -------------------------------------------------------------------------

    /// Shared observable demo state read and mutated by this flow.
    private let demoState: DemoState

    /// Shared append-only activity log.
    private let activityLog: ActivityLogState

    /// Optional service used by `deployPendingAndProvision(credentialId:)` to
    /// deploy and mint the DEMO token after the smart-account contract is
    /// deployed.
    ///
    /// When `nil`, the Deploy Now path completes XLM funding (via the SDK's
    /// `autoFund` flow) but skips the DEMO token deploy + mint. Tests typically
    /// leave this `nil`; production screens construct it via
    /// `makeDemoTokenService(activityLog:)` so all deploy entry points operate
    /// on a single service configuration.
    private let _demoTokenService: (any DemoTokenServiceType)?

    /// Exposes the injected token service so other flows can share the same
    /// instance.
    ///
    /// `WalletConnectionFlow.retryPendingDeploy` reads this getter via its
    /// injected `mainScreenFlow` so the retry path provisions DEMO tokens
    /// through the same service used by the Deploy Now path.
    public var demoTokenService: (any DemoTokenServiceType)? { _demoTokenService }

    // -------------------------------------------------------------------------
    // MARK: - Re-entrancy guard
    // -------------------------------------------------------------------------

    /// True while `initializeKit()` is executing.
    ///
    /// Prevents a second `.task` modifier (e.g. on view re-appear) from
    /// constructing a duplicate kit or racing against an in-flight init.
    private var isInitializing: Bool = false

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates a flow bound to the provided state, log, and optional token service.
    ///
    /// The flow does not perform any SDK work at init time. Call
    /// `initializeKit()` from the main screen's `.task` modifier to start kit
    /// creation.
    ///
    /// - Parameters:
    ///   - demoState: The shared observable demo state.
    ///   - activityLog: The shared activity log.
    ///   - demoTokenService: Optional shared DEMO token service. When non-nil,
    ///     `deployPendingAndProvision(credentialId:)` deploys and mints the
    ///     DEMO token after the smart-account contract is deployed so the
    ///     Deploy Now path lands the user in the same end state as the
    ///     auto-deploy creation path. When `nil`, that step is skipped.
    public init(
        demoState: DemoState,
        activityLog: ActivityLogState,
        demoTokenService: (any DemoTokenServiceType)? = nil
    ) {
        self.demoState = demoState
        self.activityLog = activityLog
        self._demoTokenService = demoTokenService
    }

    // -------------------------------------------------------------------------
    // MARK: - Kit initialisation
    // -------------------------------------------------------------------------

    /// Initialises the OZSmartAccountKit and registers it in DemoState.
    ///
    /// The method is idempotent: if the kit is already present in `demoState`
    /// or if another call is currently in flight, it returns immediately.
    ///
    /// On success:
    /// - `DemoState.setKit(_:)` is called with the new kit.
    /// - `DemoState.setExternalSignerAdapter(_:)` is called with the
    ///   ``ExternalSignerManagerAdapter`` that is configured as the wallet adapter.
    ///   The wallet-connector path routes through this adapter at signing time.
    ///   In-memory delegated keypair registration happens at multi-signer submit
    ///   time via `kit.externalSigners.addFromSecret(secretKey:)`.
    /// - A global event listener is registered on `kit.events`.
    /// - An info event is appended to the activity log.
    ///
    /// On failure:
    /// - An error event is appended to the activity log with an actionable message.
    /// - The error is not re-thrown (the activity log is the screen's error surface).
    ///
    /// Failure modes:
    /// - `DemoState.webAuthnProvider` or `DemoState.storage` is nil — this
    ///   should not occur in production because the App entry point always
    ///   injects them; treated as a programming error and reported in the log.
    /// - `OZSmartAccountConfig` construction throws — invalid constants in
    ///   `DemoConfig` (e.g. malformed `accountWasmHash`); also reported in the log.
    public func initializeKit() async {
        // Guard: already initialized
        guard demoState.kit == nil else { return }

        // Guard: re-entrancy
        guard !isInitializing else { return }
        isInitializing = true
        defer { isInitializing = false }

        do {
            // The wallet connector is handed to the adapter so its
            // `canSignFor(address:)` returns true for wallet-paired addresses.
            // In-memory keypair signers are registered at submission time via
            // `kit.externalSigners.addFromSecret(secretKey:)`.
            let sharedAdapter = ExternalSignerManagerAdapter()
            sharedAdapter.walletConnector = demoState.walletConnector

            let demoEd25519Adapter = DemoEd25519Adapter()
            let kit = try buildKit(
                walletAdapter: sharedAdapter,
                ed25519Adapter: demoEd25519Adapter
            )

            // Subscribe to kit events BEFORE registering the kit in DemoState
            // so no event emitted synchronously during setKit(_:) is missed.
            subscribeToKitEvents(kit: kit)

            demoState.setKit(kit)
            demoState.setExternalSignerAdapter(sharedAdapter)
            demoState.setDemoEd25519Adapter(demoEd25519Adapter)

            // DEMO token C-address is deterministic (admin keypair + salt are
            // pure constants); deriving it once at init time makes it available
            // to every screen across the kit's lifetime.
            let demoTokenContractId = try DemoTokenService.deriveContractAddress()
            demoState.setDemoTokenContractId(demoTokenContractId)

            activityLog.success("Smart account kit initialised.")

            // Surface which optional kit features are wired so developers can
            // see at a glance whether they are exercising the relayer + indexer
            // paths or the RPC-only / on-chain-scan fallbacks.
            if !DemoConfig.defaultRelayerURL.isEmpty {
                activityLog.info("Relayer fee sponsoring enabled.")
            } else {
                activityLog.info("Relayer disabled; submitting transactions via RPC.")
            }
            if !DemoConfig.defaultIndexerURL.isEmpty {
                activityLog.info("Indexer lookup enabled.")
            } else {
                activityLog.info("Indexer disabled; using on-chain credential scan.")
            }
        } catch {
            let message = ActivityLogState.redact(actionableMessage(for: error))
            activityLog.error("Failed to initialize SDK: \(message)")
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Balance refresh
    // -------------------------------------------------------------------------

    /// Fetches XLM and DEMO token balances for the connected wallet and updates
    /// DemoState.
    ///
    /// Silently exits when no wallet is connected — the caller is responsible
    /// for ensuring a connection exists before calling this method.
    ///
    /// XLM balance:
    /// Calls `balance(id: <contractId>)` on the native SAC address
    /// (`DemoConfig.nativeTokenContract`) via the kit's `SorobanServer`. The
    /// SAC token interface returns the balance as a signed 128-bit integer in
    /// the innermost `i128` field; the value is in stroops (10^-7 XLM).
    ///
    /// DEMO token balance:
    /// Only fetched when `DemoState.demoTokenContractId` is non-nil. Same SAC
    /// interface, returned in the token's base units. The balance is stored
    /// alongside the XLM balance in `DemoState`.
    ///
    /// Errors:
    /// Balance fetch errors are caught, logged to the activity log at `.error`
    /// level, and never re-thrown. Stale balance labels remain visible. An
    /// error here is not fatal to the session.
    public func refreshBalances() async {
        guard demoState.isConnected, let contractId = demoState.contractId else { return }

        activityLog.info("Refreshing balances…")

        do {
            let xlm = try await fetchTokenBalance(
                contractAddress: DemoConfig.nativeTokenContract,
                accountAddress: contractId
            )
            demoState.setXlmBalance(formatBaseUnitsAsDecimal(xlm))
        } catch {
            let message = ActivityLogState.redact(actionableMessage(for: error))
            activityLog.error("Failed to refresh balance: \(message)")
        }

        if let demoContractId = demoState.demoTokenContractId {
            do {
                let demo = try await fetchTokenBalance(
                    contractAddress: demoContractId,
                    accountAddress: contractId
                )
                demoState.setDemoTokenBalance(formatSmallestUnitsAsDecimal(demo))
            } catch {
                let message = ActivityLogState.redact(actionableMessage(for: error))
                activityLog.error("Failed to refresh balance: \(message)")
            }
        }

        activityLog.info("Balances refreshed.")
    }

    // -------------------------------------------------------------------------
    // MARK: - Disconnect
    // -------------------------------------------------------------------------

    /// Disconnects the current session and clears all state.
    ///
    /// Clears the kit's stored session and toggles connection state. The kit
    /// instance, external signer manager and event subscription remain alive
    /// so the next connect flow (Auto Connect, indexer, or address) can run
    /// without re-initialising the SDK.
    ///
    /// SDK teardown errors are caught and logged; connection state is cleared
    /// regardless so the user is never stuck in a partially-connected state.
    public func disconnect() async {
        if let kit = demoState.kit {
            do {
                try await kit.disconnect()
            } catch {
                activityLog.error("Disconnect failed: \(ActivityLogState.redact(actionableMessage(for: error)))")
            }
        }

        demoState.setDisconnected()
        activityLog.info("Wallet disconnected.")
    }

    // -------------------------------------------------------------------------
    // MARK: - Deploy pending
    // -------------------------------------------------------------------------

    /// Deploys a pending smart account contract for the given credential and
    /// updates the connection state to deployed.
    ///
    /// Triggered by the "Deploy Now" button on the main screen's undeployed
    /// wallet warning card, and by `UndeployedResultCard` when the user taps
    /// "Deploy Now" on the wallet creation result screen.
    ///
    /// On success the wallet is funded with XLM (via the SDK's `autoFund` flow
    /// against `DemoConfig.nativeTokenContract`) and, when a `demoTokenService`
    /// is wired, the DEMO token is deployed and minted to the new wallet. Both
    /// balances are refreshed so the wallet status card populates immediately.
    /// Mint failure is non-fatal — the deploy success is preserved.
    ///
    /// On success:
    /// - `DemoState.setConnected(_:isDeployed: true)` marks the wallet as deployed.
    /// - `refreshBalances()` is called so the XLM balance populates.
    /// - `provisionDemoTokens(...)` is invoked so the DEMO contract id is
    ///   recorded in `DemoState` and the DEMO balance label populates.
    /// - Success entries are appended to the activity log.
    ///
    /// On deploy failure:
    /// - The error is logged at error level.
    /// - The error is rethrown so the call site (the "Deploy Now" button) can
    ///   display an inline error message.
    ///
    /// - Parameter credentialId: The base64URL credential ID of the pending
    ///   credential to deploy.
    /// - Returns: The transaction hash of the deploy transaction, or `nil` when
    ///   `autoSubmit` was `false` (always `true` here).
    @discardableResult
    public func deployPendingAndProvision(credentialId: String) async throws -> String? {
        guard let kit = demoState.kit else { return nil }

        activityLog.info("Deploying pending contract for credential \(ActivityLogState.redactCredentialId(credentialId))...")
        let txHash: String?
        do {
            let result = try await kit.walletOperations.deployPendingCredential(
                credentialId: credentialId,
                autoSubmit: true,
                autoFund: true,
                nativeTokenContract: DemoConfig.nativeTokenContract
            )
            // Use setConnected so the method is safe to call from a context where
            // the wallet is not yet marked connected (e.g. WalletConnectionScreen
            // retry path on the connect screen). setDeployed(true) would be a no-op there.
            demoState.setConnected(
                contractId: result.contractId,
                credentialId: credentialId,
                isDeployed: true
            )
            activityLog.success("Contract deployed successfully.")
            await refreshBalances()
            txHash = result.transactionHash
        } catch {
            let message = ActivityLogState.redact(actionableMessage(for: error))
            activityLog.error("Deploy failed: \(message)")
            throw error
        }

        // Provision DEMO tokens for the freshly deployed wallet so the Deploy
        // Now path lands in the same end state as the auto-deploy creation
        // path. Skipped when no token service was injected or when the
        // connected contract id is unavailable (defensive — setConnected above
        // populates it in the happy path). Mint failure is non-fatal; the
        // shared helper logs the curated error and returns nil.
        if let contractId = demoState.contractId {
            await provisionDemoTokens(
                service: _demoTokenService,
                demoState: demoState,
                activityLog: activityLog,
                onRefreshBalances: { [weak self] in await self?.refreshBalances() },
                recipientContractId: contractId
            )
        }

        return txHash
    }

    // -------------------------------------------------------------------------
    // MARK: - Private: kit construction
    // -------------------------------------------------------------------------

    /// Builds the `OZSmartAccountConfig` and kit from `DemoConfig` and the
    /// platform providers that were injected at app startup.
    ///
    /// - Parameters:
    ///   - walletAdapter: The wallet adapter wired into `config.externalWallet`.
    ///     The kit's `externalSigners` uses it for wallet-connector signing.
    ///   - ed25519Adapter: The Ed25519 adapter wired into
    ///     `config.externalEd25519Adapter`. The kit's `externalSigners` calls
    ///     it for Ed25519 signing when the public key is registered in the
    ///     adapter rather than via `addEd25519FromRawKey`.
    ///
    /// Throws:
    /// - `BootstrapError.providerMissing` when the App entry point did not
    ///   inject the providers (programming error; should never happen in
    ///   production).
    /// - `SmartAccountConfigurationException` when `DemoConfig` constants are invalid.
    private func buildKit(
        walletAdapter: ExternalSignerManagerAdapter,
        ed25519Adapter: DemoEd25519Adapter
    ) throws -> OZSmartAccountKit {
        guard let webAuthnProvider = demoState.webAuthnProvider else {
            throw BootstrapError.providerMissing("WebAuthn provider was not injected. Check App.init().")
        }
        guard let storage = demoState.storage else {
            throw BootstrapError.providerMissing("Storage adapter was not injected. Check App.init().")
        }

        // Empty URL strings disable the corresponding optional feature: the
        // kit treats `nil` as absent, falls back to the RPC-only submission
        // path (no relayer) and the on-chain scan path (no indexer).
        let config = try OZSmartAccountConfig(
            rpcUrl: DemoConfig.rpcURL,
            networkPassphrase: DemoConfig.networkPassphrase,
            accountWasmHash: DemoConfig.accountWasmHash,
            webauthnVerifierAddress: DemoConfig.webauthnVerifierAddress,
            relayerUrl: DemoConfig.defaultRelayerURL.isEmpty ? nil : DemoConfig.defaultRelayerURL,
            indexerUrl: DemoConfig.defaultIndexerURL.isEmpty ? nil : DemoConfig.defaultIndexerURL,
            webauthnProvider: webAuthnProvider,
            storage: storage,
            externalWallet: walletAdapter,
            externalEd25519Adapter: ed25519Adapter,
            maxContextRuleScanId: DemoConfig.maxContextRuleScanId
        )

        return OZSmartAccountKit.create(config: config)
    }

    // -------------------------------------------------------------------------
    // MARK: - Private: kit event subscription
    // -------------------------------------------------------------------------

    /// Registers a global listener on `kit.events` that pipes each emitted
    /// event into the activity log. Each event is converted to a
    /// human-readable entry at appropriate severity. Sensitive values
    /// (credential IDs, session topics) are redacted via the log-entry helper
    /// methods on `ActivityLogState`.
    private func subscribeToKitEvents(kit: OZSmartAccountKit) {
        _ = kit.events.addListener { [weak self] event in
            guard let self else { return }
            // Listener body is synchronous (non-async); dispatch to main actor
            // explicitly so @Published properties are safe to read.
            Task { @MainActor in
                self.handleKitEvent(event)
            }
        }
    }

    /// Maps an `OZSmartAccountEvent` to an activity log entry.
    ///
    /// Credential IDs are truncated via `ActivityLogState.redactCredentialId`.
    /// Transaction hashes are allowed in full (they are public on-chain data).
    /// All other values are included without redaction unless they carry
    /// preimage-like content (which is never present in the event payloads
    /// below).
    private func handleKitEvent(_ event: OZSmartAccountEvent) {
        let (level, message) = Self.describeKitEvent(event)
        activityLog.addEntry(message, level: level)
    }

    /// Converts an `OZSmartAccountEvent` to a `(LogLevel, String)` pair.
    ///
    /// Extracted as a pure static function so `handleKitEvent` stays to 2 lines
    /// and SwiftLint complexity/body-length limits are met without suppression.
    private static func describeKitEvent(_ event: OZSmartAccountEvent) -> (LogLevel, String) {
        switch event {
        case .walletConnected(let contractId, let credentialId):
            let safeCredId = ActivityLogState.redactCredentialId(credentialId)
            return (.success,
                    "Wallet connected: \(truncateAddress(contractId)) (cred: \(safeCredId))")

        case .walletConnectedHeadless(let contractId):
            return (.info, "Connected headlessly to \(truncateAddress(contractId))")

        case .walletDisconnected(let contractId):
            return (.info, "Wallet disconnected: \(truncateAddress(contractId))")

        case .credentialCreated(let credential):
            let safeCredId = ActivityLogState.redactCredentialId(credential.credentialId)
            return (.success, "Credential registered: \(safeCredId)")

        case .credentialDeleted(let credentialId):
            let safeCredId = ActivityLogState.redactCredentialId(credentialId)
            return (.info, "Credential removed: \(safeCredId)")

        case .sessionExpired(let contractId, let credentialId):
            let safeCredId = ActivityLogState.redactCredentialId(credentialId)
            return (.error,
                    "Session expired for \(truncateAddress(contractId)) (cred: \(safeCredId)). " +
                    "Please reconnect.")

        case .transactionSigned(let contractId, let credentialId):
            let credDesc = credentialId.map { ActivityLogState.redactCredentialId($0) } ?? "external"
            return (.info,
                    "Transaction signed for \(truncateAddress(contractId)) via \(credDesc)")

        case .transactionSubmitted(let hash, let success):
            // Transaction hashes are public on-chain identifiers — no redaction needed.
            let submitLevel: LogLevel = success ? .success : .error
            let submitMsg = success
                ? "Transaction submitted: \(hash.prefix(16))…"
                : "Transaction submission failed: \(hash.prefix(16))…"
            return (submitLevel, submitMsg)

        case .credentialSyncFailed(let credentialId, let error):
            let safeCredId = ActivityLogState.redactCredentialId(credentialId)
            return (.error,
                    "Credential sync failed for \(safeCredId): \(actionableMessage(for: error))")
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Private: balance fetching
    // -------------------------------------------------------------------------

    /// Invokes `balance(id: <accountAddress>)` on a SAC token contract and returns
    /// the result as an `Int128` base-units amount.
    ///
    /// Delegates to `SACBalanceFetcher.fetchBalance(contract:account:)` so
    /// the simulation envelope construction, i128 decoding, and source-account
    /// selection are maintained in a single place shared with other callers.
    ///
    /// Throws:
    /// - `BalanceFetchError.simulationFailed` if the RPC returns an error.
    /// - `BalanceFetchError.unexpectedReturnType` if the result cannot be decoded
    ///   as an `i128` SCVal.
    private func fetchTokenBalance(
        contractAddress: String,
        accountAddress: String
    ) async throws -> Int128 {
        return try await SACBalanceFetcher.fetchBalance(
            contract: contractAddress,
            account: accountAddress
        )
    }
}

// ============================================================================
// MARK: - BootstrapError
// ============================================================================

/// Errors that can occur when building the kit from injected providers.
///
/// These are programming errors (the App entry point always injects providers
/// before the first view). They surface in the activity log via
/// `initializeKit()` rather than propagating to caller code.
public enum BootstrapError: Error, Sendable {

    /// A required platform provider was not injected before kit init was attempted.
    case providerMissing(String)
}

extension BootstrapError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .providerMissing(let detail):
            return "Platform provider not ready: \(detail)"
        }
    }
}

// ============================================================================
// MARK: - BalanceFetchError
// ============================================================================

/// Errors that can occur during a SAC token balance fetch.
///
/// These are reported to the activity log and do not propagate to the UI as
/// blocking errors (balance labels remain stale).
public enum BalanceFetchError: Error, Sendable {

    /// The Soroban RPC simulation call returned an error response.
    case simulationFailed(reason: String)

    /// The simulation returned a type that is not an `i128` balance.
    case unexpectedReturnType(detail: String)
}

extension BalanceFetchError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .simulationFailed(let reason):
            return "Balance fetch simulation failed: \(reason)"
        case .unexpectedReturnType(let detail):
            return "Unexpected balance type from RPC: \(detail)"
        }
    }
}
