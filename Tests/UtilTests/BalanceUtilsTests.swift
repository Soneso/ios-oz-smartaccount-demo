// BalanceUtilsTests.swift
// SmartAccountDemoTests
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
#if canImport(UIKit)
@testable import SmartAccountDemoLib
#else
@testable import SmartAccountDemoMacLib
#endif
import Testing

// ============================================================================
// MARK: - BalanceUtilsTests
// ============================================================================

/// Tests for `formatBaseUnitsAsDecimal` in `BalanceUtils.swift`.
///
/// Covers the integer arithmetic path (via Int64), the string-parsing overload,
/// and edge cases including zero, the Int64 minimum, and values with fractional
/// trailing zeros.
@Suite("BalanceUtils")
struct BalanceUtilsTests {

    // -------------------------------------------------------------------------
    // MARK: - formatBaseUnitsAsDecimal(Int64)
    // -------------------------------------------------------------------------

    @Test("Zero base units formats as 0.0")
    func zeroBaseUnits() {
        #expect(formatBaseUnitsAsDecimal(Int64(0)) == "0.0")
    }

    @Test("Exactly 1 XLM (10_000_000 stroops) formats as 1.0")
    func oneXlm() {
        #expect(formatBaseUnitsAsDecimal(Int64(10_000_000)) == "1.0")
    }

    @Test("100 XLM formats correctly")
    func oneHundredXlm() {
        #expect(formatBaseUnitsAsDecimal(Int64(1_000_000_000)) == "100.0")
    }

    @Test("0.5 XLM (5_000_000 stroops) formats as 0.5")
    func halfXlm() {
        #expect(formatBaseUnitsAsDecimal(Int64(5_000_000)) == "0.5")
    }

    @Test("Fractional part with trailing zeros strips extras, keeps 1")
    func trailingZerosStripped() {
        // 10_100_000 stroops = 1.01 XLM (last 5 fractional digits are 0)
        #expect(formatBaseUnitsAsDecimal(Int64(10_100_000)) == "1.01")
    }

    @Test("All 7 fractional digits preserved when non-zero")
    func allFractionalDigits() {
        // 1_234_567 stroops = 0.1234567 XLM
        #expect(formatBaseUnitsAsDecimal(Int64(1_234_567)) == "0.1234567")
    }

    @Test("Negative amount formats with leading minus")
    func negativeAmount() {
        #expect(formatBaseUnitsAsDecimal(Int64(-10_000_000)) == "-1.0")
    }

    @Test("Int64.min returns the literal string without crash")
    func int64Min() {
        #expect(formatBaseUnitsAsDecimal(Int64.min) == "-922337203685.4775808")
    }

    @Test("Int64.max formats without overflow")
    func int64Max() {
        // Int64.max = 9_223_372_036_854_775_807 stroops
        // = 922337203685.4775807 XLM
        let result = formatBaseUnitsAsDecimal(Int64.max)
        #expect(result.hasPrefix("922337203685."))
        #expect(result.hasSuffix("7"))
    }

    // -------------------------------------------------------------------------
    // MARK: - formatBaseUnitsAsDecimal(String)
    // -------------------------------------------------------------------------

    @Test("String overload parses and formats valid base-units string")
    func stringOverloadValid() {
        #expect(formatBaseUnitsAsDecimal("10000000") == "1.0")
    }

    @Test("String overload returns 0.0 for non-numeric input")
    func stringOverloadInvalid() {
        #expect(formatBaseUnitsAsDecimal("not-a-number") == "0.0")
    }

    @Test("String overload returns 0.0 for empty string")
    func stringOverloadEmpty() {
        #expect(formatBaseUnitsAsDecimal("") == "0.0")
    }

    // -------------------------------------------------------------------------
    // MARK: - formatBaseUnitsAsDecimal(Int128) — lossless overload
    // -------------------------------------------------------------------------

    @Test("Int128 overload: zero formats as 0.0")
    func int128Zero() {
        #expect(formatBaseUnitsAsDecimal(Int128(0)) == "0.0")
    }

    @Test("Int128 overload: 1 XLM formats as 1.0")
    func int128OneXlm() {
        #expect(formatBaseUnitsAsDecimal(Int128(10_000_000)) == "1.0")
    }

    @Test("Int128 overload: 0.5 XLM formats as 0.5")
    func int128HalfXlm() {
        #expect(formatBaseUnitsAsDecimal(Int128(5_000_000)) == "0.5")
    }

    @Test("Int128 overload: fractional trailing zeros stripped, keeps at least one digit")
    func int128TrailingZeros() {
        #expect(formatBaseUnitsAsDecimal(Int128(10_100_000)) == "1.01")
    }

    @Test("Int128 overload: all 7 fractional digits preserved when non-zero")
    func int128AllFractionalDigits() {
        #expect(formatBaseUnitsAsDecimal(Int128(1_234_567)) == "0.1234567")
    }

    @Test("Int128 overload: negative amount formats with leading minus")
    func int128Negative() {
        #expect(formatBaseUnitsAsDecimal(Int128(-10_000_000)) == "-1.0")
    }

    @Test("Int128 overload: value beyond Int64 range survives losslessly")
    func int128BeyondInt64Range() {
        // 2^64 base units, well above Int64.max; Int64-based formatters would
        // require sentinel substitution. The Int128 formatter preserves it.
        let baseUnits: Int128 = Int128(1) << 64
        let formatted = formatBaseUnitsAsDecimal(baseUnits)
        // 2^64 = 18_446_744_073_709_551_616 base units = 1_844_674_407_370.9551616 whole tokens
        #expect(formatted == "1844674407370.9551616")
    }

    @Test("Int128 overload: maximum positive i128 (Int128.max) formats exactly")
    func int128MaxPositive() {
        // Int128.max = 2^127 - 1 = 170141183460469231731687303715884105727 (39 digits).
        // Divide by 10^7 base units per whole token — insert the decimal point 7 digits from
        // the right:
        //   whole = 17_014_118_346_046_923_173_168_730_371_588
        //   frac  = 4_105_727
        let formatted = formatBaseUnitsAsDecimal(Int128.max)
        #expect(formatted == "17014118346046923173168730371588.4105727")
    }

    @Test("Int128 overload: minimum i128 (Int128.min) formats exactly")
    func int128MinNegative() {
        // Int128.min = -(2^127) = -170141183460469231731687303715884105728.
        // Same digit layout as Int128.max except the last digit and the sign;
        // the formatter delegates to String(Int128.min) which produces the
        // exact decimal expansion of the minimum.
        let formatted = formatBaseUnitsAsDecimal(Int128.min)
        #expect(formatted == "-17014118346046923173168730371588.4105728")
    }

    @Test("Int128 overload: very small positive (1 base unit) formats correctly")
    func int128OneBaseUnit() {
        #expect(formatBaseUnitsAsDecimal(Int128(1)) == "0.0000001")
    }

    @Test("Int128 overload: very small negative (-1 base unit) formats correctly")
    func int128MinusOneBaseUnit() {
        #expect(formatBaseUnitsAsDecimal(Int128(-1)) == "-0.0000001")
    }

    // -------------------------------------------------------------------------
    // MARK: - formatSmallestUnitsAsDecimal(Int128) — token-agnostic alias
    // -------------------------------------------------------------------------

    @Test("formatSmallestUnitsAsDecimal Int128 overload forwards to formatBaseUnitsAsDecimal")
    func smallestUnitsInt128Aliases() {
        let value: Int128 = 10_000_000
        #expect(formatSmallestUnitsAsDecimal(value) == formatBaseUnitsAsDecimal(value))
    }
}
