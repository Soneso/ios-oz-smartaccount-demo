// SignerPickerSheetTests.swift
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
// MARK: - TransferSignerInfo Model Tests
// ============================================================================

@Suite("TransferSignerInfo: Model")
@MainActor
struct TransferSignerInfoTests {

    @Test("id is signer uniqueKey")
    func idEqualsUniqueKey() {
        let info = TransferFixtures.webAuthnSignerInfo()
        #expect(info.id == info.signer.uniqueKey)
    }

    @Test("canSign is true for connected passkey signer")
    func canSignTrueForConnectedPasskey() {
        let info = TransferFixtures.webAuthnSignerInfo(
            credentialId: TransferFixtures.credentialId,
            connectedCredentialId: TransferFixtures.credentialId
        )
        #expect(info.canSign == true)
    }

    @Test("canSign is false for disconnected passkey signer")
    func canSignFalseForDisconnectedPasskey() {
        let info = TransferFixtures.webAuthnSignerInfo(
            credentialId: "differentCredentialId",
            connectedCredentialId: TransferFixtures.credentialId
        )
        #expect(info.canSign == false)
    }

    @Test("canSign is false for delegated signer with no registered keypair")
    func canSignFalseForUnregisteredDelegated() {
        let info = TransferFixtures.delegatedSignerInfo()
        #expect(info.canSign == false)
    }

    @Test("Passkey signer isExternalSigner returns true")
    func passkeySignerIsExternal() {
        let info = TransferFixtures.webAuthnSignerInfo()
        #expect(info.signer is OZExternalSigner)
    }

    @Test("Delegated signer isDelegatedSigner returns true")
    func delegatedSignerIsDelegated() {
        let info = TransferFixtures.delegatedSignerInfo()
        #expect(info.signer is OZDelegatedSigner)
    }
}

// ============================================================================
// MARK: - OZSmartAccountBuilders signer utilities
// ============================================================================

@Suite("OZSmartAccountBuilders: Signer Utilities")
@MainActor
struct SignerPickerOZBuildersTests {

    @Test("getCredentialIdStringFromSigner returns nil for delegated signer")
    func noCredentialIdForDelegated() {
        let info = TransferFixtures.delegatedSignerInfo()
        let result = OZSmartAccountBuilders.getCredentialIdStringFromSigner(signer: info.signer)
        #expect(result == nil)
    }

    @Test("getCredentialIdStringFromSigner returns non-nil for WebAuthn signer")
    func credentialIdForWebAuthnSigner() {
        let info = TransferFixtures.webAuthnSignerInfo()
        let result = OZSmartAccountBuilders.getCredentialIdStringFromSigner(signer: info.signer)
        #expect(result != nil)
    }

    @Test("signerMatchesCredentialId returns true for matching credential")
    func matchingCredentialIdReturnsTrue() {
        let info = TransferFixtures.webAuthnSignerInfo(
            credentialId: TransferFixtures.credentialId,
            connectedCredentialId: TransferFixtures.credentialId
        )
        let credIdStr = OZSmartAccountBuilders.getCredentialIdStringFromSigner(signer: info.signer) ?? ""
        let matches = OZSmartAccountBuilders.signerMatchesCredentialId(
            signer: info.signer,
            credentialId: credIdStr
        )
        #expect(matches == true)
    }

    @Test("collectUniqueSigners deduplicates identical signers")
    func deduplicatesSigners() {
        let info = TransferFixtures.webAuthnSignerInfo()
        let unique = OZSmartAccountBuilders.collectUniqueSigners(signers: [info.signer, info.signer])
        #expect(unique.count == 1)
    }

    @Test("collectUniqueSigners preserves order of first occurrence")
    func preservesInsertionOrder() {
        let info1 = TransferFixtures.webAuthnSignerInfo()
        let info2 = TransferFixtures.delegatedSignerInfo()
        let unique = OZSmartAccountBuilders.collectUniqueSigners(signers: [info1.signer, info2.signer, info1.signer])
        #expect(unique.count == 2)
        #expect(unique[0].uniqueKey == info1.signer.uniqueKey)
        #expect(unique[1].uniqueKey == info2.signer.uniqueKey)
    }
}

// ============================================================================
// MARK: - SignerPickerModel state machine
// ============================================================================

@Suite("SignerPickerModel: State Machine")
@MainActor
struct SignerPickerModelTests {

    // --- toggle gating ---

    @Test("Delegated row starts with disabled toggle and `.none` state")
    func delegatedRowStartsDisabled() throws {
        let pair = SignerPickerTestFixtures.delegatedKeypair()
        let info = try SignerPickerTestFixtures.delegatedInfo(address: pair.accountId)
        let model = SignerPickerModel(
            availableSigners: [info],
            connectedCredentialId: nil,
            walletConnector: nil
        )
        #expect(model.rows.count == 1)
        #expect(model.rows[0].auth == .none)
        #expect(model.toggleEnabled(at: 0) == false)
        #expect(model.rows[0].isSelected == false)
    }

    // --- secret-key path ---

    @Test("Verify with matching secret enables toggle and yields verified state")
    func verifyEnablesToggle() throws {
        let pair = SignerPickerTestFixtures.delegatedKeypair()
        let info = try SignerPickerTestFixtures.delegatedInfo(address: pair.accountId)
        let model = SignerPickerModel(
            availableSigners: [info],
            connectedCredentialId: nil,
            walletConnector: nil
        )
        let error = model.verifySecret(at: 0, secret: pair.secretSeed)
        #expect(error == nil)
        #expect(model.rows[0].auth == .keypairVerified)
        #expect(model.toggleEnabled(at: 0) == true)
        #expect(model.rows[0].isSelected == true)
        #expect(model.verifiedSecrets[pair.accountId] == pair.secretSeed)
    }

    @Test("Verify with mismatching address rejects and leaves state unchanged")
    func verifyMismatchRejects() throws {
        let row = SignerPickerTestFixtures.delegatedKeypair()
        let other = SignerPickerTestFixtures.delegatedKeypair()
        let info = try SignerPickerTestFixtures.delegatedInfo(address: row.accountId)
        let model = SignerPickerModel(
            availableSigners: [info],
            connectedCredentialId: nil,
            walletConnector: nil
        )
        let error = model.verifySecret(at: 0, secret: other.secretSeed)
        #expect(error != nil)
        #expect(model.rows[0].auth == .none)
        #expect(model.toggleEnabled(at: 0) == false)
        #expect(model.verifiedSecrets.isEmpty)
    }

    @Test("Verify with malformed secret returns inline error")
    func verifyMalformedRejects() throws {
        let pair = SignerPickerTestFixtures.delegatedKeypair()
        let info = try SignerPickerTestFixtures.delegatedInfo(address: pair.accountId)
        let model = SignerPickerModel(
            availableSigners: [info],
            connectedCredentialId: nil,
            walletConnector: nil
        )
        let error = model.verifySecret(at: 0, secret: "NOT-A-SECRET")
        #expect(error != nil)
        #expect(model.rows[0].auth == .none)
    }

    @Test("Clear key reverts a verified row to `.none`")
    func clearKeyReverts() throws {
        let pair = SignerPickerTestFixtures.delegatedKeypair()
        let info = try SignerPickerTestFixtures.delegatedInfo(address: pair.accountId)
        let model = SignerPickerModel(
            availableSigners: [info],
            connectedCredentialId: nil,
            walletConnector: nil
        )
        _ = model.verifySecret(at: 0, secret: pair.secretSeed)
        model.clearKey(at: 0)
        #expect(model.rows[0].auth == .none)
        #expect(model.rows[0].isSelected == false)
        #expect(model.verifiedSecrets[pair.accountId] == nil)
    }

    // --- wallet path ---

    @Test("Wallet connect with matching address transitions to `.walletConnected`")
    func walletConnectMatching() async throws {
        let pair = SignerPickerTestFixtures.delegatedKeypair()
        let info = try SignerPickerTestFixtures.delegatedInfo(address: pair.accountId)
        let connector = PickerMockWalletConnector(returnAddress: pair.accountId)
        let model = SignerPickerModel(
            availableSigners: [info],
            connectedCredentialId: nil,
            walletConnector: connector
        )
        await model.connectWallet(at: 0)
        #expect(model.rows[0].auth == .walletConnected)
        #expect(model.toggleEnabled(at: 0) == true)
        #expect(model.rows[0].isSelected == true)
        #expect(connector.connectCount == 1)
        #expect(connector.disconnectCount == 0)
    }

    @Test("Wallet connect with non-matching address yields `.walletError` and auto-disconnect")
    func walletConnectMismatch() async throws {
        let row = SignerPickerTestFixtures.delegatedKeypair()
        let other = SignerPickerTestFixtures.delegatedKeypair()
        let info = try SignerPickerTestFixtures.delegatedInfo(address: row.accountId)
        let connector = PickerMockWalletConnector(returnAddress: other.accountId)
        let model = SignerPickerModel(
            availableSigners: [info],
            connectedCredentialId: nil,
            walletConnector: connector
        )
        await model.connectWallet(at: 0)
        guard case .walletError = model.rows[0].auth else {
            Issue.record("Expected .walletError, got \(model.rows[0].auth)")
            return
        }
        #expect(model.toggleEnabled(at: 0) == false)
        #expect(model.rows[0].isSelected == false)
        #expect(connector.disconnectCount >= 1)
    }

    @Test("Wallet connect that throws yields `.walletError` without auto-disconnect")
    func walletConnectThrows() async throws {
        let pair = SignerPickerTestFixtures.delegatedKeypair()
        let info = try SignerPickerTestFixtures.delegatedInfo(address: pair.accountId)
        let connector = PickerMockWalletConnector(returnAddress: nil, throwOnConnect: .connectionTimeout)
        let model = SignerPickerModel(
            availableSigners: [info],
            connectedCredentialId: nil,
            walletConnector: connector
        )
        await model.connectWallet(at: 0)
        guard case .walletError = model.rows[0].auth else {
            Issue.record("Expected .walletError after throw, got \(model.rows[0].auth)")
            return
        }
        #expect(model.toggleEnabled(at: 0) == false)
        #expect(connector.disconnectCount == 0)
    }

    @Test("Wallet connect with no surfaced session resets to `.none`")
    func walletConnectSilentCancel() async throws {
        let pair = SignerPickerTestFixtures.delegatedKeypair()
        let info = try SignerPickerTestFixtures.delegatedInfo(address: pair.accountId)
        let connector = PickerMockWalletConnector(returnAddress: nil)
        let model = SignerPickerModel(
            availableSigners: [info],
            connectedCredentialId: nil,
            walletConnector: connector
        )
        await model.connectWallet(at: 0)
        #expect(model.rows[0].auth == .none)
        #expect(model.toggleEnabled(at: 0) == false)
    }

    @Test("Disconnect resets the row to `.none`")
    func walletDisconnect() async throws {
        let pair = SignerPickerTestFixtures.delegatedKeypair()
        let info = try SignerPickerTestFixtures.delegatedInfo(address: pair.accountId)
        let connector = PickerMockWalletConnector(returnAddress: pair.accountId)
        let model = SignerPickerModel(
            availableSigners: [info],
            connectedCredentialId: nil,
            walletConnector: connector
        )
        await model.connectWallet(at: 0)
        await model.disconnectWallet(at: 0)
        #expect(model.rows[0].auth == .none)
        #expect(model.rows[0].isSelected == false)
        #expect(connector.disconnectCount >= 1)
    }

    // --- single-wallet invariant ---

    @Test("Single-wallet invariant: any wallet active blocks other rows' connect")
    func singleWalletInvariant() async throws {
        let a = SignerPickerTestFixtures.delegatedKeypair()
        let b = SignerPickerTestFixtures.delegatedKeypair()
        let infoA = try SignerPickerTestFixtures.delegatedInfo(address: a.accountId)
        let infoB = try SignerPickerTestFixtures.delegatedInfo(address: b.accountId)
        let connector = PickerMockWalletConnector(returnAddress: a.accountId)
        let model = SignerPickerModel(
            availableSigners: [infoA, infoB],
            connectedCredentialId: nil,
            walletConnector: connector
        )
        await model.connectWallet(at: 0)
        #expect(model.anyWalletActive == true)
        #expect(model.isWalletActive(at: 0) == true)
        #expect(model.isWalletActive(at: 1) == false)
    }

    // --- dismiss / confirm wallet lifecycle ---

    @Test("Dismiss without confirm calls connector.disconnect")
    func dismissDisconnects() async throws {
        let pair = SignerPickerTestFixtures.delegatedKeypair()
        let info = try SignerPickerTestFixtures.delegatedInfo(address: pair.accountId)
        let connector = PickerMockWalletConnector(returnAddress: pair.accountId)
        let model = SignerPickerModel(
            availableSigners: [info],
            connectedCredentialId: nil,
            walletConnector: connector
        )
        await model.connectWallet(at: 0)
        let priorDisconnects = connector.disconnectCount
        await model.performDismissCleanup()
        #expect(connector.disconnectCount > priorDisconnects)
    }

    @Test("Confirm path preserves the wallet session (no disconnect on dismiss)")
    func confirmPreservesWallet() async throws {
        let pair = SignerPickerTestFixtures.delegatedKeypair()
        let info = try SignerPickerTestFixtures.delegatedInfo(address: pair.accountId)
        let connector = PickerMockWalletConnector(returnAddress: pair.accountId)
        let model = SignerPickerModel(
            availableSigners: [info],
            connectedCredentialId: nil,
            walletConnector: connector
        )
        await model.connectWallet(at: 0)
        let priorDisconnects = connector.disconnectCount
        _ = model.confirmSelection()
        await model.performDismissCleanup()
        #expect(connector.disconnectCount == priorDisconnects)
    }

    // --- confirm secrets contract ---

    @Test("Confirm with wallet-connected row omits the address from secrets map")
    func walletAddressOmittedFromSecrets() async throws {
        let walletRow = SignerPickerTestFixtures.delegatedKeypair()
        let keypairRow = SignerPickerTestFixtures.delegatedKeypair()
        let walletInfo = try SignerPickerTestFixtures.delegatedInfo(address: walletRow.accountId)
        let keypairInfo = try SignerPickerTestFixtures.delegatedInfo(address: keypairRow.accountId)
        let connector = PickerMockWalletConnector(returnAddress: walletRow.accountId)
        let model = SignerPickerModel(
            availableSigners: [walletInfo, keypairInfo],
            connectedCredentialId: nil,
            walletConnector: connector
        )
        await model.connectWallet(at: 0)
        _ = model.verifySecret(at: 1, secret: keypairRow.secretSeed)
        let result = model.confirmSelection()
        guard let result else {
            Issue.record("confirmSelection returned nil")
            return
        }
        #expect(result.delegatedSecrets[walletRow.accountId] == nil)
        #expect(result.delegatedSecrets[keypairRow.accountId] == keypairRow.secretSeed)
        #expect(result.chosenSigners.count == 2)
    }

    @Test("Confirm with no selection sets validation error and returns nil")
    func confirmEmptyFails() {
        let model = SignerPickerModel(
            availableSigners: [],
            connectedCredentialId: nil,
            walletConnector: nil
        )
        let result = model.confirmSelection()
        #expect(result == nil)
        #expect(model.validationError != nil)
    }

    // --- walletAvailable / NoOpWalletConnectorMarker ---

    @Test("walletAvailable is false when connector is nil")
    func walletAvailableNilConnector() {
        let model = SignerPickerModel(
            availableSigners: [],
            connectedCredentialId: nil,
            walletConnector: nil
        )
        #expect(model.walletAvailable == false)
    }

    @Test("walletAvailable is false for a NoOpWalletConnectorMarker")
    func walletAvailableNoOp() {
        let model = SignerPickerModel(
            availableSigners: [],
            connectedCredentialId: nil,
            walletConnector: NoOpWalletConnectorTestDouble()
        )
        #expect(model.walletAvailable == false)
    }

    @Test("walletAvailable is true for an active (non-marker) connector")
    func walletAvailableActive() {
        let model = SignerPickerModel(
            availableSigners: [],
            connectedCredentialId: nil,
            walletConnector: PickerMockWalletConnector(returnAddress: nil)
        )
        #expect(model.walletAvailable == true)
    }
}

// ============================================================================
// MARK: - Test helpers
// ============================================================================

/// Bundles a freshly-generated Stellar account for delegated-row tests.
struct DelegatedTestKeypair {
    let accountId: String
    let secretSeed: String
}

@MainActor
enum SignerPickerTestFixtures {

    /// Generates a random Ed25519 keypair and returns its G-address and S-seed.
    ///
    /// `KeyPair.generateRandomKeyPair()` always carries a private seed, so the
    /// optional `secretSeed` is force-unwrapped — failure here would indicate a
    /// regression in the SDK itself.
    static func delegatedKeypair() -> DelegatedTestKeypair {
        // swiftlint:disable force_try force_unwrapping
        let kp = try! KeyPair.generateRandomKeyPair()
        return DelegatedTestKeypair(accountId: kp.accountId, secretSeed: kp.secretSeed!)
        // swiftlint:enable force_try force_unwrapping
    }

    /// Builds a `TransferSignerInfo` wrapping an `OZDelegatedSigner` for the given address.
    static func delegatedInfo(address: String) throws -> TransferSignerInfo {
        let signer = try OZDelegatedSigner(address: address)
        return TransferSignerInfo(signer: signer, canSign: false)
    }
}

/// Configurable `WalletConnector` test double. Records call counts and lets
/// each test fix the address that `connect()` will surface (or throw a typed
/// error before any session is established).
final class PickerMockWalletConnector: WalletConnector, @unchecked Sendable {

    var returnAddress: String?
    var throwOnConnect: WalletConnectorError?

    private(set) var connectCount: Int = 0
    private(set) var disconnectCount: Int = 0

    var connectedAddress: String? { _connectedAddress }
    var walletMetadata: WalletMetadata? {
        guard _connectedAddress != nil else { return nil }
        return WalletMetadata(name: "Mock Wallet")
    }

    private var _connectedAddress: String?

    init(returnAddress: String?, throwOnConnect: WalletConnectorError? = nil) {
        self.returnAddress = returnAddress
        self.throwOnConnect = throwOnConnect
    }

    func connect() async throws {
        connectCount += 1
        if let error = throwOnConnect { throw error }
        _connectedAddress = returnAddress
    }

    func disconnect() async {
        disconnectCount += 1
        _connectedAddress = nil
    }

    func signAuthEntry(authEntryXdr: String, contextRuleIds: [UInt32]) async throws -> SignedAuthEntry {
        guard let address = _connectedAddress else {
            throw WalletConnectorError.noActiveSession
        }
        return SignedAuthEntry(signedAuthEntry: "mock-signature", signerAddress: address)
    }
}

/// `WalletConnector` test double that adopts `NoOpWalletConnectorMarker` so
/// `SignerPickerModel.walletAvailable` evaluates to `false`. Used to exercise
/// the macOS code path from shared tests without compiling the macOS-only
/// `NoOpWalletConnector` type on iOS test bundles.
final class NoOpWalletConnectorTestDouble: WalletConnector, NoOpWalletConnectorMarker, @unchecked Sendable {

    var connectedAddress: String? { nil }
    var walletMetadata: WalletMetadata? { nil }

    func connect() async throws {
        throw WalletConnectorError.notSupportedOnPlatform(reason: "test double")
    }

    func disconnect() async {}

    func signAuthEntry(authEntryXdr: String, contextRuleIds: [UInt32]) async throws -> SignedAuthEntry {
        throw WalletConnectorError.notSupportedOnPlatform(reason: "test double")
    }
}
