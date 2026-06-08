// ContextRuleEditTestSupport.swift
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

// ============================================================================
// MARK: - EditFlowPair
// ============================================================================

/// Bundles the objects produced by `EditFlowFixtures.makeFlow()` so test bodies
/// can read either side with a single binding.
@MainActor
struct EditFlowPair {

    let flow: ContextRuleFlow
    let manager: MockContextRuleManagerFull
    let executor: MockSmartAccountExecutor
    let demoState: DemoState
    /// Real external signer manager injected into `demoState`.
    let signers: OZExternalSignerManager
    /// Real Ed25519 adapter wired into the manager and `demoState`.
    let adapter: DemoEd25519Adapter
}

// ============================================================================
// MARK: - EditFlowFixtures
// ============================================================================

/// Test fixture builders for the context-rule edit-flow suite. Keeps the
/// per-test setup compact and consistent across cases.
@MainActor
enum EditFlowFixtures {

    /// Builds a fully-wired flow + mock manager pair for edit submissions.
    static func makeFlow() -> EditFlowPair {
        let manager = MockContextRuleManagerFull()
        let executor = MockSmartAccountExecutor()
        let state = ContextRuleFixtures.connectedState()
        let seam = DemoExternalSignersTestSupport.install(into: state)
        let flow = ContextRuleFlow(
            demoState: state,
            activityLog: ActivityLogState(),
            contextRuleManager: manager,
            smartAccountExecutor: executor,
            webAuthnVerifierAddress: BuilderFixtures.webauthnVerifier,
            ed25519VerifierAddress: ContextRuleFixtures.verifier
        )
        return EditFlowPair(
            flow: flow,
            manager: manager,
            executor: executor,
            demoState: state,
            signers: seam.manager,
            adapter: seam.adapter
        )
    }

    /// Returns a syntactically empty diff with optional one-off field
    /// overrides. Tests construct diffs through this helper to satisfy
    /// SwiftLint's multiline-arguments rule without redundant scaffolding.
    static func emptyDiff(
        ruleId: UInt32 = 1,
        nameChanged: Bool = false,
        newName: String? = nil,
        newSigners: [EditSignerEntry] = [],
        removedSigners: [EditSignerEntry] = [],
        newPolicies: [EditPolicyEntry] = [],
        removedPolicies: [EditPolicyEntry] = [],
        modifiedPolicies: [EditPolicyEntry] = [],
        expiryChanged: Bool = false,
        newExpiry: UInt32? = nil
    ) -> ContextRuleEditDiff {
        return ContextRuleEditDiff(
            ruleId: ruleId,
            nameChanged: nameChanged,
            newName: newName,
            newSigners: newSigners,
            removedSigners: removedSigners,
            newPolicies: newPolicies,
            removedPolicies: removedPolicies,
            modifiedPolicies: modifiedPolicies,
            expiryChanged: expiryChanged,
            newExpiry: newExpiry
        )
    }

    /// Builds a minimal modified `EditPolicyEntry` for the supplied policy
    /// info. `modified` defaults to `true` because most call sites that need
    /// this helper are testing the modified-policy execution path.
    static func policyEntry(
        info: PolicyInfo,
        onChainId: UInt32 = 1,
        modified: Bool = true
    ) -> EditPolicyEntry {
        return EditPolicyEntry(
            info: info,
            label: "x",
            address: info.address,
            installSpec: nil,
            onChainId: onChainId,
            isOriginal: true,
            modified: modified,
            originalParams: nil
        )
    }

    /// Builds an original `EditPolicyEntry` for removal scenarios. The
    /// `onChainId` is required because the remove pipeline reads it.
    static func originalPolicyEntry(
        info: PolicyInfo,
        label: String = "old",
        onChainId: UInt32
    ) -> EditPolicyEntry {
        return EditPolicyEntry(
            info: info,
            label: label,
            address: info.address,
            installSpec: nil,
            onChainId: onChainId,
            isOriginal: true
        )
    }

    /// Builds a new (non-original) `EditPolicyEntry` for add scenarios.
    static func newPolicyEntry(
        info: PolicyInfo,
        label: String,
        spec: PolicyInstallSpec
    ) -> EditPolicyEntry {
        return EditPolicyEntry(
            info: info,
            label: label,
            address: info.address,
            installSpec: spec,
            onChainId: nil,
            isOriginal: false
        )
    }

    /// Builds an original `EditSignerEntry` for removal scenarios.
    static func originalSignerEntry(
        signer: any OZSmartAccountSigner,
        onChainId: UInt32
    ) -> EditSignerEntry {
        return EditSignerEntry(signer: signer, onChainId: onChainId, isOriginal: true)
    }

    /// Builds a new (non-original) `EditSignerEntry` for add scenarios.
    static func newSignerEntry(
        signer: any OZSmartAccountSigner
    ) -> EditSignerEntry {
        return EditSignerEntry(signer: signer, onChainId: nil, isOriginal: false)
    }

    /// Modified policy entry that carries a typed spec (for non-threshold modify
    /// pipelines that need the install params to re-add).
    static func modifiedPolicyEntry(
        info: PolicyInfo,
        label: String,
        spec: PolicyInstallSpec,
        onChainId: UInt32,
        originalParams: PolicyParams?
    ) -> EditPolicyEntry {
        return EditPolicyEntry(
            info: info,
            label: label,
            address: info.address,
            installSpec: spec,
            onChainId: onChainId,
            isOriginal: true,
            modified: true,
            originalParams: originalParams
        )
    }

    /// Builds a minimal on-chain context-rule SCVal map carrying the supplied
    /// policy address and id. Used by tests that exercise the freshness check
    /// performed before submitting `set_threshold`.
    static func contextRuleRawMap(
        policyAddress: String,
        policyId: UInt32
    ) -> SCValXDR {
        // swiftlint:disable:next force_try
        let address = try! SCAddressXDR(contractId: policyAddress)
        let entries: [SCMapEntryXDR] = [
            SCMapEntryXDR(key: .symbol("policies"), val: .vec([.address(address)])),
            SCMapEntryXDR(key: .symbol("policy_ids"), val: .vec([.u32(policyId)]))
        ]
        return .map(entries)
    }
}
