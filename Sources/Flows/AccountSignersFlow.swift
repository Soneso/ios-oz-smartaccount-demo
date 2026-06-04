// AccountSignersFlow.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - SignerEntry
// ============================================================================

/// A unique signer aggregated across every context rule on the connected
/// smart account, together with the set of rules that reference it.
///
/// `loadAccountSigners()` deduplicates the signers returned by
/// `OZContextRuleManager.listContextRules()` by
/// `OZSmartAccountBuilders.getSignerKey(signer:)` and collects the rule
/// memberships for each unique signer in insertion order. The screen renders
/// one row per `SignerEntry` with rule-membership chips drawn from
/// `contextRules`.
public struct SignerEntry: Sendable {

    /// The unique smart account signer (passkey, delegated, or Ed25519).
    public let signer: any OZSmartAccountSigner

    /// Context rules whose `signers` list contains this signer.
    ///
    /// Order preserved from the rule fetch (numerically ascending id, as
    /// returned by `OZContextRuleManager.listContextRules()`).
    public let contextRules: [OZParsedContextRule]

    public init(signer: any OZSmartAccountSigner, contextRules: [OZParsedContextRule]) {
        self.signer = signer
        self.contextRules = contextRules
    }
}

// ============================================================================
// MARK: - AccountSignersFlow
// ============================================================================

/// Business logic for the read-only "Account Signers" screen.
///
/// Loads every on-chain context rule via `ContextRuleManagerType.listContextRules()`,
/// flattens their signer lists, deduplicates by
/// `OZSmartAccountBuilders.getSignerKey(signer:)`, and groups each unique
/// signer with the rules that reference it. The screen presents a
/// non-interactive list — there is no add, remove, or edit path from here.
///
/// Thread safety:
/// `@MainActor` because it mutates `ActivityLogState`. All public methods are
/// `async` and must be awaited from a `Task` / `.task` modifier.
///
/// Re-entrancy:
/// `isLoading` guards against duplicate fetches when the screen's "Refresh"
/// button is tapped while a load is already in flight. The user-facing button
/// is disabled by the screen, but the guard is an additional safeguard.
@MainActor
public final class AccountSignersFlow {

    // -------------------------------------------------------------------------
    // MARK: - Dependencies
    // -------------------------------------------------------------------------

    private let demoState: DemoState
    private let activityLog: ActivityLogState
    private let contextRuleManager: (any ContextRuleManagerType)?

    // -------------------------------------------------------------------------
    // MARK: - Re-entrancy guard
    // -------------------------------------------------------------------------

    private var isLoading: Bool = false

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates an `AccountSignersFlow`.
    ///
    /// - Parameters:
    ///   - demoState: Shared observable demo state, queried for connection state only.
    ///   - activityLog: Shared activity log; receives one info entry per successful load.
    ///   - contextRuleManager: Adapter over `OZContextRuleManager`. `nil` causes
    ///     `loadAccountSigners()` to throw `SmartAccountWalletException.NotConnected`.
    public init(
        demoState: DemoState,
        activityLog: ActivityLogState,
        contextRuleManager: (any ContextRuleManagerType)? = nil
    ) {
        self.demoState = demoState
        self.activityLog = activityLog
        self.contextRuleManager = contextRuleManager
    }

    // -------------------------------------------------------------------------
    // MARK: - Public: loadAccountSigners
    // -------------------------------------------------------------------------

    /// Fetches every context rule for the connected smart account, deduplicates
    /// the union of their signers by stable signer key, and returns one
    /// `SignerEntry` per unique signer with the list of rules it appears in.
    ///
    /// - Returns: One `SignerEntry` per unique signer, ordered by first
    ///   appearance across the rule list.
    /// - Throws: `SmartAccountWalletException.NotConnected` when there is no connected
    ///   wallet; the underlying SDK error when the rule fetch fails.
    public func loadAccountSigners() async throws -> [SignerEntry] {
        guard !isLoading else { return [] }
        guard demoState.isConnected, let manager = contextRuleManager else {
            throw SmartAccountWalletException.NotConnected(message: "No wallet connected.")
        }
        isLoading = true
        defer { isLoading = false }

        let rules = try await manager.listContextRules()
        let entries = aggregate(rules: rules)
        let signerWord = entries.count == 1 ? "signer" : "signers"
        let ruleWord = rules.count == 1 ? "context rule" : "context rules"
        activityLog.info(
            "Loaded \(entries.count) unique \(signerWord) from \(rules.count) \(ruleWord)."
        )
        return entries
    }

    // -------------------------------------------------------------------------
    // MARK: - Private: aggregate
    // -------------------------------------------------------------------------

    /// Deduplicates the union of signers across `rules` by signer key and
    /// preserves insertion order. For each unique signer, collects the rules
    /// whose `signers` list contains an entry with the same key.
    private func aggregate(rules: [OZParsedContextRule]) -> [SignerEntry] {
        var seen: Set<String> = []
        var keysInOrder: [String] = []
        var signerByKey: [String: any OZSmartAccountSigner] = [:]
        var rulesByKey: [String: [OZParsedContextRule]] = [:]

        for rule in rules {
            for signer in rule.signers {
                let key = OZSmartAccountBuilders.getSignerKey(signer: signer)
                if seen.insert(key).inserted {
                    keysInOrder.append(key)
                    signerByKey[key] = signer
                    rulesByKey[key] = [rule]
                } else if rulesByKey[key]?.contains(where: { $0.id == rule.id }) == false {
                    rulesByKey[key]?.append(rule)
                }
            }
        }

        return keysInOrder.compactMap { key -> SignerEntry? in
            guard let signer = signerByKey[key] else { return nil }
            let memberships = rulesByKey[key] ?? []
            return SignerEntry(signer: signer, contextRules: memberships)
        }
    }
}
