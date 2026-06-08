// WalletCreationTestSupport.swift
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
// MARK: - Mock: MockWalletOperations
// ============================================================================

/// Configurable mock for `WalletOperationsType`.
///
/// All test control is through `result` and `error`. Records the parameters
/// it was called with so tests can assert on them.
final class MockWalletOperations: WalletOperationsType, @unchecked Sendable {

    var result: OZCreateWalletResult?
    var error: Error?
    private(set) var lastUserName: String?
    private(set) var lastAutoSubmit: Bool?
    private(set) var lastAutoFund: Bool?
    private(set) var lastNativeTokenContract: String?
    private(set) var callCount: Int = 0

    func createWallet(
        userName: String,
        autoSubmit: Bool,
        autoFund: Bool,
        nativeTokenContract: String?
    ) async throws -> OZCreateWalletResult {
        callCount += 1
        lastUserName = userName
        lastAutoSubmit = autoSubmit
        lastAutoFund = autoFund
        lastNativeTokenContract = nativeTokenContract
        if let error { throw error }
        guard let result else {
            preconditionFailure("MockWalletOperations: neither result nor error configured")
        }
        return result
    }
}

// ============================================================================
// MARK: - Mock: MockDemoTokenService
// ============================================================================

/// Configurable mock for `DemoTokenServiceType`.
final class MockDemoTokenService: DemoTokenServiceType, @unchecked Sendable {

    var result: DemoTokenResult?
    var error: Error?
    private(set) var lastRecipientContractId: String?
    private(set) var callCount: Int = 0

    func ensureTokenAndMint(recipientContractId: String) async throws -> DemoTokenResult {
        callCount += 1
        lastRecipientContractId = recipientContractId
        if let error { throw error }
        guard let result else {
            preconditionFailure("MockDemoTokenService: neither result nor error configured")
        }
        return result
    }
}

// ============================================================================
// MARK: - Mock: MockSlowWalletOperations
// ============================================================================

/// A wallet operations mock that suspends for `delay` seconds before returning.
///
/// Used to verify re-entrancy guard behaviour: a second `createWallet(...)` call
/// issued while the first is suspended must receive `.creationFailed` immediately
/// without waiting for the slow mock to complete.
final class MockSlowWalletOperations: WalletOperationsType, @unchecked Sendable {

    var result: OZCreateWalletResult?
    var error: Error?
    private let delay: TimeInterval

    init(delay: TimeInterval) {
        self.delay = delay
    }

    func createWallet(
        userName: String,
        autoSubmit: Bool,
        autoFund: Bool,
        nativeTokenContract: String?
    ) async throws -> OZCreateWalletResult {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        if let error { throw error }
        guard let result else {
            preconditionFailure("MockSlowWalletOperations: neither result nor error configured")
        }
        return result
    }
}

// ============================================================================
// MARK: - Test Error Stubs
// ============================================================================

struct MockCancelledError: Error, LocalizedError {
    var errorDescription: String? { "The operation was cancelled by the user." }
}

struct MockNetworkError: Error, LocalizedError {
    var errorDescription: String? { "Network unreachable: connection timeout." }
}

// ============================================================================
// MARK: - WalletCreationFixtures
// ============================================================================

/// Shared test-fixture builders for wallet creation tests.
@MainActor
enum WalletCreationFixtures {

    static let defaultContractId = "CABC1234567890123456789012345678901234567890123456789012"
    static let defaultCredentialId = "dGVzdC1jcmVkZW50aWFsLWlkLWZpeHR1cmU"
    static let tokenContractId = "CDEMOTOKEN123456789012345678901234567890123456789012345"

    /// A valid 65-byte secp256r1 uncompressed key (0x04 prefix + 64 zero bytes).
    static var validPublicKey: Data {
        var key = Data(count: 65)
        key[0] = 0x04
        return key
    }

    /// Returns a `OZCreateWalletResult` with a valid secp256r1 public key.
    static func validSdkResult(
        contractId: String = defaultContractId,
        credentialId: String = defaultCredentialId,
        deployed: Bool = true
    ) -> OZCreateWalletResult {
        OZCreateWalletResult(
            credentialId: credentialId,
            contractId: contractId,
            publicKey: validPublicKey,
            signedTransactionXdr: "placeholder_xdr",
            transactionHash: deployed ? "abc123txhash" : nil
        )
    }

    /// Returns a `OZCreateWalletResult` whose 32-byte key fails the secp256r1 check.
    static func invalidKeyResult() -> OZCreateWalletResult {
        OZCreateWalletResult(
            credentialId: defaultCredentialId,
            contractId: defaultContractId,
            publicKey: Data(count: 32),
            signedTransactionXdr: "placeholder_xdr",
            transactionHash: nil
        )
    }

    /// Returns a `OZCreateWalletResult` with a 65-byte key starting with 0x02.
    static func wrongPrefixKeyResult() -> OZCreateWalletResult {
        var badKey = Data(count: 65)
        badKey[0] = 0x02
        return OZCreateWalletResult(
            credentialId: defaultCredentialId,
            contractId: defaultContractId,
            publicKey: badKey,
            signedTransactionXdr: "placeholder_xdr",
            transactionHash: nil
        )
    }

    /// Builds a `WalletCreationFlow` (without associated state/log references).
    static func makeFlow(
        walletOps: any WalletOperationsType,
        tokenService: MockDemoTokenService? = nil
    ) -> WalletCreationFlow {
        WalletCreationFlow(
            demoState: DemoState(),
            activityLog: ActivityLogState(),
            walletOperations: walletOps,
            demoTokenService: tokenService
        )
    }

    /// Builds a flow along with its DemoState and ActivityLogState for inspection.
    static func makeFlowWithDeps(
        walletOps: any WalletOperationsType,
        tokenService: MockDemoTokenService? = nil
    ) -> FlowTestDeps {
        let state = DemoState()
        let log = ActivityLogState()
        let flow = WalletCreationFlow(
            demoState: state,
            activityLog: log,
            walletOperations: walletOps,
            demoTokenService: tokenService
        )
        return FlowTestDeps(flow: flow, state: state, log: log)
    }
}

/// Dependencies returned by `WalletCreationFixtures.makeFlowWithDeps`.
struct FlowTestDeps {
    let flow: WalletCreationFlow
    let state: DemoState
    let log: ActivityLogState
}
