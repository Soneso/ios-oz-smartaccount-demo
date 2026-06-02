// ApproveFlowTests.swift
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
// MARK: - Single-signer happy path
// ============================================================================

@Suite("ApproveFlow: Single-Signer Happy Path")
struct ApproveFlowSingleSignerHappyPathTests {

    @Test("approveAllowance succeeds and returns the transaction hash")
    @MainActor
    func singleSigner_succeeds_returnsHash() async throws {
        let contractOps = MockContractCallOperations()
        contractOps.result = ApproveFixtures.successResult()
        let made = ApproveFixtures.makeFlow(contractOps: contractOps)

        let result = try await made.flow.approveAllowance(
            tokenContract: ApproveFixtures.demoTokenContract,
            spenderAddress: ApproveFixtures.spenderG,
            amount: "10",
            expirationLedger: 1_000_000
        )

        #expect(result.success)
        #expect(result.hash == ApproveFixtures.txHash)
        #expect(result.error == nil)
        #expect(contractOps.callCount == 1)
        #expect(contractOps.lastTarget == ApproveFixtures.demoTokenContract)
        #expect(contractOps.lastTargetFn == "approve")
    }

    @Test("approveAllowance builds args with from, spender, amount i128, expiration u32")
    @MainActor
    func singleSigner_argsHaveCorrectShape() async throws {
        let contractOps = MockContractCallOperations()
        contractOps.result = ApproveFixtures.successResult()
        let made = ApproveFixtures.makeFlow(contractOps: contractOps)
        _ = try await made.flow.approveAllowance(
            tokenContract: ApproveFixtures.demoTokenContract,
            spenderAddress: ApproveFixtures.spenderG,
            amount: "10.0",
            expirationLedger: 1_500_000
        )
        try ApproveArgAssertions.assertSingleSignerArgs(
            args: contractOps.lastTargetArgs,
            expectedSmartAccountId: ApproveFixtures.smartAccountContractId,
            expectedAmountLo: 100_000_000,
            expectedExpiration: 1_500_000
        )
    }

    @Test("approveAllowance logs success with hash prefix")
    @MainActor
    func singleSigner_logsSuccess() async throws {
        let contractOps = MockContractCallOperations()
        contractOps.result = ApproveFixtures.successResult()
        let made = ApproveFixtures.makeFlow(contractOps: contractOps)

        _ = try await made.flow.approveAllowance(
            tokenContract: ApproveFixtures.demoTokenContract,
            spenderAddress: ApproveFixtures.spenderG,
            amount: "5.5",
            expirationLedger: 100
        )

        let messages = made.log.entries.map(\.message)
        #expect(messages.contains { $0.hasPrefix("Approve successful! Hash:") })
    }

    @Test("approveAllowance accepts a C-address spender")
    @MainActor
    func singleSigner_acceptsContractSpender() async throws {
        let contractOps = MockContractCallOperations()
        contractOps.result = ApproveFixtures.successResult()
        let made = ApproveFixtures.makeFlow(contractOps: contractOps)

        let result = try await made.flow.approveAllowance(
            tokenContract: ApproveFixtures.demoTokenContract,
            spenderAddress: ApproveFixtures.spenderC,
            amount: "1",
            expirationLedger: 100
        )
        #expect(result.success)
        #expect(contractOps.callCount == 1)
    }
}

// ============================================================================
// MARK: - Single-signer failure paths
// ============================================================================

@Suite("ApproveFlow: Single-Signer Failures")
struct ApproveFlowSingleSignerFailureTests {

    @Test("approveAllowance returns failure result and logs error on non-success SDK result")
    @MainActor
    func sdkNonSuccess_logsAndReturnsFailure() async throws {
        let contractOps = MockContractCallOperations()
        contractOps.result = ApproveFixtures.failedResult(error: "Insufficient balance")
        let made = ApproveFixtures.makeFlow(contractOps: contractOps)

        let result = try await made.flow.approveAllowance(
            tokenContract: ApproveFixtures.demoTokenContract,
            spenderAddress: ApproveFixtures.spenderG,
            amount: "10",
            expirationLedger: 100
        )

        #expect(!result.success)
        #expect(result.hash == nil)
        #expect(result.error == "Insufficient balance")
        let messages = made.log.entries.map(\.message)
        #expect(messages.contains { $0.hasPrefix("Approve failed: ") })
    }

    @Test("approveAllowance throws invalidSpenderAddress for an arbitrary string")
    @MainActor
    func invalidSpender_throws() async throws {
        let made = ApproveFixtures.makeFlow()
        await #expect(throws: ApproveFlowError.self) {
            _ = try await made.flow.approveAllowance(
                tokenContract: ApproveFixtures.demoTokenContract,
                spenderAddress: "not-an-address",
                amount: "1",
                expirationLedger: 100
            )
        }
    }

    @Test("approveAllowance throws invalidAmount for non-numeric input")
    @MainActor
    func invalidAmount_nonNumeric_throws() async throws {
        let made = ApproveFixtures.makeFlow()
        await #expect(throws: ApproveFlowError.self) {
            _ = try await made.flow.approveAllowance(
                tokenContract: ApproveFixtures.demoTokenContract,
                spenderAddress: ApproveFixtures.spenderG,
                amount: "abc",
                expirationLedger: 100
            )
        }
    }

    @Test("approveAllowance throws invalidAmount for zero")
    @MainActor
    func invalidAmount_zero_throws() async throws {
        let made = ApproveFixtures.makeFlow()
        await #expect(throws: ApproveFlowError.self) {
            _ = try await made.flow.approveAllowance(
                tokenContract: ApproveFixtures.demoTokenContract,
                spenderAddress: ApproveFixtures.spenderG,
                amount: "0",
                expirationLedger: 100
            )
        }
    }

    @Test("approveAllowance throws NotConnected when wallet is not connected")
    @MainActor
    func notConnected_throws() async throws {
        let state = DemoState()
        let made = ApproveFixtures.makeFlow(state: state)
        await #expect(throws: (any Error).self) {
            _ = try await made.flow.approveAllowance(
                tokenContract: ApproveFixtures.demoTokenContract,
                spenderAddress: ApproveFixtures.spenderG,
                amount: "1",
                expirationLedger: 100
            )
        }
    }
}

// ============================================================================
// MARK: - Multi-signer happy path (chosenSigners + secrets)
// ============================================================================

@Suite("ApproveFlow: Multi-Signer with Delegated Secrets")
struct ApproveFlowMultiSignerDelegatedTests {

    @Test("Delegated keypair is registered for the SDK call and cleared after success")
    @MainActor
    func delegatedRegistered_thenCleared() async throws {
        let multiOps = MockMultiSignerContractCall()
        multiOps.result = ApproveFixtures.successResult()
        let made = ApproveFixtures.makeFlow(multiOps: multiOps)
        let delegatedAddress = DemoExternalSignersTestSupport.delegatedAddress
        let secret = DemoExternalSignersTestSupport.delegatedSecret

        // The keypair must be registered on the real manager while the SDK call
        // runs; capture that live state from the mock's invocation hook.
        let signers = made.signers
        var canSignDuringCall = false
        multiOps.onCall = {
            canSignDuringCall = await signers.canSignFor(address: delegatedAddress)
        }

        let delegated = try OZDelegatedSigner(address: delegatedAddress)
        let result = try await made.flow.multiSignerApproveAllowanceWithChosenSigners(
            tokenContract: ApproveFixtures.demoTokenContract,
            spenderAddress: ApproveFixtures.spenderG,
            amount: "1",
            expirationLedger: 100,
            chosenSigners: [delegated],
            delegatedSecrets: [delegatedAddress: secret]
        )

        #expect(result.success)
        // Registered while the SDK call ran...
        #expect(canSignDuringCall)
        // ...and cleared by the wrapper afterward so nothing is retained.
        #expect(!(await made.signers.canSignFor(address: delegatedAddress)))
        #expect(await made.signers.getAll().isEmpty)
        #expect(multiOps.lastSelectedSigners.count == 1)
    }

    @Test("Failed delegated registration rolls back and rethrows")
    @MainActor
    func failedRegistration_rollsBackAndThrows() async throws {
        let multiOps = MockMultiSignerContractCall()
        let made = ApproveFixtures.makeFlow(multiOps: multiOps)
        let delegatedAddress = DemoExternalSignersTestSupport.delegatedAddress

        // An invalid secret key makes the real manager's addFromSecret throw, so
        // the SDK is never reached and the wrapper cleans up.
        let invalidSecret = "SNOTAVALIDSECRETKEYATALL000000000000000000000000000000000"
        let delegated = try OZDelegatedSigner(address: delegatedAddress)
        await #expect(throws: (any Error).self) {
            _ = try await made.flow.multiSignerApproveAllowanceWithChosenSigners(
                tokenContract: ApproveFixtures.demoTokenContract,
                spenderAddress: ApproveFixtures.spenderG,
                amount: "1",
                expirationLedger: 100,
                chosenSigners: [delegated],
                delegatedSecrets: [delegatedAddress: invalidSecret]
            )
        }
        // The SDK was never called because registration failed first.
        #expect(multiOps.callCount == 0)
        // Nothing leaked: the manager registry is empty.
        #expect(await made.signers.getAll().isEmpty)
    }

    @Test("Address mismatch throws invalidDelegatedSigner")
    @MainActor
    func addressMismatch_throws() async throws {
        let multiOps = MockMultiSignerContractCall()
        let made = ApproveFixtures.makeFlow(multiOps: multiOps)

        // Picker's chosen delegated signer is for a different G-address.
        let mismatched = "GAIH3ULLFQ4DGSECF2AR555KZ4KNDGEKN4AFI4SU2M7B43MGK3QJZNSR"
        let delegated = try OZDelegatedSigner(address: mismatched)
        let secret = DemoExternalSignersTestSupport.delegatedSecret
        await #expect(throws: ApproveFlowError.self) {
            _ = try await made.flow.multiSignerApproveAllowanceWithChosenSigners(
                tokenContract: ApproveFixtures.demoTokenContract,
                spenderAddress: ApproveFixtures.spenderG,
                amount: "1",
                expirationLedger: 100,
                chosenSigners: [delegated],
                delegatedSecrets: [mismatched: secret]
            )
        }
    }
}

// ============================================================================
// MARK: - isSinglePasskeyApproval
// ============================================================================

@Suite("ApproveFlow: isSinglePasskeyApproval")
struct ApproveFlowIsSinglePasskeyApprovalTests {

    @Test("Empty list returns false")
    @MainActor
    func empty_returnsFalse() {
        let made = ApproveFixtures.makeFlow()
        #expect(!made.flow.isSinglePasskeyApproval([]))
    }

    @Test("Single matching passkey returns true")
    @MainActor
    func singleMatching_returnsTrue() {
        let made = ApproveFixtures.makeFlow()
        let signer = TransferFixtures.webAuthnSignerInfo(
            credentialId: ApproveFixtures.credentialId,
            connectedCredentialId: ApproveFixtures.credentialId
        ).signer
        #expect(made.flow.isSinglePasskeyApproval([signer]))
    }

    @Test("Single non-matching passkey returns false")
    @MainActor
    func singleNonMatching_returnsFalse() {
        let made = ApproveFixtures.makeFlow()
        let signer = TransferFixtures.webAuthnSignerInfo(
            credentialId: "different-credential-id",
            connectedCredentialId: ApproveFixtures.credentialId
        ).signer
        #expect(!made.flow.isSinglePasskeyApproval([signer]))
    }
}

// ============================================================================
// MARK: - loadAvailableSigners
// ============================================================================

@Suite("ApproveFlow: loadAvailableSigners")
struct ApproveFlowLoadAvailableSignersTests {

    @Test("Returns empty when contextRuleManager is nil")
    @MainActor
    func nilManager_returnsEmpty() async {
        let state = ApproveFixtures.connectedState()
        let log = ActivityLogState()
        let flow = ApproveFlow(
            demoState: state,
            activityLog: log,
            contractCallOperations: MockContractCallOperations(),
            multiSignerOperations: MockMultiSignerContractCall(),
            contextRuleManager: nil
        )
        let result = await flow.loadAvailableSigners()
        #expect(result.isEmpty)
    }

    @Test("Returns extracted signers when rules contain passkey + delegated")
    @MainActor
    func returnsExtractedSigners() async {
        let made = ApproveFixtures.makeFlow()
        made.ctxManager.result = TransferFixtures.contextRuleWithPasskeyAndDelegated()
        let result = await made.flow.loadAvailableSigners()
        #expect(result.count == 2)
    }

    @Test("Returns empty on list failure and logs info")
    @MainActor
    func listFailure_returnsEmpty() async {
        let made = ApproveFixtures.makeFlow()
        made.ctxManager.error = MockTransferNetworkError(detail: "rpc down")
        let result = await made.flow.loadAvailableSigners()
        #expect(result.isEmpty)
        let messages = made.log.entries.map(\.message)
        #expect(messages.contains { $0.hasPrefix("Could not load signers: ") })
    }
}

// ============================================================================
// MARK: - fetchAllowance
// ============================================================================

@Suite("ApproveFlow: fetchAllowance")
struct ApproveFlowFetchAllowanceTests {

    @Test("Returns nil when no fetcher configured")
    @MainActor
    func noFetcher_returnsNil() async {
        let state = ApproveFixtures.connectedState()
        let log = ActivityLogState()
        let flow = ApproveFlow(
            demoState: state,
            activityLog: log,
            contractCallOperations: MockContractCallOperations(),
            multiSignerOperations: MockMultiSignerContractCall(),
            allowanceFetcher: nil
        )
        let result = await flow.fetchAllowance(
            tokenContract: ApproveFixtures.demoTokenContract,
            spenderAddress: ApproveFixtures.spenderG
        )
        #expect(result == nil)
    }

    @Test("Returns nil when wallet is not connected")
    @MainActor
    func notConnected_returnsNil() async {
        let state = DemoState()
        let made = ApproveFixtures.makeFlow(state: state)
        let result = await made.flow.fetchAllowance(
            tokenContract: ApproveFixtures.demoTokenContract,
            spenderAddress: ApproveFixtures.spenderG
        )
        #expect(result == nil)
    }
}

// ============================================================================
// MARK: - Expiration option value coverage
// ============================================================================

@Suite("ApproveExpirationOption: Ledger Offset Mapping")
struct ApproveExpirationOptionTests {

    @Test("1 day maps to 17280 ledgers")
    func oneDay_offset() {
        #expect(ApproveExpirationOption.oneDay.ledgerOffset == 17_280)
    }

    @Test("10 days maps to 172800 ledgers")
    func tenDays_offset() {
        #expect(ApproveExpirationOption.tenDays.ledgerOffset == 172_800)
    }

    @Test("30 days maps to 518400 ledgers")
    func thirtyDays_offset() {
        #expect(ApproveExpirationOption.thirtyDays.ledgerOffset == 518_400)
    }

    @Test("Display labels match the canonical strings")
    func displayLabels() {
        #expect(ApproveExpirationOption.oneDay.displayLabel == "1 day")
        #expect(ApproveExpirationOption.tenDays.displayLabel == "10 days")
        #expect(ApproveExpirationOption.thirtyDays.displayLabel == "30 days")
    }
}

// ============================================================================
// MARK: - ApproveResult model
// ============================================================================

@Suite("ApproveResult: Data Model")
struct ApproveResultModelTests {

    @Test("Equality covers all fields")
    func equality_allFields() {
        let lhs = ApproveResult(success: true, hash: "abc", error: nil)
        let rhs = ApproveResult(success: true, hash: "abc", error: nil)
        #expect(lhs == rhs)
    }

    @Test("Inequality on success flag")
    func inequality_successFlag() {
        let lhs = ApproveResult(success: true, hash: "abc", error: nil)
        let rhs = ApproveResult(success: false, hash: nil, error: "boom")
        #expect(lhs != rhs)
    }
}
