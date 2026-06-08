// ContextRuleBuilderCore+SpendingDecimals.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ContextRuleBuilderCore: spending-limit decimals resolution
// ============================================================================

extension ContextRuleBuilderCore {

    /// The guarded token contract for a parsed (on-chain) rule: the call-contract
    /// target, or `nil` for default / create-contract rules.
    ///
    /// Used in edit mode to scale a stored spending-limit amount with the token's
    /// own decimals when pre-populating the inline editor.
    internal func guardedTokenContract(for parsed: ParsedContextRuleInfo) -> String? {
        guard case .callContract(let address) = parsed.contextType else { return nil }
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The token contract a spending-limit policy on this rule would guard.
    ///
    /// A spending-limit policy applies to the rule's call-contract target, so a
    /// `.callContract` rule guards `contractAddress`. Other context types do not
    /// bind to a specific token, so the conversion uses native decimals.
    internal var spendingLimitGuardedToken: String? {
        guard contextTypeOption == .callContract else { return nil }
        let trimmed = contractAddress.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Resolves the decimal scale for the current guarded token and stores it in
    /// ``spendingLimitDecimals``.
    ///
    /// Native XLM and non-token rules resolve to ``nativeTokenDecimals`` without
    /// a network call. A custom guarded token's `decimals()` value is fetched via
    /// the flow. A fetch failure is surfaced through ``spendingLimitDecimalsError``
    /// and the activity log, and the stored decimals are left unchanged so the
    /// gated "Add" button prevents converting an amount with the wrong scale.
    @MainActor
    internal func resolveSpendingLimitDecimals() async {
        let guardedToken = spendingLimitGuardedToken
        spendingLimitDecimalsError = nil

        // Native XLM and non-token rules need no round trip.
        guard let guardedToken,
              guardedToken != DemoConfig.nativeTokenContract else {
            spendingLimitDecimals = nativeTokenDecimals
            return
        }

        // A malformed address is reported by the existing field validation; do
        // not fetch for it. Fall back to native decimals so a later valid entry
        // re-triggers resolution.
        guard isValidContractAddress(guardedToken) else {
            spendingLimitDecimals = nativeTokenDecimals
            return
        }

        do {
            let resolved = try await resolvedFlow().resolveSpendingLimitDecimals(
                forGuardedToken: guardedToken
            )
            spendingLimitDecimals = resolved
        } catch {
            let msg = ActivityLogState.redact(actionableMessage(for: error))
            spendingLimitDecimalsError =
                "Could not read token decimals for the guarded contract: \(msg)"
            activityLog.error("Could not read token decimals: \(msg)")
        }
    }
}
