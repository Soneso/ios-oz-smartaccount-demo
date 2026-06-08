// ContextRuleEditFlow.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - ContextRuleFlow: edit-mode operations
// ============================================================================

public extension ContextRuleFlow {

    // -------------------------------------------------------------------------
    // MARK: - loadParsedContextRule
    // -------------------------------------------------------------------------

    /// Fetches a single ``OZParsedContextRule`` for the supplied identifier.
    ///
    /// Implemented as a filter over ``listContextRules()`` so the screen can
    /// reuse the same parsing path as the read-only list. Throws if
    /// the rule cannot be found (for example when another wallet removed it
    /// between screen load and edit dispatch).
    ///
    /// - Parameter ruleId: The on-chain rule identifier to load.
    /// - Returns: The matching ``OZParsedContextRule``.
    /// - Throws: ``SmartAccountWalletException/NotConnected`` when no wallet is connected,
    ///   any SDK error raised by `listContextRules`, or
    ///   ``ContextRuleFlowError/missingOnChainIdentifier(entity:)`` when the
    ///   rule cannot be found on chain.
    func loadParsedContextRule(ruleId: UInt32) async throws -> OZParsedContextRule {
        guard demoState.isConnected, let manager = contextRuleManager else {
            throw SmartAccountWalletException.NotConnected(message: "No wallet connected.")
        }
        let rules = try await manager.listContextRules()
        guard let match = rules.first(where: { $0.id == ruleId }) else {
            throw ContextRuleFlowError.missingOnChainIdentifier(entity: "rule #\(ruleId)")
        }
        return match
    }

    // -------------------------------------------------------------------------
    // MARK: - resolveEditDiffExpiry
    // -------------------------------------------------------------------------

    /// Resolves the diff's expiry field from a ledger offset to an absolute
    /// ledger number by adding the current Soroban ledger sequence.
    ///
    /// - If `diff.expiryChanged == false`, the diff is returned unchanged.
    /// - If `diff.newExpiry == nil` (the user requested expiry removal), the
    ///   diff is returned with `newExpiry == nil`.
    /// - Otherwise the value is treated as a ledger offset and added to the
    ///   current ledger sequence returned by the bound ``LatestLedgerSource``.
    ///
    /// - Parameter diff: The staged edit diff.
    /// - Returns: A diff with `newExpiry` rewritten to an absolute ledger
    ///   (or kept `nil` when removing expiry).
    /// - Throws: ``ContextRuleFlowError/latestLedgerFetchFailed(reason:)``
    ///   when the underlying RPC call fails.
    func resolveEditDiffExpiry(
        _ diff: ContextRuleEditDiff
    ) async throws -> ContextRuleEditDiff {
        guard diff.expiryChanged else { return diff }
        guard let offset = diff.newExpiry, offset > 0 else {
            // User cleared the expiry — propagate the nil through.
            return diff.withExpiry(nil)
        }
        let absolute = try await resolveAbsoluteLedger(offset: offset)
        return diff.withExpiry(absolute)
    }

    // -------------------------------------------------------------------------
    // MARK: - readPolicyParams
    // -------------------------------------------------------------------------

    /// Reads on-chain policy parameters for the supplied policy contract and
    /// rule. Used by the edit-form to pre-populate inline editors.
    ///
    /// Inspects the persistent storage entry keyed by
    /// `Vec([Symbol("AccountContext"), Address(smartAccount), U32(ruleId)])`
    /// and parses the stored SCVal into a ``PolicyParams`` shape matching the
    /// supplied policy `info`. Unknown or unparseable shapes return `nil` — the
    /// edit form simply omits the inline editor for that policy.
    ///
    /// - Parameters:
    ///   - info: Known-policy metadata. The `type` field controls the parser.
    ///   - ruleId: Rule identifier the policy is installed on.
    ///   - guardedToken: The rule's call-contract target (the token a
    ///     spending-limit policy guards), or `nil` for non-token rules. Used to
    ///     resolve the decimal scale for formatting a stored spending-limit
    ///     amount. Ignored for non-spending-limit policy types.
    /// - Returns: Parsed parameters, or `nil` when the entry cannot be read
    ///   or its shape does not match `info.type`.
    func readPolicyParams(
        info: PolicyInfo,
        ruleId: UInt32,
        guardedToken: String? = nil
    ) async -> PolicyParams? {
        guard let rpcUrl, let contractId = demoState.contractId else { return nil }
        let scVal = await fetchPolicyStorageValue(
            rpcUrl: rpcUrl,
            smartAccountContractId: contractId,
            policyAddress: info.address,
            ruleId: ruleId
        )
        guard let scVal else { return nil }
        switch info.type {
        case "threshold":
            return parseThresholdParams(scVal)
        case "spending_limit":
            // why: a failed decimals read must not silently fall back to a
            // wrong scale; on failure the inline editor is omitted (nil) so the
            // user removes and re-adds the policy rather than editing a
            // mis-scaled amount.
            guard let decimals = try? await resolveSpendingLimitDecimals(
                forGuardedToken: guardedToken
            ) else {
                return nil
            }
            return parseSpendingLimitParams(scVal, decimals: decimals)
        case "weighted_threshold":
            return parseWeightedThresholdParams(scVal)
        default:
            return nil
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - submitContextRuleEdits
    // -------------------------------------------------------------------------

    // swiftlint:disable cyclomatic_complexity function_body_length

    /// Executes the per-operation submission pipeline for ``ContextRuleEditDiff``.
    ///
    /// Each step runs in sequence: name update → signer adds → signer removes →
    /// auth-context guard → policy removes → policy updates → policy adds →
    /// expiry update → pending-credential cleanup. Each step is its own Stellar
    /// transaction. The progress callback fires with the verbatim step label
    /// before each step starts; the UI updates a live-region label from the
    /// callback. On step failure the run stops and returns a failure result
    /// carrying the failed step, completed-operation count, and any hashes
    /// from successful prior steps.
    ///
    /// **Auth-context guard:** if the diff added new signers AND has pending
    /// policy or expiry changes, the policy/expiry updates are deliberately
    /// skipped — adding signers changes the rule's authorization context and
    /// the SDK would reject the subsequent operations. The skipped state is
    /// surfaced via `partialDueToAuthGuard = true` so the screen can render
    /// the blue "Partial Update" card and the user can re-submit after the
    /// reload.
    ///
    /// - Parameters:
    ///   - diff: The diff to execute. Caller should resolve expiry to an
    ///     absolute ledger via ``resolveEditDiffExpiry(_:)`` first.
    ///   - selectedSigners: Multi-signer participants list. Empty triggers the
    ///     single-passkey fast-path on each step.
    ///   - onProgress: Callback fired with a verbatim step label before each
    ///     operation begins. The label format mirrors the inventory copy.
    /// - Returns: ``ContextRuleEditResult`` describing the outcome.
    /// - Throws: ``ContextRuleFlowError/editAlreadyInProgress`` on reentry;
    ///   ``SmartAccountWalletException/NotConnected`` when no wallet is connected. Per-step
    ///   SDK errors are captured in the returned result rather than rethrown,
    ///   except cancellations which propagate so the caller can render
    ///   "Passkey authentication cancelled".
    func submitContextRuleEdits(
        diff: ContextRuleEditDiff,
        selectedSigners: [OZSelectedSigner],
        onProgress: @MainActor @Sendable (String) -> Void
    ) async throws -> ContextRuleEditResult {
        guard !isEditing else {
            throw ContextRuleFlowError.editAlreadyInProgress
        }
        guard demoState.isConnected, let manager = contextRuleManager else {
            throw SmartAccountWalletException.NotConnected(message: "No wallet connected.")
        }
        isEditing = true
        defer { isEditing = false }

        if diff.isEmpty {
            return ContextRuleEditResult(
                success: true,
                completedOperations: 0,
                totalOperations: 0,
                partialDueToAuthGuard: false,
                authGuardMessage: nil,
                error: nil,
                failedStep: nil,
                transactionHashes: []
            )
        }

        var completed = 0
        var hashes: [String] = []
        let total = diff.totalOperations

        // Step 1 — name
        if diff.nameChanged {
            let step = "Updating rule name"
            onProgress("Updating rule #\(diff.ruleId)...")
            let outcome = await runStep(step: step) {
                try await manager.updateContextRuleName(
                    ruleId: diff.ruleId,
                    newName: diff.newName ?? "",
                    selectedSigners: selectedSigners
                )
            }
            switch outcome {
            case .ok(let hash):
                completed += 1
                if let hash { hashes.append(hash) }
            case .failed(let result):
                return result.toEditResult(
                    completed: completed, total: total, hashes: hashes
                )
            }
        }

        // Step 2 — add signers
        for (index, entry) in diff.newSigners.enumerated() {
            let step = "Adding signer \(index + 1) of \(diff.newSigners.count)"
            onProgress("Updating rule #\(diff.ruleId)...")
            let outcome = await runStep(step: step) {
                try await self.dispatchAddSigner(
                    manager: manager,
                    ruleId: diff.ruleId,
                    entry: entry,
                    selectedSigners: selectedSigners
                )
            }
            switch outcome {
            case .ok(let hash):
                completed += 1
                if let hash { hashes.append(hash) }
            case .failed(let result):
                return result.toEditResult(
                    completed: completed, total: total, hashes: hashes
                )
            }
        }

        // Step 3 — remove signers
        for (index, entry) in diff.removedSigners.enumerated() {
            let step = "Removing signer \(index + 1) of \(diff.removedSigners.count)"
            onProgress("Updating rule #\(diff.ruleId)...")
            guard let onChainId = entry.onChainId else {
                return ContextRuleEditResult(
                    success: false,
                    completedOperations: completed,
                    totalOperations: total,
                    partialDueToAuthGuard: false,
                    authGuardMessage: nil,
                    error: "Cannot remove signer without on-chain ID",
                    failedStep: step,
                    transactionHashes: hashes
                )
            }
            let outcome = await runStep(step: step) {
                try await manager.removeSignerFromRule(
                    ruleId: diff.ruleId,
                    signerId: onChainId,
                    selectedSigners: selectedSigners
                )
            }
            switch outcome {
            case .ok(let hash):
                completed += 1
                if let hash { hashes.append(hash) }
            case .failed(let result):
                return result.toEditResult(
                    completed: completed, total: total, hashes: hashes
                )
            }
        }

        // Step 4 — auth-context guard.
        //
        // The OZ SDK does not currently expose a typed error case for the
        // post-add-signer authorization-context mismatch. Adding signers
        // changes the on-chain authorization context for a rule, after which
        // subsequent operations in the same submission would reject with a
        // generic transaction-error string. Inspecting that string is brittle
        // (the wording depends on the contract revision and is not part of any
        // documented contract), so we keep a deterministic client-side guard:
        // when the diff added signers AND has subsequent policy/expiry
        // changes, pause the run and ask the user to re-submit those changes
        // against the freshly-reloaded rule.
        let hasPolicyOrExpiryChanges = !diff.removedPolicies.isEmpty ||
            !diff.newPolicies.isEmpty ||
            !diff.modifiedPolicies.isEmpty ||
            diff.expiryChanged
        if !diff.newSigners.isEmpty && hasPolicyOrExpiryChanges {
            let message = "Signer changes were applied successfully. Policy and expiration " +
                "updates were skipped because adding signers changes the rule's authorization " +
                "requirements. Please edit the rule again to apply the remaining changes."
            activityLog.info(message)
            return ContextRuleEditResult(
                success: true,
                completedOperations: completed,
                totalOperations: total,
                partialDueToAuthGuard: true,
                authGuardMessage: message,
                error: nil,
                failedStep: nil,
                transactionHashes: hashes
            )
        }

        // Step 5 — remove policies
        for (index, entry) in diff.removedPolicies.enumerated() {
            let step = "Removing policy \(index + 1) of \(diff.removedPolicies.count)"
            onProgress("Updating rule #\(diff.ruleId)...")
            guard let onChainId = entry.onChainId else {
                return ContextRuleEditResult(
                    success: false,
                    completedOperations: completed,
                    totalOperations: total,
                    partialDueToAuthGuard: false,
                    authGuardMessage: nil,
                    error: "Cannot remove policy without on-chain ID",
                    failedStep: step,
                    transactionHashes: hashes
                )
            }
            let outcome = await runStep(step: step) {
                try await manager.removePolicyFromRule(
                    ruleId: diff.ruleId,
                    policyId: onChainId,
                    selectedSigners: selectedSigners
                )
            }
            switch outcome {
            case .ok(let hash):
                completed += 1
                if let hash { hashes.append(hash) }
            case .failed(let result):
                return result.toEditResult(
                    completed: completed, total: total, hashes: hashes
                )
            }
        }

        // Step 6 — modify policies
        for (index, entry) in diff.modifiedPolicies.enumerated() {
            let step = "Updating policy \(index + 1) of \(diff.modifiedPolicies.count)"
            let outcome = await runModifyPolicy(
                manager: manager,
                ruleId: diff.ruleId,
                entry: entry,
                step: step,
                selectedSigners: selectedSigners,
                onProgress: onProgress
            )
            switch outcome {
            case .ok(let stepCount, let stepHashes):
                completed += stepCount
                hashes.append(contentsOf: stepHashes)
            case .partialFailure(let stepCount, let stepHashes, let result, let failedStep):
                completed += stepCount
                hashes.append(contentsOf: stepHashes)
                return ContextRuleEditResult(
                    success: false,
                    completedOperations: completed,
                    totalOperations: total,
                    partialDueToAuthGuard: false,
                    authGuardMessage: nil,
                    error: result.error,
                    failedStep: failedStep,
                    transactionHashes: hashes
                )
            }
        }

        // Step 7 — add policies
        for (index, entry) in diff.newPolicies.enumerated() {
            let step = "Adding policy \(index + 1) of \(diff.newPolicies.count)"
            onProgress("Updating rule #\(diff.ruleId)...")
            guard let spec = entry.installSpec else {
                return ContextRuleEditResult(
                    success: false,
                    completedOperations: completed,
                    totalOperations: total,
                    partialDueToAuthGuard: false,
                    authGuardMessage: nil,
                    error: "Cannot add policy without install parameters",
                    failedStep: step,
                    transactionHashes: hashes
                )
            }
            let outcome = await runStep(step: step) {
                try await self.dispatchAddPolicy(
                    manager: manager,
                    ruleId: diff.ruleId,
                    policyAddress: entry.address,
                    spec: spec,
                    selectedSigners: selectedSigners
                )
            }
            switch outcome {
            case .ok(let hash):
                completed += 1
                if let hash { hashes.append(hash) }
            case .failed(let result):
                return result.toEditResult(
                    completed: completed, total: total, hashes: hashes
                )
            }
        }

        // Step 8 — expiry
        if diff.expiryChanged {
            let step = "Updating expiration"
            onProgress("Updating rule #\(diff.ruleId)...")
            let outcome = await runStep(step: step) {
                try await manager.updateContextRuleValidUntil(
                    ruleId: diff.ruleId,
                    newValidUntil: diff.newExpiry,
                    selectedSigners: selectedSigners
                )
            }
            switch outcome {
            case .ok(let hash):
                completed += 1
                if let hash { hashes.append(hash) }
            case .failed(let result):
                return result.toEditResult(
                    completed: completed, total: total, hashes: hashes
                )
            }
        }

        activityLog.success("All \(completed) edit \(completed == 1 ? "operation" : "operations") completed successfully")
        return ContextRuleEditResult(
            success: true,
            completedOperations: completed,
            totalOperations: total,
            partialDueToAuthGuard: false,
            authGuardMessage: nil,
            error: nil,
            failedStep: nil,
            transactionHashes: hashes
        )
    }
    // swiftlint:enable cyclomatic_complexity function_body_length
}
