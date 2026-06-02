// ApproveTestSupport.swift
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
// MARK: - MockContractCallOperations
// ============================================================================

/// Configurable mock for `ContractCallOperationsType`.
///
/// Tests configure `result` or `error` and assert call parameters via the
/// `last*` records.
final class MockContractCallOperations: ContractCallOperationsType, @unchecked Sendable {

    var result: TransactionResult?
    var error: Error?
    private(set) var callCount: Int = 0
    private(set) var lastTarget: String?
    private(set) var lastTargetFn: String?
    private(set) var lastTargetArgs: [SCValXDR] = []

    func contractCall(
        target: String,
        targetFn: String,
        targetArgs: [SCValXDR]
    ) async throws -> TransactionResult {
        callCount += 1
        lastTarget = target
        lastTargetFn = targetFn
        lastTargetArgs = targetArgs
        if let error { throw error }
        guard let result else {
            preconditionFailure("MockContractCallOperations: neither result nor error configured")
        }
        return result
    }
}

// ============================================================================
// MARK: - MockMultiSignerContractCall
// ============================================================================

/// Configurable mock for `MultiSignerContractCallType`.
final class MockMultiSignerContractCall: MultiSignerContractCallType, @unchecked Sendable {

    var result: TransactionResult?
    var error: Error?
    /// Optional hook invoked (awaited) at the moment the SDK call runs, before
    /// returning `result` / throwing `error`. Lets tests capture the live
    /// registration state (adapter vs in-process) while the signing material is
    /// still registered inside the cleanup wrapper.
    var onCall: (@MainActor () async -> Void)?
    private(set) var callCount: Int = 0
    private(set) var lastTarget: String?
    private(set) var lastTargetFn: String?
    private(set) var lastTargetArgs: [SCValXDR] = []
    private(set) var lastSelectedSigners: [SelectedSigner] = []

    func multiSignerContractCall(
        target: String,
        targetFn: String,
        targetArgs: [SCValXDR],
        selectedSigners: [SelectedSigner]
    ) async throws -> TransactionResult {
        callCount += 1
        lastTarget = target
        lastTargetFn = targetFn
        lastTargetArgs = targetArgs
        lastSelectedSigners = selectedSigners
        await onCall?()
        if let error { throw error }
        guard let result else {
            preconditionFailure("MockMultiSignerContractCall: neither result nor error configured")
        }
        return result
    }
}

// ============================================================================
// MARK: - MockAllowanceFetcher
// ============================================================================

/// Configurable mock for `AllowanceFetcherType`.
final class MockAllowanceFetcher: AllowanceFetcherType, @unchecked Sendable {

    var nextResult: String?
    private(set) var callCount: Int = 0
    private(set) var lastTokenContract: String?
    private(set) var lastSmartAccountContractId: String?
    private(set) var lastSpenderAddress: String?

    func fetchAllowance(
        tokenContract: String,
        smartAccountContractId: String,
        spenderAddress: String
    ) async -> String? {
        callCount += 1
        lastTokenContract = tokenContract
        lastSmartAccountContractId = smartAccountContractId
        lastSpenderAddress = spenderAddress
        return nextResult
    }
}

// ============================================================================
// MARK: - ApproveFixtures
// ============================================================================

@MainActor
enum ApproveFixtures {

    static let smartAccountContractId = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
    static let credentialId = "dGVzdC1jcmVkZW50aWFsLWlkLWZpeHR1cmU"
    static let demoTokenContract = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
    static let spenderG = "GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5"
    static let spenderC = "CAW2Z46INPO5VIJEILMYSSEOLBVJIIII5GOE3TN5EUURSRM2FJCF7AJ6"
    static let txHash = "deadbeef01020304deadbeef01020304deadbeef01020304deadbeef01020304"

    /// Builds a `DemoState` connected with deployed=true and an admin DEMO contract.
    static func connectedState() -> DemoState {
        let state = DemoState()
        state.setConnected(
            contractId: smartAccountContractId,
            credentialId: credentialId,
            isDeployed: true
        )
        state.setDemoTokenContractId(demoTokenContract)
        state.setDemoTokenBalance("100.0")
        return state
    }

    /// Builds an `ApproveFlow` with mock dependencies and a connected state.
    static func makeFlow(
        contractOps: MockContractCallOperations = MockContractCallOperations(),
        multiOps: MockMultiSignerContractCall = MockMultiSignerContractCall(),
        ctxManager: MockContextRuleManager = MockContextRuleManager(),
        allowanceFetcher: MockAllowanceFetcher = MockAllowanceFetcher(),
        state: DemoState? = nil,
        log: ActivityLogState? = nil
    ) -> MadeApproveFlow {
        let st = state ?? connectedState()
        let lg = log ?? ActivityLogState()
        let seam = DemoExternalSignersTestSupport.install(into: st)
        let flow = ApproveFlow(
            demoState: st,
            activityLog: lg,
            contractCallOperations: contractOps,
            multiSignerOperations: multiOps,
            contextRuleManager: ctxManager,
            allowanceFetcher: allowanceFetcher
        )
        return MadeApproveFlow(
            flow: flow,
            state: st,
            log: lg,
            contractOps: contractOps,
            multiOps: multiOps,
            ctxManager: ctxManager,
            signers: seam.manager,
            adapter: seam.adapter,
            allowanceFetcher: allowanceFetcher
        )
    }

    static func successResult(hash: String = txHash) -> TransactionResult {
        TransactionResult(success: true, hash: hash, error: nil)
    }

    static func failedResult(error: String = "Insufficient balance") -> TransactionResult {
        TransactionResult(success: false, hash: nil, error: error)
    }
}

@MainActor
struct MadeApproveFlow {
    let flow: ApproveFlow
    let state: DemoState
    let log: ActivityLogState
    let contractOps: MockContractCallOperations
    let multiOps: MockMultiSignerContractCall
    let ctxManager: MockContextRuleManager
    /// Real external signer manager injected into `state`.
    let signers: OZExternalSignerManager
    /// Real Ed25519 adapter wired into the manager and `state`.
    let adapter: DemoEd25519Adapter
    let allowanceFetcher: MockAllowanceFetcher
}

// ============================================================================
// MARK: - ApproveArgAssertions
// ============================================================================

/// Shared assertion helpers used by the ApproveFlow argument-shape tests.
///
/// The `approve(from, spender, amount, expiration_ledger)` argument vector is
/// asserted in one place so the per-test bodies stay within SwiftLint's
/// `function_body_length` cap.
enum ApproveArgAssertions {

    static func assertSingleSignerArgs(
        args: [SCValXDR],
        expectedSmartAccountId: String,
        expectedAmountLo: UInt64,
        expectedExpiration: UInt32
    ) throws {
        #expect(args.count == 4)
        // [0] from — connected smart account contract.
        if case .address(let addr) = args[0], case .contract(let id) = addr {
            #expect(try Data(id.wrapped).encodeContractId() == expectedSmartAccountId)
        } else {
            Issue.record("Expected first arg to be contract Address.")
        }
        // [1] spender — G-address account address.
        if case .address(let addr) = args[1] {
            if case .account = addr {
                // Expected.
            } else {
                Issue.record("Expected second arg to be an account address.")
            }
        } else {
            Issue.record("Expected second arg to be Address.")
        }
        // [2] amount — i128 with hi=0, lo matching the expected stroops.
        if case .i128(let parts) = args[2] {
            #expect(parts.hi == 0)
            #expect(parts.lo == expectedAmountLo)
        } else {
            Issue.record("Expected third arg to be i128.")
        }
        // [3] expiration_ledger — u32 matching the expected value.
        if case .u32(let value) = args[3] {
            #expect(value == expectedExpiration)
        } else {
            Issue.record("Expected fourth arg to be u32.")
        }
    }
}
