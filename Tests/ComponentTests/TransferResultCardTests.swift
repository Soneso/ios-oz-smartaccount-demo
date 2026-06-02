// TransferResultCardTests.swift
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
// MARK: - TransferResultCard Data Model Tests
// ============================================================================

@Suite("TransferResult: Data Model")
struct TransferResultModelTests {

    @Test("TransferResult holds all fields correctly")
    func holdsAllFields() {
        let result = TransferResult(
            transactionHash: "deadbeef1234",
            amount: "10.5",
            tokenLabel: "XLM",
            recipient: "GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5",
            xlmBalance: "89.5",
            demoTokenBalance: "1000.0"
        )

        #expect(result.transactionHash == "deadbeef1234")
        #expect(result.amount == "10.5")
        #expect(result.tokenLabel == "XLM")
        #expect(result.recipient == "GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5")
        #expect(result.xlmBalance == "89.5")
        #expect(result.demoTokenBalance == "1000.0")
    }

    @Test("TransferResult allows nil DEMO balance")
    func nilDemoBalance() {
        let result = TransferResult(
            transactionHash: "hash123",
            amount: "5",
            tokenLabel: "XLM",
            recipient: "GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5",
            xlmBalance: "95.0",
            demoTokenBalance: nil
        )

        #expect(result.demoTokenBalance == nil)
    }

    @Test("TransferResult allows nil XLM balance (post-refresh failure)")
    func nilXlmBalance() {
        let result = TransferResult(
            transactionHash: "hash123",
            amount: "1",
            tokenLabel: "DEMO",
            recipient: "GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5",
            xlmBalance: nil,
            demoTokenBalance: nil
        )

        #expect(result.xlmBalance == nil)
    }

    @Test("Amount sent string contains amount and token label")
    func amountSentCombination() {
        let result = TransferResult(
            transactionHash: "hash",
            amount: "100.5",
            tokenLabel: "DEMO",
            recipient: "GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5",
            xlmBalance: nil,
            demoTokenBalance: nil
        )

        let amountSent = "\(result.amount) \(result.tokenLabel)"
        #expect(amountSent == "100.5 DEMO")
    }
}

// ============================================================================
// MARK: - TransferFlowError
// ============================================================================

@Suite("TransferFlowError: Error Descriptions")
struct TransferFlowErrorTests {

    @Test("alreadyInProgress has non-empty description")
    func alreadyInProgressDescription() {
        let error = TransferFlowError.alreadyInProgress
        #expect(!(error.errorDescription ?? "").isEmpty)
    }

    @Test("transferFailed carries reason string in description")
    func transferFailedDescription() {
        let error = TransferFlowError.transferFailed(reason: "Insufficient balance")
        #expect(error.errorDescription?.contains("Insufficient balance") == true)
    }

    @Test("transferFailed description includes 'Transfer failed' prefix")
    func transferFailedHasPrefix() {
        let error = TransferFlowError.transferFailed(reason: "Some reason")
        #expect(error.errorDescription?.hasPrefix("Transfer failed") == true)
    }
}
