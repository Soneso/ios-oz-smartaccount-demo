// CoordinationTestSupport.swift
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
// MARK: - MockCoordinationClient
// ============================================================================

/// Configurable fake for `CoordinationClientType`.
///
/// Tests seed `pending` and per-method results/errors, and assert against the
/// recorded `approveCalls` / `rejectCalls`. Serial test execution makes the
/// plain mutable storage safe under `@unchecked Sendable`.
final class MockCoordinationClient: CoordinationClientType, @unchecked Sendable {

    var pending: [CoordinationRequest] = []
    var listError: Error?
    var getError: Error?
    var approveError: Error?
    var rejectError: Error?

    /// Overrides the response of `getRequest(_:)` for a specific id; falls back
    /// to a lookup in `pending` when absent.
    var getByIdProvider: (@Sendable (String) -> CoordinationRequest?)?

    private(set) var listCallCount = 0
    private(set) var approveCalls: [(id: String, hash: String)] = []
    private(set) var rejectCalls: [(id: String, note: String?)] = []

    func listPending() async throws -> [CoordinationRequest] {
        listCallCount += 1
        if let listError { throw listError }
        return pending
    }

    func getRequest(_ id: String) async throws -> CoordinationRequest {
        if let getError { throw getError }
        if let provided = getByIdProvider?(id) { return provided }
        if let match = pending.first(where: { $0.id == id }) { return match }
        throw CoordinationError(message: "not found", statusCode: 404)
    }

    func approve(_ id: String, resultHash: String) async throws -> CoordinationRequest {
        approveCalls.append((id, resultHash))
        if let approveError { throw approveError }
        return InboxFixtures.resolved(id, status: CoordinationRequest.statusApproved, resultHash: resultHash)
    }

    func reject(_ id: String, note: String?) async throws -> CoordinationRequest {
        rejectCalls.append((id, note))
        if let rejectError { throw rejectError }
        return InboxFixtures.resolved(id, status: CoordinationRequest.statusRejected, note: note)
    }
}

// ============================================================================
// MARK: - InboxFixtures
// ============================================================================

/// Test data builders for the approval inbox flow.
enum InboxFixtures {

    /// A C-address used as the connected smart account / target token.
    static let smartAccount = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"

    /// A recipient G-address (the `to` argument of a transfer).
    static let recipientG = "GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5"

    static let txHash = "deadbeef01020304deadbeef01020304deadbeef01020304deadbeef01020304"

    /// Base64-encodes a list of `SCValXDR` arguments verbatim, as the server
    /// stores them.
    static func encodeArgs(_ args: [SCValXDR]) -> [String] {
        args.map { value in
            guard let encoded = value.xdrEncoded else {
                preconditionFailure("InboxFixtures: failed to encode SCVal argument")
            }
            return encoded
        }
    }

    /// Builds the SCVal args for `transfer(from, to, amount)`.
    static func transferArgs(from: String, to: String, amount: String) -> [String] {
        let fromAddr = try! SCAddressXDR(contractId: from) // swiftlint:disable:this force_try
        let toAddr = try! SCAddressXDR(accountId: to) // swiftlint:disable:this force_try
        let amt = try! SCValXDR.i128(stringValue: amount) // swiftlint:disable:this force_try
        return encodeArgs([.address(fromAddr), .address(toAddr), amt])
    }

    /// Builds the SCVal args for `approve(from, spender, amount, expiration)`.
    static func approveArgs(from: String, spender: String, amount: String, expiration: UInt32) -> [String] {
        let fromAddr = try! SCAddressXDR(contractId: from) // swiftlint:disable:this force_try
        let spenderAddr = try! SCAddressXDR(accountId: spender) // swiftlint:disable:this force_try
        let amt = try! SCValXDR.i128(stringValue: amount) // swiftlint:disable:this force_try
        return encodeArgs([.address(fromAddr), .address(spenderAddr), amt, .u32(expiration)])
    }

    /// Constructs a pending `CoordinationRequest`.
    static func request(
        id: String = "req-1",
        smartAccount: String = InboxFixtures.smartAccount,
        target: String = InboxFixtures.smartAccount,
        targetFn: String = "transfer",
        args: [String],
        amount: String = "150.0",
        reason: Int = OZContractErrorCodes.unauthorizedSigner,
        status: String = CoordinationRequest.statusPending
    ) -> CoordinationRequest {
        CoordinationRequest(
            id: id,
            smartAccount: smartAccount,
            target: target,
            targetFn: targetFn,
            args: args,
            amount: amount,
            reason: reason,
            status: status,
            createdAt: 1_700_000_000_000
        )
    }

    /// A resolved copy used by the mock's approve/reject responses.
    static func resolved(
        _ id: String,
        status: String,
        resultHash: String? = nil,
        note: String? = nil
    ) -> CoordinationRequest {
        CoordinationRequest(
            id: id,
            smartAccount: smartAccount,
            target: smartAccount,
            targetFn: "transfer",
            args: [],
            amount: "",
            reason: 0,
            status: status,
            createdAt: 1_700_000_000_000,
            resolvedAt: 1_700_000_100_000,
            resultHash: resultHash,
            note: note
        )
    }

    /// A `DemoState` connected to ``smartAccount``.
    @MainActor
    static func connectedState() -> DemoState {
        let state = DemoState()
        state.setConnected(contractId: smartAccount, credentialId: "cred", isDeployed: true)
        return state
    }

    /// Builds an `ApprovalInboxFlow` wired to the supplied mocks.
    @MainActor
    static func makeFlow(
        coordination: MockCoordinationClient,
        contractCall: ContractCallOperationsType?,
        state: DemoState? = nil,
        log: ActivityLogState = ActivityLogState()
    ) -> ApprovalInboxFlow {
        let st = state ?? connectedState()
        return ApprovalInboxFlow(
            coordination: coordination,
            activityLog: log,
            demoState: st,
            contractCallProvider: { contractCall }
        )
    }
}
