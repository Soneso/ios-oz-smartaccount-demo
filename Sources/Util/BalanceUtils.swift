// BalanceUtils.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - Stellar Amount Conversion
// ============================================================================

/// Converts a decimal XLM amount string (e.g. "100.5") to stroops (Int64).
///
/// Uses `NSDecimalNumberHandler` rounding (bankers' rounding, scale 0) to avoid
/// floating-point representation artefacts at high decimal counts. The caller's
/// explicit bounds check (`stroopsDecimal <= maxAllowed`) gates the `Int64`
/// conversion; `raiseOnOverflow: false` keeps the path NSException-free so the
/// returned `nil` is the single failure signal callers must handle.
///
/// - Parameter value: Decimal amount string (whole or fractional). Returns `nil`
///   for negative inputs, unparseable strings, or values that would exceed
///   `Int64.max` stroops.
/// - Returns: Stroops amount as `Int64`, or `nil` if the input cannot be
///   represented as a non-negative `Int64` stroop value.
public func stroopsFromDecimalAmount(_ value: String) -> Int64? {
    // Normalise the decimal separator to a dot so comma-decimal-separator
    // locales (e.g. de_DE) are handled identically to en_US_POSIX. The amount
    // field in the UI already validates via `validateAmount` with the same
    // normalisation; this guard keeps the conversion function independent of
    // that upstream step. `Decimal(string:)` does not accept a Locale parameter.
    let normalised = value.replacingOccurrences(of: ",", with: ".")
    guard let decimal = Decimal(string: normalised), decimal >= 0 else { return nil }
    let multiplier = Decimal(StellarProtocolConstants.stroopsPerXlm)
    let stroopsDecimal = decimal * multiplier
    let maxAllowed = Decimal(Int64.max)
    guard stroopsDecimal <= maxAllowed else { return nil }
    let number = NSDecimalNumber(decimal: stroopsDecimal)
    let handler = NSDecimalNumberHandler(
        roundingMode: .bankers,
        scale: 0,
        raiseOnExactness: false,
        raiseOnOverflow: false,
        raiseOnUnderflow: false,
        raiseOnDivideByZero: false
    )
    let rounded = number.rounding(accordingToBehavior: handler)
    return rounded.int64Value
}

// ============================================================================
// MARK: - Balance Formatting
// ============================================================================

/// Converts a stroops amount to a display string with up to 7 decimal places.
///
/// Uses integer arithmetic throughout to avoid floating-point formatting
/// artefacts. Trailing fractional zeros are stripped (e.g. 10_000_000 →
/// "1.0", not "1.0000000"). The only preserved trailing zero is the single
/// digit after the decimal point to ensure the output always contains a ".".
///
/// Special case: `Int64.min` cannot be negated in two's complement;
/// it is returned as the literal string "-922337203685.4775808".
///
/// - Parameter stroops: Amount in the token's smallest unit (1 XLM = 10^7 stroops).
/// - Returns: Formatted string such as "100.0", "0.5", or "10.1234567".
public func formatStroopsAsXlm(_ stroops: Int64) -> String {
    if stroops == Int64.min {
        // Int64.min cannot be negated; return the literal decimal representation.
        return "-922337203685.4775808"
    }
    let negative = stroops < 0
    let absStroops = negative ? -stroops : stroops
    let wholePart = absStroops / 10_000_000
    let fractionalPart = absStroops % 10_000_000
    let fractionalStr = String(fractionalPart)
        .padLeft(toLength: 7, with: "0")
        .trimTrailingZeros(keepAtLeast: 1)
    return "\(negative ? "-" : "")\(wholePart).\(fractionalStr)"
}

/// Parses a stroops string (as returned by Soroban RPC) and formats it for display.
///
/// Returns "0.0" if the string cannot be parsed as an Int64.
///
/// - Parameter stroopsStr: Numeric string in the token's smallest unit.
public func formatStroopsAsXlm(_ stroopsStr: String) -> String {
    guard let stroops = Int64(stroopsStr) else { return "0.0" }
    return formatStroopsAsXlm(stroops)
}

/// Token-agnostic alias for ``formatStroopsAsXlm(_:)`` for use at call sites
/// that format SEP-41 token amounts other than XLM (e.g. DEMO allowances).
///
/// The underlying formatter is pure decimal scaling — it has no XLM-specific
/// behaviour beyond the 7-decimal Stellar convention shared by all SEP-41
/// tokens — so this alias preserves intent at the call site without adding a
/// distinct implementation.
///
/// - Parameter smallestUnits: Amount in the token's smallest unit (1 token
///   unit = 10^7 smallest units, matching the Stellar 7-decimal convention).
/// - Returns: Formatted string such as "100.0", "0.5", or "10.1234567".
public func formatSmallestUnitsAsDecimal(_ smallestUnits: Int64) -> String {
    return formatStroopsAsXlm(smallestUnits)
}

/// `Int128` overload of ``formatStroopsAsXlm(_:)-(Int64)``.
///
/// Used on the read paths that decode an `i128` on-chain balance and must
/// preserve the full 128-bit signed range without truncating to `Int64`.
/// Formats via the same Stellar 7-decimal convention: insert the decimal
/// separator seven digits from the right of the magnitude, strip trailing
/// fractional zeros (keeping at least one), and re-attach the sign.
///
/// All arithmetic is performed on the value's decimal string representation,
/// so the formatter inherits `Int128`'s full range without needing a separate
/// `Int128.min` special case: `String(Int128.min)` already produces the exact
/// decimal expansion `"-170141183460469231731687303715884105728"`.
///
/// - Parameter stroops: Amount in the token's smallest unit, as `Int128`.
/// - Returns: Formatted string such as "100.0", "0.5", or "10.1234567".
public func formatStroopsAsXlm(_ stroops: Int128) -> String {
    let raw = String(stroops)
    let isNegative = raw.hasPrefix("-")
    var magnitude = isNegative ? String(raw.dropFirst()) : raw

    // Pad so the magnitude always has at least one whole-part digit and a
    // full seven-digit fractional component.
    if magnitude.count < 8 {
        magnitude = String(repeating: "0", count: 8 - magnitude.count) + magnitude
    }

    let splitIdx = magnitude.index(magnitude.endIndex, offsetBy: -7)
    let whole = String(magnitude[..<splitIdx])
    var fractional = String(magnitude[splitIdx...])

    // Strip trailing zeros from the fractional component, keeping at least
    // one digit so the output always contains a decimal point.
    while fractional.count > 1 && fractional.last == "0" {
        fractional.removeLast()
    }

    return "\(isNegative ? "-" : "")\(whole).\(fractional)"
}

/// `Int128` overload of ``formatSmallestUnitsAsDecimal(_:)-(Int64)``.
///
/// Same role as the `Int64` overload — preserves intent at SEP-41 call sites
/// that are not formatting XLM. Forwards to ``formatStroopsAsXlm(_:)-(Int128)``
/// so the 7-decimal Stellar convention is applied in exactly one place.
///
/// - Parameter smallestUnits: Amount in the token's smallest unit, as `Int128`.
/// - Returns: Formatted string such as "100.0", "0.5", or "10.1234567".
public func formatSmallestUnitsAsDecimal(_ smallestUnits: Int128) -> String {
    return formatStroopsAsXlm(smallestUnits)
}

// ============================================================================
// MARK: - Private String Helpers
// ============================================================================

private extension String {

    /// Returns a new string left-padded with `character` to reach `length`.
    func padLeft(toLength length: Int, with character: Character) -> String {
        guard count < length else { return self }
        return String(repeating: character, count: length - count) + self
    }

    /// Strips trailing characters matching `character`, keeping at least `min`.
    func trimTrailingZeros(keepAtLeast min: Int) -> String {
        var result = self
        while result.count > min && result.last == "0" {
            result.removeLast()
        }
        return result
    }
}
