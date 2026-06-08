// ContextRuleEditFlowTests.swift
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
// MARK: - ContextRuleEditDiff tests
// ============================================================================

@Suite("ContextRuleEditDiff: shape")
@MainActor
struct ContextRuleEditDiffShapeTests {

    @Test("Empty diff has isEmpty == true and totalOperations == 0")
    func emptyDiff() {
        let diff = EditFlowFixtures.emptyDiff()
        #expect(diff.isEmpty)
        #expect(diff.totalOperations == 0)
    }

    @Test("Name change contributes 1 operation")
    func nameChangeOps() {
        let diff = EditFlowFixtures.emptyDiff(nameChanged: true, newName: "Renamed")
        #expect(!diff.isEmpty)
        #expect(diff.totalOperations == 1)
    }

    @Test("Threshold-only modification counts as 1 op; other types count as 2")
    func modifiedPolicyOps() throws {
        let threshold = try #require(knownPolicies.first { $0.type == "threshold" })
        let spending = try #require(knownPolicies.first { $0.type == "spending_limit" })
        let weighted = try #require(knownPolicies.first { $0.type == "weighted_threshold" })
        let thresholdEntry = EditFlowFixtures.policyEntry(info: threshold)
        let spendingEntry = EditFlowFixtures.policyEntry(info: spending)
        let weightedEntry = EditFlowFixtures.policyEntry(info: weighted)
        let diff = EditFlowFixtures.emptyDiff(
            modifiedPolicies: [thresholdEntry, spendingEntry, weightedEntry]
        )
        // 1 (threshold) + 2 (spending) + 2 (weighted) = 5 ops
        #expect(diff.totalOperations == 5)
    }

    @Test("withExpiry replaces newExpiry and preserves other fields")
    func withExpiryReplaces() {
        let original = EditFlowFixtures.emptyDiff(
            ruleId: 5,
            nameChanged: true,
            newName: "abc",
            expiryChanged: true,
            newExpiry: 720
        )
        let updated = original.withExpiry(1_000_720)
        #expect(updated.newExpiry == 1_000_720)
        #expect(updated.nameChanged == true)
        #expect(updated.newName == "abc")
        #expect(updated.expiryChanged == true)
        #expect(updated.ruleId == 5)
    }
}

// ============================================================================
// MARK: - loadParsedContextRule tests
// ============================================================================

@Suite("ContextRuleFlow: loadParsedContextRule")
struct LoadParsedContextRuleTests {

    @Test("Returns the matching rule")
    @MainActor
    func loadRule_happy() async throws {
        let made = BuilderFixtures.makeFlow()
        let target = ContextRuleFixtures.defaultRule(id: 7, name: "target")
        made.manager.listResult = [
            ContextRuleFixtures.defaultRule(id: 1, name: "other"),
            target
        ]
        let result = try await made.flow.loadParsedContextRule(ruleId: 7)
        #expect(result.id == 7)
        #expect(result.name == "target")
    }

    @Test("Throws missingOnChainIdentifier when rule is absent")
    @MainActor
    func loadRule_missing() async throws {
        let made = BuilderFixtures.makeFlow()
        made.manager.listResult = []
        await #expect(throws: ContextRuleFlowError.self) {
            _ = try await made.flow.loadParsedContextRule(ruleId: 42)
        }
    }

    @Test("Throws NotConnected when wallet is not connected")
    @MainActor
    func loadRule_notConnected() async throws {
        let state = ContextRuleFixtures.disconnectedState()
        let made = BuilderFixtures.makeFlow(state: state)
        await #expect(throws: SmartAccountWalletException.NotConnected.self) {
            _ = try await made.flow.loadParsedContextRule(ruleId: 1)
        }
    }

    @Test("Propagates the underlying SDK error when listing fails")
    @MainActor
    func loadRule_propagatesUnderlyingError() async throws {
        let made = BuilderFixtures.makeFlow()
        let detail = "rpc: connection refused"
        made.manager.listError = MockContextRuleNetworkError(detail: detail)
        let log = made.log
        do {
            _ = try await made.flow.loadParsedContextRule(ruleId: 7)
            Issue.record("loadParsedContextRule should have thrown")
        } catch let error as MockContextRuleNetworkError {
            #expect(error.detail == detail)
        } catch {
            Issue.record("Unexpected error type: \(type(of: error))")
        }
        // Ensure the failed call did not leave any partial entries in the log.
        let entries = log.entries
        let infoEntries = entries.filter { $0.message.contains(detail) }
        #expect(infoEntries.isEmpty, "raw error must not appear verbatim in activity log")
    }
}

// ============================================================================
// MARK: - EditPolicyEntry.with semantics
// ============================================================================

@Suite("EditPolicyEntry: with revert")
@MainActor
struct EditPolicyEntryRevertTests {

    @Test("Reverting modified entry with installSpec: .some(nil) clears modified flag")
    func revertViaNilSpecClearsModified() throws {
        let info = try #require(knownPolicies.first { $0.type == "threshold" })
        let originalParams = PolicyParams(
            type: "threshold",
            threshold: 1,
            spendingLimit: nil,
            periodDays: nil,
            signerWeights: nil
        )
        let modified = EditPolicyEntry(
            info: info,
            label: "Threshold: 2-of-N",
            address: info.address,
            installSpec: .simpleThreshold(threshold: 2),
            onChainId: 11,
            isOriginal: true,
            modified: true,
            originalParams: originalParams
        )
        let reverted = modified.with(
            label: "Threshold: 1-of-N",
            installSpec: .some(nil),
            modified: false
        )
        #expect(reverted.modified == false)
        #expect(reverted.installSpec == nil)
        #expect(reverted.label == "Threshold: 1-of-N")
        #expect(reverted.onChainId == 11)
        #expect(reverted.isOriginal)
        #expect(reverted.originalParams == originalParams)
    }
}

// ============================================================================
// MARK: - resolveEditDiffExpiry tests
// ============================================================================

@Suite("ContextRuleFlow: resolveEditDiffExpiry")
struct ResolveEditDiffExpiryTests {

    @Test("Returns unchanged when expiryChanged is false")
    @MainActor
    func unchangedWhenNotMarked() async throws {
        let made = BuilderFixtures.makeFlow()
        made.ledger.nextSequence = 100
        let diff = EditFlowFixtures.emptyDiff()
        let resolved = try await made.flow.resolveEditDiffExpiry(diff)
        #expect(resolved.newExpiry == nil)
        #expect(made.ledger.callCount == 0)
    }

    @Test("Passes through nil expiry as removal")
    @MainActor
    func nilPropagates() async throws {
        let made = BuilderFixtures.makeFlow()
        made.ledger.nextSequence = 100
        let diff = EditFlowFixtures.emptyDiff(expiryChanged: true)
        let resolved = try await made.flow.resolveEditDiffExpiry(diff)
        #expect(resolved.newExpiry == nil)
        #expect(resolved.expiryChanged)
        #expect(made.ledger.callCount == 0)
    }

    @Test("Adds offset to current ledger")
    @MainActor
    func addsOffset() async throws {
        let made = BuilderFixtures.makeFlow()
        made.ledger.nextSequence = 1_000_000
        let diff = EditFlowFixtures.emptyDiff(expiryChanged: true, newExpiry: 720)
        let resolved = try await made.flow.resolveEditDiffExpiry(diff)
        #expect(resolved.newExpiry == 1_000_720)
    }
}
