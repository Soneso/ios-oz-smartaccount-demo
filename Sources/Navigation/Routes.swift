// Routes.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation

// ============================================================================
// MARK: - Route
// ============================================================================

/// All navigation destinations in the Smart Account Demo.
///
/// This enum is the single source of truth for the app's navigation graph.
/// Both the iOS (`NavigationStack`) and macOS (`NavigationSplitView`) route
/// handlers in their respective `RootView.swift` files map cases to views.
/// Each case is declared parameter-free unless the destination genuinely
/// needs payload data; only `contextRuleEditor` currently does.
public enum Route: Hashable {

    /// Main dashboard screen (kit init, balances, activity log, navigation).
    case main

    /// Wallet creation wizard (username entry, passkey ceremony, deploy options).
    case walletCreation

    /// Wallet connection screen (auto / indexer / direct / retry-pending).
    case walletConnection

    /// Transfer screen (XLM + DEMO token, single and multi-signer).
    case transfer

    /// Context rules list screen (read-only: list, view, remove).
    ///
    /// Operates on the currently connected wallet; carries no associated values.
    case contextRules

    /// Context rule builder screen (add: signers, policies, validUntil).
    ///
    /// Reached from the context rules screen via the `+ Add Rule` button. The
    /// builder owns its own form state and submits via `ContextRuleFlow`.
    case contextRuleBuilder

    /// Context rule builder screen pre-populated for editing an existing rule.
    ///
    /// Reached from the context rules screen via the `Edit Rule` button on
    /// each `ContextRuleCard`. Carries the on-chain rule identifier so the
    /// builder can load the rule and dispatch per-operation updates.
    case contextRuleEditor(id: UInt32)

    /// Account signers screen (aggregated read-only view of all signers
    /// registered on the connected smart account across every context rule).
    case accountSigners

    /// Approve screen for granting DEMO token spending allowances from the
    /// connected smart account.
    case approve
}
