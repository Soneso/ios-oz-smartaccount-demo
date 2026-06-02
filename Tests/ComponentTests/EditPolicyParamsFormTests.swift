// EditPolicyParamsFormTests.swift
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
// MARK: - EditPolicyParamsForm: View construction
// ============================================================================

@Suite("EditPolicyParamsForm: View construction")
@MainActor
struct EditPolicyParamsFormConstructionTests {

    @Test("Constructs for a threshold entry")
    func thresholdConstructs() throws {
        let info = try #require(knownPolicies.first { $0.type == "threshold" })
        let params = PolicyParams(
            type: "threshold",
            threshold: 2,
            spendingLimit: nil,
            periodDays: nil,
            signerWeights: nil
        )
        let entry = EditPolicyEntry(
            info: info,
            label: "Threshold: 2-of-N",
            address: info.address,
            scVal: nil,
            onChainId: 1,
            isOriginal: true,
            modified: false,
            originalParams: params
        )
        _ = EditPolicyParamsForm(
            entry: entry,
            signers: [],
            signerWeights: .constant([:]),
            isSubmitting: false
        ) { _ in }
    }

    @Test("Constructs for a spending-limit entry")
    func spendingLimitConstructs() throws {
        let info = try #require(knownPolicies.first { $0.type == "spending_limit" })
        let params = PolicyParams(
            type: "spending_limit",
            threshold: nil,
            spendingLimit: "10",
            periodDays: 1,
            signerWeights: nil
        )
        let entry = EditPolicyEntry(
            info: info,
            label: "Limit: 10 / 1 day(s)",
            address: info.address,
            scVal: nil,
            onChainId: 2,
            isOriginal: true,
            modified: false,
            originalParams: params
        )
        _ = EditPolicyParamsForm(
            entry: entry,
            signers: [],
            signerWeights: .constant([:]),
            isSubmitting: false
        ) { _ in }
    }

    @Test("Constructs for a weighted-threshold entry with signers")
    func weightedThresholdConstructs() throws {
        let info = try #require(knownPolicies.first { $0.type == "weighted_threshold" })
        let params = PolicyParams(
            type: "weighted_threshold",
            threshold: 10,
            spendingLimit: nil,
            periodDays: nil,
            signerWeights: ["passkey:test": 5]
        )
        let entry = EditPolicyEntry(
            info: info,
            label: "Weighted: threshold=10",
            address: info.address,
            scVal: nil,
            onChainId: 3,
            isOriginal: true,
            modified: false,
            originalParams: params
        )
        _ = EditPolicyParamsForm(
            entry: entry,
            signers: [BuilderFixtures.passkeySigner()],
            signerWeights: .constant([:]),
            isSubmitting: false
        ) { _ in }
    }

    @Test("Modified flag determines whether the orange status text renders")
    func modifiedFlag() throws {
        let info = try #require(knownPolicies.first { $0.type == "threshold" })
        let params = PolicyParams(
            type: "threshold",
            threshold: 1,
            spendingLimit: nil,
            periodDays: nil,
            signerWeights: nil
        )
        let unmod = EditPolicyEntry(
            info: info,
            label: "x",
            address: info.address,
            scVal: nil,
            onChainId: 1,
            isOriginal: true,
            modified: false,
            originalParams: params
        )
        let mod = unmod.with(modified: true)
        #expect(!unmod.modified)
        #expect(mod.modified)
    }
}

// ============================================================================
// MARK: - EditPolicyEntry.with(...) tests
// ============================================================================

@Suite("EditPolicyEntry.with")
struct EditPolicyEntryWithTests {

    @Test("with(scVal:) replaces the install-params SCVal")
    func replacesScVal() {
        let info = knownPolicies[0]
        let entry = EditPolicyEntry(
            info: info,
            label: "x",
            address: info.address,
            scVal: nil,
            onChainId: 1,
            isOriginal: true
        )
        let scVal = PolicyScValBuilders.buildSimpleThresholdScVal(threshold: 2)
        let updated = entry.with(scVal: scVal)
        if case .map = updated.scVal {
            // OK
        } else {
            Issue.record("scVal not updated")
        }
    }

    @Test("with(label:) updates the human-readable label")
    func updatesLabel() {
        let info = knownPolicies[0]
        let entry = EditPolicyEntry(
            info: info,
            label: "before",
            address: info.address,
            scVal: nil,
            onChainId: 1,
            isOriginal: true
        )
        let updated = entry.with(label: "after")
        #expect(updated.label == "after")
    }

    @Test("with(modified:) toggles the modified flag")
    func togglesModified() {
        let info = knownPolicies[0]
        let entry = EditPolicyEntry(
            info: info,
            label: "x",
            address: info.address,
            scVal: nil,
            onChainId: 1,
            isOriginal: true,
            modified: false
        )
        let updated = entry.with(modified: true)
        #expect(updated.modified)
    }
}
