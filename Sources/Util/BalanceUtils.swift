// BalanceUtils.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - Token Amount Conversion
// ============================================================================

/// Number of decimal places used by native XLM and the demo's same-scale tokens.
///
/// Native XLM is fixed at 7 decimals (1 XLM = 10^7 stroops). Callers that
/// convert a native-XLM amount pass this value so no `decimals()` round trip is
/// needed; callers that convert a custom token must resolve the token's own
/// decimals (via `OZTransactionOperations.fetchTokenDecimals`) and pass that.
public let nativeTokenDecimals: Int = 7

/// Converts a decimal token amount string (e.g. "100.5") to a canonical
/// base-units integer string.
///
/// Normalises the comma decimal separator to a dot before delegating to
/// `OZTransactionOperations.amountToBaseUnits(_:decimals:)`. Returning a
/// `String?` preserves the nil-on-invalid contract for callers that rely on
/// optional chaining rather than error handling (e.g. the approve flow).
///
/// - Parameters:
///   - value: Decimal amount string (whole or fractional). Returns `nil` for
///     negative inputs, unparseable strings, values carrying more fractional
///     digits than `decimals`, or a zero result.
///   - decimals: Number of fractional digits the token uses. Must be
///     non-negative; a negative value returns `nil`.
/// - Returns: Base-units amount as a non-negative decimal integer string, or
///   `nil` if the input cannot be represented as a positive base-units value.
public func baseUnitsFromDecimalAmount(_ value: String, decimals: Int) -> String? {
    guard decimals >= 0 else { return nil }
    let normalised = value
        .trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: ",", with: ".")
    return try? OZTransactionOperations.amountToBaseUnits(normalised, decimals: decimals)
}

// ============================================================================
// MARK: - Balance Formatting
// ============================================================================

/// Converts an `Int128` base-units amount to a display string using the
/// 7-decimal Stellar convention.
///
/// Inserts the decimal separator seven digits from the right of the magnitude,
/// strips trailing fractional zeros (keeping at least one), and re-attaches the
/// sign. All arithmetic is performed on the value's decimal string representation,
/// so the formatter inherits `Int128`'s full range.
///
/// - Parameter baseUnits: Amount in the token's smallest unit, as `Int128`.
/// - Returns: Formatted string such as "100.0", "0.5", or "10.1234567".
public func formatBaseUnitsAsDecimal(_ baseUnits: Int128) -> String {
    return formatBaseUnitsAsDecimal(baseUnits, decimals: nativeTokenDecimals)
}

/// Converts an `Int128` base-units amount to a display string scaled by `decimals`.
///
/// Splits the value's decimal-string magnitude `decimals` digits from the right,
/// strips trailing fractional zeros (keeping at least one), and re-attaches the
/// sign. `decimals == 0` yields a whole number followed by `.0`. All arithmetic
/// runs on the string representation so the formatter inherits `Int128`'s full
/// range with no `Int128.min` special case.
///
/// - Parameters:
///   - baseUnits: Amount in the token's smallest unit, as `Int128`.
///   - decimals: Number of fractional digits (negative values are treated as `0`).
/// - Returns: Formatted string such as "100.0", "0.5", or "10.1234567".
public func formatBaseUnitsAsDecimal(_ baseUnits: Int128, decimals: Int) -> String {
    let scale = max(0, decimals)
    let raw = String(baseUnits)
    let isNegative = raw.hasPrefix("-")
    var magnitude = isNegative ? String(raw.dropFirst()) : raw

    // Pad so the magnitude always has at least one whole-part digit and a
    // full `scale`-digit fractional component.
    let minLength = scale + 1
    if magnitude.count < minLength {
        magnitude = String(repeating: "0", count: minLength - magnitude.count) + magnitude
    }

    if scale == 0 {
        return "\(isNegative ? "-" : "")\(magnitude).0"
    }

    let splitIdx = magnitude.index(magnitude.endIndex, offsetBy: -scale)
    let whole = String(magnitude[..<splitIdx])
    var fractional = String(magnitude[splitIdx...])

    // Strip trailing zeros from the fractional component, keeping at least
    // one digit so the output always contains a decimal point.
    while fractional.count > 1 && fractional.last == "0" {
        fractional.removeLast()
    }

    return "\(isNegative ? "-" : "")\(whole).\(fractional)"
}

/// Token-agnostic alias for ``formatBaseUnitsAsDecimal(_:)`` for call sites that
/// prefer the "smallest units" phrasing (e.g. SEP-41 allowances).
///
/// Forwards to ``formatBaseUnitsAsDecimal(_:)`` so the 7-decimal Stellar
/// convention is applied in exactly one place.
///
/// - Parameter smallestUnits: Amount in the token's smallest unit, as `Int128`.
/// - Returns: Formatted string such as "100.0", "0.5", or "10.1234567".
public func formatSmallestUnitsAsDecimal(_ smallestUnits: Int128) -> String {
    return formatBaseUnitsAsDecimal(smallestUnits)
}

