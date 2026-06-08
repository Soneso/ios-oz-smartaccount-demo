// BuildSelectedSignersTransportsTests.swift
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
// MARK: - buildSelectedSigners transport-hint lookup
// ============================================================================

/// Executing assertions that ``MultiSignerRegistration/buildSelectedSigners(_:credentialManager:unsupportedShapePolicy:)``
/// resolves each passkey signer's WebAuthn transport hints from the stored
/// credential record (looked up by credential ID through the credential
/// manager).
///
/// These guard the transport-hint lookup: a passkey signer whose stored
/// credential carries `transports` must produce a `.passkey` ``OZSelectedSigner``
/// carrying exactly those transports, and a passkey signer with no stored
/// credential (or a stored credential without transports) must produce `nil`
/// transports. If the lookup were removed, the first assertion would fail
/// because the produced transports would be `nil` rather than the stored value.
@Suite("buildSelectedSigners: WebAuthn transport-hint lookup")
struct BuildSelectedSignersTransportsTests {

    // -------------------------------------------------------------------------
    // MARK: - Helpers
    // -------------------------------------------------------------------------

    /// A Base64URL credential ID used across the suite. The raw bytes decoded
    /// from it are appended to the SEC1 public key so that
    /// `OZSmartAccountBuilders.getCredentialIdStringFromSigner` round-trips
    /// back to this same string.
    private static let credentialId = "dGVzdC1jcmVkZW50aWFsLWlk"

    /// Builds a kit backed by an in-memory storage adapter. No WebAuthn provider
    /// is required because the credential manager's `createPendingCredential`
    /// and `getCredential` only touch storage.
    @MainActor
    private func makeKit() throws -> OZSmartAccountKit {
        let config = try OZSmartAccountConfig(
            rpcUrl: DemoConfig.rpcURL,
            networkPassphrase: DemoConfig.networkPassphrase,
            accountWasmHash: DemoConfig.accountWasmHash,
            webauthnVerifierAddress: DemoConfig.webauthnVerifierAddress,
            storage: OZInMemoryStorageAdapter()
        )
        return OZSmartAccountKit.create(config: config)
    }

    /// Builds a passkey `OZExternalSigner` whose embedded credential ID
    /// round-trips back to `credentialId`.
    private func makePasskeySigner(credentialId: String = credentialId) throws -> OZExternalSigner {
        let credIdBytes: Data
        if let decoded = try? Data(base64URLEncoded: credentialId) {
            credIdBytes = decoded
        } else {
            credIdBytes = Data(credentialId.utf8)
        }
        // keyData = 65-byte uncompressed SEC1 public key + raw credential ID bytes.
        var keyData = Data(count: 65)
        keyData[0] = 0x04
        keyData.append(credIdBytes)
        return try OZExternalSigner(
            verifierAddress: DemoConfig.webauthnVerifierAddress,
            keyData: keyData
        )
    }

    /// A dummy 65-byte uncompressed secp256r1 public key for seeding stored
    /// credentials. Curve membership is not validated by the credential manager;
    /// only the length and the credential ID matter for the lookup under test.
    private var dummyPublicKey: Data {
        var key = Data(count: 65)
        key[0] = 0x04
        return key
    }

    /// Extracts the transports from a `.passkey` ``OZSelectedSigner``, or `nil`
    /// for any other case.
    private func transports(of selected: OZSelectedSigner) -> [String]? {
        switch selected {
        case let .passkey(_, _, _, transports):
            return transports
        default:
            return nil
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Stored transports are forwarded
    // -------------------------------------------------------------------------

    @Test("passkey signer forwards the stored credential's transports")
    @MainActor
    func storedTransportsAreForwarded() async throws {
        let kit = try makeKit()
        let storedTransports = ["internal", "hybrid"]
        _ = try await kit.credentialManager.createPendingCredential(
            credentialId: Self.credentialId,
            publicKey: dummyPublicKey,
            contractId: "CDUMMYCONTRACTADDRESS234567ABCDEFGHIJKLMNOPQRSTUVWXYZ234567",
            transports: storedTransports
        )

        let signer = try makePasskeySigner()
        let result = try await MultiSignerRegistration.buildSelectedSigners(
            [signer],
            credentialManager: kit.credentialManager
        )

        #expect(result.count == 1)
        let selected = try #require(result.first)
        #expect(transports(of: selected) == storedTransports)
    }

    // -------------------------------------------------------------------------
    // MARK: - No stored credential yields nil transports
    // -------------------------------------------------------------------------

    @Test("passkey signer with no stored credential yields nil transports")
    @MainActor
    func missingCredentialYieldsNilTransports() async throws {
        let kit = try makeKit()
        // Deliberately do not seed any credential.

        let signer = try makePasskeySigner()
        let result = try await MultiSignerRegistration.buildSelectedSigners(
            [signer],
            credentialManager: kit.credentialManager
        )

        #expect(result.count == 1)
        let selected = try #require(result.first)
        #expect(transports(of: selected) == nil)
    }

    // -------------------------------------------------------------------------
    // MARK: - Stored credential without transports yields nil transports
    // -------------------------------------------------------------------------

    @Test("passkey signer whose stored credential has no transports yields nil transports")
    @MainActor
    func storedCredentialWithoutTransportsYieldsNil() async throws {
        let kit = try makeKit()
        _ = try await kit.credentialManager.createPendingCredential(
            credentialId: Self.credentialId,
            publicKey: dummyPublicKey,
            contractId: "CDUMMYCONTRACTADDRESS234567ABCDEFGHIJKLMNOPQRSTUVWXYZ234567",
            transports: nil
        )

        let signer = try makePasskeySigner()
        let result = try await MultiSignerRegistration.buildSelectedSigners(
            [signer],
            credentialManager: kit.credentialManager
        )

        #expect(result.count == 1)
        let selected = try #require(result.first)
        #expect(transports(of: selected) == nil)
    }
}
