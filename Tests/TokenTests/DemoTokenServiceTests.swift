// DemoTokenServiceTests.swift
// SmartAccountDemoTests
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
#if canImport(UIKit)
@testable import SmartAccountDemoLib
#else
@testable import SmartAccountDemoMacLib
#endif
import Testing

// ============================================================================
// MARK: - DemoTokenServiceTests
// ============================================================================

/// Unit tests for `DemoTokenService` covering:
/// - Admin keypair derivation stability (deterministic across runs).
/// - Salt derivation stability (deterministic across runs).
/// - Network passphrase guard (mainnet and futurenet are rejected at init).
/// - Testnet passphrase is accepted.
///
/// These tests are purely local — no network calls, no on-chain operations.
@Suite("DemoTokenService")
struct DemoTokenServiceTests {

    // -------------------------------------------------------------------------
    // MARK: - Test 1: Admin keypair derivation is stable
    // -------------------------------------------------------------------------

    @Test("Admin keypair derivation produces the same G-address on every call")
    func adminKeyDerivationIsStable() throws {
        let service = try DemoTokenService(
            rpcURL: DemoConfig.rpcURL,
            networkPassphrase: DemoConfig.networkPassphrase
        )

        // Call twice and compare.
        let keypair1 = try service.deriveAdminKeyPair()
        let keypair2 = try service.deriveAdminKeyPair()

        #expect(keypair1.accountId == keypair2.accountId)
        // The derived address must be a valid G-address (56 characters).
        #expect(keypair1.accountId.count == 56)
        #expect(keypair1.accountId.hasPrefix("G"))
    }

    @Test("Admin keypair G-address matches expected fixed value derived from seed")
    func adminKeyDerivationKnownGAddress() throws {
        // This test pins the exact G-address derived from DemoConfig.demoTokenAdminSeed.
        // If this assertion fails, the seed or derivation logic changed — confirm the
        // change is intentional and update the expected value.
        //
        // Expected value computed from SHA-256("soneso smart account demo token admin v1")
        // interpreted as an Ed25519 seed, then StrKey-encoded as a G-address.
        let expectedGAddress = "GAH74V64RW4Y6VJWSWP754O3TFCCXX6L6CYBNOS7SW4P4OL2NQMLIAXU"

        let service = try DemoTokenService(
            rpcURL: DemoConfig.rpcURL,
            networkPassphrase: DemoConfig.networkPassphrase
        )
        let keypair = try service.deriveAdminKeyPair()
        #expect(keypair.accountId == expectedGAddress)
    }

    // -------------------------------------------------------------------------
    // MARK: - Test 2: Salt derivation is stable
    // -------------------------------------------------------------------------

    @Test("Salt derivation produces the same 32-byte value on every call")
    func saltDerivationIsStable() throws {
        let service = try DemoTokenService(
            rpcURL: DemoConfig.rpcURL,
            networkPassphrase: DemoConfig.networkPassphrase
        )

        let salt1 = service.deriveSalt()
        let salt2 = service.deriveSalt()

        #expect(salt1 == salt2)
        #expect(salt1.count == 32)
    }

    @Test("Salt differs from the admin keypair seed bytes")
    func saltDiffersFromAdminSeed() throws {
        let service = try DemoTokenService(
            rpcURL: DemoConfig.rpcURL,
            networkPassphrase: DemoConfig.networkPassphrase
        )

        let salt = service.deriveSalt()
        let adminKeypair = try service.deriveAdminKeyPair()

        // The salt's raw bytes should not equal the admin keypair's public key bytes.
        // This is a sanity check that the two seeds are truly distinct derivations.
        let adminPubKeyBytes = Data(adminKeypair.publicKey.bytes)
        #expect(salt != adminPubKeyBytes)
    }

    // -------------------------------------------------------------------------
    // MARK: - Test 3: Mainnet passphrase → throws notTestnet
    // -------------------------------------------------------------------------

    @Test("Init with mainnet passphrase throws notTestnet")
    func initWithMainnetPassphrase() {
        let mainnetPassphrase = "Public Global Stellar Network ; September 2015"
        do {
            _ = try DemoTokenService(rpcURL: "https://horizon.stellar.org", networkPassphrase: mainnetPassphrase)
            Issue.record("Expected DemoTokenServiceError.notTestnet to be thrown for mainnet passphrase")
        } catch let error as DemoTokenServiceError {
            if case .notTestnet = error {
                // Expected.
            } else {
                Issue.record("Expected .notTestnet, got: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Test 4: Futurenet passphrase → throws notTestnet
    // -------------------------------------------------------------------------

    @Test("Init with futurenet passphrase throws notTestnet")
    func initWithFuturenetPassphrase() {
        let futurenetPassphrase = "Test SDF Future Network ; October 2022"
        do {
            _ = try DemoTokenService(rpcURL: "https://rpc-futurenet.stellar.org", networkPassphrase: futurenetPassphrase)
            Issue.record("Expected DemoTokenServiceError.notTestnet to be thrown for futurenet passphrase")
        } catch let error as DemoTokenServiceError {
            if case .notTestnet = error {
                // Expected.
            } else {
                Issue.record("Expected .notTestnet, got: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Test 5: Testnet passphrase → succeeds
    // -------------------------------------------------------------------------

    @Test("Init with testnet passphrase succeeds")
    func initWithTestnetPassphrase() throws {
        // Must not throw.
        let service = try DemoTokenService(
            rpcURL: DemoConfig.rpcURL,
            networkPassphrase: DemoConfig.networkPassphrase
        )
        // Verify that public methods are callable post-init.
        let salt = service.deriveSalt()
        #expect(salt.count == 32)
    }

    // -------------------------------------------------------------------------
    // MARK: - Test 6: Contract address derivation is deterministic
    // -------------------------------------------------------------------------

    @Test("deriveContractAddress produces the same C-address for the same inputs")
    func contractAddressDerministic() throws {
        let service = try DemoTokenService(
            rpcURL: DemoConfig.rpcURL,
            networkPassphrase: DemoConfig.networkPassphrase
        )
        let keypair = try service.deriveAdminKeyPair()
        let salt = service.deriveSalt()

        let address1 = try service.deriveContractAddress(deployerPublicKey: keypair.accountId, salt: salt)
        let address2 = try service.deriveContractAddress(deployerPublicKey: keypair.accountId, salt: salt)

        #expect(address1 == address2)
        // C-addresses start with "C" and are 56 characters.
        #expect(address1.hasPrefix("C"))
        #expect(address1.count == 56)
    }

    @Test("deriveContractAddress differs when salt changes")
    func contractAddressDiffersWithDifferentSalt() throws {
        let service = try DemoTokenService(
            rpcURL: DemoConfig.rpcURL,
            networkPassphrase: DemoConfig.networkPassphrase
        )
        let keypair = try service.deriveAdminKeyPair()

        let salt1 = service.deriveSalt()
        let salt2 = Data(repeating: 0xFF, count: 32)

        let address1 = try service.deriveContractAddress(deployerPublicKey: keypair.accountId, salt: salt1)
        let address2 = try service.deriveContractAddress(deployerPublicKey: keypair.accountId, salt: salt2)

        #expect(address1 != address2)
    }

    // -------------------------------------------------------------------------
    // MARK: - Test 7: DemoTokenServiceError descriptions
    // -------------------------------------------------------------------------

    @Test("notTestnet error has non-empty localised description")
    func notTestnetErrorDescription() {
        let error = DemoTokenServiceError.notTestnet
        #expect(error.errorDescription?.isEmpty == false)
        #expect(error.errorDescription?.contains("testnet") == true)
    }

    @Test("deployFailed error carries the reason")
    func deployFailedErrorDescription() {
        let error = DemoTokenServiceError.deployFailed(reason: "RPC timeout")
        #expect(error.errorDescription?.contains("RPC timeout") == true)
    }

    @Test("mintFailed error carries the reason")
    func mintFailedErrorDescription() {
        let error = DemoTokenServiceError.mintFailed(reason: "insufficient balance")
        #expect(error.errorDescription?.contains("insufficient balance") == true)
    }
}
