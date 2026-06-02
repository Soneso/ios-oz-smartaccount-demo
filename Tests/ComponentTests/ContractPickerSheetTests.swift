// ContractPickerSheetTests.swift
// SmartAccountDemoTests
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
#if canImport(UIKit)
@testable import SmartAccountDemoLib
#else
@testable import SmartAccountDemoMacLib
#endif
import Testing

// ============================================================================
// MARK: - ContractPickerSheet Logic Tests
// ============================================================================
// These tests cover the data-driven behaviour of the picker rather than SwiftUI
// rendering: ambiguous-result handling in the flow, and correct wiring of the
// credentialId that is forwarded to finalizeAmbiguous without re-prompting
// WebAuthn.

@Suite("ContractPickerSheet: Ambiguous flow integration")
struct ContractPickerSheetTests {

    // Picker receives all candidates from .ambiguous result
    @Test("Ambiguous result — all candidate addresses forwarded to picker")
    @MainActor
    func ambiguousResultCandidatesForwarded() async throws {
        let ops = MockConnectionOperations()
        ops.authResult = WalletConnectionFixtures.makeAuthResult()
        ops.connectWalletResult = WalletConnectionFixtures.makeAmbiguousResult(
            candidates: [
                WalletConnectionFixtures.contractId,
                WalletConnectionFixtures.contractId2
            ]
        )
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        let result = try await deps.flow.connectViaIndexer()

        guard case .ambiguous(_, let candidates) = result else {
            Issue.record("Expected .ambiguous result from connectViaIndexer")
            return
        }
        #expect(candidates.count == 2)
        #expect(candidates[0] == WalletConnectionFixtures.contractId)
        #expect(candidates[1] == WalletConnectionFixtures.contractId2)
    }

    // After user picks, finalizeAmbiguous uses the original credentialId
    @Test("After picker selection — finalizeAmbiguous called with original credentialId, no re-auth")
    @MainActor
    func pickerSelectionUsesOriginalCredential() async throws {
        let ops = MockConnectionOperations()
        // First call: authenticate + ambiguous
        ops.authResult = WalletConnectionFixtures.makeAuthResult(
            credentialId: WalletConnectionFixtures.credentialId
        )
        ops.connectWalletResult = WalletConnectionFixtures.makeAmbiguousResult()
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        let firstResult = try await deps.flow.connectViaIndexer()
        guard case .ambiguous(let credId, _) = firstResult else {
            Issue.record("Expected .ambiguous")
            return
        }

        // Second call: finalize — simulate picker selection
        ops.connectWalletResult = WalletConnectionFixtures.makeConnectedResult()
        ops.contextRulesCount = 1
        let finalResult = try await deps.flow.finalizeAmbiguous(
            credentialId: credId,
            contractAddress: WalletConnectionFixtures.contractId
        )

        #expect(finalResult != nil)
        // authenticate should have been called exactly once (during connectViaIndexer)
        #expect(ops.authCallCount == 1, "finalizeAmbiguous must not trigger a second WebAuthn ceremony")
        // connectWallet called twice: once for indexer, once for finalize
        #expect(ops.connectWalletCallCount == 2)
        // finalize must supply the original credentialId
        #expect(ops.lastConnectOptions?.credentialId == WalletConnectionFixtures.credentialId)
        #expect(ops.lastConnectOptions?.contractId == WalletConnectionFixtures.contractId)
    }

    // Cancel dismisses without connecting
    @Test("Cancel — no connection attempted after ambiguous cancel")
    @MainActor
    func cancelDoesNotConnect() async throws {
        let ops = MockConnectionOperations()
        ops.authResult = WalletConnectionFixtures.makeAuthResult()
        ops.connectWalletResult = WalletConnectionFixtures.makeAmbiguousResult()
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        // Simulate only the indexer call (cancel means finalizeAmbiguous is never called)
        let result = try await deps.flow.connectViaIndexer()
        guard case .ambiguous = result else {
            Issue.record("Expected .ambiguous result")
            return
        }

        // No additional SDK calls (no finalize)
        #expect(ops.connectWalletCallCount == 1)
        #expect(deps.state.isConnected == false)
    }

    // Single candidate still shows picker (ambiguous with one item)
    @Test("Ambiguous with single candidate — result still .ambiguous")
    @MainActor
    func singleCandidateStillAmbiguous() async throws {
        let ops = MockConnectionOperations()
        ops.authResult = WalletConnectionFixtures.makeAuthResult()
        ops.connectWalletResult = WalletConnectionFixtures.makeAmbiguousResult(
            candidates: [WalletConnectionFixtures.contractId]
        )
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        let result = try await deps.flow.connectViaIndexer()

        guard case .ambiguous(_, let candidates) = result else {
            Issue.record("Expected .ambiguous")
            return
        }
        #expect(candidates.count == 1)
    }
}
