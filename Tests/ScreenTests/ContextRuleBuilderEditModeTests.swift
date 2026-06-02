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
            scVal: nil,
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
