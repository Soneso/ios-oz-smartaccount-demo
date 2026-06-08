// AccountSignersFlowTests.swift
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
import Testing

// ============================================================================
// MARK: - Happy path
// ============================================================================

@Suite("AccountSignersFlow: Happy Path")
struct AccountSignersFlowHappyPathTests {

    @Test("Returns one entry per unique signer when only one rule exists")
    @MainActor
    func singleRule_returnsAllUnique() async throws {
        let ctxManager = MockContextRuleManager()
        ctxManager.result = TransferFixtures.contextRuleWithPasskeyAndDelegated()
        let state = ContextRuleFixtures.connectedState()
        let log = ActivityLogState()
        let flow = AccountSignersFlow(
            demoState: state,
            activityLog: log,
            contextRuleManager: ctxManager
        )

        let entries = try await flow.loadAccountSigners()
        #expect(entries.count == 2)
        // Each signer is referenced by exactly one rule.
        #expect(entries.allSatisfy { $0.contextRules.count == 1 })
    }

    @Test("Deduplicates the same signer across multiple rules and merges rule memberships")
    @MainActor
    func multipleRules_dedupesAndMerges() async throws {
        let passkey = ContextRuleFixtures.makePasskeySigner()
        let delegated = ContextRuleFixtures.makeDelegatedSigner()
        let ruleA = AccountSignerFixtures.rule(
            id: 1, name: "rule-a", signers: [passkey, delegated]
        )
        let ruleB = AccountSignerFixtures.rule(
            id: 2,
            name: "rule-b",
            signers: [passkey],
            contextType: .callContract(contractAddress: ContextRuleFixtures.contractId)
        )
        let flow = AccountSignerFixtures.makeFlow(rules: [ruleA, ruleB])
        let entries = try await flow.loadAccountSigners()

        #expect(entries.count == 2)
        let passkeyEntry = entries.first { $0.signer.uniqueKey == passkey.uniqueKey }
        #expect(passkeyEntry?.contextRules.count == 2)
        #expect(passkeyEntry?.contextRules.map(\.id).sorted() == [1, 2])
        let delegatedEntry = entries.first { $0.signer.uniqueKey == delegated.uniqueKey }
        #expect(delegatedEntry?.contextRules.count == 1)
        #expect(delegatedEntry?.contextRules.first?.id == 1)
    }

    @Test("Preserves insertion order of first signer appearance across rules")
    @MainActor
    func preservesInsertionOrder() async throws {
        let signerA = ContextRuleFixtures.makePasskeySigner(credId: "credA")
        let signerB = ContextRuleFixtures.makeDelegatedSigner(
            address: "GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5"
        )
        let signerC = ContextRuleFixtures.makeDelegatedSigner(
            address: "GAIH3ULLFQ4DGSECF2AR555KZ4KNDGEKN4AFI4SU2M7B43MGK3QJZNSR"
        )
        let ruleA = AccountSignerFixtures.rule(id: 1, name: "a", signers: [signerA, signerB])
        let ruleB = AccountSignerFixtures.rule(id: 2, name: "b", signers: [signerC])
        let flow = AccountSignerFixtures.makeFlow(rules: [ruleA, ruleB])

        let entries = try await flow.loadAccountSigners()
        #expect(entries.count == 3)
        #expect(entries[0].signer.uniqueKey == signerA.uniqueKey)
        #expect(entries[1].signer.uniqueKey == signerB.uniqueKey)
        #expect(entries[2].signer.uniqueKey == signerC.uniqueKey)
    }

    @Test("Logs success with N signers / M rules count")
    @MainActor
    func logsSuccess_withCorrectCounts() async throws {
        let ctxManager = MockContextRuleManager()
        ctxManager.result = TransferFixtures.contextRuleWithPasskeyAndDelegated()
        let log = ActivityLogState()
        let state = ContextRuleFixtures.connectedState()
        let flow = AccountSignersFlow(
            demoState: state,
            activityLog: log,
            contextRuleManager: ctxManager
        )

        _ = try await flow.loadAccountSigners()
        let messages = log.entries.map(\.message)
        #expect(messages.contains { $0.hasPrefix("Loaded 2 unique signers from 1 context rule.") })
    }

    @Test("Pluralizes singular signer + singular rule correctly")
    @MainActor
    func pluralizesSingular_correctly() async throws {
        let ruleId: UInt32 = 42
        let signer = ContextRuleFixtures.makePasskeySigner()
        let rule = OZParsedContextRule(
            id: ruleId,
            contextType: .defaultRule,
            name: "single",
            signers: [signer],
            signerIds: [0],
            policies: [],
            policyIds: [],
            validUntil: nil
        )
        let ctxManager = MockContextRuleManager()
        ctxManager.result = [rule]
        let log = ActivityLogState()
        let state = ContextRuleFixtures.connectedState()
        let flow = AccountSignersFlow(
            demoState: state,
            activityLog: log,
            contextRuleManager: ctxManager
        )

        _ = try await flow.loadAccountSigners()
        let messages = log.entries.map(\.message)
        #expect(messages.contains { $0.hasPrefix("Loaded 1 unique signer from 1 context rule.") })
    }
}

// ============================================================================
// MARK: - Failure / edge paths
// ============================================================================

@Suite("AccountSignersFlow: Failure / Edge")
struct AccountSignersFlowEdgeTests {

    @Test("Throws SmartAccountWalletException.NotConnected when wallet not connected")
    @MainActor
    func notConnected_throws() async {
        let state = DemoState()
        let flow = AccountSignersFlow(
            demoState: state,
            activityLog: ActivityLogState(),
            contextRuleManager: MockContextRuleManager()
        )
        await #expect(throws: (any Error).self) {
            _ = try await flow.loadAccountSigners()
        }
    }

    @Test("Throws underlying error on fetch failure")
    @MainActor
    func fetchFails_throws() async {
        let ctxManager = MockContextRuleManager()
        ctxManager.error = MockTransferNetworkError(detail: "rpc down")
        let state = ContextRuleFixtures.connectedState()
        let flow = AccountSignersFlow(
            demoState: state,
            activityLog: ActivityLogState(),
            contextRuleManager: ctxManager
        )
        await #expect(throws: (any Error).self) {
            _ = try await flow.loadAccountSigners()
        }
    }

    @Test("Returns empty array when no rules exist")
    @MainActor
    func noRules_returnsEmpty() async throws {
        let ctxManager = MockContextRuleManager()
        ctxManager.result = []
        let state = ContextRuleFixtures.connectedState()
        let flow = AccountSignersFlow(
            demoState: state,
            activityLog: ActivityLogState(),
            contextRuleManager: ctxManager
        )
        let entries = try await flow.loadAccountSigners()
        #expect(entries.isEmpty)
    }

    @Test("Returns empty array when rules exist but contain no signers")
    @MainActor
    func rulesWithoutSigners_returnsEmpty() async throws {
        let emptyRule = OZParsedContextRule(
            id: 1,
            contextType: .defaultRule,
            name: "empty",
            signers: [],
            signerIds: [],
            policies: [],
            policyIds: [],
            validUntil: nil
        )
        let ctxManager = MockContextRuleManager()
        ctxManager.result = [emptyRule]
        let state = ContextRuleFixtures.connectedState()
        let flow = AccountSignersFlow(
            demoState: state,
            activityLog: ActivityLogState(),
            contextRuleManager: ctxManager
        )
        let entries = try await flow.loadAccountSigners()
        #expect(entries.isEmpty)
    }
}

// ============================================================================
// MARK: - SignerEntry value type
// ============================================================================

@Suite("SignerEntry: Value Type")
struct SignerEntryTests {

    @Test("Init exposes signer and contextRules unchanged")
    @MainActor
    func init_exposesFields() {
        let signer = ContextRuleFixtures.makePasskeySigner()
        let rule = ContextRuleFixtures.defaultRule()
        let entry = SignerEntry(signer: signer, contextRules: [rule])
        #expect(entry.signer.uniqueKey == signer.uniqueKey)
        #expect(entry.contextRules.count == 1)
        #expect(entry.contextRules.first?.id == rule.id)
    }
}

// ============================================================================
// MARK: - AccountSignerFixtures
// ============================================================================

/// Shared helpers for the AccountSignersFlow tests so per-test bodies stay
/// within SwiftLint's `function_body_length` cap.
@MainActor
enum AccountSignerFixtures {

    /// Builds a `OZParsedContextRule` with positional signer ids.
    static func rule(
        id: UInt32,
        name: String,
        signers: [any OZSmartAccountSigner],
        contextType: OZContextRuleType = .defaultRule
    ) -> OZParsedContextRule {
        OZParsedContextRule(
            id: id,
            contextType: contextType,
            name: name,
            signers: signers,
            signerIds: Array(0..<UInt32(signers.count)),
            policies: [],
            policyIds: [],
            validUntil: nil
        )
    }

    /// Builds an `AccountSignersFlow` bound to a connected state and a mock
    /// context-rule manager configured to return `rules`.
    static func makeFlow(rules: [OZParsedContextRule]) -> AccountSignersFlow {
        let manager = MockContextRuleManager()
        manager.result = rules
        return AccountSignersFlow(
            demoState: ContextRuleFixtures.connectedState(),
            activityLog: ActivityLogState(),
            contextRuleManager: manager
        )
    }
}
