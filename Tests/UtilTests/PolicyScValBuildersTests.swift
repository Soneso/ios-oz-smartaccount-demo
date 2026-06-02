// PolicyScValBuildersTests.swift
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
import Testing

// ============================================================================
// MARK: - PolicyScValBuildersTests
// ============================================================================

/// XDR encoding tests for `PolicyScValBuilders`.
///
/// These tests pin the exact on-chain encoding produced by each builder. Any drift
/// between the iOS and Flutter `PolicyScValBuilders` implementations will surface
/// when comparing XDR bytes against these fixtures. The fixture values were computed
/// from the SDK's `XDREncoder.encode` applied to the expected `SCValXDR` structure.
///
/// Tests do not require network access — all assertions are pure in-process encoding.
///
/// Note: `SCValXDR.map` carries `[SCMapEntryXDR]?` (optional). Guards below unwrap
/// both the enum case and the inner optional in a single multi-binding guard.
@Suite("PolicyScValBuilders")
struct PolicyScValBuildersTests {

    // -------------------------------------------------------------------------
    // MARK: - Simple threshold
    // -------------------------------------------------------------------------

    @Test("buildSimpleThresholdScVal encodes threshold=2 as SCVal map")
    func simpleThresholdStructure() throws {
        let result = PolicyScValBuilders.buildSimpleThresholdScVal(threshold: 2)

        // Must be an SCVal::Map with a non-nil entry array.
        guard case .map(let entriesOpt) = result, let entries = entriesOpt else {
            Issue.record("Expected .map with entries, got: \(result)")
            return
        }

        // Exactly one entry: { "threshold": U32(2) }
        #expect(entries.count == 1)

        let entry = entries[0]
        guard case .symbol(let key) = entry.key else {
            Issue.record("Expected .symbol key, got: \(entry.key)")
            return
        }
        #expect(key == "threshold")

        guard case .u32(let value) = entry.val else {
            Issue.record("Expected .u32 value, got: \(entry.val)")
            return
        }
        #expect(value == 2)
    }

    // XDR base64 fixture for threshold=3:
    //   SCVal::Map [ Symbol("threshold") => U32(3) ]
    // Computed once by XDREncoder.encode and pinned here for cross-platform parity checks.
    private static let simpleThreshold3Fixture =
        "AAAAEQAAAAEAAAABAAAADwAAAAl0aHJlc2hvbGQAAAAAAAADAAAAAw=="

    // XDR base64 fixture for spending_limit(limit=1_000_000, periodLedgers=100):
    //   SCVal::Map [ Symbol("period_ledgers") => U32(100),
    //                Symbol("spending_limit") => I128(0, 1_000_000) ]
    private static let spendingLimit1mPer100Fixture = [
        "AAAAEQAAAAEAAAACAAAADwAAAA5wZXJpb2RfbGVkZ2VycwAAAAAAAwAAAGQAAAAP",
        "AAAADnNwZW5kaW5nX2xpbWl0AAAAAAAKAAAAAAAAAAAAAAAAAA9CQA=="
    ].joined()

    // XDR base64 fixture for weighted_threshold([(bytes([0xAA,0xBB])=>1)], threshold=1):
    //   SCVal::Map [ Symbol("signer_weights") => Map[ Bytes([0xAA,0xBB]) => U32(1) ],
    //                Symbol("threshold")      => U32(1) ]
    private static let weightedThreshold1Fixture = [
        "AAAAEQAAAAEAAAACAAAADwAAAA5zaWduZXJfd2VpZ2h0cwAAAAAAEQAAAAEAAAAB",
        "AAAADQAAAAKquwAAAAAAAwAAAAEAAAAPAAAACXRocmVzaG9sZAAAAAAAAAMAAAAB"
    ].joined()

    @Test("buildSimpleThresholdScVal XDR base64 matches pinned fixture")
    func simpleThresholdXdrFixture() throws {
        let scVal = PolicyScValBuilders.buildSimpleThresholdScVal(threshold: 3)
        let bytes = Data(try XDREncoder.encode(scVal))
        #expect(bytes.base64EncodedString() == Self.simpleThreshold3Fixture)
    }

    @Test("buildSpendingLimitScVal XDR base64 matches pinned fixture")
    func spendingLimitXdrFixture() throws {
        let scVal = PolicyScValBuilders.buildSpendingLimitScVal(limit: 1_000_000, periodLedgers: 100)
        let bytes = Data(try XDREncoder.encode(scVal))
        #expect(bytes.base64EncodedString() == Self.spendingLimit1mPer100Fixture)
    }

    @Test("buildWeightedThresholdScVal XDR base64 matches pinned fixture")
    func weightedThresholdXdrFixture() throws {
        let signerScVal = SCValXDR.bytes(Data([0xAA, 0xBB]))
        let scVal = PolicyScValBuilders.buildWeightedThresholdScVal(
            weights: [(signer: signerScVal, weight: 1)],
            threshold: 1
        )
        let bytes = Data(try XDREncoder.encode(scVal))
        #expect(bytes.base64EncodedString() == Self.weightedThreshold1Fixture)
    }

    @Test("buildSimpleThresholdScVal XDR bytes are stable across calls")
    func simpleThresholdXdrStability() throws {
        let scVal1 = PolicyScValBuilders.buildSimpleThresholdScVal(threshold: 3)
        let scVal2 = PolicyScValBuilders.buildSimpleThresholdScVal(threshold: 3)

        let bytes1 = Data(try XDREncoder.encode(scVal1))
        let bytes2 = Data(try XDREncoder.encode(scVal2))

        #expect(bytes1 == bytes2)
    }

    @Test("buildSimpleThresholdScVal threshold=0 encodes without validation")
    func simpleThresholdZero() throws {
        // The builder does not validate the threshold — that is the contract's job.
        // This test confirms the builder encodes whatever value it receives.
        let result = PolicyScValBuilders.buildSimpleThresholdScVal(threshold: 0)
        guard case .map(let entriesOpt) = result, let entries = entriesOpt else {
            Issue.record("Expected .map with entries")
            return
        }
        guard case .u32(let value) = entries.first?.val else {
            Issue.record("Expected .u32")
            return
        }
        #expect(value == 0)
    }

    // -------------------------------------------------------------------------
    // MARK: - Spending limit
    // -------------------------------------------------------------------------

    @Test("buildSpendingLimitScVal encodes period_ledgers and spending_limit in alphabetical order")
    func spendingLimitStructure() throws {
        let result = PolicyScValBuilders.buildSpendingLimitScVal(
            limit: 1_000_000,
            periodLedgers: 100
        )

        guard case .map(let entriesOpt) = result, let entries = entriesOpt else {
            Issue.record("Expected .map with entries")
            return
        }

        // Two entries in alphabetical order: "period_ledgers" then "spending_limit".
        #expect(entries.count == 2)

        guard case .symbol(let key0) = entries[0].key else {
            Issue.record("Expected .symbol at [0]")
            return
        }
        #expect(key0 == "period_ledgers")

        guard case .u32(let period) = entries[0].val else {
            Issue.record("Expected .u32 at [0].val")
            return
        }
        #expect(period == 100)

        guard case .symbol(let key1) = entries[1].key else {
            Issue.record("Expected .symbol at [1]")
            return
        }
        #expect(key1 == "spending_limit")

        guard case .i128(let limitParts) = entries[1].val else {
            Issue.record("Expected .i128 at [1].val, got: \(entries[1].val)")
            return
        }
        #expect(limitParts.hi == 0)
        #expect(limitParts.lo == 1_000_000)
    }

    @Test("buildSpendingLimitScVal XDR bytes are stable for same inputs")
    func spendingLimitXdrStability() throws {
        let scVal1 = PolicyScValBuilders.buildSpendingLimitScVal(limit: 500, periodLedgers: 50)
        let scVal2 = PolicyScValBuilders.buildSpendingLimitScVal(limit: 500, periodLedgers: 50)

        let bytes1 = Data(try XDREncoder.encode(scVal1))
        let bytes2 = Data(try XDREncoder.encode(scVal2))
        #expect(bytes1 == bytes2)
    }

    @Test("buildSpendingLimitScVal differs for different limits")
    func spendingLimitDiffersForDifferentValues() throws {
        let limit100 = PolicyScValBuilders.buildSpendingLimitScVal(limit: 100, periodLedgers: 50)
        let limit200 = PolicyScValBuilders.buildSpendingLimitScVal(limit: 200, periodLedgers: 50)

        let bytesA = Data(try XDREncoder.encode(limit100))
        let bytesB = Data(try XDREncoder.encode(limit200))
        #expect(bytesA != bytesB)
    }

    // -------------------------------------------------------------------------
    // MARK: - Weighted threshold
    // -------------------------------------------------------------------------

    @Test("buildWeightedThresholdScVal produces signer_weights and threshold in alphabetical order")
    func weightedThresholdStructure() throws {
        // Build two mock signer ScVals.
        let signer1ScVal = SCValXDR.bytes(Data([0x01, 0x02, 0x03]))
        let signer2ScVal = SCValXDR.bytes(Data([0x04, 0x05, 0x06]))

        let result = PolicyScValBuilders.buildWeightedThresholdScVal(
            weights: [
                (signer: signer1ScVal, weight: 3),
                (signer: signer2ScVal, weight: 1)
            ],
            threshold: 2
        )

        guard case .map(let outerOpt) = result, let outer = outerOpt else {
            Issue.record("Expected outer .map with entries")
            return
        }

        // Two outer entries in alphabetical order: "signer_weights" then "threshold".
        #expect(outer.count == 2)

        guard case .symbol(let key0) = outer[0].key else {
            Issue.record("Expected .symbol at outer[0]")
            return
        }
        #expect(key0 == "signer_weights")

        guard case .symbol(let key1) = outer[1].key else {
            Issue.record("Expected .symbol at outer[1]")
            return
        }
        #expect(key1 == "threshold")

        guard case .u32(let threshold) = outer[1].val else {
            Issue.record("Expected .u32 at outer[1].val")
            return
        }
        #expect(threshold == 2)

        // Inner map must have 2 entries.
        guard case .map(let innerOpt) = outer[0].val, let inner = innerOpt else {
            Issue.record("Expected inner .map with entries at outer[0].val")
            return
        }
        #expect(inner.count == 2)
    }

    @Test("buildWeightedThresholdScVal empty weights encodes without crashing")
    func weightedThresholdEmpty() throws {
        let result = PolicyScValBuilders.buildWeightedThresholdScVal(weights: [], threshold: 1)
        guard case .map(let outerOpt) = result, let outer = outerOpt else {
            Issue.record("Expected .map with entries")
            return
        }
        guard case .map(let innerOpt) = outer[0].val, let inner = innerOpt else {
            Issue.record("Expected inner .map")
            return
        }
        #expect(inner.isEmpty)
    }

    @Test("buildWeightedThresholdScVal XDR bytes are stable for same inputs")
    func weightedThresholdXdrStability() throws {
        let signerScVal = SCValXDR.bytes(Data([0xAA, 0xBB]))
        let weights: [(signer: SCValXDR, weight: UInt32)] = [(signer: signerScVal, weight: 1)]

        let scVal1 = PolicyScValBuilders.buildWeightedThresholdScVal(weights: weights, threshold: 1)
        let scVal2 = PolicyScValBuilders.buildWeightedThresholdScVal(weights: weights, threshold: 1)

        let bytes1 = Data(try XDREncoder.encode(scVal1))
        let bytes2 = Data(try XDREncoder.encode(scVal2))
        #expect(bytes1 == bytes2)
    }

    @Test("buildWeightedThresholdScVal produces different XDR for different thresholds")
    func weightedThresholdDiffersForDifferentThreshold() throws {
        let signerScVal = SCValXDR.bytes(Data([0x01]))
        let weights: [(signer: SCValXDR, weight: UInt32)] = [(signer: signerScVal, weight: 2)]

        let aScVal = PolicyScValBuilders.buildWeightedThresholdScVal(weights: weights, threshold: 1)
        let bScVal = PolicyScValBuilders.buildWeightedThresholdScVal(weights: weights, threshold: 2)

        let aBytes = Data(try XDREncoder.encode(aScVal))
        let bBytes = Data(try XDREncoder.encode(bScVal))
        #expect(aBytes != bBytes)
    }

    // -------------------------------------------------------------------------
    // MARK: - OZPolicyManager sortMapByKeyXdr (used internally)
    // -------------------------------------------------------------------------

    @Test("Weighted threshold inner map is sorted by XDR byte order")
    func weightedThresholdInnerMapIsSorted() throws {
        // Build two signers with known XDR orderings. SCValXDR.bytes([0x00]) has
        // shorter / smaller XDR than SCValXDR.bytes([0xFF]); after sort the 0x00
        // signer should come first.
        let smallSigner = SCValXDR.bytes(Data([0x00]))
        let largeSigner = SCValXDR.bytes(Data([0xFF]))

        // Pass in reverse order; expect sorted output.
        let result = PolicyScValBuilders.buildWeightedThresholdScVal(
            weights: [
                (signer: largeSigner, weight: 1),
                (signer: smallSigner, weight: 2)
            ],
            threshold: 1
        )

        guard case .map(let outerOpt) = result, let outer = outerOpt,
              case .map(let innerOpt) = outer[0].val, let inner = innerOpt else {
            Issue.record("Expected nested .map structure with entries")
            return
        }

        // The first inner entry should be the smaller signer.
        guard case .bytes(let firstKey) = inner[0].key else {
            Issue.record("Expected .bytes key")
            return
        }
        #expect(firstKey == Data([0x00]))
    }
}
