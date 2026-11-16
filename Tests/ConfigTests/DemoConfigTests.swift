// DemoConfigTests.swift
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
// MARK: - DemoConfigTests
// ============================================================================

/// Validates that DemoConfig constants are format-valid.
///
/// These tests catch typos and truncation errors in constant values without
/// requiring network access. They do not verify on-chain existence.
@Suite("DemoConfig")
struct DemoConfigTests {

    // -------------------------------------------------------------------------
    // MARK: - Network Constants
    // -------------------------------------------------------------------------

    @Test("RPC URL is a non-empty HTTPS URL")
    func rpcURLFormat() {
        let url = DemoConfig.rpcURL
        #expect(!url.isEmpty)
        #expect(url.hasPrefix("https://"))
    }

    @Test("Network passphrase matches testnet value")
    func networkPassphrase() {
        #expect(DemoConfig.networkPassphrase == "Test SDF Network ; September 2015")
    }

    // -------------------------------------------------------------------------
    // MARK: - WASM Hash
    // -------------------------------------------------------------------------

    @Test("Account WASM hash is 64 lowercase hex characters")
    func accountWasmHashFormat() {
        let hash = DemoConfig.accountWasmHash
        #expect(hash.count == 64)
        let isHex = hash.allSatisfy { $0.isHexDigit }
        #expect(isHex)
        let isLower = !hash.contains { $0.isUppercase }
        #expect(isLower)
    }

    @Test("Account WASM hash is the OZ stellar-contracts v0.8.0 build")
    func accountWasmHashIsV080() {
        #expect(
            DemoConfig.accountWasmHash ==
            "c514d35ea67eaea9bfc1fb3327854c0c06111bc1ddebd4fe217c504c1004b9e1"
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - Contract Addresses
    // -------------------------------------------------------------------------

    @Test("WebAuthn verifier address starts with C and is 56 characters")
    func webauthnVerifierAddressFormat() {
        let address = DemoConfig.webauthnVerifierAddress
        #expect(address.hasPrefix("C"))
        #expect(address.count == 56)
    }

    @Test("Ed25519 verifier address starts with C and is 56 characters")
    func ed25519VerifierAddressFormat() {
        let address = DemoConfig.ed25519VerifierAddress
        #expect(address.hasPrefix("C"))
        #expect(address.count == 56)
    }

    @Test("Native token contract address starts with C and is 56 characters")
    func nativeTokenContractFormat() {
        let address = DemoConfig.nativeTokenContract
        #expect(address.hasPrefix("C"))
        #expect(address.count == 56)
    }

    // -------------------------------------------------------------------------
    // MARK: - Demo Token
    // -------------------------------------------------------------------------

    @Test("Demo token admin seed is non-empty and differs from other known seeds")
    func demoTokenAdminSeed() {
        let seed = DemoConfig.demoTokenAdminSeed
        #expect(!seed.isEmpty)
        // The seed must contain "soneso" to confirm we are using the Soneso-specific value
        // and not any other demo's seed string.
        #expect(seed.contains("soneso"))
        // The seed must include a version suffix so it is unique across any future resets.
        #expect(seed.contains("v1"))
    }

    @Test("Demo token salt seed is non-empty and differs from admin seed")
    func demoTokenSaltSeed() {
        let salt = DemoConfig.demoTokenSaltSeed
        #expect(!salt.isEmpty)
        #expect(salt != DemoConfig.demoTokenAdminSeed)
        #expect(salt.contains("soneso"))
    }

    @Test("Demo token name and symbol are non-empty")
    func demoTokenNameAndSymbol() {
        #expect(!DemoConfig.demoTokenName.isEmpty)
        #expect(!DemoConfig.demoTokenSymbol.isEmpty)
    }

    @Test("Demo token decimals is 7")
    func demoTokenDecimals() {
        #expect(DemoConfig.demoTokenDecimals == 7)
    }

    @Test("Demo token mint amount is positive")
    func demoTokenMintAmount() {
        #expect(DemoConfig.demoTokenMintAmount > 0)
    }

    // -------------------------------------------------------------------------
    // MARK: - Service URLs
    // -------------------------------------------------------------------------

    @Test("Default relayer URL is a non-empty HTTPS URL")
    func relayerURLFormat() {
        let url = DemoConfig.defaultRelayerURL
        #expect(!url.isEmpty)
        #expect(url.hasPrefix("https://"))
    }

    @Test("Default indexer URL is a non-empty HTTPS URL")
    func indexerURLFormat() {
        let url = DemoConfig.defaultIndexerURL
        #expect(!url.isEmpty)
        #expect(url.hasPrefix("https://"))
    }

    // -------------------------------------------------------------------------
    // MARK: - WebAuthn / Passkey
    // -------------------------------------------------------------------------

    @Test("Default RP ID is soneso.com")
    func defaultRpId() {
        #expect(DemoConfig.defaultRpId == "soneso.com")
    }

    @Test("RP name is non-empty")
    func rpName() {
        #expect(!DemoConfig.rpName.isEmpty)
    }

    // -------------------------------------------------------------------------
    // MARK: - Reown
    // -------------------------------------------------------------------------

    @Test("Reown project ID is user-supplied: empty by default, 32 hex when set")
    func reownProjectId() {
        let id = DemoConfig.reownProjectId
        // The project ID is not shipped with the demo. The committed default is
        // empty, which disables external-wallet connect and hides its UI. When a
        // developer sets it, a valid Reown project ID is 32 hexadecimal chars.
        if id.isEmpty {
            #expect(id.isEmpty)
        } else {
            #expect(id.count == 32)
            #expect(id.allSatisfy { $0.isHexDigit })
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Context Rule Discovery
    // -------------------------------------------------------------------------

    @Test("Max context rule scan ID is positive and bounded")
    func maxContextRuleScanId() {
        #expect(DemoConfig.maxContextRuleScanId > 0)
        // Sanity cap: scanning more than 1000 IDs would be pathological
        #expect(DemoConfig.maxContextRuleScanId <= 1_000)
    }

    // -------------------------------------------------------------------------
    // MARK: - Known Policies
    // -------------------------------------------------------------------------

    @Test("Known policies contains exactly 3 entries")
    func knownPoliciesCount() {
        #expect(knownPolicies.count == 3)
    }

    @Test("Known policies have valid C-addresses")
    func knownPoliciesAddresses() {
        for policy in knownPolicies {
            #expect(policy.address.hasPrefix("C"), "Policy '\(policy.type)' address must start with C")
            #expect(policy.address.count == 56, "Policy '\(policy.type)' address must be 56 chars")
        }
    }

    @Test("Known policies have unique types and addresses")
    func knownPoliciesUniqueness() {
        let types = knownPolicies.map(\.type)
        let uniqueTypes = Set(types)
        #expect(types.count == uniqueTypes.count)

        let addresses = knownPolicies.map(\.address)
        let uniqueAddresses = Set(addresses)
        #expect(addresses.count == uniqueAddresses.count)
    }

    @Test("Known policies include threshold, spending_limit, and weighted_threshold")
    func knownPoliciesTypes() {
        let types = Set(knownPolicies.map(\.type))
        #expect(types.contains("threshold"))
        #expect(types.contains("spending_limit"))
        #expect(types.contains("weighted_threshold"))
    }

    @Test("Known policies have non-empty names and descriptions")
    func knownPoliciesContent() {
        for policy in knownPolicies {
            #expect(!policy.name.isEmpty, "Policy '\(policy.type)' name must not be empty")
            #expect(!policy.description.isEmpty, "Policy '\(policy.type)' description must not be empty")
        }
    }

    @Test("Known policies offer the OZ stellar-contracts v0.8.0 deployments")
    func knownPoliciesAreV080() {
        #expect(knownPolicies.map(\.type) == ["threshold", "spending_limit", "weighted_threshold"])
        #expect(knownPolicies.map(\.address) == [
            "CAZ2WFUDXGX265LOEARFEOYYUL6F4BYWXZLGUAWZNJY3MRFPNLSZVS4S",
            "CC3CEYQAP6NPNFIYSWL5MVZRCPJZGWX4XO7WDEJOUVGO2FZX5OONYPA5",
            "CDBYLFLUNPAYGE3AHZSMB4TFWECFCCHX6CJFMFO6HRPKK2W5PFU2LCKE"
        ])
    }

    @Test("Recognized policies list the offered policies, then the v0.7.0 deployments named \"(v0.7.0)\"")
    func recognizedPoliciesAddV070() {
        #expect(recognizedPolicies.count == 6)
        let offered = recognizedPolicies.prefix(3)
        #expect(offered.map(\.address) == knownPolicies.map(\.address))
        #expect(offered.map(\.name) == knownPolicies.map(\.name))

        let legacy = Array(recognizedPolicies.dropFirst(3))
        #expect(legacy.map(\.type) == ["threshold", "spending_limit", "weighted_threshold"])
        #expect(legacy.map(\.name) == [
            "Threshold (M-of-N) (v0.7.0)",
            "Spending Limit (v0.7.0)",
            "Weighted Threshold (v0.7.0)"
        ])
        #expect(legacy.map(\.address) == [
            "CAZJ3UVRY3R3S5C5BH32GMYBRSN23N75ZEEXEOLXOUUAHDFIMVP4AXUC",
            "CBQE7L3UNP5IR4I7IBKLS7NV256WHR5TTH26HTMUIK7WXJC6J64RSE2L",
            "CAF4OCRIB73T5777UWAQS7KGOG6WVIZ3EFXNNUYSPFSBKW2Q5XEIOSPW"
        ])
        #expect(legacy.map(\.description) == knownPolicies.map(\.description))
    }
}
