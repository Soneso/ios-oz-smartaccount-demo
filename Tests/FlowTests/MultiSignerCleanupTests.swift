// MultiSignerCleanupTests.swift
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
// MARK: - DemoEd25519Adapter direct tests
// ============================================================================

/// Direct, executing assertions that the Ed25519 adapter custody path is
/// distinguishable at runtime from the in-process path.
///
/// These give the adapter-vs-in-process split an executing assertion rather than
/// inspection-only: a key added via the adapter's `add(_:seedBytes:)` makes the
/// manager's `canSignEd25519For` (and the adapter's own `canSignFor`) report
/// `true`; an in-process key registered via `addEd25519FromRawKey` is absent from
/// the adapter, so the adapter reports `false` for it.
@Suite("DemoEd25519Adapter: adapter vs in-process custody")
struct DemoEd25519AdapterCustodyTests {

    @Test("Key added via adapter.add makes adapter.canSignFor true")
    @MainActor
    func adapterAdd_makesCanSignForTrue() async throws {
        let adapter = DemoEd25519Adapter()
        let identity = try DemoExternalSignersTestSupport.ed25519Identity()

        // Before: adapter holds no secret for this identity.
        #expect(!adapter.canSignFor(
            verifierAddress: identity.verifierAddress,
            publicKey: identity.publicKey
        ))

        try adapter.add(identity, seedBytes: DemoExternalSignersTestSupport.ed25519SeedBytes())

        // After add: the adapter can sign for the exact (verifier, publicKey) tuple.
        #expect(adapter.canSignFor(
            verifierAddress: identity.verifierAddress,
            publicKey: identity.publicKey
        ))

        adapter.clearAll()
        #expect(!adapter.canSignFor(
            verifierAddress: identity.verifierAddress,
            publicKey: identity.publicKey
        ))
    }

    @Test("Adapter holds no secret for an in-process Ed25519 key (canSignFor false)")
    @MainActor
    func inProcessKey_adapterReportsFalse() async throws {
        // The manager is wired with this exact adapter (adapter-first precedence).
        let adapter = DemoEd25519Adapter()
        let manager = OZExternalSignerManager(
            networkPassphrase: DemoConfig.networkPassphrase,
            walletAdapter: nil,
            walletConnectionStorage: nil,
            ed25519Adapter: adapter
        )
        let identity = try DemoExternalSignersTestSupport.ed25519Identity()

        // Register the key IN-PROCESS on the manager — never on the adapter.
        let publicKey = try await manager.addEd25519FromRawKey(
            secretKeyBytes: DemoExternalSignersTestSupport.ed25519SeedBytes(),
            verifierAddress: identity.verifierAddress
        )
        #expect(publicKey == identity.publicKey)

        // The manager can sign for it (via its in-process registry)...
        #expect(await manager.canSignEd25519For(
            verifierAddress: identity.verifierAddress,
            publicKey: identity.publicKey
        ))
        // ...but the adapter holds no secret for it, so the adapter path is false.
        #expect(!adapter.canSignFor(
            verifierAddress: identity.verifierAddress,
            publicKey: identity.publicKey
        ))

        await manager.removeEd25519(verifierAddress: identity.verifierAddress, publicKey: identity.publicKey)
        #expect(!(await manager.canSignEd25519For(
            verifierAddress: identity.verifierAddress,
            publicKey: identity.publicKey
        )))
    }

    @Test("add rejects a non-32-byte seed")
    @MainActor
    func add_rejectsBadSeedLength() async throws {
        let adapter = DemoEd25519Adapter()
        let identity = try DemoExternalSignersTestSupport.ed25519Identity()
        #expect(throws: DemoAdapterError.self) {
            try adapter.add(identity, seedBytes: Data(count: 31))
        }
    }
}

// ============================================================================
// MARK: - Structural-wrapping regression tests
// ============================================================================

/// Regression tests that guard the structural wrapping itself: delegated and
/// Ed25519 registration both run inside ONE cleanup wrapper, so if Ed25519
/// registration throws after delegated registration succeeded, the
/// already-registered delegated keypairs are still cleaned up.
///
/// These drive the same flow entry points the production submit / picker-confirm
/// paths use and force the Ed25519 registration to throw (a malformed seed). The
/// tests never invoke any cleanup helper themselves — the assertion is purely
/// that the delegated registration was reverted by the production wrapper. They
/// would FAIL if Ed25519 registration were moved back outside the wrapper.
@Suite("Multi-signer cleanup: structural wrapping regression")
struct MultiSignerCleanupRegressionTests {

    /// A malformed Ed25519 secret (wrong length) that makes both the in-process
    /// (`addEd25519FromRawKey`) and adapter (`DemoEd25519Adapter.add`) registration
    /// paths throw, so the wrapper's cleanup must run.
    @MainActor
    private static func malformedEd25519Secrets() -> [Ed25519SecretKey: Data] {
        let identity = Ed25519SecretKey(
            verifierAddress: DemoExternalSignersTestSupport.ed25519Verifier,
            publicKey: Data(count: 32)
        )
        return [identity: Data(count: 31)] // 31 bytes — not a valid seed.
    }

    // ---- In-process custody path (transfer) ----

    @Test("Transfer: Ed25519 throw cleans up the already-registered delegated keypair")
    @MainActor
    func transfer_ed25519Throws_delegatedCleanedUp() async throws {
        let made = TransferFixtures.makeFlow()
        let delegatedAddress = DemoExternalSignersTestSupport.delegatedAddress
        let delegatedSecret = DemoExternalSignersTestSupport.delegatedSecret

        // Precondition: the manager cannot yet sign for the delegated address.
        #expect(!(await made.signers.canSignFor(address: delegatedAddress)))

        let delegated = try OZDelegatedSigner(address: delegatedAddress)

        // Drive the real multi-signer transfer entry point. The wrapper registers
        // the delegated keypair first (succeeds), then the malformed Ed25519
        // secret (throws). The test does NOT call any cleanup itself.
        await #expect(throws: (any Error).self) {
            _ = try await made.flow.multiSignerTransfer(
                tokenContract: TransferFixtures.nativeTokenContract,
                recipient: TransferFixtures.recipientG,
                amount: "1",
                tokenLabel: "XLM",
                chosenSigners: [delegated],
                delegatedSecrets: [delegatedAddress: delegatedSecret],
                ed25519Secrets: Self.malformedEd25519Secrets()
            )
        }

        // The structural fix guarantee: the delegated keypair that was registered
        // before the Ed25519 throw must have been removed by the wrapper. If
        // Ed25519 registration escaped the wrapper, this delegated keypair would
        // leak and canSignFor would still be true.
        #expect(!(await made.signers.canSignFor(address: delegatedAddress)))
        #expect(await made.signers.getAll().isEmpty)
    }

    // ---- Adapter custody path (approve) ----

    @Test("Approve: Ed25519 adapter throw cleans up the already-registered delegated keypair")
    @MainActor
    func approve_ed25519AdapterThrows_delegatedCleanedUp() async throws {
        let made = ApproveFixtures.makeFlow()
        let delegatedAddress = DemoExternalSignersTestSupport.delegatedAddress
        let delegatedSecret = DemoExternalSignersTestSupport.delegatedSecret

        #expect(!(await made.signers.canSignFor(address: delegatedAddress)))

        let delegated = try OZDelegatedSigner(address: delegatedAddress)

        await #expect(throws: (any Error).self) {
            _ = try await made.flow.multiSignerApproveAllowanceWithChosenSigners(
                tokenContract: ApproveFixtures.demoTokenContract,
                spenderAddress: ApproveFixtures.spenderG,
                amount: "1",
                expirationLedger: 100,
                chosenSigners: [delegated],
                delegatedSecrets: [delegatedAddress: delegatedSecret],
                ed25519Secrets: Self.malformedEd25519Secrets()
            )
        }

        // Delegated keypair cleaned up (manager.removeAll ran in the wrapper)...
        #expect(!(await made.signers.canSignFor(address: delegatedAddress)))
        #expect(await made.signers.getAll().isEmpty)
        // ...and the adapter cleared (no partial registration left behind).
        #expect(!made.adapter.canSignFor(
            verifierAddress: DemoExternalSignersTestSupport.ed25519Verifier,
            publicKey: Data(count: 32)
        ))
    }

    // ---- Cleanup runs when the submit body throws (in-process) ----

    @Test("Transfer: delegated keypair registered then cleaned up when SDK call throws")
    @MainActor
    func transfer_bodyThrows_delegatedCleanedUp() async throws {
        let multiOps = MockMultiSignerManager()
        multiOps.error = MockTransferNetworkError(detail: "submit boom")
        let made = TransferFixtures.makeFlow(multiOps: multiOps)
        let delegatedAddress = DemoExternalSignersTestSupport.delegatedAddress
        let delegatedSecret = DemoExternalSignersTestSupport.delegatedSecret
        let delegated = try OZDelegatedSigner(address: delegatedAddress)

        await #expect(throws: (any Error).self) {
            _ = try await made.flow.multiSignerTransfer(
                tokenContract: TransferFixtures.nativeTokenContract,
                recipient: TransferFixtures.recipientG,
                amount: "1",
                tokenLabel: "XLM",
                chosenSigners: [delegated],
                delegatedSecrets: [delegatedAddress: delegatedSecret]
            )
        }

        // The SDK call ran (delegated keypair was registered first) and then
        // threw; the wrapper's cleanup removed the keypair on the throw path.
        #expect(multiOps.callCount == 1)
        #expect(!(await made.signers.canSignFor(address: delegatedAddress)))
    }

    // ---- Cleanup runs on success (in-process) ----

    @Test("Transfer: delegated keypair registered for the call then cleaned up on success")
    @MainActor
    func transfer_success_delegatedCleanedUp() async throws {
        let multiOps = MockMultiSignerManager()
        multiOps.result = TransferFixtures.successResult()
        let made = TransferFixtures.makeFlow(multiOps: multiOps)
        let delegatedAddress = DemoExternalSignersTestSupport.delegatedAddress
        let delegatedSecret = DemoExternalSignersTestSupport.delegatedSecret
        let delegated = try OZDelegatedSigner(address: delegatedAddress)

        _ = try await made.flow.multiSignerTransfer(
            tokenContract: TransferFixtures.nativeTokenContract,
            recipient: TransferFixtures.recipientG,
            amount: "1",
            tokenLabel: "XLM",
            chosenSigners: [delegated],
            delegatedSecrets: [delegatedAddress: delegatedSecret]
        )

        // The keypair was present during the SDK call (it derived to the expected
        // address, so the call did not throw invalidDelegatedSigner) and is
        // cleared afterward so it is never retained across screens.
        #expect(multiOps.callCount == 1)
        #expect(!(await made.signers.canSignFor(address: delegatedAddress)))
        #expect(await made.signers.getAll().isEmpty)
    }

    // ---- Approve: Ed25519 routes through the adapter on success ----

    @Test("Approve: Ed25519 secret is registered on the adapter (not in-process) and cleared")
    @MainActor
    func approve_ed25519RoutesThroughAdapter() async throws {
        let multiOps = MockMultiSignerContractCall()
        multiOps.result = ApproveFixtures.successResult()
        let made = ApproveFixtures.makeFlow(multiOps: multiOps)
        let identity = try DemoExternalSignersTestSupport.ed25519Identity()

        // Capture adapter / in-process state at the moment the SDK call runs by
        // recording it from the mock's invocation.
        let adapter = made.adapter
        let signers = made.signers
        var adapterSawKeyDuringCall = false
        var inProcessSawKeyDuringCall = false
        multiOps.onCall = {
            adapterSawKeyDuringCall = adapter.canSignFor(
                verifierAddress: identity.verifierAddress,
                publicKey: identity.publicKey
            )
            inProcessSawKeyDuringCall = await signers.canSignEd25519For(
                verifierAddress: identity.verifierAddress,
                publicKey: identity.publicKey
            ) && !adapter.canSignFor(
                verifierAddress: identity.verifierAddress,
                publicKey: identity.publicKey
            )
        }

        // Build an Ed25519 external signer for the picker selection.
        let ed25519Signer = try OZExternalSigner(
            verifierAddress: identity.verifierAddress,
            keyData: identity.publicKey
        )

        _ = try await made.flow.multiSignerApproveAllowanceWithChosenSigners(
            tokenContract: ApproveFixtures.demoTokenContract,
            spenderAddress: ApproveFixtures.spenderG,
            amount: "1",
            expirationLedger: 100,
            chosenSigners: [ed25519Signer],
            delegatedSecrets: [:],
            ed25519Secrets: [identity: DemoExternalSignersTestSupport.ed25519SeedBytes()]
        )

        // During the SDK call the secret lived on the adapter, not the in-process
        // registry — the adapter custody path.
        #expect(adapterSawKeyDuringCall)
        #expect(!inProcessSawKeyDuringCall)
        // After the call the adapter is cleared.
        #expect(!made.adapter.canSignFor(
            verifierAddress: identity.verifierAddress,
            publicKey: identity.publicKey
        ))
    }
}
