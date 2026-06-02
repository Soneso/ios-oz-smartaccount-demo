// FormatUtilsTests.swift
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
// MARK: - FormatUtilsTests
// ============================================================================

/// Tests for all public functions in `FormatUtils.swift`.
@Suite("FormatUtils")
struct FormatUtilsTests {

    // -------------------------------------------------------------------------
    // MARK: - truncateAddress
    // -------------------------------------------------------------------------

    @Test("Short address (at or below threshold) is returned unchanged")
    func shortAddressUnchanged() {
        // "GABC...WXYZ" — 11 chars, which is below the 2*4+3=11 char threshold;
        // the function returns the string unchanged when count <= minLength.
        let short = "GABCWXYZ"
        #expect(truncateAddress(short, chars: 4) == short)
    }

    @Test("Long address is truncated with ellipsis")
    func longAddressIsTruncated() {
        // A typical 56-char Stellar G-address.
        let address = "GAAZI4TCR3TY5OJHCTJC2A4QSY6CJWJH5IAJTGKIN2ER7LBNVKOCCWN"
        let result = truncateAddress(address, chars: 4)
        #expect(result == "GAAZ...CCWN")
    }

    @Test("Empty address is returned unchanged")
    func emptyAddressUnchanged() {
        #expect(truncateAddress("", chars: 4).isEmpty)
    }

    @Test("Default chars parameter is 4")
    func defaultCharsIsFour() {
        let address = "GAAZI4TCR3TY5OJHCTJC2A4QSY6CJWJH5IAJTGKIN2ER7LBNVKOCCWN"
        // Calling with and without explicit chars should give the same result.
        #expect(truncateAddress(address) == truncateAddress(address, chars: 4))
    }

    @Test("C-address is truncated correctly")
    func contractAddressTruncated() {
        let cAddress = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
        let result = truncateAddress(cAddress, chars: 4)
        #expect(result == "CDLZ...CYSC")
    }

    // -------------------------------------------------------------------------
    // MARK: - formatTimestamp
    // -------------------------------------------------------------------------

    @Test("formatTimestamp produces a non-empty ISO 8601 string")
    func formatTimestampNonEmpty() {
        let result = formatTimestamp(Date())
        #expect(!result.isEmpty)
        // ISO 8601 with internet date-time always contains 'T' and 'Z'.
        #expect(result.contains("T"))
        #expect(result.hasSuffix("Z"))
    }

    @Test("formatTimestamp output is parseable back to a Date")
    func formatTimestampRoundTrip() {
        let now = Date()
        let formatted = formatTimestamp(now)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsed = formatter.date(from: formatted)
        #expect(parsed != nil)
        // Round-trip precision: within 1 millisecond.
        if let parsed {
            #expect(abs(parsed.timeIntervalSince(now)) < 0.001)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - formatShortTime
    // -------------------------------------------------------------------------

    @Test("formatShortTime produces an HH:mm:ss string")
    func formatShortTimeFormat() {
        // Use a known fixed date: 2026-05-16 14:32:01 UTC
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 16
        components.hour = 14
        components.minute = 32
        components.second = 1
        components.timeZone = TimeZone(identifier: "UTC")
        let calendar = Calendar(identifier: .gregorian)
        if let date = calendar.date(from: components) {
            #expect(formatShortTime(date) == "14:32:01")
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - hexString(from:)
    // -------------------------------------------------------------------------

    @Test("hexString encodes single byte as two lowercase hex chars")
    func hexStringSingleByte() {
        let data = Data([0xAB])
        #expect(hexString(from: data) == "ab")
    }

    @Test("hexString encodes known bytes correctly")
    func hexStringKnownBytes() {
        let data = Data([0x00, 0xFF, 0x10, 0x0F])
        #expect(hexString(from: data) == "00ff100f")
    }

    @Test("hexString for empty data is empty string")
    func hexStringEmpty() {
        #expect(hexString(from: Data()).isEmpty)
    }

    // -------------------------------------------------------------------------
    // MARK: - data(fromHex:)
    // -------------------------------------------------------------------------

    @Test("data(fromHex:) decodes lowercase hex correctly")
    func dataFromHexLowercase() {
        let result = data(fromHex: "ab00ff")
        #expect(result == Data([0xAB, 0x00, 0xFF]))
    }

    @Test("data(fromHex:) decodes uppercase hex correctly")
    func dataFromHexUppercase() {
        let result = data(fromHex: "AB00FF")
        #expect(result == Data([0xAB, 0x00, 0xFF]))
    }

    @Test("data(fromHex:) round-trips with hexString(from:)")
    func dataFromHexRoundTrip() {
        let original = Data([0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0])
        let hex = hexString(from: original)
        let decoded = data(fromHex: hex)
        #expect(decoded == original)
    }

    @Test("data(fromHex:) returns nil for odd-length input")
    func dataFromHexOddLength() {
        #expect(data(fromHex: "abc") == nil)
    }

    @Test("data(fromHex:) returns nil for non-hex characters")
    func dataFromHexInvalidChars() {
        #expect(data(fromHex: "zz") == nil)
    }

    @Test("data(fromHex:) returns empty Data for empty string")
    func dataFromHexEmpty() {
        let result = data(fromHex: "")
        #expect(result == Data())
    }
}
