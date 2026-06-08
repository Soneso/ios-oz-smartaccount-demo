// ContextRuleManagerFullAdapter.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - SmartAccountExecutorType
// ============================================================================

/// Abstraction over the smart-account `execute` entry point used by the edit
/// flow to build policy-specific calls such as `set_threshold`.
///
/// `target`, `targetFn`, and `targetArgs` map directly to the underlying SDK methods.
/// Tests inject a mock implementation that records the supplied arguments.
public protocol SmartAccountExecutorType: Sendable {

    /// Single-signer (passkey fast-path) execution of `target.targetFn(targetArgs)`
    /// through the connected smart account.
    func executeAndSubmit(
        target: String,
        targetFn: String,
        targetArgs: [SCValXDR]
    ) async throws -> OZTransactionResult

    /// Multi-signer execution of `target.targetFn(targetArgs)` through the
    /// connected smart account.
    func multiSignerExecuteAndSubmit(
        target: String,
        targetFn: String,
        targetArgs: [SCValXDR],
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult
}

// ============================================================================
// MARK: - SmartAccountExecutorAdapter
// ============================================================================

/// Production adapter that forwards `SmartAccountExecutorType` calls to the
/// bare `OZTransactionOperations` and `OZMultiSignerManager` instances exposed
/// by an `OZSmartAccountKit`.
public struct SmartAccountExecutorAdapter: SmartAccountExecutorType, Sendable {

    private let transactionOperations: OZTransactionOperations
    private let multiSignerManager: OZMultiSignerManager

    public init(
        transactionOperations: OZTransactionOperations,
        multiSignerManager: OZMultiSignerManager
    ) {
        self.transactionOperations = transactionOperations
        self.multiSignerManager = multiSignerManager
    }

    public func executeAndSubmit(
        target: String,
        targetFn: String,
        targetArgs: [SCValXDR]
    ) async throws -> OZTransactionResult {
        return try await transactionOperations.executeAndSubmit(
            target: target,
            targetFn: targetFn,
            targetArgs: targetArgs
        )
    }

    public func multiSignerExecuteAndSubmit(
        target: String,
        targetFn: String,
        targetArgs: [SCValXDR],
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        return try await multiSignerManager.multiSignerExecuteAndSubmit(
            target: target,
            targetFn: targetFn,
            targetArgs: targetArgs,
            selectedSigners: selectedSigners
        )
    }
}

// ============================================================================
// MARK: - TokenDecimalsResolverType
// ============================================================================

/// Abstraction over the SDK's token `decimals()` read used by the edit flow to
/// scale spending-limit amounts for a non-native guarded token.
///
/// Tests inject a mock that returns a fixed value or throws.
public protocol TokenDecimalsResolverType: Sendable {

    /// Reads the `decimals()` value from a SEP-41 token contract.
    func fetchTokenDecimals(tokenContract: String) async throws -> Int
}

// ============================================================================
// MARK: - TokenDecimalsResolverAdapter
// ============================================================================

/// Production adapter that forwards `TokenDecimalsResolverType` calls to the
/// bare `OZTransactionOperations` exposed by an `OZSmartAccountKit`.
public struct TokenDecimalsResolverAdapter: TokenDecimalsResolverType, Sendable {

    private let transactionOperations: OZTransactionOperations

    public init(_ transactionOperations: OZTransactionOperations) {
        self.transactionOperations = transactionOperations
    }

    public func fetchTokenDecimals(tokenContract: String) async throws -> Int {
        return try await transactionOperations.fetchTokenDecimals(tokenContract: tokenContract)
    }
}

// ============================================================================
// MARK: - ContextRuleManagerFullAdapter
// ============================================================================

/// Production adapter that forwards calls to the bare per-manager subsystems
/// of an ``OZSmartAccountKit`` instance. The adapter holds bare manager
/// references only; composition that requires multiple managers lives in the
/// flow layer (see ``ContextRuleFlow``).
public struct ContextRuleManagerFullAdapter: ContextRuleManagerFullType, Sendable {

    private let contextRuleManager: OZContextRuleManager
    private let signerManager: OZSignerManager
    private let policyManager: OZPolicyManager

    /// Creates an adapter for the supplied bare managers.
    public init(
        contextRuleManager: OZContextRuleManager,
        signerManager: OZSignerManager,
        policyManager: OZPolicyManager
    ) {
        self.contextRuleManager = contextRuleManager
        self.signerManager = signerManager
        self.policyManager = policyManager
    }

    /// Convenience initialiser that pulls the bare managers from a kit.
    public init(kit: OZSmartAccountKit) {
        self.init(
            contextRuleManager: kit.contextRuleManager,
            signerManager: kit.signerManager,
            policyManager: kit.policyManager
        )
    }

    public func listContextRules() async throws -> [OZParsedContextRule] {
        return try await contextRuleManager.listContextRules()
    }

    public func removeContextRule(
        ruleId: UInt32,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        return try await contextRuleManager.removeContextRule(
            id: ruleId,
            selectedSigners: selectedSigners
        )
    }

    public func getContextRulesCount() async throws -> UInt32 {
        return try await contextRuleManager.getContextRulesCount()
    }

    // swiftlint:disable function_parameter_count
    public func addContextRule(
        contextType: OZContextRuleType,
        name: String,
        validUntil: UInt32?,
        signers: [any OZSmartAccountSigner],
        policies: [String: SCValXDR],
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        return try await contextRuleManager.addContextRule(
            contextType: contextType,
            name: name,
            validUntil: validUntil,
            signers: signers,
            policies: policies,
            selectedSigners: selectedSigners
        )
    }
    // swiftlint:enable function_parameter_count

    // -------------------------------------------------------------------------
    // MARK: - Edit operations
    // -------------------------------------------------------------------------

    public func updateContextRuleName(
        ruleId: UInt32,
        newName: String,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        return try await contextRuleManager.updateName(
            id: ruleId,
            name: newName,
            selectedSigners: selectedSigners
        )
    }

    public func updateContextRuleValidUntil(
        ruleId: UInt32,
        newValidUntil: UInt32?,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        return try await contextRuleManager.updateValidUntil(
            id: ruleId,
            validUntil: newValidUntil,
            selectedSigners: selectedSigners
        )
    }

    public func addDelegatedSignerToRule(
        ruleId: UInt32,
        address: String,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        return try await signerManager.addDelegated(
            contextRuleId: ruleId,
            address: address,
            selectedSigners: selectedSigners
        )
    }

    public func addEd25519SignerToRule(
        ruleId: UInt32,
        verifierAddress: String,
        publicKey: Data,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        return try await signerManager.addEd25519(
            contextRuleId: ruleId,
            verifierAddress: verifierAddress,
            publicKey: publicKey,
            selectedSigners: selectedSigners
        )
    }

    public func addPasskeySignerToRule(
        ruleId: UInt32,
        publicKey: Data,
        credentialId: Data,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        return try await signerManager.addPasskey(
            contextRuleId: ruleId,
            publicKey: publicKey,
            credentialId: credentialId,
            selectedSigners: selectedSigners
        )
    }

    public func removeSignerFromRule(
        ruleId: UInt32,
        signerId: UInt32,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        return try await signerManager.removeSigner(
            contextRuleId: ruleId,
            signerId: signerId,
            selectedSigners: selectedSigners
        )
    }

    public func addSimpleThresholdToRule(
        ruleId: UInt32,
        policyAddress: String,
        threshold: UInt32,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        return try await policyManager.addSimpleThreshold(
            contextRuleId: ruleId,
            policyAddress: policyAddress,
            threshold: threshold,
            selectedSigners: selectedSigners
        )
    }

    public func addWeightedThresholdToRule(
        ruleId: UInt32,
        policyAddress: String,
        entries: [PolicyWeightedEntry],
        threshold: UInt32,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        let signerWeights = entries.map {
            OZSignerWeightEntry(signer: $0.signer, weight: $0.weight)
        }
        return try await policyManager.addWeightedThreshold(
            contextRuleId: ruleId,
            policyAddress: policyAddress,
            signerWeights: signerWeights,
            threshold: threshold,
            selectedSigners: selectedSigners
        )
    }

    public func addSpendingLimitToRule(
        ruleId: UInt32,
        policyAddress: String,
        amount: String,
        decimals: Int,
        periodLedgers: UInt32,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        return try await policyManager.addSpendingLimit(
            contextRuleId: ruleId,
            policyAddress: policyAddress,
            spendingLimit: amount,
            periodLedgers: periodLedgers,
            decimals: decimals,
            selectedSigners: selectedSigners
        )
    }

    public func removePolicyFromRule(
        ruleId: UInt32,
        policyId: UInt32,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        return try await policyManager.removePolicy(
            contextRuleId: ruleId,
            policyId: policyId,
            selectedSigners: selectedSigners
        )
    }

    public func getContextRuleRaw(ruleId: UInt32) async throws -> SCValXDR {
        return try await contextRuleManager.getContextRule(id: ruleId)
    }
}
