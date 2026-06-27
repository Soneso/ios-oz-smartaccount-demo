// DelegateToAgentFlow.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - DelegationSummary
// ============================================================================

/// Structured description of an authorised delegation, shown on the
/// confirmation card after a successful submission.
public struct DelegationSummary: Sendable, Equatable {

    /// The agent's Ed25519 public key (64-character hex) that was authorised.
    public let agentPublicKey: String

    /// The token contract the agent is scoped to (C-address).
    public let tokenContract: String

    /// The human-readable spending cap (decimal string).
    public let amount: String

    /// The spending-limit rolling window in ledgers.
    public let periodLedgers: UInt32

    /// Absolute ledger past which the rule expires, or `nil` when it never
    /// expires.
    public let validUntilLedger: UInt32?

    /// The context-rule name written on-chain.
    public let ruleName: String

    /// The spending-limit policy contract address (C-address).
    public let spendingLimitPolicyAddress: String

    /// The Ed25519 verifier contract address (C-address).
    public let verifierAddress: String

    public init(
        agentPublicKey: String,
        tokenContract: String,
        amount: String,
        periodLedgers: UInt32,
        validUntilLedger: UInt32?,
        ruleName: String,
        spendingLimitPolicyAddress: String,
        verifierAddress: String
    ) {
        self.agentPublicKey = agentPublicKey
        self.tokenContract = tokenContract
        self.amount = amount
        self.periodLedgers = periodLedgers
        self.validUntilLedger = validUntilLedger
        self.ruleName = ruleName
        self.spendingLimitPolicyAddress = spendingLimitPolicyAddress
        self.verifierAddress = verifierAddress
    }
}

// ============================================================================
// MARK: - DelegationResult
// ============================================================================

/// Outcome of a ``DelegateToAgentFlow/delegateToAgent(agentPublicKey:tokenContract:amount:periodLedgers:validUntilOffsetLedgers:tokenDecimals:ruleName:)`` call.
///
/// ``success`` is true when the `addContextRule` transaction confirmed
/// on-chain. ``hash`` and ``summary`` are populated on success; ``error``
/// carries a sanitised user-facing message on failure.
public struct DelegationResult: Sendable, Equatable {

    /// True on confirmed on-chain submission.
    public let success: Bool

    /// On-chain transaction hash on success.
    public let hash: String?

    /// Sanitised error message on failure.
    public let error: String?

    /// Structured rule summary on success.
    public let summary: DelegationSummary?

    public init(success: Bool, hash: String? = nil, error: String? = nil, summary: DelegationSummary? = nil) {
        self.success = success
        self.hash = hash
        self.error = error
        self.summary = summary
    }
}

// ============================================================================
// MARK: - DelegateToAgentFlow
// ============================================================================

/// Business logic for the "Delegate to agent" screen (step 2 of the
/// agent-signer flow).
///
/// Composes a single `addContextRule` call that grants an autonomous agent a
/// scoped, spend-capped, time-bounded authority on the connected smart account:
///
/// - context type `CallContract(token)` — the rule only matches calls to the
///   one token contract the agent may touch.
/// - signers `[Ed25519 external signer]` — the agent's Ed25519 public key,
///   verified through the Ed25519 verifier contract. The agent owns the
///   matching secret; only its public key is pasted into this screen.
/// - policies `{ spending-limit: cap per period }` — a maximum spend over a
///   rolling ledger window.
/// - `validUntil` — an absolute ledger past which the rule stops applying.
///
/// Wraps the shared ``ContextRuleFlow`` for the SDK interaction
/// (`addContextRule`, `resolveAbsoluteLedger`, `resolveSpendingLimitDecimals`)
/// so the composition lives in one place and stays unit-testable without a
/// network: ``ContextRuleFlow`` is constructed with injectable manager /
/// environment adapters that tests replace with mocks.
@MainActor
public final class DelegateToAgentFlow {

    // -------------------------------------------------------------------------
    // MARK: - Constants
    // -------------------------------------------------------------------------

    /// Default human-readable name for the delegation context rule.
    ///
    /// Kept within the on-chain 20-byte name limit
    /// (`ContextRuleBuilderCore.maxRuleNameBytes`).
    public static let defaultRuleName = "Agent"

    // -------------------------------------------------------------------------
    // MARK: - Dependencies
    // -------------------------------------------------------------------------

    private let contextRuleFlow: ContextRuleFlow
    private let activityLog: ActivityLogState

    private var isSubmitting = false

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates a flow with injected dependencies.
    ///
    /// - Parameters:
    ///   - contextRuleFlow: Supplies the SDK seam (its manager / environment
    ///     adapters are themselves injectable, which makes this flow testable
    ///     without a network).
    ///   - activityLog: Receives progress messages.
    public init(contextRuleFlow: ContextRuleFlow, activityLog: ActivityLogState) {
        self.contextRuleFlow = contextRuleFlow
        self.activityLog = activityLog
    }

    // -------------------------------------------------------------------------
    // MARK: - Configuration accessors
    // -------------------------------------------------------------------------

    /// The spending-limit policy contract address from `knownPolicies`, used as
    /// the policy the delegation installs.
    public var spendingLimitPolicyAddress: String {
        knownPolicies.first { $0.type == "spending_limit" }?.address ?? ""
    }

    /// The Ed25519 verifier C-address the agent signer is registered under.
    public var ed25519VerifierAddress: String {
        contextRuleFlow.ed25519VerifierAddress ?? DemoConfig.ed25519VerifierAddress
    }

    // -------------------------------------------------------------------------
    // MARK: - Validation
    // -------------------------------------------------------------------------

    /// Validates `value` as the agent's raw 32-byte Ed25519 public key in hex.
    ///
    /// Returns `nil` when `value` is empty (so the form is not flagged on
    /// initial render) or when it is exactly 64 hex characters. Returns an error
    /// string otherwise. The agent emits its public key as raw 64-character hex,
    /// so the screen accepts the same representation.
    public func validateAgentPublicKey(_ value: String) -> String? {
        let raw = value.trimmingCharacters(in: .whitespaces).lowercased()
        if raw.isEmpty { return nil }
        if raw.count != 64 {
            return "Must be 64 hex characters (32 bytes), got \(raw.count)"
        }
        if !raw.allSatisfy(\.isHexDigit) {
            return "Invalid hex characters"
        }
        return nil
    }

    /// Validates `value` against the spending-limit amount rules.
    ///
    /// Returns `nil` when `value` is empty. Otherwise returns one of the
    /// validation error strings when the value uses scientific notation, a comma
    /// decimal separator, fails parsing, or is not positive.
    ///
    /// A comma is rejected rather than silently normalised to a dot: the cap is
    /// encoded by `OZTransactionOperations.amountToBaseUnits`, whose strict
    /// `^-?[0-9]+(\.[0-9]+)?$` grammar accepts only a dot. Normalising here would
    /// let a comma input pass UI validation and then fail at encoding time —
    /// exactly the path that must not silently drop the spend cap. Surfacing the
    /// error keeps the form and the on-chain encoding in agreement.
    ///
    /// Pure (no actor state) so it is `nonisolated` and callable from any context.
    public nonisolated static func validateAmount(_ value: String) -> String? {
        if value.isEmpty { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().contains("e") {
            return "Scientific notation is not supported"
        }
        if trimmed.contains(",") {
            return "Use a dot for the decimal separator"
        }
        if trimmed.filter({ $0 == "." }).count > 1 {
            return "Must be a valid number"
        }
        guard let parsed = Double(trimmed) else {
            return "Must be a valid number"
        }
        if parsed <= 0 {
            return "Must be greater than zero"
        }
        return nil
    }

    // -------------------------------------------------------------------------
    // MARK: - Token decimals
    // -------------------------------------------------------------------------

    /// Resolves the decimal scale of the spending-limit guarded token.
    ///
    /// Delegates to ``ContextRuleFlow/resolveSpendingLimitDecimals(forGuardedToken:)``:
    /// the native token resolves without a network call; a custom token's
    /// `decimals()` is fetched on-chain. The amount-to-base-units conversion in
    /// ``delegateToAgent(agentPublicKey:tokenContract:amount:periodLedgers:validUntilOffsetLedgers:tokenDecimals:ruleName:)``
    /// must use the value returned here so the cap is scaled with the correct
    /// precision.
    public func resolveTokenDecimals(_ tokenContract: String) async throws -> Int {
        try await contextRuleFlow.resolveSpendingLimitDecimals(forGuardedToken: tokenContract)
    }

    // -------------------------------------------------------------------------
    // MARK: - Delegate
    // -------------------------------------------------------------------------

    /// Composes and submits ONE `addContextRule` call delegating scoped,
    /// spend-capped, time-bounded authority to the agent.
    ///
    /// - Parameters:
    ///   - agentPublicKey: The agent's raw 32-byte Ed25519 public key as
    ///     64-character hex. Validated and decoded to the raw 32-byte key the
    ///     verifier contract expects.
    ///   - tokenContract: The single token the rule scopes to via `CallContract`.
    ///   - amount: The spending cap as a human decimal string, converted to
    ///     base units with `tokenDecimals`.
    ///   - periodLedgers: The spending-limit rolling window.
    ///   - validUntilOffsetLedgers: Number of ledgers from now at which the rule
    ///     expires; resolved to an absolute ledger via the current ledger. A
    ///     value `<= 0` produces no expiry.
    ///   - tokenDecimals: The guarded token's decimal scale (from
    ///     ``resolveTokenDecimals(_:)``).
    ///   - ruleName: Human-readable rule name written on-chain.
    /// - Returns: A ``DelegationResult``; on failure ``DelegationResult/error``
    ///   is sanitised and safe to display verbatim.
    public func delegateToAgent(
        agentPublicKey: String,
        tokenContract: String,
        amount: String,
        periodLedgers: UInt32,
        validUntilOffsetLedgers: UInt32,
        tokenDecimals: Int,
        ruleName: String = DelegateToAgentFlow.defaultRuleName
    ) async -> DelegationResult {
        guard !isSubmitting else {
            return DelegationResult(success: false, error: "A delegation is already in progress.")
        }
        isSubmitting = true
        defer { isSubmitting = false }

        let trimmedKey = agentPublicKey.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmedKey.count == 64, trimmedKey.allSatisfy(\.isHexDigit),
              let agentKeyBytes = data(fromHex: trimmedKey) else {
            return DelegationResult(
                success: false,
                error: "Enter the agent Ed25519 public key as 64 hex characters."
            )
        }

        let trimmedToken = tokenContract.trimmingCharacters(in: .whitespaces)
        let trimmedAmount = amount.trimmingCharacters(in: .whitespaces)

        // Pre-encode the spending-limit policy on the EXACT string that will be
        // submitted, through the IDENTICAL conversion path `addContextRule` uses
        // (`buildInstallParamsScVal`). This is the fail-closed contract: the
        // delegation must NEVER reach the chain with the agent's Ed25519 signer +
        // token scope but the spend cap silently dropped. Every encoding failure
        // is a hard validation error here, before any passkey ceremony — a comma
        // decimal the strict amount grammar rejects, a fractional precision the
        // token scale cannot represent, or a cap outside the i128 range enforced
        // by the policy contract. Because the encoding is deterministic, a spec
        // that encodes here also encodes inside `addContextRule`, so the policy
        // can never be the one that `buildPoliciesMap` omits.
        let spendingLimitSpec: PolicyInstallSpec = .spendingLimit(
            amount: trimmedAmount,
            decimals: tokenDecimals,
            periodLedgers: periodLedgers
        )
        do {
            _ = try contextRuleFlow.buildInstallParamsScVal(spec: spendingLimitSpec)
        } catch {
            let message = "Enter a spending limit greater than zero, using a dot for decimals, with at most " +
                "\(tokenDecimals) decimal places and within the supported range."
            activityLog.error(message)
            return DelegationResult(success: false, error: message)
        }

        // Build the rule components. `ExternalSigner.ed25519` validates the
        // 32-byte key length and stamps the configured verifier address; the
        // call-contract context scopes the rule to the token contract.
        let agentSigner: any OZSmartAccountSigner
        do {
            agentSigner = try ExternalSigner.ed25519(
                verifierAddress: ed25519VerifierAddress,
                publicKey: agentKeyBytes
            )
        } catch {
            let message = ActivityLogState.redact(actionableMessage(for: error))
            activityLog.error(message)
            return DelegationResult(success: false, error: message)
        }
        let contextType: OZContextRuleType = .callContract(contractAddress: trimmedToken)

        // Resolve the expiry offset to an absolute ledger from the current one.
        let validUntil: UInt32?
        if validUntilOffsetLedgers > 0 {
            do {
                validUntil = try await contextRuleFlow.resolveAbsoluteLedger(offset: validUntilOffsetLedgers)
            } catch {
                let message = ActivityLogState.redact(actionableMessage(for: error))
                activityLog.error("Failed to resolve the expiry ledger: \(message)")
                return DelegationResult(success: false, error: message)
            }
        } else {
            validUntil = nil
        }

        let policyAddress = spendingLimitPolicyAddress
        guard !policyAddress.isEmpty else {
            let message = "Spending-limit policy is not configured."
            activityLog.error(message)
            return DelegationResult(success: false, error: message)
        }
        let policy = FlowPolicyEntry(address: policyAddress, installSpec: spendingLimitSpec)

        activityLog.info(
            "Delegating to agent \(truncateAddress(trimmedKey)) scoped to \(truncateAddress(trimmedToken))..."
        )

        let result: ContextRuleResult
        do {
            result = try await contextRuleFlow.addContextRule(
                contextType: contextType,
                name: ruleName,
                validUntil: validUntil,
                signers: [agentSigner],
                policies: [policy],
                selectedSigners: [],
                delegatedSecrets: [:]
            )
        } catch {
            if isUserCancellation(error) {
                activityLog.info("Passkey authentication cancelled")
                return DelegationResult(success: false, error: "Passkey authentication cancelled")
            }
            let message = ActivityLogState.redact(actionableMessage(for: error))
            activityLog.error("Delegation failed: \(message)")
            return DelegationResult(success: false, error: message)
        }

        guard result.success else {
            return DelegationResult(success: false, error: result.error ?? "Delegation failed.")
        }

        return DelegationResult(
            success: true,
            hash: result.hash,
            summary: DelegationSummary(
                agentPublicKey: trimmedKey,
                tokenContract: trimmedToken,
                amount: trimmedAmount,
                periodLedgers: periodLedgers,
                validUntilLedger: validUntil,
                ruleName: ruleName,
                spendingLimitPolicyAddress: policyAddress,
                verifierAddress: ed25519VerifierAddress
            )
        )
    }
}
