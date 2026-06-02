// WalletConnectionFlow.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - ConnectionResult
// ============================================================================

/// Result of a wallet connection attempt.
///
/// A successful single-contract connection produces `.connected`. When the
/// indexer reports the passkey as a signer on more than one contract, the
/// result is `.ambiguous` and the caller must present a picker to let the
/// user select the desired contract before calling `finalizeAmbiguous`.
public enum ConnectionResult: Sendable, Equatable {

    /// A single contract was resolved and the session is now active.
    case connected(
        credentialId: String,
        contractId: String,
        isDeployed: Bool,
        restoredFromSession: Bool
    )

    /// The indexer returned multiple candidates. No session has been set.
    case ambiguous(credentialId: String, candidates: [String])
}

// ============================================================================
// MARK: - ConnectionSection
// ============================================================================

/// Identifies which section is currently executing a connection attempt.
///
/// Only one section may be active at a time. The screen uses this value to
/// show the spinner on the active button and disable all other section buttons.
public enum ConnectionSection: Sendable, Equatable {
    case auto
    case indexer
    case address
    case pending
}

// ============================================================================
// MARK: - ConnectionOperationsType
// ============================================================================

/// Abstraction over the SDK's wallet-operations surface needed by
/// `WalletConnectionFlow`.
///
/// Exists so unit tests can inject a mock without instantiating a real
/// `OZSmartAccountKit`. The protocol exposes only the subset of
/// `OZWalletOperations` and `OZCredentialManager` that the flow requires.
///
/// All SDK types are mapped to demo-layer DTOs (`WalletConnectOptions`,
/// `PasskeyCredential`, `PendingDeployResult`, `PendingCredentialInfo`) so
/// conforming mocks do not require `import stellarsdk`.
public protocol ConnectionOperationsType: Sendable {

    /// Attempts to connect to a wallet using the provided options.
    ///
    /// Returns the resolved `ConnectionResult`, or `nil` when no wallet was
    /// found and prompting was disabled.
    func connectWallet(options: WalletConnectOptions) async throws -> ConnectionResult?

    /// Authenticates with a platform passkey and returns the credential.
    func authenticatePasskey() async throws -> PasskeyCredential

    /// Deploys a pending credential whose on-chain contract was never confirmed.
    func deployPendingCredential(
        credentialId: String,
        autoSubmit: Bool,
        autoFund: Bool,
        nativeTokenContract: String?
    ) async throws -> PendingDeployResult

    /// Returns all credentials whose contracts have not yet been confirmed.
    func getPendingCredentials() async throws -> [PendingCredentialInfo]

    /// Deletes a credential from local storage.
    func deleteCredential(credentialId: String) async throws

    /// Returns the number of context rules for the currently connected contract.
    ///
    /// Used as a lightweight on-chain existence probe. Any throw is treated as
    /// `isDeployed = false`.
    func getContextRulesCount() async throws -> UInt32
}

// ============================================================================
// MARK: - ConnectionOperationsAdapter
// ============================================================================

/// Production adapter that forwards `ConnectionOperationsType` calls to the
/// underlying `OZSmartAccountKit`, mapping SDK types to demo DTOs.
public struct ConnectionOperationsAdapter: ConnectionOperationsType, Sendable {

    private let kit: OZSmartAccountKit

    public init(_ kit: OZSmartAccountKit) {
        self.kit = kit
    }

    public func connectWallet(options: WalletConnectOptions) async throws -> ConnectionResult? {
        let sdkResult = try await kit.walletOperations.connectWallet(options: options.toSDK())
        return sdkResult.map { $0.toConnectionResult() }
    }

    public func authenticatePasskey() async throws -> PasskeyCredential {
        let sdkResult = try await kit.walletOperations.authenticatePasskey()
        return sdkResult.asPasskeyCredential
    }

    public func deployPendingCredential(
        credentialId: String,
        autoSubmit: Bool,
        autoFund: Bool,
        nativeTokenContract: String?
    ) async throws -> PendingDeployResult {
        let sdkResult = try await kit.walletOperations.deployPendingCredential(
            credentialId: credentialId,
            autoSubmit: autoSubmit,
            autoFund: autoFund,
            nativeTokenContract: nativeTokenContract
        )
        return sdkResult.asPendingDeployResult
    }

    public func getPendingCredentials() async throws -> [PendingCredentialInfo] {
        let sdkCredentials = try await kit.credentialManagerConcrete.getPendingCredentials()
        return sdkCredentials.asPendingInfo()
    }

    public func deleteCredential(credentialId: String) async throws {
        try await kit.credentialManagerConcrete.deleteCredential(credentialId: credentialId)
    }

    public func getContextRulesCount() async throws -> UInt32 {
        try await kit.contextRuleManagerConcrete.getContextRulesCount()
    }
}

// ============================================================================
// MARK: - WalletConnectionFlow
// ============================================================================

/// Business logic for the wallet connection screen.
///
/// Implements four connection paths:
/// - Auto Connect: session restore or passkey-triggered indexer lookup.
/// - Connect via Indexer: explicit passkey authentication then indexer lookup.
/// - Connect with Address: passkey authentication then direct contract address.
/// - Pending Deployment actions: retry or delete stored pending credentials.
///
/// All SDK interactions go through `ConnectionOperationsType` so unit tests can
/// inject a mock. The screen reads results from `DemoState` and never calls the
/// SDK directly.
///
/// Thread safety:
/// `WalletConnectionFlow` is `@MainActor` because it mutates `DemoState` and
/// `ActivityLogState`, both of which have `@Published` properties.
@MainActor
public final class WalletConnectionFlow {

    // -------------------------------------------------------------------------
    // MARK: - Dependencies
    // -------------------------------------------------------------------------

    private let demoState: DemoState
    private let activityLog: ActivityLogState
    private let operations: any ConnectionOperationsType
    private let mainScreenFlow: MainScreenFlow?

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates a flow bound to the provided state, log, and operations.
    ///
    /// - Parameters:
    ///   - demoState: The shared observable demo state.
    ///   - activityLog: The shared activity log.
    ///   - operations: SDK operations adapter (or a mock for tests).
    ///   - mainScreenFlow: Optional shared main screen flow used to refresh
    ///     balances after a successful connection. When non-nil, `refreshBalances()`
    ///     is called immediately after the wallet session is set.
    public init(
        demoState: DemoState,
        activityLog: ActivityLogState,
        operations: any ConnectionOperationsType,
        mainScreenFlow: MainScreenFlow? = nil
    ) {
        self.demoState = demoState
        self.activityLog = activityLog
        self.operations = operations
        self.mainScreenFlow = mainScreenFlow
    }

    // -------------------------------------------------------------------------
    // MARK: - Auto Connect
    // -------------------------------------------------------------------------

    /// Connects using Auto Connect: restores a saved session if available, or
    /// triggers WebAuthn authentication and resolves the contract via the indexer.
    ///
    /// - Returns: `ConnectionResult.connected` or `.ambiguous`, or `nil` when
    ///   no wallet was found despite prompting.
    /// - Throws: Any error thrown by the SDK. Check `isUserCancellation(_:)` to
    ///   distinguish user-initiated cancellations from hard errors.
    public func autoConnect() async throws -> ConnectionResult? {
        let result = try await operations.connectWallet(
            options: WalletConnectOptions(prompt: true)
        )
        guard let result else {
            activityLog.info("No wallet session found.")
            return nil
        }
        return try await applyConnectResult(result)
    }

    // -------------------------------------------------------------------------
    // MARK: - Connect via Indexer
    // -------------------------------------------------------------------------

    /// Connects using the two-step indexer flow.
    ///
    /// Workflow:
    /// 1. `authenticatePasskey()` — triggers WebAuthn; returns the credential.
    /// 2. `connectWallet(credentialId:)` — indexer resolves the contract.
    ///
    /// - Returns: `ConnectionResult.connected` or `.ambiguous`, or `nil` when
    ///   the indexer finds no contract for the credential.
    /// - Throws: Any error from the WebAuthn ceremony or network call.
    public func connectViaIndexer() async throws -> ConnectionResult? {
        let credential = try await operations.authenticatePasskey()
        let safeCredId = ActivityLogState.redactCredentialId(credential.credentialId)
        activityLog.success("Authenticated with credential: \(safeCredId)")
        activityLog.info("Looking up contract for credential...")

        let result = try await operations.connectWallet(
            options: WalletConnectOptions(credentialId: credential.credentialId)
        )
        guard let result else {
            activityLog.error("No contract found for this credential.")
            return nil
        }
        return try await applyConnectResult(result)
    }

    // -------------------------------------------------------------------------
    // MARK: - Connect with Address
    // -------------------------------------------------------------------------

    /// Connects to a known contract address using any registered passkey.
    ///
    /// Workflow:
    /// 1. `authenticatePasskey()` — triggers WebAuthn; returns the credential.
    /// 2. `connectWallet(credentialId:contractId:)` — direct connect, no indexer.
    ///
    /// - Parameter contractAddress: The C-address of the smart account contract.
    /// - Returns: `ConnectionResult.connected` on success, or `nil` when the
    ///   connect call returns no result.
    /// - Throws: Any error from the WebAuthn ceremony or network call.
    public func connectWithAddress(contractAddress: String) async throws -> ConnectionResult? {
        let credential = try await operations.authenticatePasskey()
        let safeCredId = ActivityLogState.redactCredentialId(credential.credentialId)
        activityLog.success("Authenticated with credential: \(safeCredId)")

        return try await finalizeAmbiguous(
            credentialId: credential.credentialId,
            contractAddress: contractAddress
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - Finalize Ambiguous
    // -------------------------------------------------------------------------

    /// Finalizes a connection when both the credential ID and contract address
    /// are already known, without re-prompting WebAuthn.
    ///
    /// Used after the `ContractPickerSheet` resolves an `.ambiguous` result: the
    /// user has already authenticated so we reuse the credential ID from that
    /// ceremony rather than showing a second WebAuthn prompt.
    ///
    /// - Parameters:
    ///   - credentialId: The Base64URL credential ID from the prior ceremony.
    ///   - contractAddress: The C-address chosen by the user from the picker.
    /// - Returns: `ConnectionResult.connected` on success, or `nil` on failure.
    /// - Throws: Any SDK error.
    public func finalizeAmbiguous(
        credentialId: String,
        contractAddress: String
    ) async throws -> ConnectionResult? {
        activityLog.info("Connecting to contract: \(truncateAddress(contractAddress))...")
        let result = try await operations.connectWallet(
            options: WalletConnectOptions(
                credentialId: credentialId,
                contractId: contractAddress
            )
        )
        guard let result else {
            activityLog.error("Failed to connect to contract.")
            return nil
        }
        return try await applyConnectResult(result)
    }

    // -------------------------------------------------------------------------
    // MARK: - Retry Pending Deploy
    // -------------------------------------------------------------------------

    /// Retries an on-chain deployment for a stored pending credential.
    ///
    /// A pending credential exists when a previous wallet creation registered the
    /// passkey but the Stellar deploy transaction did not complete. The SDK stores
    /// such credentials locally so the user can retry the deployment here.
    ///
    /// On success: updates `DemoState` to connected+deployed, refreshes
    /// balances, and provisions DEMO tokens via the shared helper so the user
    /// lands in the same end state as the auto-deploy creation path and the
    /// main-screen Deploy Now path. The shared DEMO token service is read from
    /// the injected `mainScreenFlow` so all three deploy entry points operate
    /// on the same service configuration. DEMO mint failure is non-fatal — the
    /// deploy success is preserved.
    ///
    /// - Parameter credentialId: The Base64URL credential ID to deploy.
    /// - Returns: `ConnectionResult.connected` on success.
    /// - Throws: Deploy-step SDK errors. DEMO mint failures are caught inside
    ///   the shared helper. The caller is responsible for displaying inline
    ///   error text on the pending card for deploy-step throws.
    public func retryPendingDeploy(credentialId: String) async throws -> ConnectionResult {
        let safeCredId = ActivityLogState.redactCredentialId(credentialId)
        activityLog.info("Retrying deployment for credential \(safeCredId)...")

        let result: PendingDeployResult
        do {
            result = try await operations.deployPendingCredential(
                credentialId: credentialId,
                autoSubmit: true,
                autoFund: true,
                nativeTokenContract: DemoConfig.nativeTokenContract
            )
        } catch {
            // The SDK pre-sets the connected state before submitting the deploy
            // transaction. If submission fails, reconcile DemoState back to
            // disconnected so the UI and the kit agree.
            demoState.setDisconnected()
            throw error
        }

        activityLog.success("Contract deployed successfully: \(truncateAddress(result.contractId))")
        demoState.setConnected(
            contractId: result.contractId,
            credentialId: credentialId,
            isDeployed: true
        )
        let mainFlow = mainScreenFlow
        await mainFlow?.refreshBalances()

        // Provision DEMO tokens via the shared helper, reading the token
        // service from the injected MainScreenFlow so all deploy entry points
        // share a single DemoTokenService configuration.
        await provisionDemoTokens(
            service: mainFlow?.demoTokenService,
            demoState: demoState,
            activityLog: activityLog,
            onRefreshBalances: { await mainFlow?.refreshBalances() },
            recipientContractId: result.contractId
        )

        return .connected(
            credentialId: credentialId,
            contractId: result.contractId,
            isDeployed: true,
            restoredFromSession: false
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - Pending Credentials
    // -------------------------------------------------------------------------

    /// Loads the list of credentials whose contracts have not yet been confirmed.
    ///
    /// - Returns: An array of `PendingCredentialInfo` objects. Empty when none exist.
    /// - Throws: Any SDK storage error.
    public func loadPendingCredentials() async throws -> [PendingCredentialInfo] {
        try await operations.getPendingCredentials()
    }

    /// Deletes a pending credential from local storage.
    ///
    /// - Parameter credentialId: The Base64URL credential ID to delete.
    /// - Returns: `true` on success; `false` if the operation failed.
    @discardableResult
    public func deletePendingCredential(credentialId: String) async -> Bool {
        let safeCredId = ActivityLogState.redactCredentialId(credentialId)
        do {
            try await operations.deleteCredential(credentialId: credentialId)
            activityLog.info("Deleted pending credential \(safeCredId).")
            return true
        } catch {
            if isUserCancellation(error) {
                activityLog.info("Delete cancelled.")
                return false
            }
            let message = ActivityLogState.redact(actionableMessage(for: error))
            activityLog.error("Delete failed: \(message)")
            return false
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Private: result handling
    // -------------------------------------------------------------------------

    /// Applies a `ConnectionResult` — updating `DemoState`, probing on-chain
    /// existence for the `.connected` case, and triggering a balance refresh.
    ///
    /// For `.ambiguous`, logs info and returns unchanged without mutating state.
    private func applyConnectResult(_ result: ConnectionResult) async throws -> ConnectionResult {
        switch result {
        case .connected(let credentialId, let contractId, _, let restoredFromSession):
            if restoredFromSession {
                activityLog.success("Restored from saved session.")
            } else {
                activityLog.success("Connected to contract: \(truncateAddress(contractId))")
            }

            let isDeployed = await probeDeployed()
            demoState.setConnected(
                contractId: contractId,
                credentialId: credentialId,
                isDeployed: isDeployed
            )
            if isDeployed {
                await mainScreenFlow?.refreshBalances()
            } else {
                activityLog.info("Wallet contract not yet deployed on-chain.")
            }

            return .connected(
                credentialId: credentialId,
                contractId: contractId,
                isDeployed: isDeployed,
                restoredFromSession: restoredFromSession
            )

        case .ambiguous(let credentialId, let candidates):
            activityLog.info("Multiple wallets found for this passkey. Please pick one.")
            return .ambiguous(credentialId: credentialId, candidates: candidates)
        }
    }

    /// Probes whether a contract is deployed by calling `getContextRulesCount()`.
    ///
    /// Any error (RPC failure, contract not found) is treated as `false` so this
    /// probe is always non-fatal.
    private func probeDeployed() async -> Bool {
        do {
            _ = try await operations.getContextRulesCount()
            return true
        } catch {
            return false
        }
    }
}

// ============================================================================
// MARK: - NilConnectionOperations
// ============================================================================

/// No-op operations used when no kit is initialized.
///
/// All methods immediately throw so the flow never reaches SDK calls when no kit
/// is available. Screens already disable buttons when `demoState.kit == nil`;
/// this type acts as a safe sentinel so `WalletConnectionFlow` always has a
/// concrete `ConnectionOperationsType` without an optional.
struct NilConnectionOperations: ConnectionOperationsType {

    func connectWallet(options: WalletConnectOptions) async throws -> ConnectionResult? {
        throw PlainError("Kit not initialized.")
    }

    func authenticatePasskey() async throws -> PasskeyCredential {
        throw PlainError("Kit not initialized.")
    }

    func deployPendingCredential(
        credentialId: String,
        autoSubmit: Bool,
        autoFund: Bool,
        nativeTokenContract: String?
    ) async throws -> PendingDeployResult {
        throw PlainError("Kit not initialized.")
    }

    func getPendingCredentials() async throws -> [PendingCredentialInfo] { [] }

    func deleteCredential(credentialId: String) async throws {
        throw PlainError("Kit not initialized.")
    }

    func getContextRulesCount() async throws -> UInt32 {
        throw PlainError("Kit not initialized.")
    }
}
