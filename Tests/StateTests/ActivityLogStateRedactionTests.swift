// ActivityLogStateRedactionTests.swift
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
// MARK: - ActivityLogStateRedactionTests
// ============================================================================

/// Proves that the redaction deny-list in ActivityLogState.redact(_:) works.
///
/// Each test case asserts that a specific category of sensitive content is
/// replaced by the expected redaction token. Tests also verify that benign
/// content (addresses, operation names, short strings) is NOT redacted.
@MainActor
@Suite("ActivityLogState Redaction")
struct ActivityLogStateRedactionTests {

    // -------------------------------------------------------------------------
    // MARK: - WalletConnect URI
    // -------------------------------------------------------------------------

    @Test("WalletConnect URI is redacted")
    func walletConnectURIRedacted() {
        let input = "Pairing with wc:abc123xyz@2?relay-protocol=irn&symKey=deadbeef1234567890abcdef"
        let result = ActivityLogState.redact(input)
        #expect(!result.contains("wc:"))
        #expect(result.contains("[wc-uri:REDACTED]"))
    }

    @Test("String without wc: prefix is not redacted as WC URI")
    func nonWCStringNotRedacted() {
        let input = "Connecting to https://soroban-testnet.stellar.org"
        let result = ActivityLogState.redact(input)
        #expect(result == input)
    }

    // -------------------------------------------------------------------------
    // MARK: - Session Topic (64-char lowercase hex)
    // -------------------------------------------------------------------------

    @Test("64-char lowercase hex session topic is redacted")
    func sessionTopicRedacted() {
        let topic = String(repeating: "a1", count: 32) // 64 chars, lowercase hex
        let input = "Session topic: \(topic)"
        let result = ActivityLogState.redact(input)
        #expect(!result.contains(topic))
        #expect(result.contains("[topic:REDACTED]"))
    }

    @Test("Short hex strings are not redacted as session topics")
    func shortHexNotRedacted() {
        // 8-char hex (a typical short ID fragment) should not be redacted
        let input = "Error code: deadbeef in module"
        let result = ActivityLogState.redact(input)
        #expect(result == input)
    }

    @Test("64-char uppercase hex is also redacted (case-insensitive pattern)")
    func uppercaseHexAlsoRedacted() {
        let topic = String(repeating: "A1", count: 32) // 64 chars uppercase
        let input = "Value: \(topic)"
        let result = ActivityLogState.redact(input)
        // Both lowercase and uppercase 64-char hex are redacted (e.g. raw Ed25519 keys).
        #expect(!result.contains(topic))
        #expect(result.contains("[topic:REDACTED]"))
    }

    // -------------------------------------------------------------------------
    // MARK: - XDR Envelope (≥200 char base64)
    // -------------------------------------------------------------------------

    @Test("Base64 blob of 200+ characters is redacted as XDR")
    func longBase64RedactedAsXdr() {
        // Simulate a transaction XDR envelope (base64-encoded, no spaces)
        let longBase64 = String(repeating: "AAAA", count: 52) // 208 chars
        let input = "Transaction envelope: \(longBase64)"
        let result = ActivityLogState.redact(input)
        #expect(!result.contains(longBase64))
        #expect(result.contains("[xdr:REDACTED]"))
    }

    // -------------------------------------------------------------------------
    // MARK: - Signing Payload (100-199 char base64)
    // -------------------------------------------------------------------------

    @Test("Base64 blob of 100-199 characters is redacted as payload")
    func mediumBase64RedactedAsPayload() {
        let midBase64 = String(repeating: "AAAA", count: 26) // 104 chars
        let input = "Auth digest: \(midBase64)"
        let result = ActivityLogState.redact(input)
        #expect(!result.contains(midBase64))
        #expect(result.contains("[payload:REDACTED]"))
    }

    @Test("Short base64 strings under 100 chars are not redacted")
    func shortBase64NotRedacted() {
        // 40 chars of base64 — typical for small values, should not be redacted
        let short = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" // 40 chars
        let input = "Key data: \(short)"
        let result = ActivityLogState.redact(input)
        #expect(result == input)
    }

    // -------------------------------------------------------------------------
    // MARK: - Credential ID Truncation
    // -------------------------------------------------------------------------

    @Test("Credential ID longer than 16 chars is truncated")
    func credentialIdTruncated() {
        // "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGH"
        // first 8: "abcdefgh", last 8: "ABCDEFGH"
        let credentialId = "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGH"
        let result = ActivityLogState.redactCredentialId(credentialId)
        #expect(result.hasPrefix("cred[abcdefgh]"))
        #expect(result.hasSuffix("[ABCDEFGH]"))
        #expect(!result.contains("ijklmnopqrstuvwxyz0123456789"))
    }

    @Test("Short credential ID under 16 chars is returned unchanged")
    func shortCredentialIdUnchanged() {
        let shortId = "abc12345"
        let result = ActivityLogState.redactCredentialId(shortId)
        #expect(result == shortId)
    }

    @Test("Credential ID of exactly 16 chars is returned unchanged")
    func exactly16CharsUnchanged() {
        let exactId = "abcdefghijklmnop"
        let result = ActivityLogState.redactCredentialId(exactId)
        #expect(result == exactId)
    }

    // -------------------------------------------------------------------------
    // MARK: - Benign Content Passes Through
    // -------------------------------------------------------------------------

    @Test("Stellar C-address is not redacted")
    func contractAddressNotRedacted() {
        let address = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
        let input = "Contract: \(address)"
        let result = ActivityLogState.redact(input)
        // C-addresses are 56 chars uppercase Base32 — not base64, not 64-char lowercase hex
        #expect(result == input)
    }

    @Test("Transaction hash (hex, 64 chars) is redacted as topic")
    func txHashRedacted() {
        // Transaction hashes are 64-char lowercase hex — same pattern as session topics.
        // Policy: both are redacted. The log allows "transaction submitted" messages
        // but callers should use truncated tx hashes (first 8 chars) for display.
        let txHash = String(repeating: "a1", count: 32)
        let result = ActivityLogState.redact("Submitted tx: \(txHash)")
        #expect(result.contains("[topic:REDACTED]"))
    }

    @Test("Short operation name passes through unchanged")
    func operationNameNotRedacted() {
        let input = "createWallet completed successfully"
        let result = ActivityLogState.redact(input)
        #expect(result == input)
    }

    @Test("RPC URL passes through unchanged")
    func rpcUrlNotRedacted() {
        let input = "Connected to https://soroban-testnet.stellar.org"
        let result = ActivityLogState.redact(input)
        #expect(result == input)
    }

    // -------------------------------------------------------------------------
    // MARK: - Stellar Secret Seed Redaction (iOS-3)
    // -------------------------------------------------------------------------

    @Test("Stellar secret seed (S + 55 base32 chars) is redacted")
    func stellarSeedRedacted() {
        // A valid Stellar secret seed (S followed by 55 base32 chars) generated
        // fresh at runtime, so no secret-seed literal is committed.
        let seed = (try! KeyPair.generateRandomKeyPair().secretSeed) ?? ""
        let input = "Signing with seed: \(seed)"
        let result = ActivityLogState.redact(input)
        #expect(!result.contains(seed))
        #expect(result.contains("[seed:REDACTED]"))
    }

    @Test("A 57-character base32 string is not redacted as a seed")
    func tooLongBase32NotRedactedAsSeed() {
        // 57 chars: S + 56 base32 chars — one char longer than a seed, not a valid StrKey seed.
        // The lookaround prevents matching a seed pattern inside a longer base32 sequence.
        let notASeed = "S" + String(repeating: "A", count: 56)
        let input = "Value: \(notASeed)"
        let result = ActivityLogState.redact(input)
        // Must not be redacted as a seed (it is longer than the 56-char seed shape).
        #expect(!result.contains("[seed:REDACTED]"))
    }

    @Test("Stellar G-address is not redacted as a seed")
    func gAddressNotRedactedAsSeed() {
        // G-addresses start with 'G', not 'S', so they never match the seed pattern.
        let address = "GAAZI4TCR3TY5OJHCTJC2A4QSY6CJWJH5IAJTGKIN2ER7LBNVKOCCWN"
        let input = "Source account: \(address)"
        let result = ActivityLogState.redact(input)
        #expect(!result.contains("[seed:REDACTED]"))
        #expect(result.contains(address))
    }

    // -------------------------------------------------------------------------
    // MARK: - redactDigest API (iOS-5)
    // -------------------------------------------------------------------------

    @Test("redactDigest returns correct placeholder for 32-byte digest")
    func redactDigest32Bytes() {
        let digest = Data(repeating: 0xAB, count: 32)
        let result = ActivityLogState.redactDigest(digest)
        #expect(result == "[digest:redacted (32B)]")
    }

    @Test("redactDigest includes the actual byte count")
    func redactDigestByteCount() {
        let digest = Data(repeating: 0x00, count: 16)
        let result = ActivityLogState.redactDigest(digest)
        #expect(result.contains("16B"))
    }

    // -------------------------------------------------------------------------
    // MARK: - Windowed Context Lower-Threshold Base64 (iOS-5)
    // -------------------------------------------------------------------------

    @Test("40-char base64 adjacent to 'payload' keyword is redacted")
    func shortBase64NearPayloadKeywordRedacted() {
        // 44 chars of base64 — a 32-byte SHA-256 digest base64-encoded.
        let b64 = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" // 44 chars
        let input = "auth_digest: \(b64)"
        let result = ActivityLogState.redact(input)
        #expect(!result.contains(b64))
        #expect(result.contains("[payload:REDACTED]"))
    }

    @Test("40-char base64 outside payload context is not redacted")
    func shortBase64OutsideContextNotRedacted() {
        // Same 44-char base64 value, but no payload-context keyword nearby.
        let b64 = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" // 44 chars
        let input = "Activity log started. Value: \(b64)"
        let result = ActivityLogState.redact(input)
        // No keyword ('payload', 'auth_digest', 'signature', 'digest') in context window.
        #expect(result.contains(b64), "Benign short base64 outside context must pass through unchanged")
    }

    @Test("40-char base64 adjacent to 'signature' keyword is redacted")
    func shortBase64NearSignatureKeywordRedacted() {
        let b64 = String(repeating: "Ab", count: 22) // 44 chars, valid base64 chars
        let input = "signature: \(b64)"
        let result = ActivityLogState.redact(input)
        #expect(!result.contains(b64))
        #expect(result.contains("[payload:REDACTED]"))
    }

    // -------------------------------------------------------------------------
    // MARK: - ActivityLogState Append
    // -------------------------------------------------------------------------

    @Test("addEntry prepends and caps at maxEntries")
    func addEntryCapsAtMax() {
        let log = ActivityLogState()
        let limit = ActivityLogState.maxEntries

        for i in 0 ..< limit + 5 {
            log.info("Message \(i)")
        }

        #expect(log.entries.count == limit)
        // Newest message is at index 0
        #expect(log.entries[0].message == "Message \(limit + 4)")
    }

    @Test("clear() removes all entries")
    func clearRemovesEntries() {
        let log = ActivityLogState()
        log.info("one")
        log.success("two")
        log.error("three")
        log.clear()
        #expect(log.entries.isEmpty)
    }

    @Test("LogLevel is preserved")
    func logLevelPreserved() {
        let log = ActivityLogState()
        log.info("info msg")
        log.success("success msg")
        log.error("error msg")

        // Entries are newest-first: error → success → info
        #expect(log.entries[0].level == .error)
        #expect(log.entries[1].level == .success)
        #expect(log.entries[2].level == .info)
    }
}
