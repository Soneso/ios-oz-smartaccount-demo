// TransferTestSupport.swift
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
// MARK: - MockTransactionOperations
// ============================================================================

/// Configurable mock for `TransactionOperationsType`.
///
/// Controls return values via `result` and `error`. Records call parameters for assertions.
final class MockTransactionOperations: TransactionOperationsType, @unchecked Sendable {

    var result: OZTransactionResult?
    var error: Error?
    private(set) var callCount: Int = 0
    private(set) var lastTokenContract: String?
    private(set) var lastRecipient: String?
    private(set) var lastAmount: String?
    private(set) var lastDecimals: Int??

    func transfer(
        tokenContract: String,
        recipient: String,
        amount: String,
        decimals: Int?,
        forceMethod: OZSubmissionMethod?
    ) async throws -> OZTransactionResult {
        callCount += 1
        lastTokenContract = tokenContract
        lastRecipient = recipient
        lastAmount = amount
        lastDecimals = decimals
        if let error { throw error }
        guard let result else {
            preconditionFailure("MockTransactionOperations: neither result nor error configured")
        }
        return result
    }
}

// ============================================================================
// MARK: - MockMultiSignerManager
// ============================================================================

/// Configurable mock for `MultiSignerManagerType`.
final class MockMultiSignerManager: MultiSignerManagerType, @unchecked Sendable {

    var result: OZTransactionResult?
    var error: Error?
    /// Optional hook invoked (awaited) at the moment the SDK call runs, before
    /// returning `result` / throwing `error`. Lets tests capture the live
    /// registration state while the signing material is still registered inside
    /// the cleanup wrapper.
    var onCall: (@MainActor () async -> Void)?
    private(set) var callCount: Int = 0
    private(set) var lastTokenContract: String?
    private(set) var lastRecipient: String?
    private(set) var lastAmount: String?
    private(set) var lastDecimals: Int??
    private(set) var lastSelectedSigners: [OZSelectedSigner] = []

    // swiftlint:disable:next function_parameter_count
    func multiSignerTransfer(
        tokenContract: String,
        recipient: String,
        amount: String,
        decimals: Int?,
        selectedSigners: [OZSelectedSigner],
        forceMethod: OZSubmissionMethod?,
        resolveContextRuleIds: OZResolveContextRuleIds?
    ) async throws -> OZTransactionResult {
        callCount += 1
        lastTokenContract = tokenContract
        lastRecipient = recipient
        lastAmount = amount
        lastDecimals = decimals
        lastSelectedSigners = selectedSigners
        await onCall?()
        if let error { throw error }
        guard let result else {
            preconditionFailure("MockMultiSignerManager: neither result nor error configured")
        }
        return result
    }
}

// ============================================================================
// MARK: - MockContextRuleManager
// ============================================================================

/// Configurable mock for `ContextRuleManagerType`.
final class MockContextRuleManager: ContextRuleManagerType, @unchecked Sendable {

    var result: [OZParsedContextRule] = []
    var error: Error?
    private(set) var callCount: Int = 0

    func listContextRules() async throws -> [OZParsedContextRule] {
        callCount += 1
        if let error { throw error }
        return result
    }
}

// ============================================================================
// MARK: - MockMainScreenFlow
// ============================================================================

/// Configurable mock for `MainScreenFlowType`.
final class MockMainScreenFlow: MainScreenFlowType, @unchecked Sendable {

    private(set) var refreshCallCount: Int = 0

    func refreshBalances() async {
        refreshCallCount += 1
    }
}

// ============================================================================
// MARK: - MockWebAuthnCancelled
// ============================================================================

/// Simulates a typed WebAuthn user-cancellation error.
///
/// Used to test the `isUserCancellation` detection path without importing
/// WebAuthnException directly (which requires a real WebAuthn provider).
final class MockWebAuthnCancelledError: Error, LocalizedError, @unchecked Sendable {
    var errorDescription: String? { "The operation was cancelled by the user." }
}

// ============================================================================
// MARK: - MockNetworkError
// ============================================================================

struct MockTransferNetworkError: Error, LocalizedError, Sendable {
    let detail: String
    var errorDescription: String? { detail }
}

// ============================================================================
// MARK: - TransferFixtures
// ============================================================================

/// Shared fixture builders for `TransferFlow` tests.
@MainActor
enum TransferFixtures {

    // Canonical test addresses
    static let contractId = "CABC1234567890123456789012345678901234567890123456789012"
    static let credentialId = "dGVzdC1jcmVkZW50aWFsLWlkLWZpeHR1cmU"
    static let recipientG = "GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5"
    static let recipientC = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
    static let nativeTokenContract = DemoConfig.nativeTokenContract
    static let txHash = "deadbeef01020304deadbeef01020304deadbeef01020304deadbeef01020304"

    /// A successful `OZTransactionResult` from the SDK.
    static func successResult(hash: String = txHash) -> OZTransactionResult {
        OZTransactionResult(success: true, hash: hash, error: nil)
    }

    /// A failed `OZTransactionResult` from the SDK (success == false).
    static func failedResult(error: String = "Insufficient balance") -> OZTransactionResult {
        OZTransactionResult(success: false, hash: nil, error: error)
    }

    /// Builds a `DemoState` already connected.
    static func connectedState(
        contractId: String = Self.contractId,
        credentialId: String = Self.credentialId
    ) -> DemoState {
        let state = DemoState()
        state.setConnected(contractId: contractId, credentialId: credentialId, isDeployed: true)
        state.setXlmBalance("100.0")
        return state
    }

    /// Builds a `TransferFlow` with mock dependencies and a connected state.
    ///
    /// Returns a `MadeFlow` value grouping the flow, its state, and its log.
    static func makeFlow(
        txOps: MockTransactionOperations = MockTransactionOperations(),
        multiOps: MockMultiSignerManager = MockMultiSignerManager(),
        ctxOps: MockContextRuleManager = MockContextRuleManager(),
        mainFlow: MockMainScreenFlow = MockMainScreenFlow(),
        state: DemoState? = nil,
        log: ActivityLogState? = nil
    ) -> MadeFlow {
        let st = state ?? connectedState()
        let lg = log ?? ActivityLogState()
        let seam = DemoExternalSignersTestSupport.install(into: st)
        let flow = TransferFlow(
            demoState: st,
            activityLog: lg,
            transactionOperations: txOps,
            multiSignerManager: multiOps,
            contextRuleManager: ctxOps,
            mainScreenFlow: mainFlow
        )
        return MadeFlow(flow: flow, state: st, log: lg, signers: seam.manager, adapter: seam.adapter)
    }

    /// Builds a minimal `OZExternalSigner` that carries a WebAuthn credential ID
    /// matching `credentialId`.
    ///
    /// `credentialId` is treated as a Base64URL-encoded credential ID string (matching
    /// the format stored in `DemoState.credentialId`). The raw bytes decoded from it are
    /// appended after the 65-byte SEC1 public key so that
    /// `OZSmartAccountBuilders.getCredentialIdStringFromSigner` round-trips back to the
    /// same Base64URL string.
    ///
    /// Uses dummy verifier and key bytes; suitable only for signer-info tests.
    static func webAuthnSignerInfo(
        credentialId: String = Self.credentialId,
        connectedCredentialId: String? = Self.credentialId
    ) -> TransferSignerInfo {
        // Decode the Base64URL credential ID to raw bytes so that
        // OZSmartAccountBuilders.getCredentialIdStringFromSigner re-encodes them back
        // to the original string value.
        let credIdBytes: Data
        if let decoded = try? Data(base64URLEncoded: credentialId) {
            credIdBytes = decoded
        } else {
            credIdBytes = Data(credentialId.utf8)
        }

        // keyData = 65-byte uncompressed SEC1 public key + raw credential ID bytes
        var keyData = Data(count: 65)
        keyData[0] = 0x04
        keyData.append(credIdBytes)

        let verifier = "CAZJ3UVRY3R3S5C5BH32GMYBRSN23N75ZEEXEOLXOUUAHDFIMVP4AXUC"
        // swiftlint:disable:next force_try
        let signer = try! OZExternalSigner(verifierAddress: verifier, keyData: keyData)
        let matches = OZSmartAccountBuilders.signerMatchesCredentialId(
            signer: signer,
            credentialId: connectedCredentialId ?? ""
        )
        return TransferSignerInfo(signer: signer, canSign: matches)
    }

    /// Builds a `TransferSignerInfo` for a delegated Stellar account signer.
    static func delegatedSignerInfo(
        address: String = "GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5"
    ) -> TransferSignerInfo {
        // swiftlint:disable:next force_try
        let signer = try! OZDelegatedSigner(address: address)
        return TransferSignerInfo(signer: signer, canSign: false)
    }

    // MARK: - OZParsedContextRule fixtures

    /// Builds a `[OZParsedContextRule]` fixture containing one connected WebAuthn signer
    /// and one delegated Stellar account signer in a single default-type rule.
    ///
    /// Used to test `loadAvailableSigners` / `extractSigners` without hitting the network.
    static func contextRuleWithPasskeyAndDelegated(
        delegatedAddress: String = DemoExternalSignersTestSupport.delegatedAddress
    ) -> [OZParsedContextRule] {
        let passkeyInfo = webAuthnSignerInfo(
            credentialId: credentialId,
            connectedCredentialId: credentialId
        )
        let delegatedInfo = delegatedSignerInfo(address: delegatedAddress)
        let rule = OZParsedContextRule(
            id: 1,
            contextType: .defaultRule,
            name: "test-rule",
            signers: [passkeyInfo.signer, delegatedInfo.signer],
            signerIds: [0, 1],
            policies: [],
            policyIds: [],
            validUntil: nil
        )
        return [rule]
    }
}

// ============================================================================
// MARK: - MadeFlow
// ============================================================================

/// Groups the objects produced by `TransferFixtures.makeFlow(...)`.
///
/// Replaces the 3-tuple to satisfy SwiftLint's `large_tuple` rule.
@MainActor
struct MadeFlow {
    let flow: TransferFlow
    let state: DemoState
    let log: ActivityLogState
    /// Real external signer manager injected into `state`; assert registration /
    /// cleanup through its public surface.
    let signers: OZExternalSignerManager
    /// Real Ed25519 adapter wired into the manager and `state`.
    let adapter: DemoEd25519Adapter
}
