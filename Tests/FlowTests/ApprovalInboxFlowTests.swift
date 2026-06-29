// ApprovalInboxFlowTests.swift
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
// MARK: - Decode
// ============================================================================

@Suite("ApprovalInboxFlow: Decode")
struct ApprovalInboxFlowDecodeTests {

    @Test("transfer decodes recipient and authoritative amount from args, not server amount")
    @MainActor
    func decode_transfer() async {
        let coordination = MockCoordinationClient()
        let flow = InboxFixtures.makeFlow(coordination: coordination, contractCall: nil)
        // amountBaseUnits 1_500_000_000 = 150.0 at 7 decimals; server amount is a
        // deliberately mismatched display value to prove it is ignored.
        let request = InboxFixtures.request(
            targetFn: "transfer",
            args: InboxFixtures.transferArgs(
                from: InboxFixtures.smartAccount,
                to: InboxFixtures.recipientG,
                amount: "1500000000"
            ),
            amount: "999.0"
        )

        let decoded = flow.decodeCall(request)

        #expect(decoded.kind == .transfer)
        #expect(decoded.recipient == InboxFixtures.recipientG)
        #expect(decoded.recipientLabel == "Recipient")
        #expect(decoded.amount == "150.0")
    }

    @Test("decoded consent amount is formatted at the demo token's configured decimal scale")
    @MainActor
    func decode_amountUsesDemoTokenDecimals() async {
        let coordination = MockCoordinationClient()
        let request = InboxFixtures.request(
            targetFn: "transfer",
            args: InboxFixtures.transferArgs(
                from: InboxFixtures.smartAccount,
                to: InboxFixtures.recipientG,
                amount: "12345678"
            )
        )

        // The inbox built the way the app builds it (default tokenDecimals) formats
        // the decoded amount at the demo token's configured scale. The expected
        // value is derived from the config constant, so it tracks the configured
        // scale rather than pinning a literal.
        let defaultFlow = InboxFixtures.makeFlow(coordination: coordination, contractCall: nil)
        let expected = formatBaseUnitsAsDecimal(Int128(12_345_678), decimals: Int(DemoConfig.demoTokenDecimals))
        #expect(defaultFlow.decodeCall(request).amount == expected)

        // The scale is honored, not hard-coded: an inbox constructed with a
        // different token scale formats the same base units differently.
        let twoDecimalFlow = ApprovalInboxFlow(
            coordination: coordination,
            activityLog: ActivityLogState(),
            demoState: InboxFixtures.connectedState(),
            contractCallProvider: { nil },
            tokenDecimals: 2
        )
        #expect(twoDecimalFlow.decodeCall(request).amount == formatBaseUnitsAsDecimal(Int128(12_345_678), decimals: 2))
        #expect(defaultFlow.decodeCall(request).amount != twoDecimalFlow.decodeCall(request).amount)
    }

    @Test("approve decodes spender and amount")
    @MainActor
    func decode_approve() async {
        let coordination = MockCoordinationClient()
        let flow = InboxFixtures.makeFlow(coordination: coordination, contractCall: nil)
        let request = InboxFixtures.request(
            targetFn: "approve",
            args: InboxFixtures.approveArgs(
                from: InboxFixtures.smartAccount,
                spender: InboxFixtures.recipientG,
                amount: "1000000000",
                expiration: 2_000_000
            )
        )

        let decoded = flow.decodeCall(request)

        #expect(decoded.kind == .approve)
        #expect(decoded.recipient == InboxFixtures.recipientG)
        #expect(decoded.recipientLabel == "Spender")
        #expect(decoded.amount == "100.0")
    }

    @Test("unrecognised function surfaces the full decoded argument list")
    @MainActor
    func decode_unknown() async {
        let coordination = MockCoordinationClient()
        let flow = InboxFixtures.makeFlow(coordination: coordination, contractCall: nil)
        let args = InboxFixtures.encodeArgs([.symbol("ping"), .u32(7)])
        let request = InboxFixtures.request(targetFn: "custom_fn", args: args)

        let decoded = flow.decodeCall(request)

        #expect(decoded.kind == .unknown)
        #expect(decoded.arguments.count == 2)
        #expect(decoded.arguments[0].value == "ping")
        #expect(decoded.arguments[1].value == "7")
    }

    @Test("undecodable args are flagged and must not be approved")
    @MainActor
    func decode_undecodable() async {
        let coordination = MockCoordinationClient()
        let flow = InboxFixtures.makeFlow(coordination: coordination, contractCall: nil)
        let request = InboxFixtures.request(targetFn: "transfer", args: ["not-valid-base64-xdr"])

        let decoded = flow.decodeCall(request)

        #expect(decoded.kind == .undecodable)
        #expect(decoded.error != nil)
    }
}

// ============================================================================
// MARK: - Approve (steps 4 + 5)
// ============================================================================

@Suite("ApprovalInboxFlow: Approve")
struct ApprovalInboxFlowApproveTests {

    @Test("approve rebuilds the exact call, submits, and reports the hash back")
    @MainActor
    func approve_happyPath() async {
        let args = InboxFixtures.transferArgs(
            from: InboxFixtures.smartAccount,
            to: InboxFixtures.recipientG,
            amount: "1500000000"
        )
        let request = InboxFixtures.request(targetFn: "transfer", args: args)
        let coordination = MockCoordinationClient()
        coordination.pending = [request]
        let contractCall = MockContractCallOperations()
        contractCall.result = OZTransactionResult(success: true, hash: InboxFixtures.txHash, error: nil)
        let flow = InboxFixtures.makeFlow(coordination: coordination, contractCall: contractCall)

        let result = await flow.approveRequest(request)

        #expect(result.success)
        #expect(result.hash == InboxFixtures.txHash)
        #expect(contractCall.callCount == 1)
        #expect(contractCall.lastTarget == request.target)
        #expect(contractCall.lastTargetFn == "transfer")
        #expect(contractCall.lastTargetArgs.count == 3)
        #expect(coordination.approveCalls.count == 1)
        #expect(coordination.approveCalls.first?.hash == InboxFixtures.txHash)
    }

    @Test("approve refuses an escalation targeting a different account before any ceremony")
    @MainActor
    func approve_accountMismatch_refusesBeforeSubmit() async {
        let args = InboxFixtures.transferArgs(
            from: InboxFixtures.smartAccount,
            to: InboxFixtures.recipientG,
            amount: "1500000000"
        )
        let request = InboxFixtures.request(
            smartAccount: "CAW2Z46INPO5VIJEILMYSSEOLBVJIIII5GOE3TN5EUURSRM2FJCF7AJ6",
            target: "CAW2Z46INPO5VIJEILMYSSEOLBVJIIII5GOE3TN5EUURSRM2FJCF7AJ6",
            args: args
        )
        let coordination = MockCoordinationClient()
        let contractCall = MockContractCallOperations()
        let flow = InboxFixtures.makeFlow(coordination: coordination, contractCall: contractCall)

        let result = await flow.approveRequest(request)

        #expect(!result.success)
        #expect(contractCall.callCount == 0)
        #expect(coordination.approveCalls.isEmpty)
    }

    @Test("approve aborts when the escalation is no longer pending server-side")
    @MainActor
    func approve_staleRequest_aborts() async {
        let args = InboxFixtures.transferArgs(
            from: InboxFixtures.smartAccount,
            to: InboxFixtures.recipientG,
            amount: "1500000000"
        )
        let request = InboxFixtures.request(targetFn: "transfer", args: args)
        let coordination = MockCoordinationClient()
        coordination.getByIdProvider = { _ in
            InboxFixtures.resolved(request.id, status: CoordinationRequest.statusRejected)
        }
        let contractCall = MockContractCallOperations()
        let flow = InboxFixtures.makeFlow(coordination: coordination, contractCall: contractCall)

        let result = await flow.approveRequest(request)

        #expect(!result.success)
        #expect(contractCall.callCount == 0)
    }

    @Test("a confirmed tx whose report-back fails flags confirmedOnChain and never re-submits")
    @MainActor
    func approve_reportBackFails_thenRetrySucceeds() async {
        let args = InboxFixtures.transferArgs(
            from: InboxFixtures.smartAccount,
            to: InboxFixtures.recipientG,
            amount: "1500000000"
        )
        let request = InboxFixtures.request(targetFn: "transfer", args: args)
        let coordination = MockCoordinationClient()
        coordination.pending = [request]
        coordination.approveError = CoordinationError(message: "network down")
        let contractCall = MockContractCallOperations()
        contractCall.result = OZTransactionResult(success: true, hash: InboxFixtures.txHash, error: nil)
        let flow = InboxFixtures.makeFlow(coordination: coordination, contractCall: contractCall)

        let first = await flow.approveRequest(request)
        #expect(!first.success)
        #expect(first.confirmedOnChain)
        #expect(flow.isAwaitingReport(request.id))

        // A second approve must NOT re-submit on-chain; it routes to retry-report.
        coordination.approveError = nil
        let retry = await flow.approveRequest(request)

        #expect(retry.success)
        #expect(retry.hash == InboxFixtures.txHash)
        #expect(contractCall.callCount == 1) // still only one on-chain submission
    }

    @Test("a fresh flow sharing DemoState never re-submits a confirmed-but-unreported escalation")
    @MainActor
    func dedup_survivesFlowRebuild() async {
        let args = InboxFixtures.transferArgs(
            from: InboxFixtures.smartAccount,
            to: InboxFixtures.recipientG,
            amount: "1500000000"
        )
        let request = InboxFixtures.request(targetFn: "transfer", args: args)
        let state = InboxFixtures.connectedState()
        let coordination = MockCoordinationClient()
        coordination.pending = [request]
        coordination.approveError = CoordinationError(message: "network down")
        let contractCall = MockContractCallOperations()
        contractCall.result = OZTransactionResult(success: true, hash: InboxFixtures.txHash, error: nil)

        // First flow confirms on-chain but fails to report back, recording the
        // dedup entry on the shared DemoState.
        let flowA = InboxFixtures.makeFlow(coordination: coordination, contractCall: contractCall, state: state)
        let first = await flowA.approveRequest(request)
        #expect(first.confirmedOnChain)
        #expect(contractCall.callCount == 1)

        // A brand-new flow instance built after navigation rebuilt the inbox view,
        // sharing the same DemoState, must consult the persisted dedup and route to
        // the idempotent report-back path rather than re-submit a duplicate call.
        coordination.approveError = nil
        let flowB = InboxFixtures.makeFlow(coordination: coordination, contractCall: contractCall, state: state)
        #expect(flowB.isAwaitingReport(request.id))

        let retry = await flowB.approveRequest(request)
        #expect(retry.success)
        #expect(retry.hash == InboxFixtures.txHash)
        #expect(contractCall.callCount == 1) // still only one on-chain submission
    }

    @Test("retryReport treats a 409 (already resolved) as success")
    @MainActor
    func retryReport_409_isSuccess() async {
        let args = InboxFixtures.transferArgs(
            from: InboxFixtures.smartAccount,
            to: InboxFixtures.recipientG,
            amount: "1500000000"
        )
        let request = InboxFixtures.request(targetFn: "transfer", args: args)
        let coordination = MockCoordinationClient()
        coordination.pending = [request]
        coordination.approveError = CoordinationError(message: "network down")
        let contractCall = MockContractCallOperations()
        contractCall.result = OZTransactionResult(success: true, hash: InboxFixtures.txHash, error: nil)
        let flow = InboxFixtures.makeFlow(coordination: coordination, contractCall: contractCall)

        _ = await flow.approveRequest(request)
        coordination.approveError = CoordinationError(message: "already resolved", statusCode: 409)

        let retry = await flow.retryReport(request)

        #expect(retry.success)
        #expect(retry.hash == InboxFixtures.txHash)
        #expect(!flow.isAwaitingReport(request.id))
    }

    @Test("a failed pre-submit status re-check fails closed and never submits on-chain")
    @MainActor
    func getFailure_abortsBeforeSubmit() async {
        let args = InboxFixtures.transferArgs(
            from: InboxFixtures.smartAccount,
            to: InboxFixtures.recipientG,
            amount: "1500000000"
        )
        let request = InboxFixtures.request(targetFn: "transfer", args: args)
        let coordination = MockCoordinationClient()
        coordination.pending = [request]
        // The pre-submit `GET /requests/{id}` re-check fails. The flow must abort
        // rather than re-submit the agent's call blind, so no contract call and no
        // report-back occur, and the transaction is not flagged confirmed.
        coordination.getError = CoordinationError(message: "lookup failed", statusCode: 500)
        let contractCall = MockContractCallOperations()
        contractCall.result = OZTransactionResult(success: true, hash: InboxFixtures.txHash, error: nil)
        let flow = InboxFixtures.makeFlow(coordination: coordination, contractCall: contractCall)

        let result = await flow.approveRequest(request)

        #expect(!result.success)
        #expect(result.error != nil)
        #expect(!result.confirmedOnChain)
        #expect(contractCall.callCount == 0)
        #expect(coordination.approveCalls.isEmpty)
    }
}

// ============================================================================
// MARK: - Reject + reads
// ============================================================================

@Suite("ApprovalInboxFlow: Reject and Reads")
struct ApprovalInboxFlowRejectTests {

    @Test("reject posts the trimmed note; whitespace-only is sent as no note")
    @MainActor
    func reject_postsNote() async {
        let request = InboxFixtures.request(args: InboxFixtures.transferArgs(
            from: InboxFixtures.smartAccount, to: InboxFixtures.recipientG, amount: "1"
        ))
        let coordination = MockCoordinationClient()
        let flow = InboxFixtures.makeFlow(coordination: coordination, contractCall: nil)

        let result = await flow.rejectRequest(request, note: "  not now  ")
        #expect(result.success)
        #expect(coordination.rejectCalls.first?.note == "not now")

        _ = await flow.rejectRequest(request, note: "   ")
        #expect(coordination.rejectCalls.last?.note == nil)
    }

    @Test("loadPending scopes the listing to the connected smart account")
    @MainActor
    func loadPending_scopesToConnectedAccount() async throws {
        let mine = InboxFixtures.request(
            id: "mine",
            args: InboxFixtures.transferArgs(
                from: InboxFixtures.smartAccount, to: InboxFixtures.recipientG, amount: "1"
            )
        )
        let other = InboxFixtures.request(
            id: "other",
            smartAccount: "CAW2Z46INPO5VIJEILMYSSEOLBVJIIII5GOE3TN5EUURSRM2FJCF7AJ6",
            args: InboxFixtures.transferArgs(
                from: InboxFixtures.smartAccount, to: InboxFixtures.recipientG, amount: "1"
            )
        )
        let coordination = MockCoordinationClient()
        coordination.pending = [mine, other]
        let flow = InboxFixtures.makeFlow(coordination: coordination, contractCall: nil)

        let pending = try await flow.loadPending()
        #expect(pending.map(\.id) == ["mine"])

        let count = try await flow.pendingCount()
        #expect(count == 1)
    }

    @Test("reads return empty when no wallet is connected")
    @MainActor
    func reads_emptyWhenDisconnected() async throws {
        let coordination = MockCoordinationClient()
        coordination.pending = [InboxFixtures.request(args: InboxFixtures.transferArgs(
            from: InboxFixtures.smartAccount, to: InboxFixtures.recipientG, amount: "1"
        ))]
        let state = DemoState() // disconnected
        let flow = InboxFixtures.makeFlow(coordination: coordination, contractCall: nil, state: state)

        let pending = try await flow.loadPending()
        #expect(pending.isEmpty)
    }

    @Test("loadPending and pendingCount propagate a coordination list failure")
    @MainActor
    func listFailure_propagates() async {
        let coordination = MockCoordinationClient()
        coordination.listError = CoordinationError(message: "server unreachable", statusCode: 503)
        let flow = InboxFixtures.makeFlow(coordination: coordination, contractCall: nil)

        // Both reads must surface the server failure to the screen (so it can
        // render an error state) rather than swallow it and report an empty inbox.
        await #expect(throws: CoordinationError.self) {
            _ = try await flow.loadPending()
        }
        await #expect(throws: CoordinationError.self) {
            _ = try await flow.pendingCount()
        }
        #expect(coordination.listCallCount == 2)
    }

    @Test("reject surfaces a coordination failure and reports it to the caller")
    @MainActor
    func rejectFailure_surfacesError() async {
        let request = InboxFixtures.request(args: InboxFixtures.transferArgs(
            from: InboxFixtures.smartAccount, to: InboxFixtures.recipientG, amount: "1"
        ))
        let coordination = MockCoordinationClient()
        coordination.rejectError = CoordinationError(message: "reject failed", statusCode: 500)
        let flow = InboxFixtures.makeFlow(coordination: coordination, contractCall: nil)

        let result = await flow.rejectRequest(request, note: "no")

        // A failed reject must not be reported as success, and the attempt (with
        // the trimmed note) must still have reached the server.
        #expect(!result.success)
        #expect(result.error != nil)
        #expect(coordination.rejectCalls.count == 1)
        #expect(coordination.rejectCalls.first?.note == "no")
    }
}
