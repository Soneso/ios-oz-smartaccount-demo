// SDKAdapterSmokeTest.swift
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
// MARK: - SDKAdapterSmokeTest
// ============================================================================

/// End-to-end smoke test proving that `ExternalSignerManagerAdapter` survives contact
/// with the real `OZExternalSignerManager` SDK contract.
///
/// This test constructs a real `OZExternalSignerManager` (from the SDK), wires it with
/// an `ExternalSignerManagerAdapter` containing a `MockWalletConnector`, then drives a
/// full signing round-trip through the manager:
///
///   OZExternalSignerManager.signAuthEntry
///     → ExternalSignerManagerAdapter.signAuthEntry  (ExternalWalletAdapter)
///     → MockWalletConnector.signAuthEntry           (WalletConnector)
///     → OZExternalSignerManager verifyExternalWalletSignature
///     → SignAuthEntryResult
///
/// If this test fails, the SDK contract has drifted and the mismatch must be
/// diagnosed and addressed before merging.
@Suite("SDKAdapterSmokeTest")
struct SDKAdapterSmokeTest {

    // -------------------------------------------------------------------------
    // MARK: - Fixtures
    // -------------------------------------------------------------------------

    /// A random test keypair generated at runtime. Used both as the "wallet
    /// signer" and to produce a valid signature for the smoke test, so no
    /// secret-seed literal is committed.
    private func makeTestKeypair() throws -> KeyPair {
        return try KeyPair.generateRandomKeyPair()
    }

    /// Returns a 32-byte preimage as base64. Represents a `HashIDPreimage` XDR in tests.
    private func makePreimageBase64() -> String {
        return Data(repeating: 0xAB, count: 32).base64EncodedString()
    }

    /// Signs SHA-256(preimageBytes) with the keypair; returns raw 64-byte sig as base64.
    ///
    /// The `OZExternalSignerManager.verifyExternalWalletSignature` verifies the wallet
    /// adapter's returned signature against `SHA-256(preimage)`, so the mock wallet
    /// must produce a signature over that payload to pass the SDK's built-in check.
    private func buildValidSignature(preimageBase64: String, keypair: KeyPair) -> String? {
        guard let preimageBytes = Data(base64Encoded: preimageBase64) else { return nil }
        let hash = preimageBytes.sha256Hash
        let signatureBytes = keypair.sign([UInt8](hash))
        return Data(signatureBytes).base64EncodedString()
    }

    // -------------------------------------------------------------------------
    // MARK: - Smoke test 1: keypair path through OZExternalSignerManager
    // -------------------------------------------------------------------------

    @Test("OZExternalSignerManager.signAuthEntry routes through adapter to keypair signer")
    func smokeTestKeypairPath() async throws {
        let keypair = try makeTestKeypair()
        let preimageBase64 = makePreimageBase64()

        // Build the adapter with no wallet connector — keypair path only.
        guard let secretSeed = keypair.secretSeed else {
            Issue.record("Test keypair has no secret seed")
            return
        }
        let adapter = ExternalSignerManagerAdapter(walletConnector: nil)
        let registeredAddress = keypair.accountId

        // Wire a real OZExternalSignerManager from the SDK.
        let manager = OZExternalSignerManager(
            networkPassphrase: DemoConfig.networkPassphrase,
            walletAdapter: adapter
        )

        // Register the keypair signer directly in the manager (so it can sign for the address).
        let managerAddress = try await manager.addFromSecret(secretKey: secretSeed)
        #expect(managerAddress == registeredAddress)

        // Drive a full signing round-trip.
        let result = try await manager.signAuthEntry(
            address: registeredAddress,
            authEntry: preimageBase64
        )

        // Verify the result: 64-byte signature, correct signer address.
        guard let sigBytes = Data(base64Encoded: result.signedAuthEntry) else {
            Issue.record("signedAuthEntry is not valid base64")
            return
        }
        #expect(sigBytes.count == 64)
        #expect(result.signerAddress == registeredAddress)

        // Cross-check that the returned signature is cryptographically valid.
        // The manager's internal keypair path signs SHA-256(preimage).
        guard let preimageBytes = Data(base64Encoded: preimageBase64) else {
            Issue.record("Preimage base64 is not valid")
            return
        }
        let hash = preimageBytes.sha256Hash
        let pubKeyPair = try KeyPair(accountId: registeredAddress)
        let valid = try pubKeyPair.verify(signature: [UInt8](sigBytes), message: [UInt8](hash))
        #expect(valid, "The returned signature must verify against the preimage hash")
    }

    // -------------------------------------------------------------------------
    // MARK: - Smoke test 2: wallet path through OZExternalSignerManager
    // -------------------------------------------------------------------------

    @Test("OZExternalSignerManager.signAuthEntry routes through adapter to wallet connector")
    func smokeTestWalletPath() async throws {
        let signerKeypair = try makeTestKeypair()
        let signerAddress = signerKeypair.accountId
        let preimageBase64 = makePreimageBase64()

        // Pre-compute a valid signature that the mock wallet will return.
        // The SDK manager verifies the returned signature against SHA-256(preimage) via
        // verifyExternalWalletSignature. The mock wallet must produce a signature over
        // that exact payload to pass the SDK's built-in check.
        guard let validSignature = buildValidSignature(
            preimageBase64: preimageBase64,
            keypair: signerKeypair
        ) else {
            Issue.record("Could not build valid signature from preimage")
            return
        }

        let mockConnector = SmokeTestMockWalletConnector(
            address: signerAddress,
            signatureToReturn: validSignature
        )
        let adapter = ExternalSignerManagerAdapter(walletConnector: mockConnector)
        adapter.setContextRuleIds([])

        // Wire the real OZExternalSignerManager with the adapter as walletAdapter.
        let manager = OZExternalSignerManager(
            networkPassphrase: DemoConfig.networkPassphrase,
            walletAdapter: adapter
        )

        // Drive the full round-trip through the manager.
        let result = try await manager.signAuthEntry(
            address: signerAddress,
            authEntry: preimageBase64
        )

        // Verify: the mock was called and the result is correctly threaded through.
        #expect(mockConnector.wasSignCalled)
        #expect(result.signerAddress == signerAddress)

        // The SDK's verifyExternalWalletSignature passed — the result is trusted.
        guard let sigBytes = Data(base64Encoded: result.signedAuthEntry) else {
            Issue.record("signedAuthEntry is not valid base64")
            return
        }
        #expect(sigBytes.count == 64)
    }

    // -------------------------------------------------------------------------
    // MARK: - Smoke test 3: wrong-payload rejection
    // -------------------------------------------------------------------------

    /// Proves that `OZExternalSignerManager.verifyExternalWalletSignature` rejects a wallet
    /// that returns a valid Ed25519 signature but over the WRONG preimage.
    ///
    /// Security guarantee: a compromised or malicious wallet that signs a different payload
    /// (e.g. "attacker-bytes") and returns that signature for an unrelated auth entry will
    /// fail the SDK's verify gate before the signed entry is ever used. The adapter cannot
    /// suppress this check because it lives inside `OZExternalSignerManager.signAuthEntry`.
    @Test("OZExternalSignerManager.signAuthEntry rejects wallet signature over wrong preimage")
    func smokeTestWrongPayloadRejected() async throws {
        let signerKeypair = try makeTestKeypair()
        let signerAddress = signerKeypair.accountId

        // The legitimate preimage the caller will present to the manager.
        let legitimatePreimageBase64 = makePreimageBase64()

        // The attacker's preimage — different bytes. The mock wallet will sign THIS
        // instead of the legitimate preimage, simulating a wallet that signed the
        // wrong payload (or a replay of a different signing request).
        let attackerPreimage = Data("attacker-bytes".utf8)
        let attackerHash = attackerPreimage.sha256Hash
        let attackerSignatureBytes = signerKeypair.sign([UInt8](attackerHash))
        let attackerSignatureBase64 = Data(attackerSignatureBytes).base64EncodedString()

        // The mock connector returns the signature over the WRONG payload.
        let mockConnector = SmokeTestMockWalletConnector(
            address: signerAddress,
            signatureToReturn: attackerSignatureBase64
        )
        let adapter = ExternalSignerManagerAdapter(walletConnector: mockConnector)
        adapter.setContextRuleIds([])

        let manager = OZExternalSignerManager(
            networkPassphrase: DemoConfig.networkPassphrase,
            walletAdapter: adapter
        )

        // The SDK's verifyExternalWalletSignature must catch this and throw SigningFailed.
        do {
            _ = try await manager.signAuthEntry(
                address: signerAddress,
                authEntry: legitimatePreimageBase64
            )
            Issue.record(
                "Expected SmartAccountTransactionException.SigningFailed but signAuthEntry returned successfully"
            )
        } catch let error as SmartAccountTransactionException.SigningFailed {
            // Expected: SDK verify gate caught the wrong-payload signature.
            #expect(!error.localizedDescription.isEmpty)
        } catch {
            Issue.record(
                "Expected SmartAccountTransactionException.SigningFailed but got \(type(of: error)): \(error)"
            )
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Smoke test 5: canSignFor routing
    // -------------------------------------------------------------------------

    @Test("OZExternalSignerManager.canSignFor reflects adapter state")
    func smokeTestCanSignFor() async throws {
        let keypair = try makeTestKeypair()
        guard let secretSeed = keypair.secretSeed else {
            Issue.record("Test keypair has no secret seed")
            return
        }
        let adapter = ExternalSignerManagerAdapter(walletConnector: nil)

        let manager = OZExternalSignerManager(
            networkPassphrase: DemoConfig.networkPassphrase,
            walletAdapter: adapter
        )

        let unknownAddress = "GABC123"
        #expect(await manager.canSignFor(address: unknownAddress) == false)

        // Register the keypair in the manager (it has its own internal store).
        let address = try await manager.addFromSecret(secretKey: secretSeed)
        #expect(await manager.canSignFor(address: address) == true)
    }
}

// ============================================================================
// MARK: - SmokeTestMockWalletConnector
// ============================================================================

/// Mock wallet connector for the SDK adapter smoke test.
///
/// Returns a pre-configured signature without any real wallet interaction. Tracks
/// whether `signAuthEntry` was called to verify routing from the SDK manager.
private final class SmokeTestMockWalletConnector: WalletConnector, @unchecked Sendable {

    let connectedAddress: String?
    let walletMetadata: WalletMetadata?

    private let signatureToReturn: String
    private(set) var wasSignCalled = false

    init(address: String, signatureToReturn: String) {
        self.connectedAddress = address
        self.walletMetadata = WalletMetadata(name: "SmokeTestWallet")
        self.signatureToReturn = signatureToReturn
    }

    func connect() async throws {}
    func disconnect() async {}

    func signAuthEntry(authEntryXdr: String, contextRuleIds: [UInt32]) async throws -> SignedAuthEntry {
        wasSignCalled = true
        return SignedAuthEntry(
            signedAuthEntry: signatureToReturn,
            signerAddress: connectedAddress ?? ""
        )
    }
}
