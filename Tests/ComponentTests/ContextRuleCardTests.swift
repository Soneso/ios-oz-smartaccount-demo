// ContextRuleCardTests.swift
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
// MARK: - ContextRuleCard data-side tests
// ============================================================================

/// Tests for the formatting helpers consumed by `ContextRuleCard`.
///
/// SwiftUI view instantiation is not covered in unit tests; data-driven
/// assertions cover the label, badge, and context-type display logic.
@Suite("ContextRuleCard: Context Type Labels")
struct ContextRuleCardContextTypeLabelTests {

    @Test("Default rule label matches verbatim")
    func contextTypeLabel_default() {
        #expect(contextTypeLabel(for: .defaultRule) == "Default (Any Operation)")
    }

    @Test("CallContract label has correct prefix")
    func contextTypeLabel_callContract_prefix() {
        let address = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
        let result = contextTypeLabel(for: .callContract(contractAddress: address))
        #expect(result.hasPrefix("Call Contract:"))
        #expect(result.contains("CDLZF"))
    }

    @Test("CreateContract label has correct prefix and ellipsis suffix")
    func contextTypeLabel_createContract() {
        let hash = Data(repeating: 0xAB, count: 32)
        let result = contextTypeLabel(for: .createContract(wasmHash: hash))
        #expect(result.hasPrefix("Create Contract:"))
        #expect(result.hasSuffix("..."))
    }
}

@Suite("ContextRuleCard: Badge Labels")
struct ContextRuleCardBadgeLabelTests {

    @Test("Signer count 0 is plural")
    func signerCount_zero() { #expect(signerCountLabel(0) == "0 signers") }

    @Test("Signer count 1 is singular")
    func signerCount_one() { #expect(signerCountLabel(1) == "1 signer") }

    @Test("Signer count 3 is plural")
    func signerCount_plural() { #expect(signerCountLabel(3) == "3 signers") }

    @Test("Policy count 0 is plural")
    func policyCount_zero() { #expect(policyCountLabel(0) == "0 policies") }

    @Test("Policy count 1 is singular")
    func policyCount_one() { #expect(policyCountLabel(1) == "1 policy") }

    @Test("Policy count 5 is plural")
    func policyCount_plural() { #expect(policyCountLabel(5) == "5 policies") }
}

@Suite("ContextRuleCard: Signer Type Labels")
struct ContextRuleCardSignerTypeLabelTests {

    @Test("Passkey signer returns Passkey label")
    func signerTypeLabel_passkey() throws {
        let credIdBytes = Data(repeating: 0x01, count: 16)
        var keyData = Data(count: 65)
        keyData[0] = 0x04
        keyData.append(credIdBytes)
        let signer = try OZExternalSigner(
            verifierAddress: "CAZJ3UVRY3R3S5C5BH32GMYBRSN23N75ZEEXEOLXOUUAHDFIMVP4AXUC",
            keyData: keyData
        )
        #expect(signerTypeLabel(for: signer) == "Passkey")
    }

    @Test("Delegated signer returns G-Address label")
    func signerTypeLabel_delegated() throws {
        let signer = try OZDelegatedSigner(
            address: "GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5"
        )
        #expect(signerTypeLabel(for: signer) == "G-Address")
    }

    @Test("Ed25519 OZExternalSigner (exact 65 bytes) returns Ed25519 label")
    func signerTypeLabel_ed25519() throws {
        let keyData = Data(count: 65)
        let signer = try OZExternalSigner(
            verifierAddress: "CAZJ3UVRY3R3S5C5BH32GMYBRSN23N75ZEEXEOLXOUUAHDFIMVP4AXUC",
            keyData: keyData
        )
        #expect(signerTypeLabel(for: signer) == "Ed25519")
    }
}

@Suite("ContextRuleCard: Signer Display Identifiers")
struct ContextRuleCardSignerDisplayTests {

    @Test("Passkey display identifier is base64url (no + or /)")
    func signerDisplayIdentifier_passkey_isBase64URL() throws {
        let credIdBytes = Data(repeating: 0x01, count: 8)
        var keyData = Data(count: 65)
        keyData[0] = 0x04
        keyData.append(credIdBytes)
        let signer = try OZExternalSigner(
            verifierAddress: "CAZJ3UVRY3R3S5C5BH32GMYBRSN23N75ZEEXEOLXOUUAHDFIMVP4AXUC",
            keyData: keyData
        )
        let display = signerDisplayIdentifier(for: signer)
        #expect(!display.isEmpty)
        #expect(!display.contains("+"))
        #expect(!display.contains("/"))
    }

    @Test("Delegated signer display truncates address with ellipsis")
    func signerDisplayIdentifier_delegated_truncated() throws {
        let address = "GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5"
        let signer = try OZDelegatedSigner(address: address)
        let display = signerDisplayIdentifier(for: signer)
        #expect(display.contains("..."))
        #expect(display.hasPrefix("GBBD47"))
    }

    @Test("Ed25519 display has key: prefix and ellipsis suffix")
    func signerDisplayIdentifier_ed25519_format() throws {
        let keyData = Data(repeating: 0xFF, count: 65)
        let signer = try OZExternalSigner(
            verifierAddress: "CAZJ3UVRY3R3S5C5BH32GMYBRSN23N75ZEEXEOLXOUUAHDFIMVP4AXUC",
            keyData: keyData
        )
        let display = signerDisplayIdentifier(for: signer)
        // prefix(8) of hex gives 8 hex chars
        #expect(display == "key:ffffffff...")
    }
}
