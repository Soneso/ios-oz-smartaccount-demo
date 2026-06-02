// ContextRuleEditTypes.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - EditSignerEntry
// ============================================================================

/// A signer in the edit form, tracking its on-chain state.
///
/// Used by the builder screen in edit mode to distinguish signers that were
/// loaded from the existing on-chain rule from signers the user staged during
/// the current edit session. The on-chain identifier is required to remove an
/// existing signer; freshly staged entries have a `nil` identifier and become
/// `add_signer` invocations on submit.
public struct EditSignerEntry: Sendable {

    /// The signer object (delegated or external).
    public let signer: any OZSmartAccountSigner

    /// The on-chain signer identifier assigned by the contract, or `nil` for
    /// newly added entries that are not yet on-chain.
    public let onChainId: UInt32?

    /// `true` when this entry was loaded from the existing on-chain rule.
    public let isOriginal: Bool

    /// `true` when this is a freshly-registered passkey credential whose local
    /// `pending` record should be promoted to a confirmed credential once the
    /// on-chain `add_signer` succeeds.
    public let isPending: Bool

    public init(
        signer: any OZSmartAccountSigner,
        onChainId: UInt32?,
        isOriginal: Bool,
        isPending: Bool = false
    ) {
        self.signer = signer
        self.onChainId = onChainId
        self.isOriginal = isOriginal
        self.isPending = isPending
    }
}

// ============================================================================
// MARK: - PolicyParams
// ============================================================================

/// On-chain parameters read from a policy contract's storage entry.
///
/// Populated by ``ContextRuleFlow/readPolicyParams(info:ruleId:)``
/// for each known policy attached to the rule being edited. Empty / unparsed
/// shapes are dropped on read (the flow logs a single info entry and returns
/// `nil`), so a non-`nil` value indicates the corresponding `type` field
/// matched a known policy variant.
public struct PolicyParams: Sendable, Equatable {

    /// Policy type identifier (`"threshold"`, `"spending_limit"`,
    /// `"weighted_threshold"`).
    public let type: String

    /// Threshold value for `"threshold"` and `"weighted_threshold"` policies.
    public let threshold: UInt32?

    /// XLM amount string (e.g. `"1000"`) for `"spending_limit"` policies.
    public let spendingLimit: String?

    /// Period in days for `"spending_limit"` policies; minimum 1.
    public let periodDays: Int?

    /// Per-signer weight map for `"weighted_threshold"` policies, keyed by the
    /// signer's identity string (`OZSmartAccountBuilders.getSignerKey(...)`).
    public let signerWeights: [String: UInt32]?

    public init(
        type: String,
        threshold: UInt32?,
        spendingLimit: String?,
        periodDays: Int?,
        signerWeights: [String: UInt32]?
    ) {
        self.type = type
        self.threshold = threshold
        self.spendingLimit = spendingLimit
        self.periodDays = periodDays
        self.signerWeights = signerWeights
    }
}

// ============================================================================
// MARK: - EditPolicyEntry
// ============================================================================

/// A policy in the edit form, tracking on-chain state and inline edits.
///
/// Entries with `isOriginal == true` were loaded from the existing rule and
/// render an inline parameter-edit form pre-populated from `originalParams`.
/// The `modified` flag flips to `true` when the user changes any value and
/// triggers a per-policy update on submit (1 op for threshold-only changes
/// via `set_threshold`, 2 ops for other types via remove + re-add).
public struct EditPolicyEntry: Sendable {

    /// Known-policy descriptor, or `nil` for an unknown policy contract.
    public let info: PolicyInfo?

    /// Human-readable label shown in the list (e.g. `"Threshold: 2-of-N"`).
    public let label: String

    /// Policy contract address (`C…`).
    public let address: String

    /// Encoded install parameters, or `nil` for an existing original policy
    /// whose params have not been edited (in which case the existing on-chain
    /// params remain installed).
    public let scVal: SCValXDR?

    /// On-chain policy identifier assigned by the contract, or `nil` for newly
    /// staged entries.
    public let onChainId: UInt32?

    /// `true` when this entry was loaded from the existing on-chain rule.
    public let isOriginal: Bool

    /// `true` when the user changed any parameter on an original policy.
    public let modified: Bool

    /// On-chain parameters loaded at edit start, used by the inline edit form
    /// and the `modified` comparison.
    public let originalParams: PolicyParams?

    public init(
        info: PolicyInfo?,
        label: String,
        address: String,
        scVal: SCValXDR?,
        onChainId: UInt32?,
        isOriginal: Bool,
        modified: Bool = false,
        originalParams: PolicyParams? = nil
    ) {
        self.info = info
        self.label = label
        self.address = address
        self.scVal = scVal
        self.onChainId = onChainId
        self.isOriginal = isOriginal
        self.modified = modified
        self.originalParams = originalParams
    }

    /// Returns a copy of this entry with selected fields replaced.
    public func with(
        label: String? = nil,
        scVal: SCValXDR?? = nil,
        modified: Bool? = nil
    ) -> Self {
        let nextScVal: SCValXDR?
        if let unwrapped = scVal {
            nextScVal = unwrapped
        } else {
            nextScVal = self.scVal
        }
        return Self(
            info: info,
            label: label ?? self.label,
            address: address,
            scVal: nextScVal,
            onChainId: onChainId,
            isOriginal: isOriginal,
            modified: modified ?? self.modified,
            originalParams: originalParams
        )
    }
}

// ============================================================================
// MARK: - ContextRuleEditDiff
// ============================================================================

/// Describes the difference between an original on-chain rule and the current
/// edit-form state. Computed by the builder before submission and consumed by
/// ``ContextRuleFlow/submitContextRuleEdits(diff:selectedSigners:onProgress:)``
/// to drive the per-operation execution sequence.
///
/// `totalOperations` counts the number of on-chain transactions that will be
/// executed. Threshold-only policy modifications use `set_threshold` and count
/// as 1 op; all other modifications remove + re-add and count as 2 ops.
public struct ContextRuleEditDiff: Sendable {

    /// On-chain rule identifier being edited.
    public let ruleId: UInt32

    /// `true` if the rule name was modified.
    public let nameChanged: Bool

    /// New name value, or `nil` when unchanged.
    public let newName: String?

    /// Signers newly added during the edit session.
    public let newSigners: [EditSignerEntry]

    /// Original signers removed by the user during the edit session.
    public let removedSigners: [EditSignerEntry]

    /// Policies newly added during the edit session.
    public let newPolicies: [EditPolicyEntry]

    /// Original policies removed by the user during the edit session.
    public let removedPolicies: [EditPolicyEntry]

    /// Original policies whose parameters were edited inline.
    public let modifiedPolicies: [EditPolicyEntry]

    /// `true` if the expiry was changed (set, cleared, or replaced).
    public let expiryChanged: Bool

    /// New expiry value. While the diff is staged this carries the ledger
    /// offset chosen in the dropdown; the flow resolves it to an absolute
    /// ledger before submission via
    /// ``ContextRuleFlow/resolveEditDiffExpiry(_:)``. `nil` means "remove
    /// expiry".
    public let newExpiry: UInt32?

    public init(
        ruleId: UInt32,
        nameChanged: Bool,
        newName: String?,
        newSigners: [EditSignerEntry],
        removedSigners: [EditSignerEntry],
        newPolicies: [EditPolicyEntry],
        removedPolicies: [EditPolicyEntry],
        modifiedPolicies: [EditPolicyEntry],
        expiryChanged: Bool,
        newExpiry: UInt32?
    ) {
        self.ruleId = ruleId
        self.nameChanged = nameChanged
        self.newName = newName
        self.newSigners = newSigners
        self.removedSigners = removedSigners
        self.newPolicies = newPolicies
        self.removedPolicies = removedPolicies
        self.modifiedPolicies = modifiedPolicies
        self.expiryChanged = expiryChanged
        self.newExpiry = newExpiry
    }

    /// `true` when no field has changed and no operation needs to be submitted.
    public var isEmpty: Bool {
        !nameChanged &&
        newSigners.isEmpty &&
        removedSigners.isEmpty &&
        newPolicies.isEmpty &&
        removedPolicies.isEmpty &&
        modifiedPolicies.isEmpty &&
        !expiryChanged
    }

    /// Total number of on-chain operations that will be executed.
    public var totalOperations: Int {
        var count = 0
        if nameChanged { count += 1 }
        count += newSigners.count
        count += removedSigners.count
        count += removedPolicies.count
        count += newPolicies.count
        for policy in modifiedPolicies {
            count += policy.info?.type == "threshold" ? 1 : 2
        }
        if expiryChanged { count += 1 }
        return count
    }

    /// Returns a copy of the diff with the supplied expiry value.
    public func withExpiry(_ value: UInt32?) -> Self {
        Self(
            ruleId: ruleId,
            nameChanged: nameChanged,
            newName: newName,
            newSigners: newSigners,
            removedSigners: removedSigners,
            newPolicies: newPolicies,
            removedPolicies: removedPolicies,
            modifiedPolicies: modifiedPolicies,
            expiryChanged: expiryChanged,
            newExpiry: value
        )
    }
}

// ============================================================================
// MARK: - ContextRuleEditResult
// ============================================================================

/// Result returned by
/// ``ContextRuleFlow/submitContextRuleEdits(diff:selectedSigners:onProgress:)``
/// covering full success, partial success (auth-context guard skipped later
/// steps), and failure.
public struct ContextRuleEditResult: Sendable {

    /// `true` when execution completed without a failing step (full or partial
    /// success). The `partialDueToAuthGuard` flag distinguishes the two.
    public let success: Bool

    /// Number of on-chain operations that succeeded before the run ended.
    public let completedOperations: Int

    /// Total operations the diff planned (`ContextRuleEditDiff.totalOperations`).
    public let totalOperations: Int

    /// `true` when later steps were skipped because adding signers altered the
    /// rule's authorization context.
    public let partialDueToAuthGuard: Bool

    /// Auth-guard explanatory text when `partialDueToAuthGuard` is `true`.
    public let authGuardMessage: String?

    /// Sanitised error message when `success` is `false`.
    public let error: String?

    /// Human-readable description of the step that failed, when applicable.
    public let failedStep: String?

    /// Per-operation transaction hashes in execution order.
    public let transactionHashes: [String]

    public init(
        success: Bool,
        completedOperations: Int,
        totalOperations: Int,
        partialDueToAuthGuard: Bool,
        authGuardMessage: String?,
        error: String?,
        failedStep: String?,
        transactionHashes: [String] = []
    ) {
        self.success = success
        self.completedOperations = completedOperations
        self.totalOperations = totalOperations
        self.partialDueToAuthGuard = partialDueToAuthGuard
        self.authGuardMessage = authGuardMessage
        self.error = error
        self.failedStep = failedStep
        self.transactionHashes = transactionHashes
    }
}
