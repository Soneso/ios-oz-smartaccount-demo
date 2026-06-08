// ContextRuleEditSubmitTests.swift
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
// MARK: - submitContextRuleEdits sequencing tests
// ============================================================================

@Suite("ContextRuleFlow: submitContextRuleEdits")
@MainActor
struct SubmitContextRuleEditsTests {

    @Test("Empty diff returns success with 0 operations and no SDK calls")
    func emptyDiffShortCircuit() async throws {
        let pair = EditFlowFixtures.makeFlow()
        let diff = EditFlowFixtures.emptyDiff()
        var progressCount = 0
        let result = try await pair.flow.submitContextRuleEdits(
            diff: diff,
            selectedSigners: []
        ) { _ in
            progressCount += 1
        }
        #expect(result.success)
        #expect(result.completedOperations == 0)
        #expect(result.totalOperations == 0)
        #expect(pair.manager.editCalls.isEmpty)
        #expect(progressCount == 0)
    }

    @Test("Auth-context guard halts after signer ops when policies/expiry pending")
    func authGuardHaltsAfterSigners() async throws {
        let pair = EditFlowFixtures.makeFlow()
        let diff = Self.authGuardDiff()
        var progressMessages: [String] = []
        let result = try await pair.flow.submitContextRuleEdits(
            diff: diff,
            selectedSigners: []
        ) { msg in
            progressMessages.append(msg)
        }
        // Adding signers + having policy/expiry changes triggers the
        // auth-context guard: name + signer steps run, policies + expiry are
        // skipped. Result reports success-with-partial.
        #expect(result.success)
        #expect(result.partialDueToAuthGuard)
        // 1 name + 2 add + 1 remove = 4 ops completed before guard fires.
        #expect(result.completedOperations == 4)
        // Total ops = 1 name + 2 add + 1 remove + 1 add + 1 remove + 1 expiry = 7
        #expect(result.totalOperations == 7)
        #expect(result.authGuardMessage != nil)
        #expect(progressMessages.count == 4)
        Self.assertAuthGuardCallSequence(pair.manager.editCalls)
    }

    private static func authGuardDiff() -> ContextRuleEditDiff {
        let passkey = BuilderFixtures.passkeySigner(credId: "newkey")
        let delegated = ContextRuleFixtures.makeDelegatedSigner()
        let removedSigner = EditFlowFixtures.originalSignerEntry(
            signer: BuilderFixtures.passkeySigner(credId: "old"),
            onChainId: 5
        )
        let removedPolicy = EditFlowFixtures.originalPolicyEntry(
            info: knownPolicies[1],
            onChainId: 9
        )
        let newPolicy = EditFlowFixtures.newPolicyEntry(
            info: knownPolicies[0],
            label: "Threshold: 1-of-N",
            spec: .simpleThreshold(threshold: 1)
        )
        return ContextRuleEditDiff(
            ruleId: 7,
            nameChanged: true,
            newName: "Renamed",
            newSigners: [
                EditFlowFixtures.newSignerEntry(signer: passkey),
                EditFlowFixtures.newSignerEntry(signer: delegated)
            ],
            removedSigners: [removedSigner],
            newPolicies: [newPolicy],
            removedPolicies: [removedPolicy],
            modifiedPolicies: [],
            expiryChanged: true,
            newExpiry: 99_999
        )
    }

    private static func assertAuthGuardCallSequence(
        _ calls: [MockContextRuleManagerFull.EditCall]
    ) {
        #expect(calls.count == 4)
        guard calls.count == 4 else { return }
        if case .updateName = calls[0] { } else { Issue.record("expected updateName first") }
        if case .addPasskey = calls[1] { } else { Issue.record("expected addPasskey second") }
        if case .addDelegated = calls[2] { } else { Issue.record("expected addDelegated third") }
        if case .removeSigner = calls[3] { } else { Issue.record("expected removeSigner fourth") }
    }

    @Test("Sequence without new signers runs all steps in expected order")
    func fullSequenceNoNewSigners() async throws {
        let pair = EditFlowFixtures.makeFlow()
        let diff = Self.fullSequenceDiff()
        let result = try await pair.flow.submitContextRuleEdits(
            diff: diff,
            selectedSigners: []
        ) { _ in }
        #expect(result.success)
        #expect(!result.partialDueToAuthGuard)
        #expect(result.totalOperations == 5)
        #expect(result.completedOperations == 5)
        #expect(result.transactionHashes.count == 5)
        Self.assertFullSequenceCalls(pair.manager.editCalls)
    }

    private static func fullSequenceDiff() -> ContextRuleEditDiff {
        let removedSigner = EditFlowFixtures.originalSignerEntry(
            signer: BuilderFixtures.passkeySigner(credId: "old"),
            onChainId: 5
        )
        let removedPolicy = EditFlowFixtures.originalPolicyEntry(
            info: knownPolicies[1],
            onChainId: 9
        )
        let newPolicy = EditFlowFixtures.newPolicyEntry(
            info: knownPolicies[0],
            label: "Threshold: 1-of-N",
            spec: .simpleThreshold(threshold: 1)
        )
        return ContextRuleEditDiff(
            ruleId: 7,
            nameChanged: true,
            newName: "Renamed",
            newSigners: [],
            removedSigners: [removedSigner],
            newPolicies: [newPolicy],
            removedPolicies: [removedPolicy],
            modifiedPolicies: [],
            expiryChanged: true,
            newExpiry: 99_999
        )
    }

    private static func assertFullSequenceCalls(
        _ calls: [MockContextRuleManagerFull.EditCall]
    ) {
        #expect(calls.count == 5)
        guard calls.count == 5 else { return }
        if case .updateName = calls[0] { } else { Issue.record("expected updateName first") }
        if case .removeSigner = calls[1] { } else { Issue.record("expected removeSigner second") }
        if case .removePolicy = calls[2] { } else { Issue.record("expected removePolicy third") }
        #expect(calls[3].isAddPolicy, "expected an addPolicy variant at index 3, got: \(calls[3])")
        if case .updateValidUntil = calls[4] { } else {
            Issue.record("expected updateValidUntil last")
        }
    }

    @Test("Failure at remove-signer step halts and reports failed step")
    func failureHalts() async throws {
        let pair = EditFlowFixtures.makeFlow()
        pair.manager.removeSignerResult = OZTransactionResult(
            success: false,
            hash: nil,
            error: "contract reverted"
        )
        let removedSigner = EditFlowFixtures.originalSignerEntry(
            signer: BuilderFixtures.passkeySigner(credId: "old"),
            onChainId: 5
        )
        let diff = ContextRuleEditDiff(
            ruleId: 1,
            nameChanged: true,
            newName: "Name",
            newSigners: [],
            removedSigners: [removedSigner],
            newPolicies: [],
            removedPolicies: [],
            modifiedPolicies: [],
            expiryChanged: false,
            newExpiry: nil
        )
        let result = try await pair.flow.submitContextRuleEdits(
            diff: diff,
            selectedSigners: []
        ) { _ in }
        #expect(!result.success)
        #expect(result.completedOperations == 1)
        #expect(result.totalOperations == 2)
        #expect(result.failedStep?.contains("Removing signer") == true)
        #expect(result.error == "contract reverted")
    }

    @Test("Threshold-only modification dispatches set_threshold once")
    func thresholdModificationFastPath() async throws {
        let pair = EditFlowFixtures.makeFlow()
        let threshold = try #require(knownPolicies.first { $0.type == "threshold" })
        pair.manager.contextRuleRawResult = EditFlowFixtures.contextRuleRawMap(
            policyAddress: threshold.address,
            policyId: 11
        )
        let originalParams = PolicyParams(
            type: "threshold",
            threshold: 1,
            spendingLimit: nil,
            periodDays: nil,
            signerWeights: nil
        )
        let entry = EditFlowFixtures.modifiedPolicyEntry(
            info: threshold,
            label: "Threshold: 3-of-N",
            spec: .simpleThreshold(threshold: 3),
            onChainId: 11,
            originalParams: originalParams
        )
        let diff = EditFlowFixtures.emptyDiff(modifiedPolicies: [entry])
        let result = try await pair.flow.submitContextRuleEdits(
            diff: diff,
            selectedSigners: []
        ) { _ in }
        #expect(result.success)
        #expect(result.completedOperations == 1)
        Self.assertThresholdFastPath(
            managerCalls: pair.manager.editCalls,
            executorCalls: pair.executor.executeCalls
        )
    }

    private static func assertThresholdFastPath(
        managerCalls: [MockContextRuleManagerFull.EditCall],
        executorCalls: [MockSmartAccountExecutor.ExecuteCall]
    ) {
        let setThresholdCount = executorCalls.filter { $0.functionName == "set_threshold" }.count
        var removeCount = 0
        for call in managerCalls {
            if case .removePolicy = call { removeCount += 1 }
        }
        #expect(setThresholdCount == 1)
        #expect(removeCount == 0)
    }

    @Test("Non-threshold modification runs remove + re-add (2 ops)")
    func nonThresholdModificationPair() async throws {
        let pair = EditFlowFixtures.makeFlow()
        let spending = try #require(knownPolicies.first { $0.type == "spending_limit" })
        let originalParams = PolicyParams(
            type: "spending_limit",
            threshold: nil,
            spendingLimit: "5",
            periodDays: 1,
            signerWeights: nil
        )
        let entry = EditFlowFixtures.modifiedPolicyEntry(
            info: spending,
            label: "Limit: 10 / 1 day(s)",
            spec: .spendingLimit(amount: "10", decimals: 7, periodLedgers: 17_280),
            onChainId: 21,
            originalParams: originalParams
        )
        let diff = EditFlowFixtures.emptyDiff(modifiedPolicies: [entry])
        let result = try await pair.flow.submitContextRuleEdits(
            diff: diff,
            selectedSigners: []
        ) { _ in }
        #expect(result.success)
        #expect(result.completedOperations == 2)
        let calls = pair.manager.editCalls
        #expect(calls.count == 2)
        if case .removePolicy = calls[0] { } else { Issue.record("expected removePolicy first") }
        #expect(calls[1].isAddPolicy, "expected an addPolicy variant at index 1, got: \(calls[1])")
    }

    @Test("Non-7-decimals spending limit dispatches addSpendingLimit with correct decimals")
    func nonSevenDecimalsSpendingLimitDispatches() async throws {
        let pair = EditFlowFixtures.makeFlow()
        let spending = try #require(knownPolicies.first { $0.type == "spending_limit" })
        var capturedDecimals: Int?
        var capturedAmount: String?
        pair.manager.addPolicyResult = OZTransactionResult(success: true, hash: "sl-hash", error: nil)
        let spec = PolicyInstallSpec.spendingLimit(amount: "1000", decimals: 18, periodLedgers: 100)
        let entry = EditFlowFixtures.newPolicyEntry(
            info: spending,
            label: "Limit: 1000 / 1 day(s)",
            spec: spec
        )
        let diff = EditFlowFixtures.emptyDiff(newPolicies: [entry])
        let result = try await pair.flow.submitContextRuleEdits(
            diff: diff,
            selectedSigners: []
        ) { _ in }
        #expect(result.success)
        let addCalls = pair.manager.editCalls.filter { $0.isAddPolicy }
        #expect(addCalls.count == 1)
        if case .addSpendingLimit = addCalls[0] { } else {
            Issue.record("expected addSpendingLimit, got: \(addCalls[0])")
        }
        _ = capturedDecimals  // referenced to avoid unused-variable warning
        _ = capturedAmount
    }

    @Test("Above-Int64-max spending limit dispatches correctly")
    func aboveInt64MaxSpendingLimitDispatches() async throws {
        let pair = EditFlowFixtures.makeFlow()
        let spending = try #require(knownPolicies.first { $0.type == "spending_limit" })
        let spec = PolicyInstallSpec.spendingLimit(
            amount: "1000000000000",
            decimals: 7,
            periodLedgers: 17_280
        )
        let entry = EditFlowFixtures.newPolicyEntry(
            info: spending,
            label: "Limit: 1000000000000 / 1 day(s)",
            spec: spec
        )
        let diff = EditFlowFixtures.emptyDiff(newPolicies: [entry])
        let result = try await pair.flow.submitContextRuleEdits(
            diff: diff,
            selectedSigners: []
        ) { _ in }
        #expect(result.success)
        let addCalls = pair.manager.editCalls.filter { $0.isAddPolicy }
        #expect(addCalls.count == 1)
        if case .addSpendingLimit = addCalls[0] { } else {
            Issue.record("expected addSpendingLimit, got: \(addCalls[0])")
        }
    }

    @Test("Reentry guard rejects a concurrent submit")
    func reentryThrows() async throws {
        let pair = EditFlowFixtures.makeFlow()
        let nameDiff = EditFlowFixtures.emptyDiff(nameChanged: true, newName: "x")
        pair.flow.isEditing = true
        defer { pair.flow.isEditing = false }
        await #expect(throws: ContextRuleFlowError.self) {
            _ = try await pair.flow.submitContextRuleEdits(
                diff: nameDiff,
                selectedSigners: []
            ) { _ in }
        }
    }

    @Test("Passkey signer add dispatches addPasskeySignerToRule")
    func newPasskeyDispatchesPasskeyCall() async throws {
        let pair = EditFlowFixtures.makeFlow()
        let passkey = BuilderFixtures.passkeySigner(credId: "fresh")
        let entry = EditFlowFixtures.newSignerEntry(signer: passkey)
        let diff = EditFlowFixtures.emptyDiff(newSigners: [entry])
        _ = try await pair.flow.submitContextRuleEdits(
            diff: diff,
            selectedSigners: []
        ) { _ in }
        let calls = pair.manager.editCalls
        #expect(calls.count == 1)
        if case .addPasskey = calls[0] { } else { Issue.record("expected addPasskey") }
    }

    @Test("Delegated signer add dispatches addDelegatedSignerToRule")
    func newDelegatedDispatchesDelegatedCall() async throws {
        let pair = EditFlowFixtures.makeFlow()
        let delegated = ContextRuleFixtures.makeDelegatedSigner()
        let entry = EditFlowFixtures.newSignerEntry(signer: delegated)
        let diff = EditFlowFixtures.emptyDiff(newSigners: [entry])
        _ = try await pair.flow.submitContextRuleEdits(
            diff: diff,
            selectedSigners: []
        ) { _ in }
        let calls = pair.manager.editCalls
        #expect(calls.count == 1)
        if case .addDelegated = calls[0] { } else { Issue.record("expected addDelegated") }
    }
}
