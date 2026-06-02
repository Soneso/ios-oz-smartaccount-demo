// WalletCreationFlowTests.swift
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
// MARK: - WalletCreationFlowTests: Username Validation
// ============================================================================

@Suite("WalletCreationFlow: Username Validation")
struct WalletCreationFlowUsernameTests {

    @Test("Throws invalidUsername for empty string — SDK never called")
    @MainActor
    func emptyUsernameThrows() async throws {
        let ops = MockWalletOperations()
        let flow = WalletCreationFixtures.makeFlow(walletOps: ops)

        await #expect(throws: WalletCreationError.self) {
            _ = try await flow.createWallet(username: "", autoSubmit: true)
        }
        #expect(ops.callCount == 0)
    }

    @Test("Throws invalidUsername for whitespace-only string — SDK never called")
    @MainActor
    func whitespaceOnlyUsernameThrows() async throws {
        let ops = MockWalletOperations()
        let flow = WalletCreationFixtures.makeFlow(walletOps: ops)

        await #expect(throws: WalletCreationError.self) {
            _ = try await flow.createWallet(username: "   ", autoSubmit: true)
        }
        #expect(ops.callCount == 0)
    }

    @Test("Trims whitespace from username before passing to SDK")
    @MainActor
    func usernameIsTrimmedBeforeSdkCall() async throws {
        let ops = MockWalletOperations()
        ops.result = WalletCreationFixtures.validSdkResult()
        let flow = WalletCreationFixtures.makeFlow(walletOps: ops)

        _ = try await flow.createWallet(username: "  Alice  ", autoSubmit: true)

        #expect(ops.lastUserName == "Alice")
    }
}

// ============================================================================
// MARK: - WalletCreationFlowTests: Happy Path
// ============================================================================

@Suite("WalletCreationFlow: Happy Path")
struct WalletCreationFlowHappyPathTests {

    @Test("autoSubmit=true: DemoState connected, result isDeployed, autoFund derived true")
    @MainActor
    func happyPathAutoSubmit() async throws {
        let ops = MockWalletOperations()
        ops.result = WalletCreationFixtures.validSdkResult(deployed: true)
        let deps = WalletCreationFixtures.makeFlowWithDeps(walletOps: ops)

        let result = try await deps.flow.createWallet(username: "TestUser", autoSubmit: true)

        #expect(result.isDeployed == true)
        #expect(!result.contractAddress.isEmpty)
        #expect(!result.credentialId.isEmpty)
        #expect(deps.state.isConnected == true)
        #expect(deps.state.isDeployed == true)
        #expect(ops.lastAutoSubmit == true)
        // autoFund is derived from autoSubmit — when autoSubmit=true, autoFund=true.
        #expect(ops.lastAutoFund == true)
        #expect(ops.lastNativeTokenContract == DemoConfig.nativeTokenContract)
        #expect(deps.log.entries.contains { $0.level == .success && $0.message.contains("deployed") })
    }

    @Test("autoSubmit=false: DemoState connected but isDeployed=false, autoFund derived false")
    @MainActor
    func autoSubmitFalseCreatesPendingState() async throws {
        let ops = MockWalletOperations()
        ops.result = WalletCreationFixtures.validSdkResult(deployed: false)
        let deps = WalletCreationFixtures.makeFlowWithDeps(walletOps: ops)

        let result = try await deps.flow.createWallet(username: "Pending User", autoSubmit: false)

        #expect(result.isDeployed == false)
        #expect(deps.state.isConnected == true)
        #expect(deps.state.isDeployed == false)
        // autoFund is derived from autoSubmit — when autoSubmit=false, autoFund=false.
        #expect(ops.lastAutoFund == false)
        #expect(ops.lastNativeTokenContract == nil)
    }

    @Test("autoSubmit=true: transactionHash populated in result when SDK returns one")
    @MainActor
    func transactionHashPopulatedWhenSdkReturnsOne() async throws {
        let ops = MockWalletOperations()
        ops.result = WalletCreationFixtures.validSdkResult(deployed: true)
        let deps = WalletCreationFixtures.makeFlowWithDeps(walletOps: ops)

        let result = try await deps.flow.createWallet(username: "Alice", autoSubmit: true)

        #expect(result.transactionHash == "abc123txhash")
    }

    @Test("autoSubmit=false: transactionHash is nil")
    @MainActor
    func transactionHashNilWhenNotDeployed() async throws {
        let ops = MockWalletOperations()
        ops.result = WalletCreationFixtures.validSdkResult(deployed: false)
        let deps = WalletCreationFixtures.makeFlowWithDeps(walletOps: ops)

        let result = try await deps.flow.createWallet(username: "Bob", autoSubmit: false)

        #expect(result.transactionHash == nil)
    }

    @Test("Successful creation resets stale balance values")
    @MainActor
    func balancesResetOnCreation() async throws {
        let ops = MockWalletOperations()
        ops.result = WalletCreationFixtures.validSdkResult()
        let deps = WalletCreationFixtures.makeFlowWithDeps(walletOps: ops)
        deps.state.setXlmBalance("100.00 XLM")
        deps.state.setDemoTokenBalance("50.00 DEMO")

        _ = try await deps.flow.createWallet(username: "Karl", autoSubmit: true)

        #expect(deps.state.xlmBalance != "100.00 XLM")
    }

    @Test("xlmBalance and demoTokenBalance in result reflect DemoState after refresh")
    @MainActor
    func resultBalancesReflectDemoState() async throws {
        let ops = MockWalletOperations()
        ops.result = WalletCreationFixtures.validSdkResult()
        let deps = WalletCreationFixtures.makeFlowWithDeps(walletOps: ops)
        // No mainScreenFlow injected, so balances stay nil after refresh no-op.
        let result = try await deps.flow.createWallet(username: "Eve", autoSubmit: true)

        // Without mainScreenFlow the balances are nil (refresh is a no-op).
        #expect(result.xlmBalance == nil)
        #expect(result.demoTokenBalance == nil)
    }
}

// ============================================================================
// MARK: - WalletCreationFlowTests: DEMO Token Mint
// ============================================================================

@Suite("WalletCreationFlow: DEMO Token Mint")
struct WalletCreationFlowMintTests {

    @Test("autoSubmit=true with token service: service is called, demoTokenContractId set")
    @MainActor
    func autoSubmitTrueCallsTokenService() async throws {
        let ops = MockWalletOperations()
        ops.result = WalletCreationFixtures.validSdkResult()
        let tokenSvc = MockDemoTokenService()
        tokenSvc.result = DemoTokenResult(
            tokenContractId: WalletCreationFixtures.tokenContractId,
            amountMinted: DemoConfig.demoTokenMintAmount,
            alreadyExisted: false
        )
        let deps = WalletCreationFixtures.makeFlowWithDeps(
            walletOps: ops,
            tokenService: tokenSvc
        )

        _ = try await deps.flow.createWallet(username: "Carol", autoSubmit: true)

        #expect(tokenSvc.callCount == 1)
        #expect(deps.state.demoTokenContractId == WalletCreationFixtures.tokenContractId)
    }

    @Test("autoSubmit=false: token service is NOT called even when injected")
    @MainActor
    func autoSubmitFalseSkipsTokenService() async throws {
        let ops = MockWalletOperations()
        ops.result = WalletCreationFixtures.validSdkResult(deployed: false)
        let tokenSvc = MockDemoTokenService()
        tokenSvc.result = DemoTokenResult(
            tokenContractId: WalletCreationFixtures.tokenContractId,
            amountMinted: 0,
            alreadyExisted: false
        )
        let flow = WalletCreationFixtures.makeFlow(walletOps: ops, tokenService: tokenSvc)

        _ = try await flow.createWallet(username: "Dave", autoSubmit: false)

        #expect(tokenSvc.callCount == 0)
    }

    @Test("Mint failure is non-fatal: wallet state committed, result returned, log has error")
    @MainActor
    func mintFailureIsNonFatal() async throws {
        let ops = MockWalletOperations()
        ops.result = WalletCreationFixtures.validSdkResult()
        let tokenSvc = MockDemoTokenService()
        tokenSvc.error = DemoTokenServiceError.mintFailed(reason: "simulated failure")
        let deps = WalletCreationFixtures.makeFlowWithDeps(
            walletOps: ops,
            tokenService: tokenSvc
        )

        // Must NOT throw — mint failure is non-fatal after the new signature.
        let result = try await deps.flow.createWallet(username: "Eve", autoSubmit: true)

        #expect(result.isDeployed == true)
        #expect(deps.state.isConnected == true)
        #expect(deps.log.entries.contains { $0.level == .error && $0.message.contains("mint") })
    }
}

// ============================================================================
// MARK: - WalletCreationFlowTests: Error Paths
// ============================================================================

@Suite("WalletCreationFlow: Error Paths")
struct WalletCreationFlowErrorTests {

    @Test("User cancels passkey: userCanceled error, neutral log entry")
    @MainActor
    func userCancellationMappedToUserCanceled() async throws {
        let ops = MockWalletOperations()
        ops.error = MockCancelledError()
        let deps = WalletCreationFixtures.makeFlowWithDeps(walletOps: ops)

        var thrownError: WalletCreationError?
        do {
            _ = try await deps.flow.createWallet(username: "Frank", autoSubmit: true)
        } catch let err as WalletCreationError {
            thrownError = err
        }

        guard case .userCanceled = thrownError else {
            Issue.record("Expected .userCanceled, got \(String(describing: thrownError))")
            return
        }
        let hasNeutralEntry = deps.log.entries.contains {
            $0.message.lowercased().contains("cancel") && $0.level == .info
        }
        #expect(hasNeutralEntry)
    }

    @Test("userCanceled errorDescription equals canonical string")
    func userCanceledErrorDescription() {
        let err = WalletCreationError.userCanceled
        #expect(err.errorDescription == "Passkey registration cancelled by user")
    }

    @Test("SDK network error: creationFailed wraps underlying error")
    @MainActor
    func sdkErrorMappedToCreationFailed() async throws {
        let ops = MockWalletOperations()
        ops.error = MockNetworkError()
        let deps = WalletCreationFixtures.makeFlowWithDeps(walletOps: ops)

        var thrownError: WalletCreationError?
        do {
            _ = try await deps.flow.createWallet(username: "Grace", autoSubmit: true)
        } catch let err as WalletCreationError {
            thrownError = err
        }

        guard case .creationFailed = thrownError else {
            Issue.record("Expected .creationFailed, got \(String(describing: thrownError))")
            return
        }
        #expect(!deps.state.isConnected)
        #expect(deps.log.entries.contains { $0.level == .error })
    }

    @Test("Concurrent createWallet call throws creationFailed immediately")
    @MainActor
    func concurrentCreateWalletThrowsReentrancyError() async throws {
        // The re-entrancy guard in createWallet should reject any call that
        // arrives while isCreating is true. MockSlowWalletOperations suspends
        // for the specified duration so a second call can be issued while the
        // first is in flight.
        let ops = MockSlowWalletOperations(delay: 0.1)
        ops.result = WalletCreationFixtures.validSdkResult()
        let flow = WalletCreationFixtures.makeFlow(walletOps: ops)

        var secondCallError: WalletCreationError?

        // Launch first call in an unstructured Task so it suspends at the
        // slow mock's sleep without blocking the test body.
        let firstTask = Task { @MainActor in
            _ = try await flow.createWallet(username: "Alice", autoSubmit: true)
        }

        // Yield once so the first task runs until it hits the first suspension
        // point (Task.sleep inside MockSlowWalletOperations) and sets isCreating=true.
        for _ in 0 ..< 5 { await Task.yield() }

        // Second call must throw creationFailed (re-entrancy guard fires).
        do {
            _ = try await flow.createWallet(username: "Bob", autoSubmit: true)
        } catch let err as WalletCreationError {
            secondCallError = err
        }

        // Wait for first task to finish before the test exits.
        _ = await firstTask.result

        guard case .creationFailed = secondCallError else {
            let desc = String(describing: secondCallError)
            Issue.record("Expected .creationFailed from re-entrancy guard, got \(desc)")
            return
        }
    }
}

// ============================================================================
// MARK: - WalletCreationFlowTests: autoFund Derivation
// ============================================================================

@Suite("WalletCreationFlow: autoFund Derivation")
struct WalletCreationFlowAutoFundTests {

    @Test("autoSubmit=true passes nativeTokenContract to SDK (autoFund derived true)")
    @MainActor
    func autoSubmitTruePassesNativeContract() async throws {
        let ops = MockWalletOperations()
        ops.result = WalletCreationFixtures.validSdkResult()
        let flow = WalletCreationFixtures.makeFlow(walletOps: ops)

        _ = try await flow.createWallet(username: "Alice", autoSubmit: true)

        #expect(ops.lastAutoFund == true)
        #expect(ops.lastNativeTokenContract == DemoConfig.nativeTokenContract)
    }

    @Test("autoSubmit=false omits nativeTokenContract from SDK call (autoFund derived false)")
    @MainActor
    func autoSubmitFalseOmitsNativeContract() async throws {
        let ops = MockWalletOperations()
        ops.result = WalletCreationFixtures.validSdkResult(deployed: false)
        let flow = WalletCreationFixtures.makeFlow(walletOps: ops)

        _ = try await flow.createWallet(username: "Bob", autoSubmit: false)

        #expect(ops.lastAutoFund == false)
        #expect(ops.lastNativeTokenContract == nil)
    }
}

// ============================================================================
// MARK: - WalletCreationFlowTests: Credential Key Format Verification
// ============================================================================

@Suite("WalletCreationFlow: Credential Key Format Verification")
struct WalletCreationFlowVerificationTests {

    @Test("32-byte publicKey triggers webAuthnKeyFormatInvalid and error log")
    @MainActor
    func invalidPublicKeySizeTriggersFailure() async throws {
        let ops = MockWalletOperations()
        ops.result = WalletCreationFixtures.invalidKeyResult()
        let deps = WalletCreationFixtures.makeFlowWithDeps(walletOps: ops)

        var thrownError: WalletCreationError?
        do {
            _ = try await deps.flow.createWallet(username: "Heidi", autoSubmit: true)
        } catch let err as WalletCreationError {
            thrownError = err
        }

        guard case .webAuthnKeyFormatInvalid(let reason) = thrownError else {
            Issue.record("Expected .webAuthnKeyFormatInvalid, got \(String(describing: thrownError))")
            return
        }
        #expect(!reason.isEmpty)
        #expect(!deps.state.isConnected)
        #expect(deps.log.entries.contains { $0.level == .error })
    }

    @Test("Valid 65-byte publicKey (0x04) passes verification")
    @MainActor
    func validPublicKeyPassesVerification() async throws {
        let ops = MockWalletOperations()
        ops.result = WalletCreationFixtures.validSdkResult()
        let deps = WalletCreationFixtures.makeFlowWithDeps(walletOps: ops)

        let result = try await deps.flow.createWallet(username: "Ivan", autoSubmit: true)

        #expect(!result.contractAddress.isEmpty)
        #expect(deps.state.isConnected == true)
    }

    @Test("65-byte key with 0x02 prefix (compressed) triggers webAuthnKeyFormatInvalid")
    @MainActor
    func compressedKeyPrefixTriggersFailure() async throws {
        let ops = MockWalletOperations()
        ops.result = WalletCreationFixtures.wrongPrefixKeyResult()
        let deps = WalletCreationFixtures.makeFlowWithDeps(walletOps: ops)

        var thrownError: WalletCreationError?
        do {
            _ = try await deps.flow.createWallet(username: "Judy", autoSubmit: false)
        } catch let err as WalletCreationError {
            thrownError = err
        }

        guard case .webAuthnKeyFormatInvalid = thrownError else {
            Issue.record("Expected .webAuthnKeyFormatInvalid, got \(String(describing: thrownError))")
            return
        }
        #expect(!deps.state.isConnected)
    }
}

// ============================================================================
// MARK: - WalletCreationFlowTests: WalletCreationResult fields
// ============================================================================

@Suite("WalletCreationFlow: WalletCreationResult fields")
struct WalletCreationFlowResultFieldTests {

    @Test("Result contractAddress and credentialId match SDK output")
    @MainActor
    func resultIdentityFieldsMatchSDK() async throws {
        let ops = MockWalletOperations()
        ops.result = WalletCreationFixtures.validSdkResult(
            contractId: WalletCreationFixtures.defaultContractId,
            credentialId: WalletCreationFixtures.defaultCredentialId
        )
        let flow = WalletCreationFixtures.makeFlow(walletOps: ops)

        let result = try await flow.createWallet(username: "Alice", autoSubmit: true)

        #expect(result.contractAddress == WalletCreationFixtures.defaultContractId)
        #expect(result.credentialId == WalletCreationFixtures.defaultCredentialId)
    }

    @Test("WalletCreationError cases are exhaustively enumerable without a default branch")
    func walletCreationErrorCasesAreExhaustive() {
        // An exhaustive switch over WalletCreationError with no `default:` branch
        // will produce a compile error if any case is added or removed. This is
        // stronger than a runtime count check.
        let sample: WalletCreationError = .userCanceled
        switch sample {
        case .invalidUsername:
            break
        case .userCanceled:
            break
        case .webAuthnKeyFormatInvalid:
            break
        case .creationFailed:
            break
        }
        // Reaching here means the compiler accepted all four cases — no default
        // branch means any future case addition is a compile error in this test.
        #expect(Bool(true))
    }
}
