// ContextRuleFormatTests.swift
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
// MARK: - ContextRuleFormat tests
// ============================================================================

@Suite("ContextRuleFormat: contextTypeLabel")
struct ContextRuleFormatContextTypeLabelTests {

    @Test("Default rule label matches verbatim")
    func contextTypeLabel_default_verbatim() {
        #expect(contextTypeLabel(for: .defaultRule) == "Default (Any Operation)")
    }

    @Test("CallContract label has correct prefix")
    func contextTypeLabel_callContract_prefix() {
        let address = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
        let result = contextTypeLabel(for: .callContract(contractAddress: address))
        #expect(result.hasPrefix("Call Contract: "))
    }

    @Test("CallContract label includes truncated address with ellipsis")
    func contextTypeLabel_callContract_truncated() {
        let address = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
        let result = contextTypeLabel(for: .callContract(contractAddress: address))
        #expect(result.contains("CDLZFC"))
        #expect(result.contains("..."))
        #expect(result.contains("GCYSC"))
    }

    @Test("CreateContract label has correct prefix")
    func contextTypeLabel_createContract_prefix() {
        let hash = Data(repeating: 0xDE, count: 32)
        let result = contextTypeLabel(for: .createContract(wasmHash: hash))
        #expect(result.hasPrefix("Create Contract: "))
    }

    @Test("CreateContract label includes first 8 hex chars and ellipsis")
    func contextTypeLabel_createContract_hexContent() {
        let hash = Data([0xAB, 0xCD, 0xEF, 0x01, 0x23, 0x45, 0x67, 0x89] + Array(repeating: 0, count: 24))
        let result = contextTypeLabel(for: .createContract(wasmHash: hash))
        #expect(result.contains("abcdef01"))
        #expect(result.hasSuffix("..."))
    }
}

@Suite("ContextRuleFormat: signerTypeLabel")
struct ContextRuleFormatSignerTypeLabelTests {

    @Test("Passkey signer returns Passkey")
    func signerTypeLabel_passkey() throws {
        let credIdBytes = Data(repeating: 0x01, count: 8)
        var keyData = Data(count: 65)
        keyData[0] = 0x04
        keyData.append(credIdBytes)
        let signer = try OZExternalSigner(
            verifierAddress: "CAZJ3UVRY3R3S5C5BH32GMYBRSN23N75ZEEXEOLXOUUAHDFIMVP4AXUC",
            keyData: keyData
        )
        #expect(signerTypeLabel(for: signer) == "Passkey")
    }

    @Test("Delegated signer returns G-Address")
    func signerTypeLabel_delegated() throws {
        let signer = try OZDelegatedSigner(
            address: "GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5"
        )
        #expect(signerTypeLabel(for: signer) == "G-Address")
    }
}

@Suite("ContextRuleFormat: signerDisplayIdentifier")
struct ContextRuleFormatSignerDisplayTests {

    @Test("Delegated display uses 6-char prefix truncation")
    func signerDisplayIdentifier_delegated_prefix6() throws {
        let address = "GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5"
        let signer = try OZDelegatedSigner(address: address)
        let result = signerDisplayIdentifier(for: signer)
        #expect(result.hasPrefix("GBBD47"))
        #expect(result.hasSuffix("FLA5"))
    }

    @Test("Ed25519 display uses key: prefix and 8-char hex snippet")
    func signerDisplayIdentifier_ed25519_format() throws {
        let keyData = Data(repeating: 0xAA, count: 65)
        let signer = try OZExternalSigner(
            verifierAddress: "CAZJ3UVRY3R3S5C5BH32GMYBRSN23N75ZEEXEOLXOUUAHDFIMVP4AXUC",
            keyData: keyData
        )
        let result = signerDisplayIdentifier(for: signer)
        // prefix(8) of hex string = 8 hex chars = "aaaaaaaa"
        #expect(result == "key:aaaaaaaa...")
    }
}

@Suite("ContextRuleFormat: Count Labels")
struct ContextRuleFormatCountLabelTests {

    @Test("Signer count label singular and plural")
    func signerCountLabel_singularPlural() {
        #expect(signerCountLabel(0) == "0 signers")
        #expect(signerCountLabel(1) == "1 signer")
        #expect(signerCountLabel(2) == "2 signers")
        #expect(signerCountLabel(100) == "100 signers")
    }

    @Test("Policy count label singular and plural")
    func policyCountLabel_singularPlural() {
        #expect(policyCountLabel(0) == "0 policies")
        #expect(policyCountLabel(1) == "1 policy")
        #expect(policyCountLabel(2) == "2 policies")
        #expect(policyCountLabel(10) == "10 policies")
    }
}
