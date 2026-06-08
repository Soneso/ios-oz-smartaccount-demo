// TransferFlow.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - TransferResult
// ============================================================================

/// Successful outcome of a token transfer.
///
/// Populated when `TransferFlow.transfer(...)` or
/// `TransferFlow.multiSignerTransfer(...)` returns without throwing.
public struct TransferResult: Sendable {

    /// On-chain transaction hash confirming the transfer.
    public let transactionHash: String

    /// Amount transferred, in the display format provided by the caller.
    public let amount: String

    /// Token label displayed alongside the amount (e.g. `"XLM"` or `"DEMO"`).
    public let tokenLabel: String

    /// Recipient address as entered by the user.
    public let recipient: String

    /// XLM balance string as refreshed immediately after the transfer, or nil.
    public let xlmBalance: String?

    /// DEMO token balance string as refreshed immediately after the transfer, or nil.
    public let demoTokenBalance: String?
}

// ============================================================================
// MARK: - TransferSignerInfo
// ============================================================================

/// A signer extracted from context rules, carrying its signing capability.
///
/// `canSign` is `true` when the signer can currently authorize a transaction:
/// - For passkey (WebAuthn) signers: the credential ID matches the connected credential.
/// - For delegated account signers: the external signer manager can sign for the address.
public struct TransferSignerInfo: Sendable, Identifiable {

    /// Stable string identity derived from the signer's `uniqueKey`.
    public var id: String { signer.uniqueKey }

    /// The smart account signer object.
    public let signer: any OZSmartAccountSigner

    /// Whether this signer can currently authorize transactions.
    public let canSign: Bool
}

// ============================================================================
// MARK: - TransactionOperationsType
// ============================================================================

/// Abstraction over `OZTransactionOperations` used by `TransferFlow`.
///
/// Exposes only the `transfer` method consumed by the single-signer path.
/// Tests inject `MockTransactionOperations`.
public protocol TransactionOperationsType: Sendable {

    /// Transfers tokens from the connected smart account to a recipient.
    ///
    /// `decimals` selects the amount scale: pass `nativeTokenDecimals` for native
    /// XLM to skip the on-chain `decimals()` read, or `nil` to let the SDK fetch
    /// the token's own decimals.
    func transfer(
        tokenContract: String,
        recipient: String,
        amount: String,
        decimals: Int?,
        forceMethod: OZSubmissionMethod?
    ) async throws -> OZTransactionResult
}

// ============================================================================
// MARK: - TransactionOperationsAdapter
// ============================================================================

/// Production adapter that forwards `TransactionOperationsType` calls to `OZTransactionOperations`.
public struct TransactionOperationsAdapter: TransactionOperationsType, Sendable {

    private let inner: OZTransactionOperations

    public init(_ inner: OZTransactionOperations) {
        self.inner = inner
    }

    public func transfer(
        tokenContract: String,
        recipient: String,
        amount: String,
        decimals: Int?,
        forceMethod: OZSubmissionMethod?
    ) async throws -> OZTransactionResult {
        return try await inner.transfer(
            tokenContract: tokenContract,
            recipient: recipient,
            amount: amount,
            decimals: decimals,
            forceMethod: forceMethod
        )
    }
}

// ============================================================================
// MARK: - MultiSignerManagerType
// ============================================================================

/// Abstraction over `OZMultiSignerManager` used by `TransferFlow`.
///
/// Exposes only `multiSignerTransfer`. Tests inject `MockMultiSignerManager`.
public protocol MultiSignerManagerType: Sendable {

    // swiftlint:disable:next function_parameter_count
    func multiSignerTransfer(
        tokenContract: String,
        recipient: String,
        amount: String,
        decimals: Int?,
        selectedSigners: [OZSelectedSigner],
        forceMethod: OZSubmissionMethod?,
        resolveContextRuleIds: OZResolveContextRuleIds?
    ) async throws -> OZTransactionResult
}

// ============================================================================
// MARK: - MultiSignerManagerAdapter
// ============================================================================

/// Production adapter that forwards `MultiSignerManagerType` calls to `OZMultiSignerManager`.
public struct MultiSignerManagerAdapter: MultiSignerManagerType, Sendable {

    private let inner: OZMultiSignerManager

    public init(_ inner: OZMultiSignerManager) {
        self.inner = inner
    }

    // swiftlint:disable:next function_parameter_count
    public func multiSignerTransfer(
        tokenContract: String,
        recipient: String,
        amount: String,
        decimals: Int?,
        selectedSigners: [OZSelectedSigner],
        forceMethod: OZSubmissionMethod?,
        resolveContextRuleIds: OZResolveContextRuleIds?
    ) async throws -> OZTransactionResult {
        return try await inner.multiSignerTransfer(
            tokenContract: tokenContract,
            recipient: recipient,
            amount: amount,
            decimals: decimals,
            selectedSigners: selectedSigners,
            forceMethod: forceMethod,
            resolveContextRuleIds: resolveContextRuleIds
        )
    }
}

// ============================================================================
// MARK: - ContextRuleManagerType
// ============================================================================

/// Abstraction over `OZContextRuleManager` used by `TransferFlow` for signer loading.
///
/// Exposes only `listContextRules`. Tests inject `MockContextRuleManager`.
public protocol ContextRuleManagerType: Sendable {

    /// Fetches all context rules from the connected smart account.
    func listContextRules() async throws -> [OZParsedContextRule]
}

// ============================================================================
// MARK: - ContextRuleManagerAdapter
// ============================================================================

/// Production adapter that forwards calls to `OZContextRuleManager`.
public struct ContextRuleManagerAdapter: ContextRuleManagerType, Sendable {

    private let inner: OZContextRuleManager

    public init(_ inner: OZContextRuleManager) {
        self.inner = inner
    }

    public func listContextRules() async throws -> [OZParsedContextRule] {
        return try await inner.listContextRules()
    }
}

// ============================================================================
// MARK: - MainScreenFlowType
// ============================================================================

/// Abstraction over `MainScreenFlow` used by `TransferFlow` for balance refresh.
public protocol MainScreenFlowType: Sendable {

    /// Refreshes both XLM and DEMO token balances in `DemoState`.
    func refreshBalances() async
}

extension MainScreenFlow: MainScreenFlowType {}

// ============================================================================
// MARK: - TransferFlow
// ============================================================================

/// Business logic for the token transfer screen.
///
/// Supports two transfer variants:
/// - Single-signer: one passkey ceremony, direct submit via `transactionOperations.transfer`.
/// - Multi-signer: explicit signer list, orchestrated via `multiSignerManager.multiSignerTransfer`.
///
/// On screen entry the caller calls `loadAvailableSigners()`. When the returned list has
/// at most one entry the Transfer button submits directly. When the list has more than
/// one entry the signer picker is shown first.
///
/// Thread safety:
/// `TransferFlow` is `@MainActor` because it mutates `DemoState` and `ActivityLogState`.
///
/// Re-entrancy:
/// Both transfer methods are guarded by `isTransferring`. The screen's `LoadingButton`
/// also prevents double-tap; this flag is an additional safeguard.
@MainActor
public final class TransferFlow {

    // -------------------------------------------------------------------------
    // MARK: - Dependencies
    // -------------------------------------------------------------------------

    private let demoState: DemoState
    private let activityLog: ActivityLogState
    private let transactionOperations: any TransactionOperationsType
    private let multiSignerManager: any MultiSignerManagerType
    private let contextRuleManager: (any ContextRuleManagerType)?
    private let mainScreenFlow: (any MainScreenFlowType)?

    // -------------------------------------------------------------------------
    // MARK: - Re-entrancy guard
    // -------------------------------------------------------------------------

    private var isTransferring: Bool = false

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates a `TransferFlow` with the provided dependencies.
    ///
    /// - Parameters:
    ///   - demoState: Shared observable demo state.
    ///   - activityLog: Shared activity log.
    ///   - transactionOperations: Adapter over `OZTransactionOperations`.
    ///   - multiSignerManager: Adapter over `OZMultiSignerManager`.
    ///   - contextRuleManager: Adapter over `OZContextRuleManager` for signer loading.
    ///     `nil` causes `loadAvailableSigners()` to return an empty list.
    ///   - mainScreenFlow: Used to refresh balances after a successful transfer.
    ///     `nil` skips balance refresh (unit tests).
    public init(
        demoState: DemoState,
        activityLog: ActivityLogState,
        transactionOperations: any TransactionOperationsType,
        multiSignerManager: any MultiSignerManagerType,
        contextRuleManager: (any ContextRuleManagerType)? = nil,
        mainScreenFlow: (any MainScreenFlowType)? = nil
    ) {
        self.demoState = demoState
        self.activityLog = activityLog
        self.transactionOperations = transactionOperations
        self.multiSignerManager = multiSignerManager
        self.contextRuleManager = contextRuleManager
        self.mainScreenFlow = mainScreenFlow
    }

    // -------------------------------------------------------------------------
    // MARK: - Public: loadAvailableSigners
    // -------------------------------------------------------------------------

    /// Loads unique signers from all context rules of the connected smart account.
    ///
    /// Called once on screen entry to decide the single-signer vs. multi-signer path.
    /// On any failure, returns an empty list so the screen falls back to single-signer mode.
    ///
    /// - Returns: List of `TransferSignerInfo` with signing capability flags, ordered by
    ///   first appearance across all context rules.
    public func loadAvailableSigners() async -> [TransferSignerInfo] {
        return await MultiSignerRegistration.loadAvailableSigners(
            demoState: demoState,
            activityLog: activityLog,
            contextRuleManager: contextRuleManager,
            failureLogPrefix: "Could not load signers from context rules"
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - Public: transfer (single-signer)
    // -------------------------------------------------------------------------

    /// Transfers tokens via a single passkey ceremony.
    ///
    /// Calls `transactionOperations.transfer(...)` which triggers the WebAuthn ceremony
    /// and submits the transaction. On success, refreshes balances and returns a result.
    ///
    /// - Parameters:
    ///   - tokenContract: C-address of the token contract.
    ///   - recipient: Recipient G- or C-address.
    ///   - amount: Decimal amount string (e.g. `"10"` or `"10.5"`).
    ///   - tokenLabel: Display label for the token (`"XLM"` or `"DEMO"`).
    /// - Returns: `TransferResult` describing the transfer outcome.
    /// - Throws: SDK errors including `WebAuthnException.Cancelled` for user cancellations.
    public func transfer(
        tokenContract: String,
        recipient: String,
        amount: String,
        tokenLabel: String
    ) async throws -> TransferResult {
        guard !isTransferring else {
            throw TransferFlowError.alreadyInProgress
        }
        isTransferring = true
        defer { isTransferring = false }

        let recipientDisplay = recipient.isValidContractId()
            ? truncateContractAddress(recipient)
            : truncateAddress(recipient)
        activityLog.info("Transferring \(amount) \(tokenLabel) to \(recipientDisplay)...")

        let sdkResult = try await transactionOperations.transfer(
            tokenContract: tokenContract,
            recipient: recipient,
            amount: amount,
            decimals: transferDecimals(forTokenContract: tokenContract),
            forceMethod: nil
        )

        guard sdkResult.success, let hash = sdkResult.hash else {
            let msg = ActivityLogState.redact(sdkResult.error ?? "Transfer failed with no error detail")
            throw TransferFlowError.transferFailed(reason: msg)
        }

        activityLog.success("Transfer successful. Hash: \(truncateAddress(hash, chars: 8))")
        await refreshBalances()

        return TransferResult(
            transactionHash: hash,
            amount: amount,
            tokenLabel: tokenLabel,
            recipient: recipient,
            xlmBalance: demoState.xlmBalance,
            demoTokenBalance: demoState.demoTokenBalance
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - Public: multiSignerTransfer
    // -------------------------------------------------------------------------

    /// Transfers tokens via multiple signers.
    ///
    /// Before calling `multiSignerManager.multiSignerTransfer`, this method:
    /// 1. Registers each delegated signer's secret key via `kit.externalSigners.addFromSecret`.
    /// 2. Registers each Ed25519 signer's secret bytes via `kit.externalSigners.addEd25519FromRawKey`.
    /// 3. Builds the `[OZSelectedSigner]` list from `chosenSigners`.
    ///
    /// On success, refreshes balances and returns a result.
    ///
    /// - Parameters:
    ///   - tokenContract: C-address of the token contract.
    ///   - recipient: Recipient G- or C-address.
    ///   - amount: Decimal amount string.
    ///   - tokenLabel: Display label for the token.
    ///   - chosenSigners: Signers selected in the picker.
    ///   - delegatedSecrets: Map of G-address to secret key for delegated Stellar account signers.
    ///   - ed25519Secrets: Map of `Ed25519SecretKey` to 32 raw secret bytes for Ed25519 signers.
    /// - Returns: `TransferResult` describing the transfer outcome.
    /// - Throws: SDK errors including `WebAuthnException.Cancelled`.
    public func multiSignerTransfer( // swiftlint:disable:this function_parameter_count
        tokenContract: String,
        recipient: String,
        amount: String,
        tokenLabel: String,
        chosenSigners: [any OZSmartAccountSigner],
        delegatedSecrets: [String: String],
        ed25519Secrets: [Ed25519SecretKey: Data] = [:]
    ) async throws -> TransferResult {
        guard !isTransferring else {
            throw TransferFlowError.alreadyInProgress
        }
        isTransferring = true
        defer { isTransferring = false }

        let hash = try await registerAndExecute(
            tokenContract: tokenContract,
            recipient: recipient,
            amount: amount,
            tokenLabel: tokenLabel,
            chosenSigners: chosenSigners,
            delegatedSecrets: delegatedSecrets,
            ed25519Secrets: ed25519Secrets
        )
        activityLog.success("Multi-signer transfer successful. Hash: \(truncateAddress(hash, chars: 8))")
        await refreshBalances()
        return TransferResult(
            transactionHash: hash,
            amount: amount,
            tokenLabel: tokenLabel,
            recipient: recipient,
            xlmBalance: demoState.xlmBalance,
            demoTokenBalance: demoState.demoTokenBalance
        )
    }

    /// Logs a human-readable intent message for a multi-signer transfer.
    private func logMultiSignerIntent(amount: String, tokenLabel: String, recipient: String, count: Int) {
        let suffix = count == 1 ? "1 signer" : "\(count) signers"
        let display = recipient.isValidContractId()
            ? truncateContractAddress(recipient)
            : truncateAddress(recipient)
        activityLog.info("Multi-signer transfer: \(amount) \(tokenLabel) to \(display)... (\(suffix))")
    }

    /// Registers delegated and in-process Ed25519 signing material, calls the SDK
    /// multi-signer transfer, and clears all registered material on both success
    /// and failure so it is never retained across screens.
    ///
    /// The transfer flow demonstrates the in-process Ed25519 custody path:
    /// Ed25519 secrets are registered directly on `kit.externalSigners` via
    /// `addEd25519FromRawKey`, so the demo adapter holds no secret for them and
    /// the SDK resolves them through the manager's in-memory registry. Both
    /// registrations, `buildSelectedSigners`, and the SDK call all run inside a
    /// single cleanup wrapper, so no signing material leaks if any step throws.
    ///
    /// The delegated registration is wrapped so its
    /// ``MultiSignerRegistrationError`` surfaces as the flow's typed
    /// ``TransferFlowError/invalidDelegatedSigner(_:)``.
    ///
    /// - Returns: The confirmed transaction hash.
    private func registerAndExecute( // swiftlint:disable:this function_parameter_count
        tokenContract: String,
        recipient: String,
        amount: String,
        tokenLabel: String,
        chosenSigners: [any OZSmartAccountSigner],
        delegatedSecrets: [String: String],
        ed25519Secrets: [Ed25519SecretKey: Data]
    ) async throws -> String {
        let sdkResult: OZTransactionResult
        do {
            sdkResult = try await MultiSignerRegistration.registerInProcessSignersWithCleanup(
                delegatedSecrets: delegatedSecrets,
                ed25519Secrets: ed25519Secrets,
                manager: demoState.externalSigners
            ) {
                let selectedSigners = try await MultiSignerRegistration.buildSelectedSigners(
                    chosenSigners,
                    credentialManager: demoState.kit?.credentialManagerConcrete
                )
                logMultiSignerIntent(
                    amount: amount,
                    tokenLabel: tokenLabel,
                    recipient: recipient,
                    count: selectedSigners.count
                )
                return try await multiSignerManager.multiSignerTransfer(
                    tokenContract: tokenContract,
                    recipient: recipient,
                    amount: amount,
                    decimals: transferDecimals(forTokenContract: tokenContract),
                    selectedSigners: selectedSigners,
                    forceMethod: nil,
                    resolveContextRuleIds: nil
                )
            }
        } catch let MultiSignerRegistrationError.invalidDelegatedSigner(expected) {
            throw TransferFlowError.invalidDelegatedSigner(expected)
        }
        guard sdkResult.success, let hash = sdkResult.hash else {
            let msg = ActivityLogState.redact(sdkResult.error ?? "Transfer failed with no error detail")
            throw TransferFlowError.transferFailed(reason: msg)
        }
        return hash
    }

    // -------------------------------------------------------------------------
    // MARK: - Public: isSinglePasskeyTransfer
    // -------------------------------------------------------------------------

    /// Returns `true` only when exactly one signer is selected and it is an
    /// `OZExternalSigner` whose credential ID matches the connected credential;
    /// all other combinations use the multi-signer path.
    ///
    /// - Parameter chosenSigners: Signers chosen in the signer picker.
    /// - Returns: `true` when the fast-path is applicable.
    public func isSinglePasskeyTransfer(_ chosenSigners: [any OZSmartAccountSigner]) -> Bool {
        return MultiSignerRegistration.isSinglePasskey(
            chosenSigners,
            connectedCredentialId: demoState.credentialId
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - Private: decimals selection
    // -------------------------------------------------------------------------

    /// Resolves the amount scale to pass to the SDK transfer methods.
    ///
    /// Native XLM is fixed at `nativeTokenDecimals`, so the demo supplies it
    /// directly to avoid an extra `decimals()` round trip. For any other token,
    /// returns `nil` so the SDK fetches the token contract's own decimals.
    private func transferDecimals(forTokenContract tokenContract: String) -> Int? {
        tokenContract == DemoConfig.nativeTokenContract ? nativeTokenDecimals : nil
    }

    // -------------------------------------------------------------------------
    // MARK: - Private: balance refresh
    // -------------------------------------------------------------------------

    private func refreshBalances() async {
        await mainScreenFlow?.refreshBalances()
    }
}

// ============================================================================
// MARK: - TransferFlowError
// ============================================================================

/// Errors thrown by `TransferFlow` at the flow layer (not from the SDK).
///
/// SDK errors (`WebAuthnException`, `SmartAccountValidationException`, etc.) are propagated
/// directly without wrapping. These cases guard flow-level constraints only.
public enum TransferFlowError: Error, Sendable {

    /// A transfer is already in progress. The re-entrancy guard rejected the second call.
    case alreadyInProgress

    /// The SDK returned a non-success `OZTransactionResult` with the attached reason.
    /// The reason string is pre-redacted by `ActivityLogState.redact` before being stored.
    case transferFailed(reason: String)

    /// The registered keypair for a delegated signer derived a different G-address
    /// than the one recorded in the signer picker. This indicates either a user entry
    /// error or a corrupted secret key.
    case invalidDelegatedSigner(String)
}

extension TransferFlowError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .alreadyInProgress:
            return "A transfer is already in progress."
        case .transferFailed(let reason):
            return "Transfer failed: \(reason)"
        case .invalidDelegatedSigner(let address):
            return "The secret key does not match the expected signer address (\(truncateAddress(address)))."
        }
    }
}

// ============================================================================
// MARK: - No-op stubs (used when kit is nil)
// ============================================================================

/// No-op stub for `TransactionOperationsType`, used by both platform screens
/// when the smart-account kit is not yet connected.
///
/// Throwing here is safe: the Transfer button is disabled when the kit is nil,
/// so this path is only reached if screen state is inconsistent.
struct NoOpTransactionOperations: TransactionOperationsType {
    func transfer(
        tokenContract: String,
        recipient: String,
        amount: String,
        decimals: Int?,
        forceMethod: OZSubmissionMethod?
    ) async throws -> OZTransactionResult {
        throw SmartAccountWalletException.NotConnected(message: "No wallet connected.")
    }
}

/// No-op stub for `MultiSignerManagerType`, used by both platform screens
/// when the smart-account kit is not yet connected.
struct NoOpMultiSignerManager: MultiSignerManagerType {
    // swiftlint:disable:next function_parameter_count
    func multiSignerTransfer(
        tokenContract: String,
        recipient: String,
        amount: String,
        decimals: Int?,
        selectedSigners: [OZSelectedSigner],
        forceMethod: OZSubmissionMethod?,
        resolveContextRuleIds: OZResolveContextRuleIds?
    ) async throws -> OZTransactionResult {
        throw SmartAccountWalletException.NotConnected(message: "No wallet connected.")
    }
}
