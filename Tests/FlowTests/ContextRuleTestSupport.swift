// ContextRuleTestSupport.swift
// SmartAccountDemoTests
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
#if canImport(UIKit)
@testable import SmartAccountDemoLib
#else
@testable import SmartAccountDemoMacLib
#endif
import stellarsdk

// ============================================================================
// MARK: - MockContextRuleManagerFull
// ============================================================================

/// Configurable mock for `ContextRuleManagerFullType`.
///
/// Controls return values via `listResult`, `listError`, `removeResult`, and
/// `removeError`. Records call parameters for assertions.
final class MockContextRuleManagerFull: ContextRuleManagerFullType, @unchecked Sendable {

    // List
    var listResult: [OZParsedContextRule] = []
    var listError: Error?
    private(set) var listCallCount: Int = 0

    // Remove
    var removeResult: OZTransactionResult?
    var removeError: Error?
    private(set) var removeCallCount: Int = 0
    private(set) var lastRemovedRuleId: UInt32?
    private(set) var lastRemoveSelectedSigners: [OZSelectedSigner] = []

    // Count
    var countResult: UInt32 = 0
    var countError: Error?

    // Add
    var addResult: OZTransactionResult?
    var addError: Error?
    private(set) var addCallCount: Int = 0
    private(set) var lastAddContextType: OZContextRuleType?
    private(set) var lastAddName: String?
    private(set) var lastAddValidUntil: UInt32?
    private(set) var lastAddSigners: [any OZSmartAccountSigner] = []
    private(set) var lastAddPolicies: [String: SCValXDR] = [:]
    private(set) var lastAddSelectedSigners: [OZSelectedSigner] = []

    func listContextRules() async throws -> [OZParsedContextRule] {
        listCallCount += 1
        if let error = listError { throw error }
        return listResult
    }

    func removeContextRule(
        ruleId: UInt32,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        removeCallCount += 1
        lastRemovedRuleId = ruleId
        lastRemoveSelectedSigners = selectedSigners
        if let error = removeError { throw error }
        guard let result = removeResult else {
            preconditionFailure("MockContextRuleManagerFull: neither removeResult nor removeError configured")
        }
        return result
    }

    func getContextRulesCount() async throws -> UInt32 {
        if let error = countError { throw error }
        return countResult
    }

    // swiftlint:disable function_parameter_count
    func addContextRule(
        contextType: OZContextRuleType,
        name: String,
        validUntil: UInt32?,
        signers: [any OZSmartAccountSigner],
        policies: [String: SCValXDR],
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        addCallCount += 1
        lastAddContextType = contextType
        lastAddName = name
        lastAddValidUntil = validUntil
        lastAddSigners = signers
        lastAddPolicies = policies
        lastAddSelectedSigners = selectedSigners
        if let error = addError { throw error }
        guard let result = addResult else {
            preconditionFailure("MockContextRuleManagerFull: addResult not configured")
        }
        return result
    }
    // swiftlint:enable function_parameter_count

    // -------------------------------------------------------------------------
    // MARK: - Edit-mode per-operation seams
    // -------------------------------------------------------------------------

    /// Sequential per-call recorder used by the edit flow tests to assert the
    /// order in which operations were dispatched.
    enum EditCall: Equatable {
        case updateName(ruleId: UInt32, newName: String)
        case updateValidUntil(ruleId: UInt32, newValidUntil: UInt32?)
        case addDelegated(ruleId: UInt32, address: String)
        case addEd25519(ruleId: UInt32, verifier: String, pubKey: Data)
        case addPasskey(ruleId: UInt32, pubKey: Data, credentialId: Data)
        case removeSigner(ruleId: UInt32, signerId: UInt32)
        case addPolicy(ruleId: UInt32, address: String)
        case removePolicy(ruleId: UInt32, policyId: UInt32)
        case setThreshold(ruleId: UInt32, address: String, newThreshold: UInt32)
        case getContextRuleRaw(ruleId: UInt32)
    }

    /// Per-method canned outcomes. Test sets one of these to control a step.
    /// When `nil`, the mock returns a generic success result.
    var updateNameResult: OZTransactionResult?
    var updateNameError: Error?
    var updateValidUntilResult: OZTransactionResult?
    var updateValidUntilError: Error?
    var addDelegatedResult: OZTransactionResult?
    var addDelegatedError: Error?
    var addEd25519Result: OZTransactionResult?
    var addEd25519Error: Error?
    var addPasskeyResult: OZTransactionResult?
    var addPasskeyError: Error?
    var removeSignerResult: OZTransactionResult?
    var removeSignerError: Error?
    var addPolicyResult: OZTransactionResult?
    var addPolicyError: Error?
    var removePolicyResult: OZTransactionResult?
    var removePolicyError: Error?
    var contextRuleRawResult: SCValXDR?
    var contextRuleRawError: Error?

    /// Recorded call ledger (in execution order). Tests assert against this.
    private(set) var editCalls: [EditCall] = []

    private static func defaultEditSuccess(_ name: String) -> OZTransactionResult {
        OZTransactionResult(success: true, hash: "edit-\(name)-hash", error: nil)
    }

    func updateContextRuleName(
        ruleId: UInt32,
        newName: String,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        editCalls.append(.updateName(ruleId: ruleId, newName: newName))
        if let error = updateNameError { throw error }
        return updateNameResult ?? Self.defaultEditSuccess("name")
    }

    func updateContextRuleValidUntil(
        ruleId: UInt32,
        newValidUntil: UInt32?,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        editCalls.append(.updateValidUntil(ruleId: ruleId, newValidUntil: newValidUntil))
        if let error = updateValidUntilError { throw error }
        return updateValidUntilResult ?? Self.defaultEditSuccess("validUntil")
    }

    func addDelegatedSignerToRule(
        ruleId: UInt32,
        address: String,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        editCalls.append(.addDelegated(ruleId: ruleId, address: address))
        if let error = addDelegatedError { throw error }
        return addDelegatedResult ?? Self.defaultEditSuccess("addDelegated")
    }

    func addEd25519SignerToRule(
        ruleId: UInt32,
        verifierAddress: String,
        publicKey: Data,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        editCalls.append(
            .addEd25519(ruleId: ruleId, verifier: verifierAddress, pubKey: publicKey)
        )
        if let error = addEd25519Error { throw error }
        return addEd25519Result ?? Self.defaultEditSuccess("addEd25519")
    }

    func addPasskeySignerToRule(
        ruleId: UInt32,
        publicKey: Data,
        credentialId: Data,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        editCalls.append(
            .addPasskey(ruleId: ruleId, pubKey: publicKey, credentialId: credentialId)
        )
        if let error = addPasskeyError { throw error }
        return addPasskeyResult ?? Self.defaultEditSuccess("addPasskey")
    }

    func removeSignerFromRule(
        ruleId: UInt32,
        signerId: UInt32,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        editCalls.append(.removeSigner(ruleId: ruleId, signerId: signerId))
        if let error = removeSignerError { throw error }
        return removeSignerResult ?? Self.defaultEditSuccess("removeSigner")
    }

    func addPolicyToRule(
        ruleId: UInt32,
        policyAddress: String,
        installParams: SCValXDR,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        editCalls.append(.addPolicy(ruleId: ruleId, address: policyAddress))
        if let error = addPolicyError { throw error }
        return addPolicyResult ?? Self.defaultEditSuccess("addPolicy")
    }

    func removePolicyFromRule(
        ruleId: UInt32,
        policyId: UInt32,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        editCalls.append(.removePolicy(ruleId: ruleId, policyId: policyId))
        if let error = removePolicyError { throw error }
        return removePolicyResult ?? Self.defaultEditSuccess("removePolicy")
    }

    func getContextRuleRaw(ruleId: UInt32) async throws -> SCValXDR {
        editCalls.append(.getContextRuleRaw(ruleId: ruleId))
        if let error = contextRuleRawError { throw error }
        return contextRuleRawResult ?? .void
    }
}

// ============================================================================
// MARK: - ContextRuleFixtures
// ============================================================================

/// Shared fixture builders for `ContextRuleFlow` tests.
@MainActor
enum ContextRuleFixtures {

    // Canonical test values. Stellar contract addresses (C-strkey) use the
    // base32 alphabet `A-Z` + `2-7` only — digits `0`, `1`, `8`, `9` are not
    // valid, so synthesised fixtures must avoid them. `contractId` here is a
    // real-shaped C-address used by tests that exercise the SDK's
    // `SCAddressXDR(contractId:)` constructor (notably the threshold-only
    // edit path).
    static let contractId = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
    static let credentialId = "dGVzdC1jcmVkZW50aWFsLWlkLWZpeHR1cmU"
    static let txHash = "deadbeef01020304deadbeef01020304deadbeef01020304deadbeef01020304"
    static let verifier = "CAZJ3UVRY3R3S5C5BH32GMYBRSN23N75ZEEXEOLXOUUAHDFIMVP4AXUC"
    static let delegatedAddress = "GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5"

    // MARK: - OZParsedContextRule builders

    /// Builds a default-type rule with one passkey signer and one delegated signer.
    static func defaultRule(
        id: UInt32 = 1,
        name: String = "default",
        validUntil: UInt32? = nil
    ) -> OZParsedContextRule {
        OZParsedContextRule(
            id: id,
            contextType: .defaultRule,
            name: name,
            signers: [makePasskeySigner(), makeDelegatedSigner()],
            signerIds: [0, 1],
            policies: [],
            policyIds: [],
            validUntil: validUntil
        )
    }

    /// Builds a callContract-type rule with one passkey signer and one policy address.
    static func callContractRule(
        id: UInt32 = 2,
        name: String = "token-rule",
        contractAddress: String = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
    ) -> OZParsedContextRule {
        OZParsedContextRule(
            id: id,
            contextType: .callContract(contractAddress: contractAddress),
            name: name,
            signers: [makePasskeySigner()],
            signerIds: [0],
            policies: [contractAddress],
            policyIds: [0],
            validUntil: nil
        )
    }

    /// Builds a rule with no signers and no policies.
    static func emptyRule(id: UInt32 = 3, name: String = "empty") -> OZParsedContextRule {
        OZParsedContextRule(
            id: id,
            contextType: .defaultRule,
            name: name,
            signers: [],
            signerIds: [],
            policies: [],
            policyIds: [],
            validUntil: nil
        )
    }

    /// Builds a rule with an empty name (exercises the "Unnamed Rule" fallback).
    static func unnamedRule(id: UInt32 = 4) -> OZParsedContextRule {
        OZParsedContextRule(
            id: id,
            contextType: .defaultRule,
            name: "",
            signers: [makePasskeySigner()],
            signerIds: [0],
            policies: [],
            policyIds: [],
            validUntil: nil
        )
    }

    /// Builds an edge-case rule whose parsed shape is structurally unusual:
    /// `.createContract` context with a 32-byte hash filled with `0xFF` (a
    /// shape the production UI rarely renders), an empty name, no signers,
    /// and no policies. Used by the parser-fallback test to verify the flow
    /// preserves and returns the unparsed shape without throwing.
    static func fallbackRule(id: UInt32 = 99) -> OZParsedContextRule {
        OZParsedContextRule(
            id: id,
            contextType: .createContract(wasmHash: Data(repeating: 0xFF, count: 32)),
            name: "",
            signers: [],
            signerIds: [],
            policies: [],
            policyIds: [],
            validUntil: nil
        )
    }

    // MARK: - Signer builders

    static func makePasskeySigner(credId: String = credentialId) -> OZExternalSigner {
        let credIdBytes: Data
        if let decoded = try? Data(base64URLEncoded: credId) {
            credIdBytes = decoded
        } else {
            credIdBytes = Data(credId.utf8)
        }
        var keyData = Data(count: 65)
        keyData[0] = 0x04
        keyData.append(credIdBytes)
        // swiftlint:disable:next force_try
        return try! OZExternalSigner(verifierAddress: verifier, keyData: keyData)
    }

    static func makeDelegatedSigner(
        address: String = delegatedAddress
    ) -> OZDelegatedSigner {
        // swiftlint:disable:next force_try
        return try! OZDelegatedSigner(address: address)
    }

    // MARK: - TransferSignerInfo builders

    static func passkeySignerInfo(
        credId: String = credentialId,
        canSign: Bool = true
    ) -> TransferSignerInfo {
        TransferSignerInfo(signer: makePasskeySigner(credId: credId), canSign: canSign)
    }

    static func delegatedSignerInfo(
        address: String = delegatedAddress,
        canSign: Bool = false
    ) -> TransferSignerInfo {
        TransferSignerInfo(signer: makeDelegatedSigner(address: address), canSign: canSign)
    }

    // MARK: - OZTransactionResult

    static func successResult(hash: String = txHash) -> OZTransactionResult {
        OZTransactionResult(success: true, hash: hash, error: nil)
    }

    static func failedResult(error: String = "Insufficient fee") -> OZTransactionResult {
        OZTransactionResult(success: false, hash: nil, error: error)
    }

    // MARK: - DemoState

    static func connectedState(
        contractId: String = Self.contractId,
        credentialId: String = Self.credentialId
    ) -> DemoState {
        let state = DemoState()
        state.setConnected(contractId: contractId, credentialId: credentialId, isDeployed: true)
        return state
    }

    static func disconnectedState() -> DemoState {
        DemoState()
    }

    // MARK: - Flow builder

    static func makeFlow(
        manager: MockContextRuleManagerFull = MockContextRuleManagerFull(),
        state: DemoState? = nil,
        log: ActivityLogState? = nil
    ) -> MadeContextRuleFlow {
        let st = state ?? connectedState()
        let lg = log ?? ActivityLogState()
        let seam = DemoExternalSignersTestSupport.install(into: st)
        let flow = ContextRuleFlow(
            demoState: st,
            activityLog: lg,
            contextRuleManager: manager
        )
        return MadeContextRuleFlow(
            flow: flow,
            state: st,
            log: lg,
            manager: manager,
            signers: seam.manager,
            adapter: seam.adapter
        )
    }
}

// ============================================================================
// MARK: - MadeContextRuleFlow
// ============================================================================

/// Groups objects produced by `ContextRuleFixtures.makeFlow(...)`.
@MainActor
struct MadeContextRuleFlow {
    let flow: ContextRuleFlow
    let state: DemoState
    let log: ActivityLogState
    let manager: MockContextRuleManagerFull
    /// Real external signer manager injected into `state`.
    let signers: OZExternalSignerManager
    /// Real Ed25519 adapter wired into the manager and `state`.
    let adapter: DemoEd25519Adapter
}

// ============================================================================
// MARK: - MockContextRuleFlowError
// ============================================================================

struct MockContextRuleNetworkError: Error, LocalizedError, Sendable {
    let detail: String
    var errorDescription: String? { detail }
}

// ============================================================================
// MARK: - UnsupportedTestSigner
// ============================================================================

/// A third-party `OZSmartAccountSigner` implementation used by tests to verify
/// that `ContextRuleFlow.removeContextRule` rejects signer kinds outside the
/// supported set (`OZExternalSigner` with credential ID, `OZDelegatedSigner`).
struct UnsupportedTestSigner: OZSmartAccountSigner, Sendable {

    let uniqueKey: String

    init(uniqueKey: String = "unsupported:test") {
        self.uniqueKey = uniqueKey
    }

    func toScVal() throws -> SCValXDR {
        return .void
    }
}
