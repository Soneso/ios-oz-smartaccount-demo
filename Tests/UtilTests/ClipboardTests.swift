// ClipboardTests.swift
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
// MARK: - FakeClipboard
// ============================================================================

/// Test double for `ClipboardService`.
///
/// Records the last call to `copy(_:sensitive:)` without touching the real
/// system pasteboard. Tests inject this type to verify that Flows and callers
/// invoke the protocol with the correct arguments.
final class FakeClipboard: ClipboardService, @unchecked Sendable {

    private(set) var lastText: String?
    private(set) var lastSensitive: Bool?
    private(set) var callCount: Int = 0

    func copy(_ text: String, sensitive: Bool) {
        lastText = text
        lastSensitive = sensitive
        callCount += 1
    }
}

// ============================================================================
// MARK: - ClipboardTests
// ============================================================================

/// Tests for the `ClipboardService` protocol and the `FakeClipboard` test double.
///
/// Real platform implementations (`UIKitClipboard`, `AppKitClipboard`) are
/// excluded from unit tests because they write to the system pasteboard, which
/// causes test flakiness and security warnings on CI. The protocol contract is
/// verified here via injection.
@Suite("ClipboardService")
struct ClipboardTests {

    // -------------------------------------------------------------------------
    // MARK: - Protocol Contract via FakeClipboard
    // -------------------------------------------------------------------------

    @Test("copy(_:sensitive:) forwards text to the backing store")
    func copyStoresText() {
        let fake = FakeClipboard()
        fake.copy("Hello, clipboard!", sensitive: false)
        #expect(fake.lastText == "Hello, clipboard!")
    }

    @Test("copy(_:sensitive:false) records non-sensitive flag")
    func copyNonSensitiveFlag() {
        let fake = FakeClipboard()
        fake.copy("public-address", sensitive: false)
        #expect(fake.lastSensitive == false)
    }

    @Test("copy(_:sensitive:true) records sensitive flag")
    func copySensitiveFlag() {
        let fake = FakeClipboard()
        fake.copy("s3cr3t-material", sensitive: true)
        #expect(fake.lastSensitive == true)
    }

    @Test("Multiple copy calls update lastText each time")
    func multipleCopiesUpdateLastText() {
        let fake = FakeClipboard()
        fake.copy("first", sensitive: false)
        fake.copy("second", sensitive: true)
        #expect(fake.lastText == "second")
        #expect(fake.callCount == 2)
    }

    @Test("Empty string is copied without error")
    func emptyStringCopied() {
        let fake = FakeClipboard()
        fake.copy("", sensitive: false)
        #expect(fake.lastText?.isEmpty == true)
    }

    // -------------------------------------------------------------------------
    // MARK: - Protocol Conformance
    // -------------------------------------------------------------------------

    @Test("FakeClipboard conforms to ClipboardService")
    func fakeConformsToProtocol() {
        // Verify that FakeClipboard is usable wherever ClipboardService is expected.
        let service: any ClipboardService = FakeClipboard()
        service.copy("check", sensitive: false)
        // No assertion needed — type-checking at compile time proves conformance.
        #expect(true)
    }
}
