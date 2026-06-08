// PolicyManagementSectionTests.swift
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
// MARK: - StagedPolicy model tests
// ============================================================================

@Suite("StagedPolicy: Model")
struct StagedPolicyModelTests {

    @Test("id mirrors address")
    func idMatchesAddress() throws {
        let info = try #require(knownPolicies.first { $0.type == "threshold" })
        let staged = StagedPolicy(
            info: info,
            label: "x",
            address: info.address,
            installSpec: .simpleThreshold(threshold: 1)
        )
        #expect(staged.id == info.address)
    }
}

// ============================================================================
// MARK: - PolicyManagementSection construction tests
// ============================================================================

@Suite("PolicyManagementSection: View Construction")
@MainActor
struct PolicyManagementSectionConstructionTests {

    @Test("Section can be constructed with empty staged policies")
    func emptyPolicies_constructs() {
        let policies: [StagedPolicy] = []
        let weights: [String: String] = [:]
        let errors: [String: String] = [:]
        _ = PolicyManagementSection(
            policies: .constant(policies),
            signerWeights: .constant(weights),
            fieldErrors: .constant(errors),
            signers: [],
            isSubmitting: false
        )
    }

    @Test("Section can be constructed with a staged policy and signer")
    func withPolicyAndSigner_constructs() throws {
        let info = try #require(knownPolicies.first { $0.type == "threshold" })
        let staged = StagedPolicy(
            info: info,
            label: "Threshold: 1-of-N",
            address: info.address,
            installSpec: .simpleThreshold(threshold: 1)
        )
        _ = PolicyManagementSection(
            policies: .constant([staged]),
            signerWeights: .constant([:]),
            fieldErrors: .constant([:]),
            signers: [BuilderFixtures.passkeySigner()],
            isSubmitting: false
        )
    }
}

// ============================================================================
// MARK: - Inventory string parity
// ============================================================================

@Suite("PolicyManagementSection: Inventory String Parity")
struct PolicyInventoryStringTests {

    @Test("Known policies cover all three canonical types")
    func knownPolicies_typesCovered() {
        let types = Set(knownPolicies.map { $0.type })
        #expect(types.contains("threshold"))
        #expect(types.contains("spending_limit"))
        #expect(types.contains("weighted_threshold"))
    }

    @Test("OZConstants.maxSigners and maxPolicies match the SDK contract limits")
    func ozConstantsValues() {
        #expect(OZConstants.maxSigners == 15)
        #expect(OZConstants.maxPolicies == 5)
    }
}
