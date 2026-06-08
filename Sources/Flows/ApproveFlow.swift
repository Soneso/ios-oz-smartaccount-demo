// ApproveFlow.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - ApproveResult
// ============================================================================

/// Outcome of a token allowance approval.
///
/// Populated when `ApproveFlow.approveAllowance(...)` or
/// `ApproveFlow.multiSignerApproveAllowance(...)` returns. The shape mirrors
/// the SDK's `OZTransactionResult` so the screen can render success / failure
/// cards from a single value.
public struct ApproveResult: Sendable, Equatable {

    /// `true` when the on-chain transaction was submitted and confirmed.
    public let success: Bool

    /// Confirmed Stellar transaction hash on success, otherwise `nil`.
    public let hash: String?

    /// Sanitised error message when `success` is `false`, otherwise `nil`.
    public let error: String?

    public init(success: Bool, hash: String?, error: String?) {
        self.success = success
        self.hash = hash
        self.error = error
    }
}

// ============================================================================
// MARK: - ContractCallOperationsType
// ============================================================================

/// Abstraction over `OZTransactionOperations` for the single-signer contract
/// call path used by `ApproveFlow.approveAllowance(...)`.
///
/// Exposes only `contractCall` to keep the test seam minimal. Tests inject
/// `MockContractCallOperations`.
public protocol ContractCallOperationsType: Sendable {

    /// Calls an arbitrary contract function from the connected smart account
    /// via Soroban `require_auth`.
    func contractCall(
        target: String,
        targetFn: String,
        targetArgs: [SCValXDR]
    ) async throws -> OZTransactionResult
}

// ============================================================================
// MARK: - ContractCallOperationsAdapter
// ============================================================================

/// Production adapter that forwards `ContractCallOperationsType` calls to
/// `OZTransactionOperations.contractCall(target:targetFn:targetArgs:)`.
public struct ContractCallOperationsAdapter: ContractCallOperationsType, Sendable {

    private let inner: OZTransactionOperations

    public init(_ inner: OZTransactionOperations) {
        self.inner = inner
    }

    public func contractCall(
        target: String,
        targetFn: String,
        targetArgs: [SCValXDR]
    ) async throws -> OZTransactionResult {
        return try await inner.contractCall(
            target: target,
            targetFn: targetFn,
            targetArgs: targetArgs
        )
    }
}

// ============================================================================
// MARK: - MultiSignerContractCallType
// ============================================================================

/// Abstraction over `OZMultiSignerManager` for the multi-signer contract call
/// path used by `ApproveFlow.multiSignerApproveAllowance(...)`.
public protocol MultiSignerContractCallType: Sendable {

    /// Calls an arbitrary contract function from the connected smart account
    /// authorized by every signer in `selectedSigners`.
    func multiSignerContractCall(
        target: String,
        targetFn: String,
        targetArgs: [SCValXDR],
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult
}

// ============================================================================
// MARK: - MultiSignerContractCallAdapter
// ============================================================================

/// Production adapter that forwards `MultiSignerContractCallType` calls to
/// `OZMultiSignerManager.multiSignerContractCall(...)`.
public struct MultiSignerContractCallAdapter: MultiSignerContractCallType, Sendable {

    private let inner: OZMultiSignerManager

    public init(_ inner: OZMultiSignerManager) {
        self.inner = inner
    }

    public func multiSignerContractCall(
        target: String,
        targetFn: String,
        targetArgs: [SCValXDR],
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        return try await inner.multiSignerContractCall(
            target: target,
            targetFn: targetFn,
            targetArgs: targetArgs,
            selectedSigners: selectedSigners
        )
    }
}

// ============================================================================
// MARK: - AllowanceFetcherType
// ============================================================================

/// Abstraction over the SEP-41 `allowance(from, spender)` simulation used by
/// `ApproveFlow.fetchAllowance(...)`.
///
/// The production implementation uses `SorobanServer.simulateTransaction(...)`
/// to invoke the token contract's read-only `allowance` function. Tests
/// inject `MockAllowanceFetcher`.
public protocol AllowanceFetcherType: Sendable {

    /// Simulates `allowance(from, spender)` on `tokenContract` and returns
    /// the result formatted as a decimal display string (e.g. `"100.0"`).
    ///
    /// Returns `nil` when the simulation fails or the returned value cannot
    /// be decoded as an `i128`. The fetcher never throws; the result card
    /// surfaces `nil` as `"Unable to fetch"`.
    func fetchAllowance(
        tokenContract: String,
        smartAccountContractId: String,
        spenderAddress: String
    ) async -> String?
}

// ============================================================================
// MARK: - ApproveFlow
// ============================================================================

/// Business logic for the token allowance approval screen.
///
/// Supports two approval variants:
/// - Single-signer: `transactionOperations.contractCall(target:targetFn:"approve",targetArgs:)`.
/// - Multi-signer: `multiSignerManager.multiSignerContractCall(...)` with an
///   explicit `[OZSelectedSigner]` list, used when more than one signer is
///   available on the connected smart account.
///
/// Multi-signer ordering & atomicity:
/// Delegated keypairs are registered in-process via
/// `kit.externalSigners.addFromSecret`; Ed25519 secrets are registered on the
/// demo ``DemoEd25519Adapter`` (the adapter custody path) so the SDK routes their
/// signing through the adapter. Both registrations and the SDK call run inside a
/// single cleanup wrapper that clears the delegated keypairs via
/// `kit.externalSigners.removeAll()` and the adapter via `DemoEd25519Adapter.clearAll()`
/// on both success and failure, so no signing material is retained across screens.
///
/// `fetchAllowance` is a best-effort post-success read: it waits 5 seconds for
/// the network to propagate the new allowance, simulates the SEP-41
/// `allowance` function on the token contract, and returns the decoded display
/// string. Returns `nil` on any failure; the screen renders `nil` as the
/// "Unable to fetch" hint.
///
/// Thread safety:
/// `@MainActor` because it mutates `ActivityLogState`. Both approve methods
/// are guarded by `isApproving`. The screen's `LoadingButton` also prevents
/// double-tap; this flag is an additional safeguard.
@MainActor
public final class ApproveFlow {

    // -------------------------------------------------------------------------
    // MARK: - Dependencies
    // -------------------------------------------------------------------------

    private let demoState: DemoState
    private let activityLog: ActivityLogState
    private let contractCallOperations: any ContractCallOperationsType
    private let multiSignerOperations: any MultiSignerContractCallType
    private let contextRuleManager: (any ContextRuleManagerType)?
    private let allowanceFetcher: (any AllowanceFetcherType)?

    // -------------------------------------------------------------------------
    // MARK: - Re-entrancy guard
    // -------------------------------------------------------------------------

    private var isApproving: Bool = false

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates an `ApproveFlow`.
    ///
    /// - Parameters:
    ///   - demoState: Shared observable demo state.
    ///   - activityLog: Shared activity log.
    ///   - contractCallOperations: Adapter over `OZTransactionOperations.contractCall(...)`.
    ///   - multiSignerOperations: Adapter over `OZMultiSignerManager.multiSignerContractCall(...)`.
    ///   - contextRuleManager: Adapter over `OZContextRuleManager` used by
    ///     ``loadAvailableSigners()``. `nil` causes that method to return an
    ///     empty list.
    ///   - allowanceFetcher: Adapter that simulates the post-approve `allowance(...)`
    ///     read. `nil` causes `fetchAllowance(_:_:)` to return `nil` immediately.
    public init(
        demoState: DemoState,
        activityLog: ActivityLogState,
        contractCallOperations: any ContractCallOperationsType,
        multiSignerOperations: any MultiSignerContractCallType,
        contextRuleManager: (any ContextRuleManagerType)? = nil,
        allowanceFetcher: (any AllowanceFetcherType)? = nil
    ) {
        self.demoState = demoState
        self.activityLog = activityLog
        self.contractCallOperations = contractCallOperations
        self.multiSignerOperations = multiSignerOperations
        self.contextRuleManager = contextRuleManager
        self.allowanceFetcher = allowanceFetcher
    }

    // -------------------------------------------------------------------------
    // MARK: - Public: loadAvailableSigners
    // -------------------------------------------------------------------------

    /// Loads unique signers across every on-chain context rule and annotates
    /// each with `canSign` per the connected credential and external signer
    /// manager. On any failure returns an empty list so the screen falls back
    /// to single-signer mode.
    ///
    /// - Returns: `[TransferSignerInfo]` ordered by first appearance.
    public func loadAvailableSigners() async -> [TransferSignerInfo] {
        return await MultiSignerRegistration.loadAvailableSigners(
            demoState: demoState,
            activityLog: activityLog,
            contextRuleManager: contextRuleManager
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - Public: approveAllowance (single-signer)
    // -------------------------------------------------------------------------

    /// Approves a token spending allowance for `spenderAddress` via a single
    /// passkey ceremony.
    ///
    /// Builds the SEP-41 `approve(from, spender, amount, expiration_ledger)`
    /// argument vector — with `from` set to the connected smart account
    /// contract ID, `amount` as a non-negative `i128` value in the token's
    /// smallest unit, and `expiration_ledger` set to the absolute ledger
    /// produced by `expirationLedger` — and submits via
    /// `OZTransactionOperations.contractCall(...)`.
    ///
    /// - Parameters:
    ///   - tokenContract: Token contract address (`C…` strkey).
    ///   - spenderAddress: G- or C-address authorised to spend the allowance.
    ///   - amount: Decimal amount string (e.g. `"10"` or `"10.5"`).
    ///   - expirationLedger: Absolute ledger number after which the allowance
    ///     is no longer valid.
    /// - Returns: `ApproveResult` describing the outcome.
    /// - Throws: `ApproveFlowError.alreadyInProgress` when reentered;
    ///   `ApproveFlowError.invalidAmount` when the amount cannot be parsed
    ///   into a positive base-units value within the signed 128-bit range;
    ///   `SmartAccountWalletException.NotConnected` when no wallet is connected; any
    ///   SDK error including `WebAuthnException.Cancelled` for user
    ///   cancellations.
    public func approveAllowance(
        tokenContract: String,
        spenderAddress: String,
        amount: String,
        expirationLedger: UInt32
    ) async throws -> ApproveResult {
        guard !isApproving else { throw ApproveFlowError.alreadyInProgress }
        guard demoState.isConnected, let smartAccountId = demoState.contractId else {
            throw SmartAccountWalletException.NotConnected(message: "No wallet connected.")
        }
        isApproving = true
        defer { isApproving = false }

        let args = try buildApproveArgs(
            smartAccountContractId: smartAccountId,
            spenderAddress: spenderAddress,
            amount: amount,
            expirationLedger: expirationLedger
        )

        let sdkResult = try await contractCallOperations.contractCall(
            target: tokenContract,
            targetFn: "approve",
            targetArgs: args
        )
        return handleSingleSignerResult(sdkResult)
    }

    // -------------------------------------------------------------------------
    // MARK: - Public: multiSignerApproveAllowanceWithChosenSigners
    // -------------------------------------------------------------------------

    /// Approves a token spending allowance via multiple signers, handling
    /// delegated keypair registration and signer-list construction internally.
    ///
    /// Atomicity: registers each delegated signer's secret key in-process via
    /// `kit.externalSigners.addFromSecret` and each Ed25519 secret on the demo
    /// adapter, builds the `[OZSelectedSigner]` list, then submits via the
    /// multi-signer manager — all inside a single cleanup wrapper. On any failure
    /// — including registration mismatches and non-success SDK results — both the
    /// delegated keypairs and the adapter secrets are cleared before the error
    /// propagates so credentials are never retained across screens. On success,
    /// both are also cleared.
    ///
    /// - Parameters:
    ///   - tokenContract: Token contract address (`C…` strkey).
    ///   - spenderAddress: G- or C-address authorised to spend the allowance.
    ///   - amount: Decimal amount string.
    ///   - expirationLedger: Absolute ledger number after which the allowance
    ///     is no longer valid.
    ///   - chosenSigners: Signers chosen in the signer picker (passkey
    ///     credentials and/or delegated G-addresses).
    ///   - delegatedSecrets: Map of G-address → secret key for delegated
    ///     Stellar account signers. Required for each delegated entry in
    ///     `chosenSigners`.
    ///   - ed25519Secrets: Map of `Ed25519SecretKey` → 32 raw secret bytes for
    ///     Ed25519 external signers. Required for each Ed25519 entry in `chosenSigners`.
    /// - Returns: `ApproveResult` describing the outcome.
    public func multiSignerApproveAllowanceWithChosenSigners( // swiftlint:disable:this function_parameter_count
        tokenContract: String,
        spenderAddress: String,
        amount: String,
        expirationLedger: UInt32,
        chosenSigners: [any OZSmartAccountSigner],
        delegatedSecrets: [String: String],
        ed25519Secrets: [Ed25519SecretKey: Data] = [:]
    ) async throws -> ApproveResult {
        guard !isApproving else { throw ApproveFlowError.alreadyInProgress }
        guard demoState.isConnected, let smartAccountId = demoState.contractId else {
            throw SmartAccountWalletException.NotConnected(message: "No wallet connected.")
        }
        isApproving = true
        defer { isApproving = false }

        let args = try buildApproveArgs(
            smartAccountContractId: smartAccountId,
            spenderAddress: spenderAddress,
            amount: amount,
            expirationLedger: expirationLedger
        )
        let sdkResult = try await registerAndCallMulti(
            tokenContract: tokenContract,
            args: args,
            chosenSigners: chosenSigners,
            delegatedSecrets: delegatedSecrets,
            ed25519Secrets: ed25519Secrets
        )
        return handleMultiSignerResult(sdkResult)
    }

    /// Registers delegated keypairs in-process and Ed25519 secrets on the demo
    /// adapter, invokes the multi-signer pipeline, and clears both stores on
    /// every exit path.
    ///
    /// The approve flow demonstrates the Ed25519 adapter custody path: Ed25519
    /// secrets are held by ``DemoEd25519Adapter`` (whose `canSignFor` returns
    /// `true` for them), so the SDK routes their signing through the adapter. The
    /// registrations and the SDK call all run inside
    /// ``MultiSignerRegistration/registerAdapterSignersWithCleanup(delegatedSecrets:ed25519Secrets:manager:adapter:body:)``
    /// so neither delegated keypairs nor adapter secrets leak if any step throws.
    ///
    /// The delegated registration is wrapped so its
    /// ``MultiSignerRegistrationError`` surfaces as the flow's typed
    /// ``ApproveFlowError/invalidDelegatedSigner(_:)``.
    ///
    /// Kept separate from ``multiSignerApproveAllowanceWithChosenSigners(...)`` so
    /// that method stays within SwiftLint's `function_body_length` cap.
    private func registerAndCallMulti(
        tokenContract: String,
        args: [SCValXDR],
        chosenSigners: [any OZSmartAccountSigner],
        delegatedSecrets: [String: String],
        ed25519Secrets: [Ed25519SecretKey: Data]
    ) async throws -> OZTransactionResult {
        do {
            return try await MultiSignerRegistration.registerAdapterSignersWithCleanup(
                delegatedSecrets: delegatedSecrets,
                ed25519Secrets: ed25519Secrets,
                manager: demoState.externalSigners,
                adapter: demoState.demoEd25519Adapter
            ) {
                let built = try await MultiSignerRegistration.buildSelectedSigners(
                    chosenSigners,
                    credentialManager: demoState.kit?.credentialManager
                )
                return try await multiSignerOperations.multiSignerContractCall(
                    target: tokenContract,
                    targetFn: "approve",
                    targetArgs: args,
                    selectedSigners: built
                )
            }
        } catch let MultiSignerRegistrationError.invalidDelegatedSigner(expected) {
            throw ApproveFlowError.invalidDelegatedSigner(expected)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Public: fetchAllowance
    // -------------------------------------------------------------------------

    /// Returns the spender's current allowance on `tokenContract` formatted
    /// as a decimal display string (e.g. `"100.0"`).
    ///
    /// Sleeps for 5 seconds before issuing the simulation so the network has
    /// time to propagate the freshly-approved allowance. Returns `nil` when
    /// the fetcher is not configured, when the wallet is not connected, when
    /// the simulation fails, or when the returned `SCValXDR` is not an `i128`.
    /// Never throws; the screen renders `nil` as `"Unable to fetch"`.
    public func fetchAllowance(
        tokenContract: String,
        spenderAddress: String
    ) async -> String? {
        guard let fetcher = allowanceFetcher,
              demoState.isConnected,
              let smartAccountId = demoState.contractId else {
            return nil
        }
        // 5-second wait for ledger propagation matches the post-approve read
        // pattern used by the demo's other allowance-style consumers.
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        return await fetcher.fetchAllowance(
            tokenContract: tokenContract,
            smartAccountContractId: smartAccountId,
            spenderAddress: spenderAddress
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - Private: argument construction
    // -------------------------------------------------------------------------

    /// Builds the SEP-41 `approve(from, spender, amount, expiration_ledger)`
    /// argument vector.
    ///
    /// `from` is always the connected smart account contract ID.
    /// `spender` is encoded as a G- or C-address `SCAddressXDR`.
    /// `amount` is encoded as `i128` in the token's smallest unit (base units).
    /// `expiration_ledger` is encoded as `u32`.
    ///
    /// - Throws: `ApproveFlowError.invalidSpenderAddress` if the spender is
    ///   neither a valid G-address nor a valid C-address;
    ///   `ApproveFlowError.invalidSmartAccountAddress` if the connected smart
    ///   account contract ID cannot be decoded as a C-address (corrupt
    ///   ``DemoState/contractId`` — should not happen in normal flow);
    ///   `ApproveFlowError.invalidAmount` if the amount is not a positive
    ///   decimal within the signed 128-bit base-units range.
    internal func buildApproveArgs(
        smartAccountContractId: String,
        spenderAddress: String,
        amount: String,
        expirationLedger: UInt32
    ) throws -> [SCValXDR] {
        let spenderAddr = try decodeSpenderAddress(spenderAddress)
        let fromAddr: SCAddressXDR
        do {
            fromAddr = try SCAddressXDR(contractId: smartAccountContractId)
        } catch {
            throw ApproveFlowError.invalidSmartAccountAddress(reason: error.localizedDescription)
        }
        guard let baseUnits = baseUnitsFromDecimalAmount(
            amount.trimmingCharacters(in: .whitespaces),
            decimals: nativeTokenDecimals
        ) else {
            throw ApproveFlowError.invalidAmount
        }
        let amountScVal: SCValXDR
        do {
            amountScVal = try SCValXDR.i128(stringValue: baseUnits)
        } catch {
            throw ApproveFlowError.invalidAmount
        }
        return [
            .address(fromAddr),
            .address(spenderAddr),
            amountScVal,
            .u32(expirationLedger)
        ]
    }

    /// Decodes a user-entered spender string to `SCAddressXDR`. Accepts G- or
    /// C-addresses; throws `invalidSpenderAddress` otherwise. Extracted to
    /// keep ``buildApproveArgs(...)`` within the SwiftLint body-length cap.
    private func decodeSpenderAddress(_ spender: String) throws -> SCAddressXDR {
        let trimmed = spender.trimmingCharacters(in: .whitespaces)
        do {
            if trimmed.isValidEd25519PublicKey() {
                return try SCAddressXDR(accountId: trimmed)
            }
            if trimmed.isValidContractId() {
                return try SCAddressXDR(contractId: trimmed)
            }
        } catch {
            throw ApproveFlowError.invalidSpenderAddress(reason: error.localizedDescription)
        }
        throw ApproveFlowError.invalidSpenderAddress(
            reason: "Must be a valid Stellar account (G...) or contract (C...) address"
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - Public: isSinglePasskeyApproval
    // -------------------------------------------------------------------------

    /// Returns `true` when exactly one passkey signer matching the connected
    /// credential was chosen, so the single-passkey fast-path should be used.
    public func isSinglePasskeyApproval(_ chosenSigners: [any OZSmartAccountSigner]) -> Bool {
        return MultiSignerRegistration.isSinglePasskey(
            chosenSigners,
            connectedCredentialId: demoState.credentialId
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - Private: result handling
    // -------------------------------------------------------------------------

    private func handleSingleSignerResult(_ sdkResult: OZTransactionResult) -> ApproveResult {
        if sdkResult.success, let hash = sdkResult.hash {
            activityLog.success("Approve successful! Hash: \(truncateAddress(hash, chars: 8))")
            return ApproveResult(success: true, hash: hash, error: nil)
        }
        let msg = ActivityLogState.redact(sdkResult.error ?? "Approve failed with no error detail")
        activityLog.error("Approve failed: \(msg)")
        return ApproveResult(success: false, hash: nil, error: msg)
    }

    private func handleMultiSignerResult(_ sdkResult: OZTransactionResult) -> ApproveResult {
        if sdkResult.success, let hash = sdkResult.hash {
            activityLog.success(
                "Multi-signer approve successful! Hash: \(truncateAddress(hash, chars: 8))"
            )
            return ApproveResult(success: true, hash: hash, error: nil)
        }
        let msg = ActivityLogState.redact(sdkResult.error ?? "Approve failed with no error detail")
        activityLog.error("Multi-signer approve failed: \(msg)")
        return ApproveResult(success: false, hash: nil, error: msg)
    }
}

// ============================================================================
// MARK: - ApproveFlowError
// ============================================================================

/// Errors thrown by `ApproveFlow` at the flow layer (not from the SDK).
///
/// SDK errors (`WebAuthnException`, `SmartAccountValidationException`, etc.) are
/// propagated directly without wrapping. These cases guard flow-level
/// constraints only.
public enum ApproveFlowError: Error, Sendable {

    /// An approval is already in progress. The re-entrancy guard rejected the call.
    case alreadyInProgress

    /// The spender string could not be parsed as a valid Stellar account or
    /// contract address.
    case invalidSpenderAddress(reason: String)

    /// The connected smart account contract ID stored in ``DemoState`` could
    /// not be decoded as a valid C-address. Distinct from
    /// ``invalidSpenderAddress(reason:)`` so the call site can render an
    /// actionable message that does not blame the user's spender input.
    case invalidSmartAccountAddress(reason: String)

    /// The amount string is not a positive decimal within the signed 128-bit
    /// base-units range.
    case invalidAmount

    /// The registered keypair for a delegated signer derived a different
    /// G-address than the one recorded in the signer picker. Indicates either
    /// a user entry error or a corrupted secret key.
    case invalidDelegatedSigner(String)
}

extension ApproveFlowError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .alreadyInProgress:
            return "An approve operation is already in progress."
        case .invalidSpenderAddress(let reason):
            return "Invalid spender address: \(reason)"
        case .invalidSmartAccountAddress(let reason):
            return "Invalid smart account address: \(reason)"
        case .invalidAmount:
            return "Amount must be a positive decimal value."
        case .invalidDelegatedSigner(let address):
            return "The secret key does not match the expected signer address (\(truncateAddress(address)))."
        }
    }
}

// ============================================================================
// MARK: - No-op stubs (used when kit is nil)
// ============================================================================

/// No-op stub for `ContractCallOperationsType` used when the smart-account kit
/// is not yet connected. The approve button is disabled in that state; this stub
/// exists so the flow can be constructed without optional unwrap at call sites.
struct NoOpContractCallOperations: ContractCallOperationsType {
    func contractCall(
        target: String,
        targetFn: String,
        targetArgs: [SCValXDR]
    ) async throws -> OZTransactionResult {
        throw SmartAccountWalletException.NotConnected(message: "No wallet connected.")
    }
}

/// No-op stub for `MultiSignerContractCallType`.
struct NoOpMultiSignerContractCall: MultiSignerContractCallType {
    func multiSignerContractCall(
        target: String,
        targetFn: String,
        targetArgs: [SCValXDR],
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        throw SmartAccountWalletException.NotConnected(message: "No wallet connected.")
    }
}
