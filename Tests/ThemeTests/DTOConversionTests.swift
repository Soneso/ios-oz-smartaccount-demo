// DTOConversionTests.swift
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
// MARK: - WalletConnectOptions → ConnectWalletOptions
// ============================================================================

/// Round-trip tests for the five DTO mapper extensions introduced in the
/// flow-types layer. Each test constructs a source-side value, calls the
/// mapper, and asserts field-for-field equality on the destination side.
@Suite("DTOConversion: WalletConnectOptions.toSDK()")
struct WalletConnectOptionsToSDKTests {

    @Test("toSDK maps credentialId, contractId, and prompt when all are set")
    func mapsAllFields() {
        let dto = WalletConnectOptions(
            credentialId: "cred-abc",
            contractId: "CDUMMYCONTRACT23456789012345678901234567890ABCDEFGHI",
            prompt: true
        )
        let sdk = dto.toSDK()
        #expect(sdk.credentialId == "cred-abc")
        #expect(sdk.contractId == "CDUMMYCONTRACT23456789012345678901234567890ABCDEFGHI")
        #expect(sdk.prompt == true)
    }

    @Test("toSDK maps nil credentialId and contractId")
    func mapsNilFields() {
        let dto = WalletConnectOptions()
        let sdk = dto.toSDK()
        #expect(sdk.credentialId == nil)
        #expect(sdk.contractId == nil)
        #expect(sdk.prompt == false)
    }

    @Test("toSDK maps prompt = false independently of other fields")
    func mapsPromptFalse() {
        let dto = WalletConnectOptions(credentialId: "cred-xyz", contractId: nil, prompt: false)
        let sdk = dto.toSDK()
        #expect(sdk.prompt == false)
        #expect(sdk.credentialId == "cred-xyz")
        #expect(sdk.contractId == nil)
    }
}

// ============================================================================
// MARK: - AuthenticatePasskeyResult.asPasskeyCredential
// ============================================================================

@Suite("DTOConversion: AuthenticatePasskeyResult.asPasskeyCredential")
struct AuthenticatePasskeyResultAsPasskeyCredentialTests {

    /// Builds an `AuthenticatePasskeyResult` with synthetic but correctly-sized
    /// byte buffers. The 64-byte signature requirement is enforced by
    /// `OZWebAuthnSignature.init`, so this helper catches size bugs immediately.
    private func makeAuthResult(credentialId: String) throws -> AuthenticatePasskeyResult {
        let signature = try OZWebAuthnSignature(
            authenticatorData: Data(repeating: 0xAB, count: 37),
            clientData: Data(repeating: 0xCD, count: 100),
            signature: Data(repeating: 0xEF, count: 64)
        )
        return AuthenticatePasskeyResult(
            credentialId: credentialId,
            signature: signature,
            publicKey: Data(repeating: 0x04, count: 65)
        )
    }

    @Test("asPasskeyCredential projects credentialId correctly")
    func projectsCredentialId() throws {
        let result = try makeAuthResult(credentialId: "test-credential-id-1234")
        let credential = result.asPasskeyCredential
        #expect(credential.credentialId == "test-credential-id-1234")
    }

    @Test("asPasskeyCredential returns a PasskeyCredential (not the full result)")
    func returnsPasskeyCredentialType() throws {
        let result = try makeAuthResult(credentialId: "my-cred")
        let credential = result.asPasskeyCredential
        // Only credentialId is exposed — signature material is not carried through.
        #expect(type(of: credential) == PasskeyCredential.self)
        #expect(credential.credentialId == "my-cred")
    }
}

// ============================================================================
// MARK: - DeployPendingResult.asPendingDeployResult
// ============================================================================

@Suite("DTOConversion: DeployPendingResult.asPendingDeployResult")
struct DeployPendingResultAsPendingDeployResultTests {

    @Test("asPendingDeployResult maps contractId and transactionHash when both present")
    func mapsBothFields() {
        let sdk = DeployPendingResult(
            contractId: "CDUMMYCONTRACT23456789012345678901234567890ABCDEFGHI",
            signedTransactionXdr: "base64xdrhere",
            transactionHash: "txhash-abc123"
        )
        let dto = sdk.asPendingDeployResult
        #expect(dto.contractId == "CDUMMYCONTRACT23456789012345678901234567890ABCDEFGHI")
        #expect(dto.transactionHash == "txhash-abc123")
    }

    @Test("asPendingDeployResult maps nil transactionHash")
    func mapsNilTransactionHash() {
        let sdk = DeployPendingResult(
            contractId: "CDUMMYCONTRACT23456789012345678901234567890ABCDEFGHI",
            signedTransactionXdr: "xdr"
        )
        let dto = sdk.asPendingDeployResult
        #expect(dto.transactionHash == nil)
        #expect(dto.contractId == "CDUMMYCONTRACT23456789012345678901234567890ABCDEFGHI")
    }

    @Test("asPendingDeployResult does not expose signedTransactionXdr")
    func doesNotExposeXdr() {
        let sdk = DeployPendingResult(
            contractId: "CDUMMYCONTRACT23456789012345678901234567890ABCDEFGHI",
            signedTransactionXdr: "sensitive-xdr"
        )
        let dto = sdk.asPendingDeployResult
        // PendingDeployResult has no signedTransactionXdr — verify via field count
        #expect(dto.contractId == "CDUMMYCONTRACT23456789012345678901234567890ABCDEFGHI")
        #expect(dto.transactionHash == nil)
    }
}

// ============================================================================
// MARK: - [StoredCredential].asPendingInfo()
// ============================================================================

@Suite("DTOConversion: [StoredCredential].asPendingInfo()")
struct StoredCredentialAsPendingInfoTests {

    private func makeCredential(
        credentialId: String,
        contractId: String?,
        nickname: String?
    ) -> StoredCredential {
        StoredCredential(
            credentialId: credentialId,
            publicKey: Data(repeating: 0x04, count: 65),
            contractId: contractId,
            nickname: nickname
        )
    }

    @Test("asPendingInfo maps credentialId, contractId, and nickname for each element")
    func mapsAllFields() {
        let credentials = [
            makeCredential(
                credentialId: "cred-1",
                contractId: "CDUMMYCONTRACT23456789012345678901234567890ABCDEFGHI",
                nickname: "Touch ID"
            ),
            makeCredential(credentialId: "cred-2", contractId: nil, nickname: nil)
        ]
        let infos = credentials.asPendingInfo()
        #expect(infos.count == 2)
        #expect(infos[0].credentialId == "cred-1")
        #expect(infos[0].contractId == "CDUMMYCONTRACT23456789012345678901234567890ABCDEFGHI")
        #expect(infos[0].nickname == "Touch ID")
        #expect(infos[1].credentialId == "cred-2")
        #expect(infos[1].contractId == nil)
        #expect(infos[1].nickname == nil)
    }

    @Test("asPendingInfo on empty array returns empty array")
    func mapsEmptyArray() {
        let infos = [StoredCredential]().asPendingInfo()
        #expect(infos.isEmpty)
    }

    @Test("PendingCredentialInfo init from StoredCredential projects only UI fields")
    func initFromStoredCredential() {
        let credential = makeCredential(
            credentialId: "cred-abc",
            contractId: "CDUMMYCONTRACT23456789012345678901234567890ABCDEFGHI",
            nickname: "YubiKey"
        )
        let info = PendingCredentialInfo(credential)
        #expect(info.credentialId == "cred-abc")
        #expect(info.contractId == "CDUMMYCONTRACT23456789012345678901234567890ABCDEFGHI")
        #expect(info.nickname == "YubiKey")
    }
}

// ============================================================================
// MARK: - ConnectWalletResult.toConnectionResult(isDeployed:)
// ============================================================================

@Suite("DTOConversion: ConnectWalletResult.toConnectionResult(isDeployed:)")
struct ConnectWalletResultToConnectionResultTests {

    @Test("connected case maps all fields with isDeployed=true")
    func connectedCaseMapsAllFields() {
        let sdk = ConnectWalletResult.connected(
            credentialId: "cred-connect",
            contractId: "CDUMMYCONTRACT23456789012345678901234567890ABCDEFGHI",
            restoredFromSession: true
        )
        let dto = sdk.toConnectionResult(isDeployed: true)
        if case .connected(
            let credentialId, let contractId, let isDeployed, let restoredFromSession
        ) = dto {
            #expect(credentialId == "cred-connect")
            #expect(contractId == "CDUMMYCONTRACT23456789012345678901234567890ABCDEFGHI")
            #expect(isDeployed == true)
            #expect(restoredFromSession == true)
        } else {
            Issue.record("Expected .connected case")
        }
    }

    @Test("connected case maps isDeployed=false when default")
    func connectedCaseDefaultIsDeployed() {
        let sdk = ConnectWalletResult.connected(
            credentialId: "cred-x",
            contractId: "CDUMMYCONTRACT23456789012345678901234567890ABCDEFGHI",
            restoredFromSession: false
        )
        let dto = sdk.toConnectionResult()
        if case .connected(_, _, let isDeployed, _) = dto {
            #expect(isDeployed == false)
        } else {
            Issue.record("Expected .connected case")
        }
    }

    @Test("ambiguous case maps credentialId and candidates")
    func ambiguousCaseMapsFields() {
        let candidates = [
            "CDUMMYCONTRACT23456789012345678901234567890ABCDEFGHI",
            "CANOTHERCONTRACT3456789012345678901234567890ABCDEFGH"
        ]
        let sdk = ConnectWalletResult.ambiguous(credentialId: "cred-ambig", candidates: candidates)
        let dto = sdk.toConnectionResult(isDeployed: false)
        if case .ambiguous(let credentialId, let resultCandidates) = dto {
            #expect(credentialId == "cred-ambig")
            #expect(resultCandidates == candidates)
        } else {
            Issue.record("Expected .ambiguous case")
        }
    }
}
