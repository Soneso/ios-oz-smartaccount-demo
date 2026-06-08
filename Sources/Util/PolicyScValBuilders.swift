// PolicyScValBuilders.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - PolicyScValBuilders
// ============================================================================

/// Hand-rolled `SCValXDR` builders for OZ smart-account policy installation parameters.
///
/// These functions construct the `SCVal::Map` values that the OZ smart-account contract
/// expects as the `install_params` argument when adding a policy via `add_policy`.
/// The map key ordering follows alphabetical / XDR byte ordering requirements imposed
/// by the Soroban host.
///
/// On-chain schema overview:
/// - `threshold`:         `Map { "threshold": U32 }`
/// - `spending_limit`:    `Map { "period_ledgers": U32, "spending_limit": I128 }`
/// - `weighted_threshold`: `Map { "signer_weights": Map[SCVal => U32], "threshold": U32 }`
///
/// All builders are pure functions — no network calls, no stored state.
public enum PolicyScValBuilders {

    // =========================================================================
    // MARK: - Simple threshold
    // =========================================================================

    /// Builds the `SCValXDR` for a simple M-of-N threshold policy.
    ///
    /// On-chain map structure (alphabetical key order):
    /// ```
    /// Map { Symbol("threshold"): U32(threshold) }
    /// ```
    ///
    /// The threshold contract requires at least `threshold` of the context rule's
    /// signers to have signed for an operation to be authorised.
    ///
    /// - Parameter threshold: Number of signatures required. Must be > 0.
    /// - Returns: An `SCValXDR.map` suitable for passing as `installParams` to the
    ///            `add_policy` contract call.
    public static func buildSimpleThresholdScVal(threshold: UInt32) -> SCValXDR {
        let entries: [SCMapEntryXDR] = [
            SCMapEntryXDR(key: .symbol("threshold"), val: .u32(threshold))
        ]
        return .map(entries)
    }

    // =========================================================================
    // MARK: - Spending limit
    // =========================================================================

    /// Builds the `SCValXDR` for a spending limit policy.
    ///
    /// On-chain map structure (alphabetical key order):
    /// ```
    /// Map {
    ///   Symbol("period_ledgers"): U32(periodLedgers),
    ///   Symbol("spending_limit"): I128(limit)
    /// }
    /// ```
    ///
    /// The spending limit contract enforces that no more than `limit` base units may be
    /// transferred within a rolling window of `periodLedgers` ledgers. The token contract
    /// address is stored in the context rule, not in `installParams` — this builder does
    /// not accept a token parameter because it does not belong in the encoded map.
    /// The `limit` is expressed as an `Int64` base-units value (positive) which fits safely
    /// into the I128 low word.
    ///
    /// - Parameters:
    ///   - limit: Maximum base units allowed per period (positive, fits in Int64).
    ///   - periodLedgers: Rolling reset period expressed as a ledger count. Must be > 0.
    /// - Returns: An `SCValXDR.map` suitable for passing as `installParams`.
    public static func buildSpendingLimitScVal(
        limit: Int64,
        periodLedgers: UInt32
    ) -> SCValXDR {
        // The limit is always non-negative in the demo context. Use i128 with hi=0
        // to encode the positive value in the low word.
        let limitI128 = SCValXDR.i128(
            Int128PartsXDR(hi: limit < 0 ? -1 : 0, lo: UInt64(bitPattern: limit))
        )
        let entries: [SCMapEntryXDR] = [
            SCMapEntryXDR(key: .symbol("period_ledgers"), val: .u32(periodLedgers)),
            SCMapEntryXDR(key: .symbol("spending_limit"), val: limitI128)
        ]
        return .map(entries)
    }

    // =========================================================================
    // MARK: - Weighted threshold
    // =========================================================================

    /// Builds the `SCValXDR` for a weighted-threshold policy.
    ///
    /// On-chain map structure (alphabetical key order):
    /// ```
    /// Map {
    ///   Symbol("signer_weights"): Map[SCValXDR(signer) => U32(weight)],
    ///   Symbol("threshold"): U32(threshold)
    /// }
    /// ```
    ///
    /// The inner `signer_weights` map is sorted by the XDR-encoded byte representation
    /// of each signer key, matching the ordering the Soroban host enforces for `ScMap`
    /// key uniqueness. Duplicate signers are not de-duplicated here — the contract host
    /// will reject them at simulation time.
    ///
    /// - Parameters:
    ///   - weights: Array of (signer ScVal, weight) pairs. Each signer must be an
    ///              already-encoded `SCValXDR` (e.g. from `OZSmartAccountSigner.toScVal()`).
    ///   - threshold: Minimum total weight required for authorization. Must be > 0.
    /// - Returns: An `SCValXDR.map` suitable for passing as `installParams`.
    public static func buildWeightedThresholdScVal(
        weights: [(signer: SCValXDR, weight: UInt32)],
        threshold: UInt32
    ) -> SCValXDR {
        var innerEntries: [SCMapEntryXDR] = weights.map { pair in
            SCMapEntryXDR(key: pair.signer, val: .u32(pair.weight))
        }

        // Sort the inner map by XDR-encoded byte ordering of each key.
        // The Soroban host rejects ScMap values with unsorted keys.
        innerEntries = OZPolicyManager.sortMapByKeyXdr(innerEntries)

        let outerEntries: [SCMapEntryXDR] = [
            SCMapEntryXDR(
                key: .symbol("signer_weights"),
                val: .map(innerEntries)
            ),
            SCMapEntryXDR(
                key: .symbol("threshold"),
                val: .u32(threshold)
            )
        ]
        return .map(outerEntries)
    }
}
