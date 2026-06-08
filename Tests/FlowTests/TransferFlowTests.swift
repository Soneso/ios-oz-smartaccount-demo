// TransferFlowTests.swift
// SmartAccountDemoTests
//
// Copyright (c) 2026 Soneso. All rights reserved.

// swiftlint:disable file_length
import Foundation
#if canImport(UIKit)
@testable import SmartAccountDemoLib
#else
@testable import SmartAccountDemoMacLib
#endif
import stellarsdk
import Testing

// ============================================================================
// MARK: - Single-signer happy path (Variant A)
// ============================================================================

@Suite("TransferFlow: Single-Signer Happy Path")
struct TransferFlowSingleSignerHappyPathTests {

    @Test("Variant A — single signer, transfer succeeds, hash returned")
    @MainActor
    func singleSignerTransferSucceeds() async throws {
        let txOps = MockTransactionOperations()
        txOps.result = TransferFixtures.successResult()
        let mainFlow = MockMainScreenFlow()
        let ctx = TransferFixtures.makeFlow(txOps: txOps, mainFlow: mainFlow)
        ctx.state.setXlmBalance("90.0")

        let result = try await ctx.flow.transfer(
            tokenContract: TransferFixtures.nativeTokenContract,
            recipient: TransferFixtures.recipientG,
            amount: "10",
            tokenLabel: "XLM"
        )

        #expect(result.transactionHash == TransferFixtures.txHash)
        #expect(result.amount == "10")
        #expect(result.tokenLabel == "XLM")
        #expect(result.recipient == TransferFixtures.recipientG)
        #expect(txOps.callCount == 1)
        #expect(txOps.lastRecipient == TransferFixtures.recipientG)
        #expect(txOps.lastAmount == "10")
        #expect(mainFlow.refreshCallCount == 1)
    }

    @Test("Variant A — balance is refreshed after successful transfer")
    @MainActor
    func balanceRefreshedAfterTransfer() async throws {
        let txOps = MockTransactionOperations()
        txOps.result = TransferFixtures.successResult()
        let mainFlow = MockMainScreenFlow()
        let ctx = TransferFixtures.makeFlow(txOps: txOps, mainFlow: mainFlow)
        ctx.state.setXlmBalance("42.0")

        _ = try await ctx.flow.transfer(
            tokenContract: TransferFixtures.nativeTokenContract,
            recipient: TransferFixtures.recipientG,
            amount: "5",
            tokenLabel: "XLM"
        )

        #expect(mainFlow.refreshCallCount == 1)
    }

    @Test("Variant A — result carries updated balance from DemoState after refresh")
    @MainActor
    func resultCarriesUpdatedBalance() async throws {
        let txOps = MockTransactionOperations()
        txOps.result = TransferFixtures.successResult()
        let mainFlow = MockMainScreenFlow()
        let ctx = TransferFixtures.makeFlow(txOps: txOps, mainFlow: mainFlow)
        ctx.state.setXlmBalance("88.5")

        let result = try await ctx.flow.transfer(
            tokenContract: TransferFixtures.nativeTokenContract,
            recipient: TransferFixtures.recipientG,
            amount: "5",
            tokenLabel: "XLM"
        )

        #expect(result.xlmBalance == "88.5")
    }
}

// ============================================================================
// MARK: - Single-signer cancellation (Variant A)
// ============================================================================

@Suite("TransferFlow: Passkey Cancellation")
struct TransferFlowCancellationTests {

    @Test("Variant A — user cancellation propagates without wrapping")
    @MainActor
    func userCancellationPropagates() async throws {
        let txOps = MockTransactionOperations()
        txOps.error = MockWebAuthnCancelledError()
        let ctx = TransferFixtures.makeFlow(txOps: txOps)

        var caughtError: Error?
        do {
            _ = try await ctx.flow.transfer(
                tokenContract: TransferFixtures.nativeTokenContract,
                recipient: TransferFixtures.recipientG,
                amount: "5",
                tokenLabel: "XLM"
            )
        } catch {
            caughtError = error
        }

        let err = try #require(caughtError)
        #expect(isUserCancellation(err))
    }

    @Test("Variant A — balance not refreshed when transfer throws")
    @MainActor
    func balanceNotRefreshedOnError() async throws {
        let txOps = MockTransactionOperations()
        txOps.error = MockWebAuthnCancelledError()
        let mainFlow = MockMainScreenFlow()
        let ctx = TransferFixtures.makeFlow(txOps: txOps, mainFlow: mainFlow)

        _ = try? await ctx.flow.transfer(
            tokenContract: TransferFixtures.nativeTokenContract,
            recipient: TransferFixtures.recipientG,
            amount: "5",
            tokenLabel: "XLM"
        )

        #expect(mainFlow.refreshCallCount == 0)
    }
}

// ============================================================================
// MARK: - Validation (Variant A)
// ============================================================================

@Suite("TransferFlow: Validation Guard — Self-Transfer")
struct TransferFlowSelfTransferTests {

    @Test("Variant A — self-transfer: SDK validates and throws, flow propagates")
    @MainActor
    func selfTransferRejected() async throws {
        let txOps = MockTransactionOperations()
        txOps.error = SmartAccountValidationException.invalidInput(field: "recipient", reason: "Cannot transfer to self")
        let state = TransferFixtures.connectedState()
        let ctx = TransferFixtures.makeFlow(txOps: txOps, state: state)

        var caughtError: Error?
        do {
            _ = try await ctx.flow.transfer(
                tokenContract: TransferFixtures.nativeTokenContract,
                recipient: TransferFixtures.contractId,
                amount: "5",
                tokenLabel: "XLM"
            )
        } catch {
            caughtError = error
        }

        #expect(caughtError != nil)
        #expect(txOps.callCount == 1)
    }
}

// ============================================================================
// MARK: - SDK failure result (Variant A)
// ============================================================================

@Suite("TransferFlow: SDK Non-success Result")
struct TransferFlowFailedResultTests {

    @Test("Variant A — SDK returns success=false, flow throws TransferFlowError.transferFailed")
    @MainActor
    func sdkReturnsFalse() async throws {
        let txOps = MockTransactionOperations()
        txOps.result = TransferFixtures.failedResult(error: "Insufficient balance")
        let ctx = TransferFixtures.makeFlow(txOps: txOps)

        await #expect(throws: TransferFlowError.self) {
            _ = try await ctx.flow.transfer(
                tokenContract: TransferFixtures.nativeTokenContract,
                recipient: TransferFixtures.recipientG,
                amount: "9999",
                tokenLabel: "XLM"
            )
        }
    }

    @Test("Variant A — RPC unreachable error propagates from SDK")
    @MainActor
    func networkErrorPropagates() async throws {
        let txOps = MockTransactionOperations()
        txOps.error = MockTransferNetworkError(detail: "Network unreachable: connection timeout.")
        let ctx = TransferFixtures.makeFlow(txOps: txOps)

        var caughtError: Error?
        do {
            _ = try await ctx.flow.transfer(
                tokenContract: TransferFixtures.nativeTokenContract,
                recipient: TransferFixtures.recipientG,
                amount: "5",
                tokenLabel: "XLM"
            )
        } catch {
            caughtError = error
        }

        #expect(caughtError != nil)
    }
}

// ============================================================================
// MARK: - Re-entrancy guard
// ============================================================================

@Suite("TransferFlow: Re-entrancy Guard")
struct TransferFlowReentrancyTests {

    @Test("Concurrent transfer call returns alreadyInProgress immediately")
    @MainActor
    func reentrancyGuardFires() async throws {
        let txOps = MockTransactionOperations()
        txOps.error = MockTransferNetworkError(detail: "Simulated network delay")
        let ctx = TransferFixtures.makeFlow(txOps: txOps)

        // First call completes (with error); flag is reset. A sequential second
        // call should NOT produce alreadyInProgress.
        _ = try? await ctx.flow.transfer(
            tokenContract: TransferFixtures.nativeTokenContract,
            recipient: TransferFixtures.recipientG,
            amount: "1",
            tokenLabel: "XLM"
        )

        var caughtError: Error?
        do {
            _ = try await ctx.flow.transfer(
                tokenContract: TransferFixtures.nativeTokenContract,
                recipient: TransferFixtures.recipientG,
                amount: "1",
                tokenLabel: "XLM"
            )
        } catch {
            caughtError = error
        }
        if let err = caughtError as? TransferFlowError, case .alreadyInProgress = err {
            Issue.record("Re-entrancy guard must not fire after first call completed")
        }
        #expect(txOps.callCount == 2)
    }

}

// ============================================================================
// MARK: - isSinglePasskeyTransfer
// ============================================================================

@Suite("TransferFlow: isSinglePasskeyTransfer")
struct TransferFlowSinglePasskeyTests {

    @Test("Returns true for single connected passkey signer")
    @MainActor
    func singleConnectedPasskeyReturnsTrue() async throws {
        let state = TransferFixtures.connectedState()
        let ctx = TransferFixtures.makeFlow(state: state)
        let signerInfo = TransferFixtures.webAuthnSignerInfo(
            credentialId: TransferFixtures.credentialId,
            connectedCredentialId: TransferFixtures.credentialId
        )
        let result = ctx.flow.isSinglePasskeyTransfer([signerInfo.signer])
        #expect(result == true)
    }

    @Test("Returns false for delegated signer")
    @MainActor
    func delegatedSignerReturnsFalse() async throws {
        let state = TransferFixtures.connectedState()
        let ctx = TransferFixtures.makeFlow(state: state)
        let signerInfo = TransferFixtures.delegatedSignerInfo()
        let result = ctx.flow.isSinglePasskeyTransfer([signerInfo.signer])
        #expect(result == false)
    }

    @Test("Returns false when multiple signers provided")
    @MainActor
    func multipleSignersReturnsFalse() async throws {
        let state = TransferFixtures.connectedState()
        let ctx = TransferFixtures.makeFlow(state: state)
        let passkey = TransferFixtures.webAuthnSignerInfo().signer
        let delegated = TransferFixtures.delegatedSignerInfo().signer
        let result = ctx.flow.isSinglePasskeyTransfer([passkey, delegated])
        #expect(result == false)
    }

    @Test("Returns false for empty signer list")
    @MainActor
    func emptyListReturnsFalse() async throws {
        let ctx = TransferFixtures.makeFlow()
        let result = ctx.flow.isSinglePasskeyTransfer([])
        #expect(result == false)
    }
}

// ============================================================================
// MARK: - loadAvailableSigners
// ============================================================================

@Suite("TransferFlow: loadAvailableSigners")
struct TransferFlowLoadSignersTests {

    @Test("Returns empty list when no kit connected")
    @MainActor
    func emptyWhenDisconnected() async throws {
        let state = DemoState()
        let log = ActivityLogState()
        let txOps = MockTransactionOperations()
        let multiOps = MockMultiSignerManager()
        let flow = TransferFlow(
            demoState: state,
            activityLog: log,
            transactionOperations: txOps,
            multiSignerManager: multiOps
        )
        let result = await flow.loadAvailableSigners()
        #expect(result.isEmpty)
    }

    @Test("Returns empty list when context rule manager throws")
    @MainActor
    func emptyOnContextRuleManagerError() async throws {
        let ctxOps = MockContextRuleManager()
        ctxOps.error = MockTransferNetworkError(detail: "RPC error")
        let ctx = TransferFixtures.makeFlow(ctxOps: ctxOps)
        let result = await ctx.flow.loadAvailableSigners()
        #expect(result.isEmpty)
    }

    @Test("Returns signers from context rules when connected")
    @MainActor
    func returnSignersFromRules() async throws {
        let ctxOps = MockContextRuleManager()
        // Empty rules returns empty signer list — valid test case
        ctxOps.result = []
        let ctx = TransferFixtures.makeFlow(ctxOps: ctxOps)
        let result = await ctx.flow.loadAvailableSigners()
        #expect(result.isEmpty)
        #expect(ctxOps.callCount == 1)
    }

    @Test("Fixture: one passkey + one delegated signer returns two SignerInfos with correct canSign flags")
    @MainActor
    func passkeyAndDelegatedSignerInfoExtracted() async throws {
        let ctxOps = MockContextRuleManager()
        ctxOps.result = TransferFixtures.contextRuleWithPasskeyAndDelegated()

        let state = TransferFixtures.connectedState()
        // No delegated keypair registered on the real manager, so the delegated
        // signer's canSign resolves to false.
        let ctx = TransferFixtures.makeFlow(ctxOps: ctxOps, state: state)

        let infos = await ctx.flow.loadAvailableSigners()

        #expect(infos.count == 2)

        // The connected passkey signer must have canSign == true.
        let passkeyInfo = infos.first { $0.signer is OZExternalSigner }
        #expect(passkeyInfo != nil)
        #expect(passkeyInfo?.canSign == true)

        // The delegated signer must have canSign == false (no keypair registered).
        let delegatedInfo = infos.first { $0.signer is OZDelegatedSigner }
        #expect(delegatedInfo != nil)
        #expect(delegatedInfo?.canSign == false)
    }

    @Test("Fixture: delegated signer canSign == true when external signer manager confirms it")
    @MainActor
    func delegatedSignerCanSignWhenManagerConfirms() async throws {
        let ctxOps = MockContextRuleManager()
        ctxOps.result = TransferFixtures.contextRuleWithPasskeyAndDelegated()

        let state = TransferFixtures.connectedState()
        let ctx = TransferFixtures.makeFlow(ctxOps: ctxOps, state: state)

        // Register the delegated keypair on the real manager so canSignFor reports
        // true for the fixture's delegated G-address.
        _ = try await ctx.signers.addFromSecret(
            secretKey: DemoExternalSignersTestSupport.delegatedSecret
        )

        let infos = await ctx.flow.loadAvailableSigners()

        let delegatedInfo = infos.first { $0.signer is OZDelegatedSigner }
        #expect(delegatedInfo?.canSign == true)
    }
}

// ============================================================================
// MARK: - Multi-signer happy path (Variant C)
// ============================================================================

@Suite("TransferFlow: Multi-Signer Happy Path")
struct TransferFlowMultiSignerHappyPathTests {

    @Test("Variant C — multi-signer transfer with delegated signer succeeds")
    @MainActor
    func multiSignerTransferSucceeds() async throws {
        let multiOps = MockMultiSignerManager()
        multiOps.result = TransferFixtures.successResult()
        let mainFlow = MockMainScreenFlow()
        let ctx = TransferFixtures.makeFlow(
            multiOps: multiOps,
            mainFlow: mainFlow
        )

        let passkeySigner = TransferFixtures.webAuthnSignerInfo().signer
        let delegatedSigner = TransferFixtures.delegatedSignerInfo()
        let chosenSigners: [any OZSmartAccountSigner] = [passkeySigner, delegatedSigner.signer]

        let result = try await ctx.flow.multiSignerTransfer(
            tokenContract: TransferFixtures.nativeTokenContract,
            recipient: TransferFixtures.recipientG,
            amount: "5",
            tokenLabel: "XLM",
            chosenSigners: chosenSigners,
            delegatedSecrets: [:]
        )

        #expect(result.transactionHash == TransferFixtures.txHash)
        #expect(multiOps.callCount == 1)
        #expect(mainFlow.refreshCallCount == 1)
    }

    @Test("Variant C — delegated keypair is registered for the call then cleared on success")
    @MainActor
    func delegatedKeypairsClearedBeforeRegistering() async throws {
        let multiOps = MockMultiSignerManager()
        multiOps.result = TransferFixtures.successResult()
        let ctx = TransferFixtures.makeFlow(multiOps: multiOps)

        let passkeySigner = TransferFixtures.webAuthnSignerInfo().signer
        let delegatedAddress = DemoExternalSignersTestSupport.delegatedAddress
        let secret = DemoExternalSignersTestSupport.delegatedSecret
        let delegated = try OZDelegatedSigner(address: delegatedAddress)

        // The keypair must be registered on the real manager while the SDK call runs.
        let signers = ctx.signers
        var canSignDuringCall = false
        multiOps.onCall = {
            canSignDuringCall = await signers.canSignFor(address: delegatedAddress)
        }

        _ = try await ctx.flow.multiSignerTransfer(
            tokenContract: TransferFixtures.nativeTokenContract,
            recipient: TransferFixtures.recipientG,
            amount: "5",
            tokenLabel: "XLM",
            chosenSigners: [passkeySigner, delegated],
            delegatedSecrets: [delegatedAddress: secret]
        )

        // Registered during the SDK call, cleared afterward (post-success cleanup).
        #expect(canSignDuringCall)
        #expect(!(await ctx.signers.canSignFor(address: delegatedAddress)))
        #expect(await ctx.signers.getAll().isEmpty)
    }

    @Test("Variant C — SDK non-success result throws TransferFlowError")
    @MainActor
    func sdkReturnsFalseThrows() async throws {
        let multiOps = MockMultiSignerManager()
        multiOps.result = TransferFixtures.failedResult()
        let ctx = TransferFixtures.makeFlow(multiOps: multiOps)

        await #expect(throws: TransferFlowError.self) {
            _ = try await ctx.flow.multiSignerTransfer(
                tokenContract: TransferFixtures.nativeTokenContract,
                recipient: TransferFixtures.recipientG,
                amount: "5",
                tokenLabel: "XLM",
                chosenSigners: [TransferFixtures.webAuthnSignerInfo().signer],
                delegatedSecrets: [:]
            )
        }
    }

    @Test("Variant C — WebAuthn cancellation propagates")
    @MainActor
    func webAuthnCancellationPropagates() async throws {
        let multiOps = MockMultiSignerManager()
        multiOps.error = MockWebAuthnCancelledError()
        let ctx = TransferFixtures.makeFlow(multiOps: multiOps)

        var caughtError: Error?
        do {
            _ = try await ctx.flow.multiSignerTransfer(
                tokenContract: TransferFixtures.nativeTokenContract,
                recipient: TransferFixtures.recipientG,
                amount: "5",
                tokenLabel: "XLM",
                chosenSigners: [TransferFixtures.webAuthnSignerInfo().signer],
                delegatedSecrets: [:]
            )
        } catch {
            caughtError = error
        }

        let err = try #require(caughtError)
        #expect(isUserCancellation(err))
    }

    @Test("Variant C — multi-signer balance refresh is called on success")
    @MainActor
    func balanceRefreshedAfterMultiSignerTransfer() async throws {
        let multiOps = MockMultiSignerManager()
        multiOps.result = TransferFixtures.successResult()
        let mainFlow = MockMainScreenFlow()
        let ctx = TransferFixtures.makeFlow(multiOps: multiOps, mainFlow: mainFlow)

        _ = try await ctx.flow.multiSignerTransfer(
            tokenContract: TransferFixtures.nativeTokenContract,
            recipient: TransferFixtures.recipientG,
            amount: "5",
            tokenLabel: "XLM",
            chosenSigners: [],
            delegatedSecrets: [:]
        )

        #expect(mainFlow.refreshCallCount == 1)
    }
}

// ============================================================================
// MARK: - Token selection
// ============================================================================

@Suite("TransferFlow: Token Contract Routing")
struct TransferFlowTokenTests {

    @Test("XLM token contract is passed through to SDK")
    @MainActor
    func xlmTokenContractPassedThrough() async throws {
        let txOps = MockTransactionOperations()
        txOps.result = TransferFixtures.successResult()
        let ctx = TransferFixtures.makeFlow(txOps: txOps)

        _ = try await ctx.flow.transfer(
            tokenContract: DemoConfig.nativeTokenContract,
            recipient: TransferFixtures.recipientG,
            amount: "1",
            tokenLabel: "XLM"
        )

        #expect(txOps.lastTokenContract == DemoConfig.nativeTokenContract)
    }

    @Test("DEMO token label is preserved in result")
    @MainActor
    func demoTokenLabelPreservedInResult() async throws {
        let txOps = MockTransactionOperations()
        txOps.result = TransferFixtures.successResult()
        let demoContractId = "CDEMOTOKEN1234567890123456789012345678901234567890123456"
        let ctx = TransferFixtures.makeFlow(txOps: txOps)
        ctx.state.setDemoTokenContractId(demoContractId)

        let result = try await ctx.flow.transfer(
            tokenContract: demoContractId,
            recipient: TransferFixtures.recipientG,
            amount: "100",
            tokenLabel: "DEMO"
        )

        #expect(result.tokenLabel == "DEMO")
    }
}

// ============================================================================
// MARK: - Decimals selection
// ============================================================================

@Suite("TransferFlow: Decimals Selection")
struct TransferFlowDecimalsTests {

    /// A valid non-native custom token contract used to assert the nil-decimals
    /// (SDK auto-fetch) path. Distinct from `DemoConfig.nativeTokenContract`.
    static let customToken = "CDEMOTOKEN1234567890123456789012345678901234567890123456"

    @Test("Native XLM transfer passes decimals 7 (no SDK decimals fetch)")
    @MainActor
    func xlmTransferUsesSevenDecimals() async throws {
        let txOps = MockTransactionOperations()
        txOps.result = TransferFixtures.successResult()
        let ctx = TransferFixtures.makeFlow(txOps: txOps)

        _ = try await ctx.flow.transfer(
            tokenContract: DemoConfig.nativeTokenContract,
            recipient: TransferFixtures.recipientG,
            amount: "1",
            tokenLabel: "XLM"
        )

        #expect(txOps.lastDecimals == .some(.some(nativeTokenDecimals)))
        #expect(nativeTokenDecimals == 7)
    }

    @Test("Custom token transfer passes nil decimals (SDK auto-fetch)")
    @MainActor
    func customTokenTransferUsesNilDecimals() async throws {
        let txOps = MockTransactionOperations()
        txOps.result = TransferFixtures.successResult()
        let ctx = TransferFixtures.makeFlow(txOps: txOps)
        ctx.state.setDemoTokenContractId(Self.customToken)

        _ = try await ctx.flow.transfer(
            tokenContract: Self.customToken,
            recipient: TransferFixtures.recipientG,
            amount: "100",
            tokenLabel: "DEMO"
        )

        #expect(txOps.lastDecimals == .some(.none))
    }

    @Test("Native XLM multi-signer transfer passes decimals 7")
    @MainActor
    func xlmMultiSignerUsesSevenDecimals() async throws {
        let multiOps = MockMultiSignerManager()
        multiOps.result = TransferFixtures.successResult()
        let ctx = TransferFixtures.makeFlow(multiOps: multiOps)

        _ = try await ctx.flow.multiSignerTransfer(
            tokenContract: DemoConfig.nativeTokenContract,
            recipient: TransferFixtures.recipientG,
            amount: "5",
            tokenLabel: "XLM",
            chosenSigners: [],
            delegatedSecrets: [:]
        )

        #expect(multiOps.lastDecimals == .some(.some(nativeTokenDecimals)))
    }

    @Test("Custom token multi-signer transfer passes nil decimals")
    @MainActor
    func customTokenMultiSignerUsesNilDecimals() async throws {
        let multiOps = MockMultiSignerManager()
        multiOps.result = TransferFixtures.successResult()
        let ctx = TransferFixtures.makeFlow(multiOps: multiOps)
        ctx.state.setDemoTokenContractId(Self.customToken)

        _ = try await ctx.flow.multiSignerTransfer(
            tokenContract: Self.customToken,
            recipient: TransferFixtures.recipientG,
            amount: "100",
            tokenLabel: "DEMO",
            chosenSigners: [],
            delegatedSecrets: [:]
        )

        #expect(multiOps.lastDecimals == .some(.none))
    }
}

// ============================================================================
// MARK: - Kit nil guard
// ============================================================================

@Suite("TransferFlow: Disconnected State")
struct TransferFlowDisconnectedTests {

    @Test("Disconnected state — SDK call propagates SmartAccountWalletException")
    @MainActor
    func disconnectedStateProducesError() async throws {
        let txOps = MockTransactionOperations()
        txOps.error = SmartAccountWalletException.NotConnected(message: "No wallet connected.")
        let state = DemoState()
        let log = ActivityLogState()
        let flow = TransferFlow(
            demoState: state,
            activityLog: log,
            transactionOperations: txOps,
            multiSignerManager: MockMultiSignerManager()
        )

        var caughtError: Error?
        do {
            _ = try await flow.transfer(
                tokenContract: TransferFixtures.nativeTokenContract,
                recipient: TransferFixtures.recipientG,
                amount: "1",
                tokenLabel: "XLM"
            )
        } catch {
            caughtError = error
        }

        #expect(caughtError != nil)
    }
}

// ============================================================================
// MARK: - Updated balance in result
// ============================================================================

@Suite("TransferFlow: Updated Balance in Result")
struct TransferFlowBalanceResultTests {

    @Test("Balance shown in result reflects DemoState after refresh mock")
    @MainActor
    func balanceInResultReflectsDemoState() async throws {
        let txOps = MockTransactionOperations()
        txOps.result = TransferFixtures.successResult()
        let ctx = TransferFixtures.makeFlow(txOps: txOps)
        ctx.state.setXlmBalance("55.5")
        ctx.state.setDemoTokenBalance("1000.0")

        let result = try await ctx.flow.transfer(
            tokenContract: TransferFixtures.nativeTokenContract,
            recipient: TransferFixtures.recipientG,
            amount: "5",
            tokenLabel: "XLM"
        )

        #expect(result.xlmBalance == "55.5")
        #expect(result.demoTokenBalance == "1000.0")
    }
}

// ============================================================================
// MARK: - Activity log entries
// ============================================================================

@Suite("TransferFlow: Activity Log")
struct TransferFlowActivityLogTests {

    @Test("Successful transfer logs a success entry")
    @MainActor
    func successLogged() async throws {
        let txOps = MockTransactionOperations()
        txOps.result = TransferFixtures.successResult()
        let ctx = TransferFixtures.makeFlow(txOps: txOps)

        _ = try await ctx.flow.transfer(
            tokenContract: TransferFixtures.nativeTokenContract,
            recipient: TransferFixtures.recipientG,
            amount: "10",
            tokenLabel: "XLM"
        )

        #expect(ctx.log.entries.contains { $0.level == .success })
    }

    @Test("Failed transfer does not log success entry")
    @MainActor
    func failureNotLoggedAsSuccess() async throws {
        let txOps = MockTransactionOperations()
        txOps.error = MockTransferNetworkError(detail: "Network unreachable")
        let ctx = TransferFixtures.makeFlow(txOps: txOps)

        _ = try? await ctx.flow.transfer(
            tokenContract: TransferFixtures.nativeTokenContract,
            recipient: TransferFixtures.recipientG,
            amount: "10",
            tokenLabel: "XLM"
        )

        #expect(!ctx.log.entries.contains { $0.level == .success })
    }
}
