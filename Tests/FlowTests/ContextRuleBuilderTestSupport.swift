// ContextRuleBuilderTestSupport.swift
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
// MARK: - MockLatestLedgerSource
// ============================================================================

/// In-memory `LatestLedgerSource` used by the builder tests.
final class MockLatestLedgerSource: LatestLedgerSource, @unchecked Sendable {

    var nextSequence: UInt32 = 0
    var error: Error?
    private(set) var callCount: Int = 0

    func latestLedgerSequence() async throws -> UInt32 {
        callCount += 1
        if let error { throw error }
        return nextSequence
    }
}

// ============================================================================
// MARK: - MockWebAuthnProvider
// ============================================================================

/// Configurable `WebAuthnProvider` mock that returns a deterministic
/// registration result and records call counts so add-rule tests can assert
/// that registration is invoked.
final class MockWebAuthnProvider: WebAuthnProvider, @unchecked Sendable {

    var registrationResult: WebAuthnRegistrationResult?
    var registrationError: Error?
    private(set) var registerCallCount: Int = 0
    private(set) var lastUserName: String?

    func register(
        challenge: Data,
        userId: Data,
        userName: String
    ) async throws -> WebAuthnRegistrationResult {
        registerCallCount += 1
        lastUserName = userName
        if let registrationError { throw registrationError }
        if let registrationResult { return registrationResult }
        return Self.defaultRegistration()
    }

    func authenticate(
        challenge: Data,
        allowCredentials: [WebAuthnAllowCredential]?
    ) async throws -> WebAuthnAuthenticationResult {
        throw WebAuthnException.NotSupported(
            message: "Authenticate not used in builder tests"
        )
    }

    private static func defaultRegistration() -> WebAuthnRegistrationResult {
        var publicKey = Data(repeating: 0, count: 65)
        publicKey[0] = 0x04
        for index in 1..<65 {
            publicKey[index] = UInt8(index)
        }
        return WebAuthnRegistrationResult(
            credentialId: Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]),
            publicKey: publicKey,
            attestationObject: Data(),
            transports: [],
            deviceType: "singleDevice",
            backedUp: false
        )
    }
}

// ============================================================================
// MARK: - MockContextRuleManagerWithAdd
// ============================================================================

/// Configurable mock for `ContextRuleManagerFullType` that captures the
/// `addContextRule` invocation parameters so create-mode tests can verify
/// the SDK is called with the expected arguments.
final class MockContextRuleManagerWithAdd: ContextRuleManagerFullType, @unchecked Sendable {

    var listResult: [OZParsedContextRule] = []
    var listError: Error?
    private(set) var listCallCount: Int = 0

    var removeResult: OZTransactionResult?
    var removeError: Error?
    private(set) var removeCallCount: Int = 0

    var countResult: UInt32 = 0
    var countError: Error?

    var addResult: OZTransactionResult?
    var addError: Error?
    private(set) var addCallCount: Int = 0
    private(set) var lastAddContextType: OZContextRuleType?
    private(set) var lastAddName: String?
    private(set) var lastAddValidUntil: UInt32?
    private(set) var lastAddSigners: [any OZSmartAccountSigner] = []
    private(set) var lastAddPolicies: [String: SCValXDR] = [:]
    private(set) var lastAddSelectedSigners: [OZSelectedSigner] = []

    /// Optional hook invoked (awaited) at the moment `addContextRule` runs, used
    /// to capture whether a delegated keypair is registered on the real manager
    /// while the SDK call is in flight (i.e. inside the cleanup wrapper). Its
    /// return value is recorded in ``lastCanSignDuringAdd``.
    var onAddContextRule: (@MainActor () async -> Bool)?

    /// The value returned by ``onAddContextRule`` on the most recent
    /// `addContextRule` invocation.
    private(set) var lastCanSignDuringAdd: Bool?

    func listContextRules() async throws -> [OZParsedContextRule] {
        listCallCount += 1
        if let listError { throw listError }
        return listResult
    }

    func removeContextRule(
        ruleId: UInt32,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        removeCallCount += 1
        if let removeError { throw removeError }
        guard let removeResult else {
            preconditionFailure("removeResult not configured")
        }
        return removeResult
    }

    func getContextRulesCount() async throws -> UInt32 {
        if let countError { throw countError }
        return countResult
    }

    // swiftlint:disable function_parameter_count
    func addContextRule(
        contextType: OZContextRuleType,
        name: String,
        validUntil: UInt32?,
        signers: [any OZSmartAccountSigner],
        policies: [String: SCValXDR],
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        addCallCount += 1
        lastAddContextType = contextType
        lastAddName = name
        lastAddValidUntil = validUntil
        lastAddSigners = signers
        lastAddPolicies = policies
        lastAddSelectedSigners = selectedSigners
        if let onAddContextRule {
            lastCanSignDuringAdd = await onAddContextRule()
        }
        if let addError { throw addError }
        guard let addResult else {
            preconditionFailure("addResult not configured")
        }
        return addResult
    }
    // swiftlint:enable function_parameter_count

    // Stub edit-mode protocol methods — these mocks are reused only by the
    // 7b-create tests, which never exercise the edit dispatch path. Returning
    // a generic success keeps them satisfied for the compiler.
    private static func successTx(_ tag: String) -> OZTransactionResult {
        OZTransactionResult(success: true, hash: "addmock-\(tag)", error: nil)
    }

    func updateContextRuleName(
        ruleId: UInt32,
        newName: String,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        return Self.successTx("updateName")
    }

    func updateContextRuleValidUntil(
        ruleId: UInt32,
        newValidUntil: UInt32?,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        return Self.successTx("updateValidUntil")
    }

    func addDelegatedSignerToRule(
        ruleId: UInt32,
        address: String,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        return Self.successTx("addDelegated")
    }

    func addEd25519SignerToRule(
        ruleId: UInt32,
        verifierAddress: String,
        publicKey: Data,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        return Self.successTx("addEd25519")
    }

    func addPasskeySignerToRule(
        ruleId: UInt32,
        publicKey: Data,
        credentialId: Data,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        return Self.successTx("addPasskey")
    }

    func removeSignerFromRule(
        ruleId: UInt32,
        signerId: UInt32,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        return Self.successTx("removeSigner")
    }

    func addSimpleThresholdToRule(
        ruleId: UInt32,
        policyAddress: String,
        threshold: UInt32,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        return Self.successTx("addSimpleThreshold")
    }

    func addWeightedThresholdToRule(
        ruleId: UInt32,
        policyAddress: String,
        entries: [PolicyWeightedEntry],
        threshold: UInt32,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        return Self.successTx("addWeightedThreshold")
    }

    func addSpendingLimitToRule(
        ruleId: UInt32,
        policyAddress: String,
        amount: String,
        decimals: Int,
        periodLedgers: UInt32,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        return Self.successTx("addSpendingLimit")
    }

    func removePolicyFromRule(
        ruleId: UInt32,
        policyId: UInt32,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        return Self.successTx("removePolicy")
    }

    func getContextRuleRaw(ruleId: UInt32) async throws -> SCValXDR {
        return .void
    }
}

// ============================================================================
// MARK: - BuilderFixtures
// ============================================================================

@MainActor
enum BuilderFixtures {

    static let verifier = ContextRuleFixtures.verifier
    static let webauthnVerifier = "CB26VN37RCVNTHJZDEPK6IRO2MMTS3Z2IEO5JD5BINY2OOJ5KKJG7NKY"

    /// Builds a fully-configured `ContextRuleFlow` with mock dependencies for
    /// the builder test suite.
    static func makeFlow(
        manager: MockContextRuleManagerWithAdd = MockContextRuleManagerWithAdd(),
        ledger: MockLatestLedgerSource = MockLatestLedgerSource(),
        provider: MockWebAuthnProvider = MockWebAuthnProvider(),
        state: DemoState? = nil,
        log: ActivityLogState? = nil,
        verifierAddress: String = Self.webauthnVerifier
    ) -> MadeBuilderFlow {
        let st = state ?? ContextRuleFixtures.connectedState()
        let lg = log ?? ActivityLogState()
        let seam = DemoExternalSignersTestSupport.install(into: st)
        let flow = ContextRuleFlow(
            demoState: st,
            activityLog: lg,
            contextRuleManager: manager,
            webAuthnProvider: provider,
            webAuthnVerifierAddress: verifierAddress,
            ledgerSource: ledger
        )
        return MadeBuilderFlow(
            flow: flow,
            state: st,
            log: lg,
            manager: manager,
            signers: seam.manager,
            adapter: seam.adapter,
            ledger: ledger,
            provider: provider
        )
    }

    /// Builds an `OZExternalSigner` for use as a passkey signer with the
    /// configured WebAuthn verifier so reuse / dedupe tests behave the same
    /// way as production.
    static func passkeySigner(
        credId: String = "passkeyA",
        verifier: String = Self.webauthnVerifier
    ) -> OZExternalSigner {
        let credBytes: Data = {
            if let decoded = try? Data(base64URLEncoded: credId), !decoded.isEmpty {
                return decoded
            }
            return Data(credId.utf8)
        }()
        var keyData = Data(count: 65)
        keyData[0] = 0x04
        keyData.append(credBytes)
        // swiftlint:disable:next force_try
        return try! OZExternalSigner(verifierAddress: verifier, keyData: keyData)
    }

    static func successTx(hash: String = ContextRuleFixtures.txHash) -> OZTransactionResult {
        OZTransactionResult(success: true, hash: hash, error: nil)
    }

    static func failedTx(error: String = "submit failed") -> OZTransactionResult {
        OZTransactionResult(success: false, hash: nil, error: error)
    }
}

@MainActor
struct MadeBuilderFlow {
    let flow: ContextRuleFlow
    let state: DemoState
    let log: ActivityLogState
    let manager: MockContextRuleManagerWithAdd
    /// Real external signer manager injected into `state`.
    let signers: OZExternalSignerManager
    /// Real Ed25519 adapter wired into the manager and `state`.
    let adapter: DemoEd25519Adapter
    let ledger: MockLatestLedgerSource
    let provider: MockWebAuthnProvider
}
