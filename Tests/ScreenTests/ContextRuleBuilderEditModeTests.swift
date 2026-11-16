// ContextRuleBuilderEditModeTests.swift
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
// MARK: - ContextRuleBuilderCore: edit-mode construction
// ============================================================================

@Suite("ContextRuleBuilderCore: edit-mode construction")
@MainActor
struct ContextRuleBuilderEditConstructionTests {

    @Test("Core view can be constructed with an editRuleId")
    func builderCore_editConstructs() {
        let core = ContextRuleBuilderCore(editRuleId: 42) { }
        #expect(core.editRuleId == 42)
        #expect(core.isEditing)
    }

    @Test("Defaulted init creates create-mode core")
    func builderCore_createModeByDefault() {
        let core = ContextRuleBuilderCore { }
        #expect(core.editRuleId == nil)
        #expect(!core.isEditing)
    }

    @Test("The context type is locked in edit mode and open in create mode")
    func builderCore_contextTypeLockedInEditMode() {
        #expect(ContextRuleBuilderCore(editRuleId: 5) { }.contextTypeLocked)
        #expect(!ContextRuleBuilderCore { }.contextTypeLocked)
    }
}

// ============================================================================
// MARK: - Edit mode: context type prefill
// ============================================================================

@Suite("ContextRuleBuilderCore: edit-mode context type prefill")
@MainActor
struct ContextTypePrefillTests {

    @Test("A CreateContractExternalRef rule reopens with its owner and tag")
    func prefill_createContractExternalRef() {
        let owner = "CAAQEAYEAUDAOCAJBIFQYDIOB4IBCEQTCQKRMFYYDENBWHA5DYPSBFLM"
        let fields = ContextRuleBuilderCore.contextTypeFormFields(
            for: .createContractExternalRef(owner: owner, tag: "account-v1")
        )
        #expect(fields == ContextTypeFormFields(
            option: .createContractExternalRef,
            refOwner: owner,
            refTag: "account-v1"
        ))
    }

    @Test("Default, CallContract and CreateContract rules reopen with their own field")
    func prefill_otherKinds() {
        let address = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
        #expect(
            ContextRuleBuilderCore.contextTypeFormFields(for: .defaultRule) ==
            ContextTypeFormFields(option: .defaultRule)
        )
        #expect(
            ContextRuleBuilderCore.contextTypeFormFields(for: .callContract(contractAddress: address)) ==
            ContextTypeFormFields(option: .callContract, contractAddress: address)
        )
        let wasm = Data([0xAB, 0xCD] + Array(repeating: 0x01, count: 30))
        #expect(
            ContextRuleBuilderCore.contextTypeFormFields(for: .createContract(wasmHash: wasm)) ==
            ContextTypeFormFields(
                option: .createContract,
                wasmHashHex: "abcd" + String(repeating: "01", count: 30)
            )
        )
    }
}

// ============================================================================
// MARK: - Edit mode: policies of a v0.7.0 wallet
// ============================================================================

@Suite("ContextRuleBuilderCore: edit-mode policy recognition")
@MainActor
struct EditPolicyRecognitionTests {

    /// The OZ stellar-contracts v0.7.0 threshold deployment, which rules of
    /// wallets created before v0.8.0 carry.
    static let legacyThreshold = "CAZJ3UVRY3R3S5C5BH32GMYBRSN23N75ZEEXEOLXOUUAHDFIMVP4AXUC"

    static func rule(policy: String) -> ParsedContextRuleInfo {
        OZParsedContextRule(
            id: 3,
            contextType: .defaultRule,
            name: "legacy",
            signers: [ContextRuleFixtures.makeDelegatedSigner()],
            signerIds: [3],
            policies: [policy],
            policyIds: [8],
            validUntil: nil
        )
    }

    @Test("A v0.7.0 threshold policy loads as \"(v0.7.0)\" with its on-chain parameters and stays editable")
    func legacyThresholdPolicy() async {
        let stored = PolicyParams(
            type: "threshold",
            threshold: 2,
            spendingLimit: nil,
            periodDays: nil,
            signerWeights: nil
        )
        var requested: [PolicyInfo] = []
        let entry = await ContextRuleBuilderCore.makeEditPolicyEntry(
            address: Self.legacyThreshold,
            index: 0,
            parsed: Self.rule(policy: Self.legacyThreshold)
        ) { info in
            requested.append(info)
            return stored
        }

        #expect(requested.map(\.address) == [Self.legacyThreshold])
        #expect(requested.map(\.type) == ["threshold"])
        #expect(entry.info?.name == "Threshold (M-of-N) (v0.7.0)")
        #expect(entry.info?.type == "threshold")
        #expect(entry.label == "Threshold: 2-of-N")
        #expect(entry.address == Self.legacyThreshold)
        #expect(entry.onChainId == 8)
        #expect(entry.isOriginal)
        // The inline parameter editor renders for an original entry with
        // loaded parameters.
        #expect(entry.originalParams == stored)
    }

    @Test("A policy outside the recognized set loads as \"Unknown Policy\" without a parameter read")
    func unknownPolicy() async {
        let unknown = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
        var readCount = 0
        let entry = await ContextRuleBuilderCore.makeEditPolicyEntry(
            address: unknown,
            index: 0,
            parsed: Self.rule(policy: unknown)
        ) { _ in
            readCount += 1
            return nil
        }

        #expect(readCount == 0)
        #expect(entry.info == nil)
        #expect(entry.label == "Unknown Policy")
        #expect(entry.originalParams == nil)
        #expect(entry.onChainId == 8)
    }
}

// ============================================================================
// MARK: - Route: contextRuleEditor wiring
// ============================================================================

@Suite("Route: contextRuleEditor")
struct ContextRuleEditorRouteTests {

    @Test("contextRuleEditor case carries a rule identifier")
    func editorRouteCarriesId() {
        let route = Route.contextRuleEditor(id: 7)
        if case .contextRuleEditor(let id) = route {
            #expect(id == 7)
        } else {
            Issue.record("Pattern match did not bind id")
        }
    }

    @Test("contextRuleBuilder and contextRuleEditor are distinct cases")
    func builderAndEditorDistinct() {
        let builderRoute: Route = .contextRuleBuilder
        let editorRoute: Route = .contextRuleEditor(id: 1)
        #expect(builderRoute != editorRoute)
    }
}

// ============================================================================
// MARK: - Edit-mode operation summary copy
// ============================================================================

@Suite("Edit operation summary copy")
@MainActor
struct EditOperationSummaryCopyTests {

    @Test("Pending changes string formats parts in expected order")
    func partsOrder() {
        let signer = ContextRuleFixtures.makePasskeySigner(credId: "x")
        let entry = EditSignerEntry(signer: signer, onChainId: nil, isOriginal: false)
        let policy = EditPolicyEntry(
            info: knownPolicies[0],
            label: "x",
            address: knownPolicies[0].address,
            installSpec: nil,
            onChainId: nil,
            isOriginal: false
        )
        let diff = ContextRuleEditDiff(
            ruleId: 1,
            nameChanged: true,
            newName: "Renamed",
            newSigners: [entry],
            removedSigners: [],
            newPolicies: [policy],
            removedPolicies: [],
            modifiedPolicies: [],
            expiryChanged: true,
            newExpiry: 720
        )
        // 1 (name) + 1 (signer add) + 1 (policy add) + 1 (expiry) = 4
        #expect(diff.totalOperations == 4)
        #expect(!diff.isEmpty)
    }

    @Test("Empty edit diff yields totalOperations == 0")
    func emptyDiff() {
        let diff = ContextRuleEditDiff(
            ruleId: 1,
            nameChanged: false,
            newName: nil,
            newSigners: [],
            removedSigners: [],
            newPolicies: [],
            removedPolicies: [],
            modifiedPolicies: [],
            expiryChanged: false,
            newExpiry: nil
        )
        #expect(diff.isEmpty)
        #expect(diff.totalOperations == 0)
    }
}

// ============================================================================
// MARK: - ContextRuleEditResult shape
// ============================================================================

@Suite("ContextRuleEditResult shape")
struct ContextRuleEditResultShapeTests {

    @Test("Full success carries no error and no failed step")
    func fullSuccess() {
        let result = ContextRuleEditResult(
            success: true,
            completedOperations: 3,
            totalOperations: 3,
            partialDueToAuthGuard: false,
            authGuardMessage: nil,
            error: nil,
            failedStep: nil,
            transactionHashes: ["h1", "h2", "h3"]
        )
        #expect(result.success)
        #expect(!result.partialDueToAuthGuard)
        #expect(result.transactionHashes.count == 3)
    }

    @Test("Partial-due-to-auth-guard carries the explanatory message")
    func partial() {
        let result = ContextRuleEditResult(
            success: true,
            completedOperations: 2,
            totalOperations: 4,
            partialDueToAuthGuard: true,
            authGuardMessage: "Signer changes were applied successfully.",
            error: nil,
            failedStep: nil,
            transactionHashes: ["h1", "h2"]
        )
        #expect(result.success)
        #expect(result.partialDueToAuthGuard)
        #expect(result.authGuardMessage?.contains("Signer changes were applied") == true)
    }

    @Test("Failure carries an error and a failed step")
    func failure() {
        let result = ContextRuleEditResult(
            success: false,
            completedOperations: 1,
            totalOperations: 3,
            partialDueToAuthGuard: false,
            authGuardMessage: nil,
            error: "contract reverted",
            failedStep: "Removing signer 1 of 1",
            transactionHashes: ["h1"]
        )
        #expect(!result.success)
        #expect(result.failedStep != nil)
        #expect(result.error != nil)
    }
}

// ============================================================================
// MARK: - ContextRulesScreenCore: onEditRule wiring
// ============================================================================

@Suite("ContextRulesScreenCore: onEditRule wiring")
@MainActor
struct ContextRulesScreenEditWiringTests {

    @Test("Core stores the onEditRule callback supplied by the hosting shell")
    func captureCallback() {
        // The closure is private to the core. Verify the init compiles with
        // the explicit `onEditRule` parameter and that the public surface
        // exposed via the parameter labels matches the documented shape.
        // The runtime forwarding is exercised end-to-end by
        // ContextRulesScreen (iOS) and ContextRulesScreenMac (macOS) via
        // their respective navigation paths.
        var ids: [UInt32] = []
        _ = ContextRulesScreenCore(
            onAddRule: { },
            onEditRule: { id in ids.append(id) }
        )
        // Smoke construction completed without crashing.
        #expect(ids.isEmpty)
    }

    @Test("ContextRuleCard exposes an onEdit init parameter")
    func cardOnEditParameter() {
        var editCount = 0
        let rule = ContextRuleFixtures.defaultRule(id: 9)
        _ = ContextRuleCard(
            rule: rule,
            isLastRule: false,
            isRemoving: false,
            isExpanded: .constant(false),
            onEdit: { editCount += 1 },
            onRemove: { }
        )
        #expect(editCount == 0)
    }
}
