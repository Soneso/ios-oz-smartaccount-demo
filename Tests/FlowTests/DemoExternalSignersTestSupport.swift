// DemoExternalSignersTestSupport.swift
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
// MARK: - DemoExternalSignersTestSupport
// ============================================================================

/// Builds and injects the real signing-material seam used by every multi-signer
/// flow test.
///
/// `OZExternalSignerManager` is a Swift `actor` and cannot be subclassed, so the
/// flows are exercised against a real manager instance constructed standalone via
/// its public initialiser. The same instance is injected into `DemoState` via
/// ``DemoState/setInjectedExternalSigners(_:)`` so the flow's
/// `demoState.externalSigners` accessor resolves to it (instead of a full kit).
///
/// A real ``DemoEd25519Adapter`` is wired into the manager (as its
/// `ed25519Adapter`) and into `DemoState` (via
/// ``DemoState/setDemoEd25519Adapter(_:)``) so the adapter custody path can be
/// asserted with executing code, not inspection.
///
/// Tests assert registration / cleanup behaviour through the manager's public
/// surface — ``OZExternalSignerManager/canSignFor(address:)``,
/// ``OZExternalSignerManager/canSignEd25519For(verifierAddress:publicKey:)``,
/// ``OZExternalSignerManager/getAll()`` — and the adapter's
/// ``DemoEd25519Adapter/canSignFor(verifierAddress:publicKey:)``, so each test
/// fails if the production registration or cleanup were removed.
@MainActor
enum DemoExternalSignersTestSupport {

    /// A real `OZExternalSignerManager` plus the real `DemoEd25519Adapter` wired
    /// into it.
    struct Seam {
        let manager: OZExternalSignerManager
        let adapter: DemoEd25519Adapter
    }

    /// Builds a real external signer manager + Ed25519 adapter and injects both
    /// into `state`.
    ///
    /// - Parameter state: The demo state to wire. The manager is injected via
    ///   ``DemoState/setInjectedExternalSigners(_:)`` and the adapter via
    ///   ``DemoState/setDemoEd25519Adapter(_:)``.
    /// - Returns: The wired ``Seam`` so tests can assert on it directly.
    @discardableResult
    static func install(into state: DemoState) -> Seam {
        let adapter = DemoEd25519Adapter()
        let manager = OZExternalSignerManager(
            networkPassphrase: DemoConfig.networkPassphrase,
            walletAdapter: nil,
            walletConnectionStorage: nil,
            ed25519Adapter: adapter
        )
        state.setInjectedExternalSigners(manager)
        state.setDemoEd25519Adapter(adapter)
        return Seam(manager: manager, adapter: adapter)
    }

    /// A single random Stellar keypair generated once per test run. Both
    /// ``delegatedSecret`` and ``delegatedAddress`` are derived from this one
    /// instance so the seed and its account id always stay a consistent pair,
    /// and no secret-seed literal is committed.
    static let delegatedKeyPair: KeyPair = {
        // swiftlint:disable:next force_try
        try! KeyPair.generateRandomKeyPair()
    }()

    /// A Stellar secret key (S-address) used to register a delegated keypair on
    /// the real manager and assert `canSignFor` flips true. Its derived account
    /// id is ``delegatedAddress``, so the two always match the real SDK
    /// derivation.
    static let delegatedSecret: String = delegatedKeyPair.secretSeed ?? ""

    /// The G-address derived from ``delegatedSecret`` by the real SDK `KeyPair`.
    static let delegatedAddress: String = delegatedKeyPair.accountId

    /// Generates a fresh random Stellar keypair and returns its
    /// `(secretSeed, accountId)` pair. Used where a second distinct delegated
    /// signer is needed without hardcoding a (secret, address) pair.
    static func freshKeypair() -> (secret: String, address: String) {
        let kp = try! KeyPair.generateRandomKeyPair() // swiftlint:disable:this force_try
        return (kp.secretSeed ?? "", kp.accountId)
    }

    /// A valid C-address usable as an Ed25519 verifier in fixtures (base32
    /// alphabet only — no digits 0/1/8/9).
    static let ed25519Verifier = "CAZJ3UVRY3R3S5C5BH32GMYBRSN23N75ZEEXEOLXOUUAHDFIMVP4AXUC"

    /// 32 raw Ed25519 seed bytes used to register an Ed25519 signer in fixtures.
    static func ed25519SeedBytes() -> Data {
        Data((0..<32).map { UInt8($0) })
    }

    /// Returns the `(verifierAddress, publicKey)` identity for the seed produced
    /// by ``ed25519SeedBytes()`` under ``ed25519Verifier``.
    static func ed25519Identity() throws -> Ed25519SecretKey {
        let publicKey = try Ed25519KeyDerivation.deriveKeypair(
            fromSecretBytes: ed25519SeedBytes()
        ).publicKey
        return Ed25519SecretKey(verifierAddress: ed25519Verifier, publicKey: publicKey)
    }
}
