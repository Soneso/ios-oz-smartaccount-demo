// DelegateToAgentFlowTests.swift
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
// MARK: - Helpers
// ============================================================================

private enum DelegateFixtures {

    static let agentKeyHex = String(repeating: "ab", count: 32)
    static let tokenContract = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"

    @MainActor
    static func make(
        manager: MockContextRuleManagerFull = MockContextRuleManagerFull()
    ) -> (flow: DelegateToAgentFlow, manager: MockContextRuleManagerFull) {
        let made = ContextRuleFixtures.makeFlow(manager: manager)
        let flow = DelegateToAgentFlow(contextRuleFlow: made.flow, activityLog: made.log)
        return (flow, made.manager)
    }
}

// ============================================================================
// MARK: - Validation
// ============================================================================

@Suite("DelegateToAgentFlow: Validation")
struct DelegateToAgentFlowValidationTests {

    @Test("agent key validation accepts 64 hex and rejects bad length / non-hex")
    @MainActor
    func validateAgentPublicKey() {
        let (flow, _) = DelegateFixtures.make()
        #expect(flow.validateAgentPublicKey("") == nil)
        #expect(flow.validateAgentPublicKey(DelegateFixtures.agentKeyHex) == nil)
        #expect(flow.validateAgentPublicKey("abcd") != nil)
        #expect(flow.validateAgentPublicKey(String(repeating: "zz", count: 32)) != nil)
    }

    @Test("amount validation rejects scientific notation, commas, non-numbers, and non-positive values")
    func validateAmount() {
        #expect(DelegateToAgentFlow.validateAmount("") == nil)
        #expect(DelegateToAgentFlow.validateAmount("100.0") == nil)
        #expect(DelegateToAgentFlow.validateAmount("1e3") != nil)
        #expect(DelegateToAgentFlow.validateAmount("abc") != nil)
        #expect(DelegateToAgentFlow.validateAmount("0") != nil)
        #expect(DelegateToAgentFlow.validateAmount("-5") != nil)
        // A comma is rejected, never normalised to a dot: the on-chain encoding
        // path accepts only a dot, so a normalised comma would pass UI validation
        // and abort at encoding time with a generic error instead of this
        // immediate field error.
        #expect(DelegateToAgentFlow.validateAmount("1,5") != nil)
    }
}

// ============================================================================
// MARK: - Delegate composition
// ============================================================================

@Suite("DelegateToAgentFlow: Delegate")
struct DelegateToAgentFlowDelegateTests {

    @Test("delegate composes a CallContract rule with the Ed25519 signer and spending-limit policy")
    @MainActor
    func delegate_composesRule() async {
        let manager = MockContextRuleManagerFull()
        manager.addResult = OZTransactionResult(success: true, hash: InboxFixtures.txHash, error: nil)
        let (flow, _) = DelegateFixtures.make(manager: manager)

        let result = await flow.delegateToAgent(
            agentPublicKey: DelegateFixtures.agentKeyHex,
            tokenContract: DelegateFixtures.tokenContract,
            amount: "100.0",
            periodLedgers: 17_280,
            validUntilOffsetLedgers: 0,
            tokenDecimals: 7
        )

        #expect(result.success)
        #expect(result.hash == InboxFixtures.txHash)
        #expect(manager.addCallCount == 1)
        #expect(manager.lastAddContextType == .callContract(contractAddress: DelegateFixtures.tokenContract))
        // One Ed25519 external signer + one spending-limit policy.
        #expect(manager.lastAddSigners.count == 1)
        #expect(manager.lastAddPolicies.count == 1)
        #expect(result.summary?.agentPublicKey == DelegateFixtures.agentKeyHex)
        // No ledger source wired in the test flow, so an offset yields no expiry.
        #expect(result.summary?.validUntilLedger == nil)
    }

    @Test("an invalid spending amount fails before any submission")
    @MainActor
    func delegate_invalidAmount_failsBeforeSubmit() async {
        let manager = MockContextRuleManagerFull()
        let (flow, _) = DelegateFixtures.make(manager: manager)

        let result = await flow.delegateToAgent(
            agentPublicKey: DelegateFixtures.agentKeyHex,
            tokenContract: DelegateFixtures.tokenContract,
            amount: "0",
            periodLedgers: 17_280,
            validUntilOffsetLedgers: 0,
            tokenDecimals: 7
        )

        #expect(!result.success)
        #expect(manager.addCallCount == 0)
    }

    @Test("a comma-decimal cap fails closed before submit: the spend cap is never dropped")
    @MainActor
    func delegate_commaCap_failsBeforeSubmit() async {
        let manager = MockContextRuleManagerFull()
        let (flow, _) = DelegateFixtures.make(manager: manager)

        // A comma decimal is what the strict on-chain amount grammar rejects.
        // The delegation must abort here rather than submit the agent's Ed25519
        // signer + token scope with the spending-limit policy silently omitted.
        let result = await flow.delegateToAgent(
            agentPublicKey: DelegateFixtures.agentKeyHex,
            tokenContract: DelegateFixtures.tokenContract,
            amount: "1,5",
            periodLedgers: 17_280,
            validUntilOffsetLedgers: 0,
            tokenDecimals: 7
        )

        #expect(!result.success)
        #expect(manager.addCallCount == 0)
    }

    @Test("an i128-overflow cap fails closed before submit")
    @MainActor
    func delegate_overflowCap_failsBeforeSubmit() async {
        let manager = MockContextRuleManagerFull()
        let (flow, _) = DelegateFixtures.make(manager: manager)

        // A cap that overflows i128 after scaling passes the amount grammar but
        // is rejected by the policy contract's i128 range check. That rejection
        // must abort the delegation, not drop the policy and submit uncapped.
        let result = await flow.delegateToAgent(
            agentPublicKey: DelegateFixtures.agentKeyHex,
            tokenContract: DelegateFixtures.tokenContract,
            amount: String(repeating: "9", count: 50),
            periodLedgers: 17_280,
            validUntilOffsetLedgers: 0,
            tokenDecimals: 7
        )

        #expect(!result.success)
        #expect(manager.addCallCount == 0)
    }

    @Test("a malformed agent key fails before any submission")
    @MainActor
    func delegate_malformedKey_failsBeforeSubmit() async {
        let manager = MockContextRuleManagerFull()
        let (flow, _) = DelegateFixtures.make(manager: manager)

        let result = await flow.delegateToAgent(
            agentPublicKey: "not-hex",
            tokenContract: DelegateFixtures.tokenContract,
            amount: "100.0",
            periodLedgers: 17_280,
            validUntilOffsetLedgers: 0,
            tokenDecimals: 7
        )

        #expect(!result.success)
        #expect(manager.addCallCount == 0)
    }
}
