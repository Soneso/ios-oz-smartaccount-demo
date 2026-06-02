// FormatUtils.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation

// ============================================================================
// MARK: - Address Formatting
// ============================================================================

/// Truncates a Stellar address for compact display, keeping `chars` characters
/// at each end separated by an ellipsis.
///
/// If the address is shorter than `2 * chars + 3` the full value is returned
/// unchanged — truncation would remove more characters than the ellipsis saves.
///
/// Examples:
/// - `truncateAddress("GABCDEFG", chars: 4)` → `"GABCDEFG"` (unchanged; already short)
/// - `truncateAddress("GABCDEFGHIJ...STUVWXYZ", chars: 4)` → `"GABC...WXYZ"`
///
/// - Parameters:
///   - address: Full Stellar G- or C-address.
///   - chars: Number of characters to preserve at each end. Default is 4.
public func truncateAddress(_ address: String, chars: Int = 4) -> String {
    let minLength = chars * 2 + 3
    guard address.count > minLength else { return address }
    let prefix = address.prefix(chars)
    let suffix = address.suffix(chars)
    return "\(prefix)...\(suffix)"
}

/// Truncates a Stellar contract address for compact display (12 + 12 format).
///
/// Shows the first 12 characters, an ellipsis, and the last 12 characters so
/// both the "C" prefix region and the checksum suffix are visible. This is the
/// canonical truncation for C-addresses used across pickers and cards.
///
/// If the address is 28 characters or fewer the full value is returned unchanged.
///
/// - Parameter address: Full Stellar C-address.
public func truncateContractAddress(_ address: String) -> String {
    truncateAddress(address, chars: 12)
}

// ============================================================================
// MARK: - Date Formatting
// ============================================================================

/// A shared ISO 8601 date formatter for log timestamps and export strings.
///
/// Configured with fractional seconds (millisecond precision) and UTC timezone
/// to produce unambiguous, sortable strings across locales.
///
/// Declared `nonisolated(unsafe)` to satisfy Swift 6 strict concurrency:
/// ISO8601DateFormatter is documented thread-safe after configuration, and
/// this instance is configured once at initialisation and never mutated.
nonisolated(unsafe) private let iso8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

/// Formats a `Date` as an ISO 8601 UTC string with millisecond precision.
///
/// Suitable for activity log timestamps and debug exports.
///
/// - Parameter date: The date to format.
/// - Returns: A string such as `"2026-05-16T14:32:01.123Z"`.
public func formatTimestamp(_ date: Date) -> String {
    iso8601Formatter.string(from: date)
}

/// A shared short time formatter for in-app display (HH:mm:ss).
///
/// See the `nonisolated(unsafe)` note on `iso8601Formatter` above.
nonisolated(unsafe) private let shortTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter
}()

/// Formats a `Date` as a short UTC time string for activity log list items.
///
/// - Parameter date: The date to format.
/// - Returns: A string such as `"14:32:01"`.
public func formatShortTime(_ date: Date) -> String {
    shortTimeFormatter.string(from: date)
}

// ============================================================================
// MARK: - Hex Encoding / Decoding
// ============================================================================

/// Converts a `Data` value to a lowercase hexadecimal string.
///
/// - Parameter data: The bytes to encode.
/// - Returns: A lowercase hex string of length `data.count * 2`.
public func hexString(from data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

/// Decodes a hexadecimal string to `Data`.
///
/// - Parameter hex: An even-length string of hexadecimal digits (case-insensitive).
/// - Returns: The decoded bytes, or `nil` if `hex` has odd length or contains
///   non-hex characters.
public func data(fromHex hex: String) -> Data? {
    guard hex.count.isMultiple(of: 2) else { return nil }
    var result = Data(capacity: hex.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
        let byteIndex = hex.index(index, offsetBy: 2)
        guard let byte = UInt8(hex[index ..< byteIndex], radix: 16) else { return nil }
        result.append(byte)
        index = byteIndex
    }
    return result
}
