// SignerManagementSectionTests.swift
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
import SwiftUI
import Testing

// ============================================================================
// MARK: - SignerAddMode enum tests
// ============================================================================

@Suite("SignerAddMode: Display Names")
struct SignerAddModeDisplayTests {

    @Test("Delegated display name matches the inventory")
    func delegatedDisplayName() {
        #expect(SignerAddMode.delegated.displayName == "Delegated (G-address)")
    }

    @Test("Ed25519 display name matches the inventory")
    func ed25519DisplayName() {
        #expect(SignerAddMode.ed25519.displayName == "Ed25519 Public Key")
    }

    @Test("Passkey display name matches the inventory")
    func passkeyDisplayName() {
        #expect(SignerAddMode.passkey.displayName == "Passkey (WebAuthn)")
    }

    @Test("Description strings match the inventory")
    func descriptions() {
        #expect(
            SignerAddMode.delegated.description ==
            "Stellar account using native require_auth verification"
        )
        #expect(
            SignerAddMode.ed25519.description ==
            "Ed25519 key verified by an external verifier contract"
        )
        #expect(
            SignerAddMode.passkey.description ==
            "Passkey verified by the WebAuthn verifier contract"
        )
    }
}

// ============================================================================
// MARK: - SignerManagementSection construction tests
// ============================================================================

@Suite("SignerManagementSection: View Construction")
@MainActor
struct SignerManagementSectionConstructionTests {

    @Test("Section can be constructed with empty signers")
    func emptySigners_constructs() {
        let signers: [any OZSmartAccountSigner] = []
        let weights: [String: String] = [:]
        let errors: [String: String] = [:]
        let made = BuilderFixtures.makeFlow()
        _ = SignerManagementSection(
            signers: .constant(signers),
            signerWeights: .constant(weights),
            fieldErrors: .constant(errors),
            isSubmitting: false,
            flow: made.flow,
            connectedCredentialId: ContextRuleFixtures.credentialId,
            ed25519VerifierAddress: DemoConfig.ed25519VerifierAddress
        )
    }

    @Test("Section can be constructed with submission flag set")
    func submittingFlag_constructs() {
        let signer = BuilderFixtures.passkeySigner()
        let signers: [any OZSmartAccountSigner] = [signer]
        let weights: [String: String] = [:]
        let errors: [String: String] = [:]
        let made = BuilderFixtures.makeFlow()
        _ = SignerManagementSection(
            signers: .constant(signers),
            signerWeights: .constant(weights),
            fieldErrors: .constant(errors),
            isSubmitting: true,
            flow: made.flow,
            connectedCredentialId: nil,
            ed25519VerifierAddress: DemoConfig.ed25519VerifierAddress
        )
    }
}
