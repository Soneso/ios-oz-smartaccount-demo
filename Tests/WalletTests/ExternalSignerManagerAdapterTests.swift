// ExternalSignerManagerAdapterTests.swift
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
// MARK: - ExternalSignerManagerAdapterTests
// ============================================================================

/// Tests for routing logic in `ExternalSignerManagerAdapter`.
///
/// Uses a `MockWalletConnector` as a test double so tests run without network access,
/// passkey ceremonies, or a real WalletConnect relay. All tests exercise the adapter's
/// decision logic: routing and error paths.
///
/// Note: The `OZExternalSignerManager` SDK performs its own post-return signature
/// verification. The adapter's role is pure routing — it does not re-verify the
/// signature. Routing correctness is tested here; signature security is covered by
/// the SDK itself (see `SDKAdapterSmokeTest`).
@Suite("ExternalSignerManagerAdapter")
struct ExternalSignerManagerAdapterTests {

    // -------------------------------------------------------------------------
    // MARK: - Helpers
    // -------------------------------------------------------------------------

    /// A random test keypair generated at runtime. Every assertion derives the
    /// account id from this keypair, so no secret-seed literal is committed. The
    /// keypair is not a real account and has no value on any network.
    private func makeTestKeypair() throws -> KeyPair {
        return try KeyPair.generateRandomKeyPair()
    }

    /// Builds a minimal 32-byte preimage (all zeros) and returns it as base64.
    private func makeTestPreimageBase64() -> String {
        return Data(repeating: 0x00, count: 32).base64EncodedString()
    }

    // -------------------------------------------------------------------------
    // MARK: - Test 1: wallet path — routes to connector
    // -------------------------------------------------------------------------

    @Test("Routes to wallet connector when address matches connected wallet")
    func walletPathRoutes() async throws {
        // Arrange: mock connector reports a specific address as connected.
        let signerKeypair = try makeTestKeypair()
        let signerAddress = signerKeypair.accountId
        let preimageBase64 = makeTestPreimageBase64()

        // The mock returns a fixed 64-byte (all zeros) base64 string.
        // The real SDK manager will verify the signature — we only test that routing
        // reached the connector. Using a real signature so the adapter doesn't fail
        // on base64 decoding (the raw bytes do not matter for routing tests).
        let fakeSignature = Data(repeating: 0x00, count: 64).base64EncodedString()

        let mockConnector = MockWalletConnector(
            connectedAddress: signerAddress,
            responseToReturn: fakeSignature,
            shouldFail: false
        )

        let adapter = ExternalSignerManagerAdapter(walletConnector: mockConnector)
        adapter.setContextRuleIds([1, 2])

        // Act: sign via wallet path (no keypair registered for this address).
        let result = try await adapter.signAuthEntry(
            preimageXdr: preimageBase64,
            options: SignAuthEntryOptions(address: signerAddress)
        )

        // Assert: connector was called and the result is threaded through.
        #expect(mockConnector.signAuthEntryCalled)
        #expect(result.signedAuthEntry == fakeSignature)
        #expect(result.signerAddress == signerAddress)
    }

    // -------------------------------------------------------------------------
    // MARK: - Test 2: wallet path — connector rejection propagates
    // -------------------------------------------------------------------------

    @Test("Propagates WalletConnectorError when connector throws signingRejected")
    func walletPathRejectionPropagates() async throws {
        let signerKeypair = try makeTestKeypair()
        let signerAddress = signerKeypair.accountId

        let mockConnector = MockWalletConnector(
            connectedAddress: signerAddress,
            responseToReturn: "",
            shouldFail: true
        )
        let adapter = ExternalSignerManagerAdapter(walletConnector: mockConnector)
        adapter.setContextRuleIds([1])

        // Act + Assert: the connector's error must propagate.
        do {
            _ = try await adapter.signAuthEntry(
                preimageXdr: makeTestPreimageBase64(),
                options: SignAuthEntryOptions(address: signerAddress)
            )
            Issue.record("Expected connector rejection to be thrown")
        } catch let error as WalletConnectorError {
            if case .signingRejected = error {
                // Expected.
            } else {
                Issue.record("Expected signingRejected, got: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Test 3: neither wallet nor keypair matches — not found
    // -------------------------------------------------------------------------

    @Test("Throws signerNotFound when address has no wallet or keypair")
    func signerNotFound() async throws {
        // Arrange: connector is connected to a different address.
        let mockConnector = MockWalletConnector(
            connectedAddress: "GDIFFERENTADDRESS",
            responseToReturn: "",
            shouldFail: false
        )
        let adapter = ExternalSignerManagerAdapter(walletConnector: mockConnector)

        // Act: request signing for an address not covered by wallet or keypairs.
        do {
            _ = try await adapter.signAuthEntry(
                preimageXdr: makeTestPreimageBase64(),
                options: SignAuthEntryOptions(address: "GUNKNOWNADDRESS")
            )
            Issue.record("Expected signerNotFound to be thrown")
        } catch let error as AdapterError {
            if case .signerNotFound = error {
                // Expected.
            } else {
                Issue.record("Expected signerNotFound, got: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - canSignFor
    // -------------------------------------------------------------------------

    @Test("canSignFor returns true for connected wallet address")
    func canSignForWallet() {
        let connector = MockWalletConnector(
            connectedAddress: "GWALLET",
            responseToReturn: "",
            shouldFail: false
        )
        let adapter = ExternalSignerManagerAdapter(walletConnector: connector)
        #expect(adapter.canSignFor(address: "GWALLET"))
    }

    @Test("canSignFor returns false for unknown address")
    func canSignForUnknown() {
        let adapter = ExternalSignerManagerAdapter(walletConnector: nil)
        #expect(!adapter.canSignFor(address: "GUNKNOWN"))
    }

    // -------------------------------------------------------------------------
    // MARK: - getConnectedWallets
    // -------------------------------------------------------------------------

    @Test("getConnectedWallets returns wallet info when connector is active")
    func getConnectedWalletsActive() {
        let connector = MockWalletConnector(
            connectedAddress: "GWALLET",
            responseToReturn: "",
            shouldFail: false,
            walletMeta: WalletMetadata(name: "TestWallet")
        )
        let adapter = ExternalSignerManagerAdapter(walletConnector: connector)
        let wallets = adapter.getConnectedWallets()
        #expect(wallets.count == 1)
        #expect(wallets.first?.address == "GWALLET")
        #expect(wallets.first?.walletName == "TestWallet")
    }

    @Test("getConnectedWallets returns empty when no connector")
    func getConnectedWalletsEmpty() {
        let adapter = ExternalSignerManagerAdapter(walletConnector: nil)
        #expect(adapter.getConnectedWallets().isEmpty)
    }
}

// ============================================================================
// MARK: - MockWalletConnector
// ============================================================================

/// Test double for `WalletConnector`.
///
/// Configurable at construction time to control the address it reports as connected,
/// the signature it returns from `signAuthEntry`, and whether it throws.
private final class MockWalletConnector: WalletConnector, @unchecked Sendable {

    let connectedAddress: String?
    let walletMetadata: WalletMetadata?

    private let responseToReturn: String
    private let shouldFail: Bool

    /// True after `signAuthEntry` was called at least once.
    private(set) var signAuthEntryCalled = false

    init(
        connectedAddress: String?,
        responseToReturn: String,
        shouldFail: Bool,
        walletMeta: WalletMetadata? = nil
    ) {
        self.connectedAddress = connectedAddress
        self.responseToReturn = responseToReturn
        self.shouldFail = shouldFail
        self.walletMetadata = walletMeta ?? (connectedAddress.map { WalletMetadata(name: "Mock:\($0)") })
    }

    func connect() async throws {}

    func disconnect() async {}

    func signAuthEntry(authEntryXdr: String, contextRuleIds: [UInt32]) async throws -> SignedAuthEntry {
        signAuthEntryCalled = true
        if shouldFail {
            throw WalletConnectorError.signingRejected(reason: "Test rejection")
        }
        return SignedAuthEntry(
            signedAuthEntry: responseToReturn,
            signerAddress: connectedAddress ?? ""
        )
    }
}
