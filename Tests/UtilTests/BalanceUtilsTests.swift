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
import stellarsdk
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

    // -------------------------------------------------------------------------
    // MARK: - baseUnitsFromDecimalAmount(_:decimals:)
    // -------------------------------------------------------------------------

    @Test("baseUnitsFromDecimalAmount with 7 decimals scales by 10^7")
    func baseUnitsSevenDecimals() {
        #expect(baseUnitsFromDecimalAmount("1", decimals: 7) == "10000000")
        #expect(baseUnitsFromDecimalAmount("1.5", decimals: 7) == "15000000")
    }

    @Test("baseUnitsFromDecimalAmount with 2 decimals scales by 10^2")
    func baseUnitsTwoDecimals() {
        #expect(baseUnitsFromDecimalAmount("1", decimals: 2) == "100")
        #expect(baseUnitsFromDecimalAmount("12.34", decimals: 2) == "1234")
    }

    @Test("baseUnitsFromDecimalAmount with 0 decimals yields whole base units")
    func baseUnitsZeroDecimals() {
        #expect(baseUnitsFromDecimalAmount("42", decimals: 0) == "42")
        // Fractional digits beyond the token scale are rejected, not rounded.
        #expect(baseUnitsFromDecimalAmount("42.4", decimals: 0) == nil)
    }

    @Test("baseUnitsFromDecimalAmount with 18 decimals scales by 10^18")
    func baseUnitsEighteenDecimals() {
        #expect(baseUnitsFromDecimalAmount("1", decimals: 18) == "1000000000000000000")
    }

    @Test("baseUnitsFromDecimalAmount rejects negative decimals")
    func baseUnitsNegativeDecimalsRejected() {
        #expect(baseUnitsFromDecimalAmount("1", decimals: -1) == nil)
    }

    @Test("baseUnitsFromDecimalAmount rejects negative amount")
    func baseUnitsNegativeAmountRejected() {
        #expect(baseUnitsFromDecimalAmount("-1", decimals: 7) == nil)
    }

    @Test("baseUnitsFromDecimalAmount normalises comma decimal separator")
    func baseUnitsCommaSeparator() {
        #expect(baseUnitsFromDecimalAmount("1,5", decimals: 7) == "15000000")
    }

    @Test("baseUnitsFromDecimalAmount rejects zero and empty results")
    func baseUnitsZeroRejected() {
        #expect(baseUnitsFromDecimalAmount("0", decimals: 7) == nil)
        #expect(baseUnitsFromDecimalAmount("0.0", decimals: 7) == nil)
        #expect(baseUnitsFromDecimalAmount("", decimals: 7) == nil)
    }

    @Test("baseUnitsFromDecimalAmount rejects excess fractional precision")
    func baseUnitsExcessFraction() {
        // Eight fractional digits exceed the 7-decimal scale of native XLM.
        #expect(baseUnitsFromDecimalAmount("1.12345678", decimals: 7) == nil)
    }

    @Test("baseUnitsFromDecimalAmount returns full range above Int64.max")
    func baseUnitsAboveInt64Max() {
        // 1000 tokens at 18 decimals = 10^21 base units, far above Int64.max
        // (~9.22 * 10^18). The string result preserves the full value.
        let result = baseUnitsFromDecimalAmount("1000", decimals: 18)
        #expect(result == "1000000000000000000000")
        // Confirm the value genuinely exceeds the Int64 ceiling.
        #expect(Int64(result ?? "") == nil)
        #expect(Int128(result ?? "") == Int128(1000) * Int128(1_000_000_000_000_000_000))
    }

    @Test("baseUnitsFromDecimalAmount large 7-decimal amount above Int64.max")
    func baseUnitsLargeSevenDecimal() {
        // 1_000_000_000_000 XLM * 10^7 = 10^19 base units (> Int64.max).
        let result = baseUnitsFromDecimalAmount("1000000000000", decimals: 7)
        #expect(result == "10000000000000000000")
        #expect(Int64(result ?? "") == nil)
    }

    // -------------------------------------------------------------------------
    // MARK: - formatBaseUnitsAsDecimal(_:decimals:)
    // -------------------------------------------------------------------------

    @Test("formatBaseUnitsAsDecimal Int128 with 2 decimals")
    func formatTwoDecimals() {
        #expect(formatBaseUnitsAsDecimal(Int128(1234), decimals: 2) == "12.34")
        #expect(formatBaseUnitsAsDecimal(Int128(100), decimals: 2) == "1.0")
    }

    @Test("formatBaseUnitsAsDecimal Int128 with 0 decimals appends .0")
    func formatZeroDecimals() {
        #expect(formatBaseUnitsAsDecimal(Int128(42), decimals: 0) == "42.0")
    }

    @Test("formatBaseUnitsAsDecimal default overload matches 7-decimal explicit form")
    func formatDefaultMatchesSeven() {
        #expect(
            formatBaseUnitsAsDecimal(Int128(15_000_000)) ==
            formatBaseUnitsAsDecimal(Int128(15_000_000), decimals: 7)
        )
    }

    @Test("baseUnitsFromDecimalAmount and formatBaseUnitsAsDecimal round-trip at non-7 scale")
    func roundTripNonSevenScale() throws {
        let baseUnitsStr = try #require(baseUnitsFromDecimalAmount("12.34", decimals: 2))
        let baseUnits = try #require(Int128(baseUnitsStr))
        #expect(formatBaseUnitsAsDecimal(baseUnits, decimals: 2) == "12.34")
    }

    @Test("Large spending-limit decimal round-trips through encode and read")
    func roundTripLargeSpendingLimit() throws {
        // 1000 tokens at 18 decimals overflows Int64; the full value must survive
        // the decimal -> base units -> OZPolicyInstallParams.toScVal -> Int128 -> display round trip.
        let decimals = 18
        let original = "1000"
        let baseUnitsStr = try #require(baseUnitsFromDecimalAmount(original, decimals: decimals))

        let params = OZPolicyInstallParams.spendingLimit(
            spendingLimit: baseUnitsStr,
            periodLedgers: 100
        )
        let scVal = try params.toScVal()
        guard case .map(let entriesOpt) = scVal, let entries = entriesOpt,
              let limitEntry = entries.first(where: {
                  if case .symbol("spending_limit") = $0.key { return true }
                  return false
              }) else {
            Issue.record("Expected spending_limit entry")
            return
        }
        let decoded = try SACBalanceFetcher.extractI128AsInt128(from: limitEntry.val)
        #expect(decoded == Int128(1000) * Int128(1_000_000_000_000_000_000))
        #expect(formatBaseUnitsAsDecimal(decoded, decimals: decimals) == "1000.0")
    }
}
