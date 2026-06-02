// SACBalanceFetcherTests.swift
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
// MARK: - SACBalanceFetcherTests
// ============================================================================

/// Tests for `SACBalanceFetcher` and the `BalanceFetchError` type.
///
/// Network-facing methods (`fetchBalance(contract:account:kit:)`) are
/// integration-only and not exercised here. This file covers:
/// - `extractI128AsInt128(from:)` — lossless pure decoding logic, no network.
/// - `BalanceFetchError` error descriptions — formatting contracts.
///
/// Running:
///   swift test --filter "SACBalanceFetcher"
@Suite("SACBalanceFetcher")
struct SACBalanceFetcherTests {

    // -------------------------------------------------------------------------
    // MARK: - i128 decoding (lossless via Int128)
    // -------------------------------------------------------------------------

    @Test("extractI128AsInt128: zero i128 returns 0")
    func extractI128Zero() throws {
        let scVal = SCValXDR.i128(Int128PartsXDR(hi: 0, lo: 0))
        let result = try SACBalanceFetcher.extractI128AsInt128(from: scVal)
        #expect(result == 0)
    }

    @Test("extractI128AsInt128: small positive balance returns exact value")
    func extractI128SmallPositive() throws {
        // 100_000_000 stroops = 10 XLM.
        let scVal = SCValXDR.i128(Int128PartsXDR(hi: 0, lo: 100_000_000))
        let result = try SACBalanceFetcher.extractI128AsInt128(from: scVal)
        #expect(result == 100_000_000)
    }

    @Test("extractI128AsInt128: lo at maximum UInt64 (hi=0) returns 2^64 - 1")
    func extractI128MaxUInt64Lo() throws {
        // Maximum unsigned 64-bit lo with hi=0 reconstructs as 2^64 - 1
        // exactly; no two's-complement sign reinterpretation.
        let scVal = SCValXDR.i128(Int128PartsXDR(hi: 0, lo: UInt64.max))
        let result = try SACBalanceFetcher.extractI128AsInt128(from: scVal)
        let expected: Int128 = (Int128(1) << 64) - 1
        #expect(result == expected)
    }

    @Test("extractI128AsInt128: hi=1 lo=0 reconstructs as 2^64")
    func extractI128HighLimbOne() throws {
        let scVal = SCValXDR.i128(Int128PartsXDR(hi: 1, lo: 0))
        let result = try SACBalanceFetcher.extractI128AsInt128(from: scVal)
        #expect(result == Int128(1) << 64)
    }

    @Test("extractI128AsInt128: hi=1 lo=42 reconstructs as 2^64 + 42")
    func extractI128HighLimbOneLoFortyTwo() throws {
        let scVal = SCValXDR.i128(Int128PartsXDR(hi: 1, lo: 42))
        let result = try SACBalanceFetcher.extractI128AsInt128(from: scVal)
        #expect(result == (Int128(1) << 64) + 42)
    }

    @Test("extractI128AsInt128: large positive hi reconstructs full 128-bit value")
    func extractI128LargeHi() throws {
        let hi: Int64 = 0xDEAD_BEEF
        let lo: UInt64 = 12_345
        let scVal = SCValXDR.i128(Int128PartsXDR(hi: hi, lo: lo))
        let result = try SACBalanceFetcher.extractI128AsInt128(from: scVal)
        let expected: Int128 = (Int128(hi) << 64) + Int128(lo)
        #expect(result == expected)
    }

    @Test("extractI128AsInt128: maximum positive i128 (hi=Int64.max, lo=UInt64.max) returns Int128.max")
    func extractI128MaxPositive() throws {
        let scVal = SCValXDR.i128(Int128PartsXDR(hi: Int64.max, lo: UInt64.max))
        let result = try SACBalanceFetcher.extractI128AsInt128(from: scVal)
        #expect(result == Int128.max)
    }

    @Test("extractI128AsInt128: hi=-1 lo=0 reconstructs as -2^64")
    func extractI128NegativeHighLimb() throws {
        let scVal = SCValXDR.i128(Int128PartsXDR(hi: -1, lo: 0))
        let result = try SACBalanceFetcher.extractI128AsInt128(from: scVal)
        #expect(result == -(Int128(1) << 64))
    }

    @Test("extractI128AsInt128: minimum i128 (hi=Int64.min, lo=0) returns Int128.min")
    func extractI128MinNegative() throws {
        let scVal = SCValXDR.i128(Int128PartsXDR(hi: Int64.min, lo: 0))
        let result = try SACBalanceFetcher.extractI128AsInt128(from: scVal)
        #expect(result == Int128.min)
    }

    @Test("extractI128AsInt128: non-i128 SCVal throws unexpectedReturnType")
    func extractI128WrongTypeThrows() throws {
        let scVal = SCValXDR.bool(true)
        #expect(throws: BalanceFetchError.self) {
            _ = try SACBalanceFetcher.extractI128AsInt128(from: scVal)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - BalanceFetchError descriptions
    // -------------------------------------------------------------------------

    @Test("BalanceFetchError.simulationFailed has a localizedDescription")
    func balanceFetchSimulationFailedDescription() throws {
        let err = BalanceFetchError.simulationFailed(reason: "timeout")
        let desc = err.errorDescription
        #expect(desc != nil)
        let message = try #require(desc)
        #expect(message.contains("simulation") || message.contains("failed"))
    }

    @Test("BalanceFetchError.unexpectedReturnType has a localizedDescription")
    func balanceFetchUnexpectedTypeDescription() throws {
        let err = BalanceFetchError.unexpectedReturnType(detail: "got bool")
        let desc = err.errorDescription
        #expect(desc != nil)
        let message = try #require(desc)
        #expect(message.contains("Unexpected") || message.contains("type"))
    }

    @Test("BalanceFetchError.simulationFailed reason is included in description")
    func balanceFetchSimulationFailedIncludesReason() throws {
        let reason = "RPC_ENDPOINT_UNREACHABLE"
        let err = BalanceFetchError.simulationFailed(reason: reason)
        let message = try #require(err.errorDescription)
        #expect(message.contains(reason))
    }

    @Test("BalanceFetchError.unexpectedReturnType detail is included in description")
    func balanceFetchUnexpectedTypeIncludesDetail() throws {
        let detail = "Expected i128 SCVal, got bool"
        let err = BalanceFetchError.unexpectedReturnType(detail: detail)
        let message = try #require(err.errorDescription)
        #expect(message.contains(detail))
    }

    // -------------------------------------------------------------------------
    // MARK: - Simulation source address
    // -------------------------------------------------------------------------

    @Test("SACBalanceFetcher simulation source address is a valid G-address")
    func simulationSourceAddressIsValidGAddress() {
        let addr = SACBalanceFetcher.simulationSourceAddress
        // A valid Stellar G-address is 56 characters starting with 'G'.
        #expect(addr.count == 56)
        #expect(addr.hasPrefix("G"))
    }
}
