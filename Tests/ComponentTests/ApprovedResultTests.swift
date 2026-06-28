// ApprovedResultTests.swift
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
// MARK: - ApprovedResult
// ============================================================================

@Suite("ApprovedResult: Persistent approved-results model")
struct ApprovedResultTests {

    private static let fullHash =
        "3389e9f0f1d44b5f1d5a4e2c7a9b8c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b"

    @Test("a real hash is copyable and exposes a stellar.expert testnet explorer URL")
    func realHash_isCopyableWithExplorerURL() {
        let result = ApprovedResult(requestId: "req-1", txHash: Self.fullHash, contextLabel: "transfer 150.0 to GABC…WXYZ")

        #expect(result.hasHash)
        // The FULL hash is retained verbatim for copying — never truncated.
        #expect(result.txHash == Self.fullHash)
        #expect(result.explorerURL ==
            URL(string: "https://stellar.expert/explorer/testnet/tx/\(Self.fullHash)"))
        #expect(result.id == "req-1")
    }

    @Test("the confirmed-without-hash case exposes no copy or explorer affordance")
    func emptyHash_degradesGracefully() {
        let result = ApprovedResult(requestId: "req-2", txHash: "", contextLabel: "transfer 150.0 to GABC…WXYZ")

        #expect(!result.hasHash)
        #expect(result.explorerURL == nil)
    }

    @Test("context label summarises a decoded transfer with amount and recipient")
    @MainActor
    func contextLabel_transfer() {
        let request = InboxFixtures.request(
            targetFn: "transfer",
            args: InboxFixtures.transferArgs(
                from: InboxFixtures.smartAccount,
                to: InboxFixtures.recipientG,
                amount: "1500000000"
            )
        )
        let coordination = MockCoordinationClient()
        let decoded = InboxFixtures.makeFlow(coordination: coordination, contractCall: nil).decodeCall(request)

        let label = ApprovedResult.contextLabel(for: request, decoded: decoded)

        #expect(label == "transfer 150.0 to \(truncateAddress(InboxFixtures.recipientG))")
    }

    @Test("context label summarises a decoded approve with the spender recipient")
    @MainActor
    func contextLabel_approve() {
        let request = InboxFixtures.request(
            targetFn: "approve",
            args: InboxFixtures.approveArgs(
                from: InboxFixtures.smartAccount,
                spender: InboxFixtures.recipientG,
                amount: "1000000000",
                expiration: 2_000_000
            )
        )
        let coordination = MockCoordinationClient()
        let decoded = InboxFixtures.makeFlow(coordination: coordination, contractCall: nil).decodeCall(request)

        let label = ApprovedResult.contextLabel(for: request, decoded: decoded)

        #expect(label == "approve 100.0 to \(truncateAddress(InboxFixtures.recipientG))")
    }

    @Test("context label falls back to the function name for an unrecognised call")
    @MainActor
    func contextLabel_unknownFallsBackToFunctionName() {
        let request = InboxFixtures.request(
            targetFn: "custom_fn",
            args: InboxFixtures.encodeArgs([.symbol("ping"), .u32(7)])
        )
        let coordination = MockCoordinationClient()
        let decoded = InboxFixtures.makeFlow(coordination: coordination, contractCall: nil).decodeCall(request)

        let label = ApprovedResult.contextLabel(for: request, decoded: decoded)

        #expect(label == "custom_fn")
    }
}
