// ContextRuleFlow.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - ContextRuleManagerFullType
// ============================================================================

/// Full abstraction over `OZContextRuleManager` used by `ContextRuleFlow`.
///
/// Extends `ContextRuleManagerType` (list only) with remove, add, count, and
/// the per-operation edit methods used by
/// ``ContextRuleFlow/submitContextRuleEdits(diff:selectedSigners:onProgress:)``.
/// Tests inject `MockContextRuleManagerFull` from `ContextRuleTestSupport.swift`.
public protocol ContextRuleManagerFullType: ContextRuleManagerType {

    /// Removes a context rule from the connected smart account.
    ///
    /// - Parameters:
    ///   - ruleId: The numeric rule identifier to remove.
    ///   - selectedSigners: Signer list for multi-signer authorization, or empty
    ///     for single-passkey authorization.
    /// - Returns: An `OZTransactionResult` describing the on-chain outcome.
    func removeContextRule(
        ruleId: UInt32,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult

    /// Returns the current number of context rules registered on the smart account.
    func getContextRulesCount() async throws -> UInt32

    // swiftlint:disable function_parameter_count

    /// Adds a new context rule to the connected smart account.
    ///
    /// - Parameters:
    ///   - contextType: Operation-matching context (default / call / create contract).
    ///   - name: Human-readable rule name (must be non-empty).
    ///   - validUntil: Optional absolute ledger number when this rule expires.
    ///   - signers: Signers authorized by this rule.
    ///   - policies: Map of policy contract addresses to install parameters.
    ///   - selectedSigners: Signer list for multi-signer authorization, or empty
    ///     for single-passkey authorization.
    /// - Returns: An `OZTransactionResult` describing the on-chain outcome.
    func addContextRule(
        contextType: OZContextRuleType,
        name: String,
        validUntil: UInt32?,
        signers: [any OZSmartAccountSigner],
        policies: [String: SCValXDR],
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult

    // swiftlint:enable function_parameter_count

    // -------------------------------------------------------------------------
    // MARK: - Per-operation edit calls
    // -------------------------------------------------------------------------

    /// Updates the rule's display name.
    func updateContextRuleName(
        ruleId: UInt32,
        newName: String,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult

    /// Updates the rule's expiration ledger (`nil` removes expiry).
    func updateContextRuleValidUntil(
        ruleId: UInt32,
        newValidUntil: UInt32?,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult

    /// Adds a delegated (G-address) signer to the rule.
    func addDelegatedSignerToRule(
        ruleId: UInt32,
        address: String,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult

    /// Adds a raw Ed25519 signer to the rule using the configured verifier.
    func addEd25519SignerToRule(
        ruleId: UInt32,
        verifierAddress: String,
        publicKey: Data,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult

    /// Adds a WebAuthn passkey signer to the rule.
    func addPasskeySignerToRule(
        ruleId: UInt32,
        publicKey: Data,
        credentialId: Data,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult

    /// Removes a signer from the rule by on-chain identifier.
    func removeSignerFromRule(
        ruleId: UInt32,
        signerId: UInt32,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult

    /// Adds a policy with encoded install params to the rule.
    func addPolicyToRule(
        ruleId: UInt32,
        policyAddress: String,
        installParams: SCValXDR,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult

    /// Removes a policy from the rule by on-chain identifier.
    func removePolicyFromRule(
        ruleId: UInt32,
        policyId: UInt32,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult

    /// Returns the rule's raw on-chain `SCValXDR` form, used by the edit-flow
    /// to feed `set_threshold`.
    func getContextRuleRaw(ruleId: UInt32) async throws -> SCValXDR
}

// ============================================================================
// MARK: - ContextRuleFlow
// ============================================================================

/// Business logic for the context rules screen.
///
/// Responsibilities:
/// - Load all on-chain context rules via `listContextRules()`.
/// - Remove a rule with optional multi-signer authorization via `removeContextRule(...)`.
/// - Load available signers for the signer picker on multi-signer removal.
/// - Guard against removing the last rule (the screen additionally disables the button,
///   but this flow enforces the invariant as a safety net).
///
/// Thread safety:
/// `ContextRuleFlow` is `@MainActor` because it mutates `ActivityLogState`
/// and is driven by SwiftUI screens running on the main actor.
///
/// Re-entrancy:
/// Both mutating operations are guarded by `isRemoving`. The screen's
/// `LoadingButton` also prevents double-tap; this guard is an additional safeguard.
@MainActor
public final class ContextRuleFlow {

    // -------------------------------------------------------------------------
    // MARK: - Dependencies
    // -------------------------------------------------------------------------

    internal let demoState: DemoState
    internal let activityLog: ActivityLogState
    internal let contextRuleManager: (any ContextRuleManagerFullType)?
    internal let smartAccountExecutor: (any SmartAccountExecutorType)?
    internal let webAuthnProvider: (any WebAuthnProvider)?
    internal let webAuthnVerifierAddress: String?
    internal let ed25519VerifierAddress: String?
    internal let ledgerSource: (any LatestLedgerSource)?
    internal let rpcUrl: String?

    // -------------------------------------------------------------------------
    // MARK: - Re-entrancy guard
    // -------------------------------------------------------------------------

    private var isRemoving: Bool = false
    internal var isAdding: Bool = false
    internal var isEditing: Bool = false

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates a `ContextRuleFlow` with the provided dependencies.
    ///
    /// - Parameters:
    ///   - demoState: Shared observable demo state.
    ///   - activityLog: Shared activity log.
    ///   - contextRuleManager: Adapter over `OZContextRuleManager`. `nil` causes
    ///     all operations to produce empty results or throw `SmartAccountWalletException.NotConnected`.
    ///   - smartAccountExecutor: Adapter over the smart account's `execute` entry
    ///     point, used by the edit-flow for policy operations such as
    ///     `set_threshold`. `nil` causes threshold-only modifications to throw.
    ///   - webAuthnProvider: Platform WebAuthn provider used by
    ///     ``registerPasskeySigner(name:)``. Required only for that method.
    ///   - webAuthnVerifierAddress: WebAuthn verifier contract address (`C…`) used
    ///     when constructing freshly-registered passkey signers.
    ///   - ed25519VerifierAddress: Ed25519 verifier contract address (`C…`) used
    ///     when dispatching `addEd25519SignerToRule` during edit mode.
    ///   - ledgerSource: Source for the current Soroban ledger sequence used by
    ///     ``resolveAbsoluteLedger(offset:)``. Tests inject a deterministic mock.
    ///   - rpcUrl: Soroban RPC URL used by ``readPolicyParams(info:ruleId:)``
    ///     to inspect on-chain policy storage. `nil` disables policy parameter
    ///     reads (the edit form simply omits the inline editor).
    public init(
        demoState: DemoState,
        activityLog: ActivityLogState,
        contextRuleManager: (any ContextRuleManagerFullType)? = nil,
        smartAccountExecutor: (any SmartAccountExecutorType)? = nil,
        webAuthnProvider: (any WebAuthnProvider)? = nil,
        webAuthnVerifierAddress: String? = nil,
        ed25519VerifierAddress: String? = nil,
        ledgerSource: (any LatestLedgerSource)? = nil,
        rpcUrl: String? = nil
    ) {
        self.demoState = demoState
        self.activityLog = activityLog
        self.contextRuleManager = contextRuleManager
        self.smartAccountExecutor = smartAccountExecutor
        self.webAuthnProvider = webAuthnProvider
        self.webAuthnVerifierAddress = webAuthnVerifierAddress
        self.ed25519VerifierAddress = ed25519VerifierAddress
        self.ledgerSource = ledgerSource
        self.rpcUrl = rpcUrl
    }

    // -------------------------------------------------------------------------
    // MARK: - Public: listContextRules
    // -------------------------------------------------------------------------

    /// Fetches all on-chain context rules for the connected smart account.
    ///
    /// Logs the fetch attempt and outcome. On success, logs the count. On failure,
    /// the error is propagated so the screen can display an error card.
    ///
    /// - Returns: Array of `OZParsedContextRule`, sorted by ID ascending.
    /// - Throws: SDK errors if the RPC call fails.
    public func listContextRules() async throws -> [OZParsedContextRule] {
        guard demoState.isConnected, let manager = contextRuleManager else {
            throw SmartAccountWalletException.NotConnected(message: "No wallet connected.")
        }
        activityLog.info("Loading context rules...")
        let rules = try await manager.listContextRules()
        let sorted = rules.sorted { $0.id < $1.id }
        activityLog.success("\(pluralize(sorted.count, "context rule", "context rules")) loaded.")
        return sorted
    }

    // -------------------------------------------------------------------------
    // MARK: - Public: removeContextRule
    // -------------------------------------------------------------------------

    /// Removes a context rule from the connected smart account.
    ///
    /// Performs a last-rule safety check before calling the SDK. If only one rule
    /// remains, throws `ContextRuleFlowError.cannotRemoveLastRule`.
    ///
    /// **`selectedSigners` contract:**
    /// - Empty array → single-passkey fast-path: the SDK performs one WebAuthn
    ///   ceremony with the currently connected credential and submits.
    /// - Non-empty array → multi-signer authorization. Each entry MUST be one of:
    ///   - `OZExternalSigner` carrying a WebAuthn credential ID (passkey signer), OR
    ///   - `OZDelegatedSigner` (G-address signer; its secret key must appear in
    ///     `delegatedSecrets` so it can be registered with the external signer
    ///     manager before submission).
    ///
    ///   Any other signer kind (raw Ed25519 verifier, `OZExternalSigner` with
    ///   no credential ID, third-party signer types) is rejected with
    ///   `ContextRuleFlowError.unsupportedSignerKind`.
    ///
    /// For multi-signer removal, registers any delegated keypairs in the external
    /// signer manager before invoking the SDK, then clears them afterward.
    ///
    /// On success, logs the transaction hash. On failure, cleans up keypairs and
    /// propagates the error.
    ///
    /// - Parameters:
    ///   - ruleId: The rule to remove.
    ///   - ruleName: Display name used in log messages. Redacted before being
    ///     written to `activityLog` so any on-chain string the contract emitted
    ///     cannot exfiltrate via the visible log.
    ///   - totalRuleCount: Current total number of rules (used for last-rule guard).
    ///   - selectedSigners: Multi-signer list (empty = single-passkey path).
    ///   - delegatedSecrets: G-address → secret-key map for delegated signers.
    ///   - ed25519Secrets: Map of `Ed25519SecretKey` → 32 raw secret bytes for
    ///     any Ed25519 entries included in `selectedSigners`.
    /// - Returns: The confirmed transaction hash.
    /// - Throws: `ContextRuleFlowError.cannotRemoveLastRule` /
    ///   `ContextRuleFlowError.alreadyInProgress` /
    ///   `ContextRuleFlowError.unsupportedSignerKind` / SDK errors.
    public func removeContextRule(
        ruleId: UInt32,
        ruleName: String,
        totalRuleCount: Int,
        selectedSigners: [any OZSmartAccountSigner],
        delegatedSecrets: [String: String],
        ed25519Secrets: [Ed25519SecretKey: Data] = [:]
    ) async throws -> String {
        guard !isRemoving else {
            throw ContextRuleFlowError.alreadyInProgress
        }
        guard totalRuleCount > 1 else {
            throw ContextRuleFlowError.cannotRemoveLastRule
        }
        guard demoState.isConnected, let manager = contextRuleManager else {
            throw SmartAccountWalletException.NotConnected(message: "No wallet connected.")
        }
        isRemoving = true
        defer { isRemoving = false }

        let display = ActivityLogState.redact(ruleName.isEmpty ? "Unnamed Rule" : ruleName)
        activityLog.info("Removing context rule #\(ruleId) \"\(display)\"...")

        let built = try await resolveSelectedSignersForRemoval(selectedSigners)
        let sdkResult = try await registerAndExecuteRemove(
            manager: manager,
            ruleId: ruleId,
            built: built,
            delegatedSecrets: delegatedSecrets,
            ed25519Secrets: ed25519Secrets
        )

        guard sdkResult.success, let hash = sdkResult.hash else {
            let msg = ActivityLogState.redact(sdkResult.error ?? "Remove failed with no error detail")
            throw ContextRuleFlowError.removeFailed(reason: msg)
        }
        activityLog.success("Rule #\(ruleId) removed. Hash: \(truncateAddress(hash, chars: 8))")
        return hash
    }

    /// Converts user-selected signers to ``OZSelectedSigner`` and wraps the
    /// shared "unsupported signer kind" error into
    /// ``ContextRuleFlowError/unsupportedSignerKind(description:)`` so the
    /// flow's typed error surface stays stable for tests and callers.
    private func resolveSelectedSignersForRemoval(
        _ selectedSigners: [any OZSmartAccountSigner]
    ) async throws -> [OZSelectedSigner] {
        try await buildSelectedSigners(selectedSigners)
    }

    /// Flow seam that converts user-selected signers to ``OZSelectedSigner``,
    /// looking up each passkey's stored WebAuthn transport hints through the
    /// connected kit's credential manager.
    ///
    /// Exposed so the context-rule builder component can reach the credential
    /// manager without importing the SDK directly. Wraps the shared
    /// "unsupported signer kind" error into
    /// ``ContextRuleFlowError/unsupportedSignerKind(description:)`` so the
    /// flow's typed error surface stays stable for tests and callers.
    ///
    /// - Parameter selectedSigners: User-selected signers in picker order.
    /// - Returns: ``OZSelectedSigner`` list in the same order.
    /// - Throws: ``ContextRuleFlowError/unsupportedSignerKind(description:)``
    ///   when a signer shape cannot be honoured.
    internal func buildSelectedSigners(
        _ selectedSigners: [any OZSmartAccountSigner]
    ) async throws -> [OZSelectedSigner] {
        do {
            return try await MultiSignerRegistration.buildSelectedSigners(
                selectedSigners,
                credentialManager: demoState.kit?.credentialManagerConcrete,
                unsupportedShapePolicy: .throwError
            )
        } catch let MultiSignerRegistrationError.unsupportedSignerKind(description) {
            throw ContextRuleFlowError.unsupportedSignerKind(description: description)
        }
    }

    /// Registers delegated and in-process Ed25519 signing material, calls
    /// `manager.removeContextRule(...)`, and clears all registered material on
    /// both the success path and the catch / rethrow path so credentials are
    /// never retained across screens.
    ///
    /// The context-rule flow demonstrates the in-process Ed25519 custody path:
    /// Ed25519 secrets are registered directly on `kit.externalSigners` via
    /// `addEd25519FromRawKey`, so the demo adapter holds no secret for them. Both
    /// registrations and the SDK call run inside one cleanup wrapper, so no
    /// signing material leaks if any step throws.
    ///
    /// The delegated registration is wrapped so its
    /// ``MultiSignerRegistrationError`` surfaces as the flow's typed
    /// ``ContextRuleFlowError/invalidDelegatedSigner(_:)``.
    private func registerAndExecuteRemove(
        manager: any ContextRuleManagerFullType,
        ruleId: UInt32,
        built: [OZSelectedSigner],
        delegatedSecrets: [String: String],
        ed25519Secrets: [Ed25519SecretKey: Data]
    ) async throws -> OZTransactionResult {
        do {
            return try await MultiSignerRegistration.registerInProcessSignersWithCleanup(
                delegatedSecrets: delegatedSecrets,
                ed25519Secrets: ed25519Secrets,
                manager: demoState.externalSigners
            ) {
                try await manager.removeContextRule(
                    ruleId: ruleId,
                    selectedSigners: built
                )
            }
        } catch let MultiSignerRegistrationError.invalidDelegatedSigner(expected) {
            throw ContextRuleFlowError.invalidDelegatedSigner(expected)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Public: loadAvailableSigners
    // -------------------------------------------------------------------------

    /// Loads unique signers from all context rules for the signer picker.
    ///
    /// Called before showing the signer picker on multi-signer removal.
    /// On any failure, returns an empty list so the screen falls back to single-signer mode.
    ///
    /// - Returns: `[TransferSignerInfo]` with signing capability flags.
    public func loadAvailableSigners() async -> [TransferSignerInfo] {
        return await MultiSignerRegistration.loadAvailableSigners(
            demoState: demoState,
            activityLog: activityLog,
            contextRuleManager: contextRuleManager
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - Public: isSinglePasskeyRemoval
    // -------------------------------------------------------------------------

    /// Returns `true` when the single-passkey fast-path should be used for removal.
    ///
    /// The fast-path applies when exactly one signer is selected and that signer
    /// is a passkey whose credential ID matches the connected credential.
    ///
    /// - Parameter chosenSigners: Signers chosen in the signer picker.
    public func isSinglePasskeyRemoval(_ chosenSigners: [any OZSmartAccountSigner]) -> Bool {
        return MultiSignerRegistration.isSinglePasskey(
            chosenSigners,
            connectedCredentialId: demoState.credentialId
        )
    }
}

// ============================================================================
// MARK: - ContextRuleFlowError
// ============================================================================

/// Errors thrown by `ContextRuleFlow` at the flow layer (not from the SDK).
///
/// SDK errors are propagated directly without wrapping. These cases guard
/// flow-level constraints only.
public enum ContextRuleFlowError: Error, Sendable {

    /// A removal is already in progress. The re-entrancy guard rejected the call.
    case alreadyInProgress

    /// The caller attempted to remove the only remaining context rule.
    case cannotRemoveLastRule

    /// The SDK returned a non-success `OZTransactionResult` with the attached reason.
    case removeFailed(reason: String)

    /// The registered keypair for a delegated signer derived a different G-address.
    case invalidDelegatedSigner(String)

    /// A signer kind that this flow does not support was supplied to
    /// `removeContextRule(...)`. Only `OZExternalSigner` with a credential ID
    /// (passkey) and `OZDelegatedSigner` (G-address) are accepted.
    case unsupportedSignerKind(description: String)

    /// The flow requires a platform WebAuthn provider but none was injected.
    /// Returned by ``ContextRuleFlow/registerPasskeySigner(name:)`` when the
    /// hosting platform has not supplied an authenticator.
    case webAuthnProviderUnavailable

    /// The flow requires a Soroban RPC client but none was injected. Returned
    /// by ``ContextRuleFlow/resolveAbsoluteLedger(offset:)`` when called without
    /// a ledger source.
    case ledgerSourceUnavailable

    /// The Soroban RPC `getLatestLedger` call failed. Carries the raw error
    /// detail from the SDK.
    case latestLedgerFetchFailed(reason: String)

    /// The user-entered context type could not be resolved into a valid
    /// ``OZContextRuleType`` (for example, a malformed WASM hash for the
    /// "create contract" option). Distinct from ``removeFailed`` so the call
    /// site can render an actionable per-field error.
    case invalidContextType(reason: String)

    /// An edit submission is already in progress. The re-entrancy guard
    /// rejected the call.
    case editAlreadyInProgress

    /// A step within an edit submission failed. Carries the step description
    /// and the underlying error reason for surfacing in the result card.
    case editStepFailed(step: String, reason: String)

    /// A signer entry required to remove on-chain state lacked its identifier
    /// (loaded from a malformed rule). Distinct from ``removeFailed`` so the
    /// call site can render an actionable copy.
    case missingOnChainIdentifier(entity: String)

    /// Decoding an on-chain SCVal failed (for example when reading the install
    /// parameters of a known policy via ``readPolicyParams(info:ruleId:)``).
    case scValDecodeFailed(reason: String)
}

extension ContextRuleFlowError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .alreadyInProgress:
            return "A removal operation is already in progress."
        case .cannotRemoveLastRule:
            return "Cannot remove the last context rule."
        case .removeFailed(let reason):
            return "Remove failed: \(reason)"
        case .invalidDelegatedSigner(let address):
            return "The secret key does not match the expected signer address (\(truncateAddress(address)))."
        case .unsupportedSignerKind(let description):
            return "Unsupported signer kind: \(description)."
        case .webAuthnProviderUnavailable:
            return "WebAuthn provider is not available on this platform."
        case .ledgerSourceUnavailable:
            return "Ledger source is not available; cannot resolve expiry."
        case .latestLedgerFetchFailed(let reason):
            return "Failed to fetch the current ledger: \(reason)."
        case .invalidContextType(let reason):
            return "Invalid context type: \(reason)."
        case .editAlreadyInProgress:
            return "An edit operation is already in progress."
        case .editStepFailed(let step, let reason):
            return "\(step) failed: \(reason)."
        case .missingOnChainIdentifier(let entity):
            return "Missing on-chain identifier for \(entity)."
        case .scValDecodeFailed(let reason):
            return "Failed to decode on-chain value: \(reason)."
        }
    }
}
