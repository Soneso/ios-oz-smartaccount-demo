// ContextRuleEditFlow+Snapshot.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - ContextRuleFlow: on-chain rule snapshot + staleness check
// ============================================================================

extension ContextRuleFlow {

    /// Minimal snapshot of a freshly-fetched context rule used to detect drift
    /// against the originally loaded state before submitting a threshold
    /// modification. Only the fields the staleness check needs are extracted.
    internal struct ContextRuleSnapshot {
        let policyIds: [UInt32]
        let policyAddresses: [String]
    }

    /// Parses a raw on-chain context-rule SCVal map into a
    /// ``ContextRuleSnapshot``. Returns `nil` when the supplied SCVal is not a
    /// map or when the policy fields cannot be decoded.
    internal func parseContextRuleSnapshot(_ scVal: SCValXDR) -> ContextRuleSnapshot? {
        guard case .map(let entries) = scVal, let entries else { return nil }
        var policyIds: [UInt32] = []
        var addresses: [String] = []
        for entry in entries {
            applySnapshotField(entry: entry, policyIds: &policyIds, addresses: &addresses)
        }
        return ContextRuleSnapshot(policyIds: policyIds, policyAddresses: addresses)
    }

    private func applySnapshotField(
        entry: SCMapEntryXDR,
        policyIds: inout [UInt32],
        addresses: inout [String]
    ) {
        guard case .symbol(let key) = entry.key else { return }
        switch key {
        case "policies":
            if case .vec(let vec) = entry.val, let vec {
                addresses = vec.compactMap { policyAddressString(from: $0) }
            }
        case "policy_ids":
            if case .vec(let vec) = entry.val, let vec {
                policyIds = vec.compactMap { item in
                    if case .u32(let value) = item { return value }
                    return nil
                }
            }
        default:
            return
        }
    }

    private func policyAddressString(from scVal: SCValXDR) -> String? {
        guard case .address(let address) = scVal else { return nil }
        if let contractId = address.contractId,
           let strkey = try? contractId.encodeContractIdHex() {
            return strkey
        }
        return address.accountId
    }

    /// Compares the freshly fetched on-chain context rule against the original
    /// state the user loaded the editor with. Returns a sanitised error message
    /// describing the mismatch when the rule has been modified on chain since
    /// load (e.g. by a concurrent edit from another session), or `nil` when the
    /// rule shape still matches.
    ///
    /// The check inspects the rule's policy address set extracted from the raw
    /// SCVal: if the set drifts, the threshold modification is rejected so it
    /// cannot be applied to a rule the user did not authorize.
    internal func detectStaleRuleMismatch(
        ruleId: UInt32,
        policyAddress: String,
        freshRule: SCValXDR,
        entry: EditPolicyEntry
    ) -> String? {
        guard let onChainId = entry.onChainId else { return nil }
        guard let snapshot = parseContextRuleSnapshot(freshRule) else {
            return "Could not validate the current on-chain rule. " +
                "Reload the rule and try again."
        }
        if !snapshot.policyIds.contains(onChainId) {
            return "Policy is no longer attached to rule #\(ruleId). " +
                "Reload the rule and try again."
        }
        if !snapshot.policyAddresses.contains(policyAddress) {
            return "Policy address is no longer attached to rule #\(ruleId). " +
                "Reload the rule and try again."
        }
        return nil
    }
}
