// ActivityLogState.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Combine
import Foundation

// ============================================================================
// MARK: - LogLevel
// ============================================================================

/// Severity level for an activity log entry.
public enum LogLevel: Sendable {
    case info
    case success
    case error
}

// ============================================================================
// MARK: - LogEntry
// ============================================================================

/// An immutable record in the activity log.
public struct LogEntry: Identifiable, Sendable {

    public let id: UUID
    public let message: String
    public let level: LogLevel
    public let timestamp: Date

    public init(message: String, level: LogLevel, timestamp: Date = Date()) {
        self.id = UUID()
        self.message = message
        self.level = level
        self.timestamp = timestamp
    }
}

// ============================================================================
// MARK: - ActivityLogState
// ============================================================================

/// Append-only observable activity log shared across all screens.
///
/// Screens display the log to show the user what operations are in progress or
/// have completed. Log entries are prepended (newest first) and capped at
/// `maxEntries` to prevent unbounded memory growth.
///
/// Uses `ObservableObject` with `@Published` for iOS 16 compatibility
/// (`@Observable` requires iOS 17+).
///
/// SECURITY: The log is visible on-screen and may be copied by the user.
/// All callers MUST pass messages through `redact(_:)` before logging any
/// value that contains credential IDs, session topics, or XDR payloads.
/// See the deny-list in `redact(_:)` for the full policy.
@MainActor
public final class ActivityLogState: ObservableObject {

    // -------------------------------------------------------------------------
    // MARK: - Constants
    // -------------------------------------------------------------------------

    /// Maximum number of entries retained in memory.
    ///
    /// Oldest entries beyond this limit are discarded. 50 provides adequate
    /// debug history without accumulating unbounded memory for long-lived sessions.
    nonisolated static let maxEntries = 50

    // -------------------------------------------------------------------------
    // MARK: - State
    // -------------------------------------------------------------------------

    /// All log entries, newest first.
    @Published public private(set) var entries: [LogEntry] = []

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    public init() {}

    // -------------------------------------------------------------------------
    // MARK: - Append
    // -------------------------------------------------------------------------

    /// Adds a new entry to the log.
    ///
    /// The entry is prepended so that the newest item is always at index 0.
    /// Entries beyond `maxEntries` are dropped from the tail.
    public func addEntry(_ message: String, level: LogLevel = .info) {
        let entry = LogEntry(message: message, level: level)
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
    }

    /// Logs an informational message.
    public func info(_ message: String) {
        addEntry(message, level: .info)
    }

    /// Logs a success message.
    public func success(_ message: String) {
        addEntry(message, level: .success)
    }

    /// Logs an error message.
    public func error(_ message: String) {
        addEntry(message, level: .error)
    }

    /// Removes all entries.
    public func clear() {
        entries.removeAll()
    }

    // -------------------------------------------------------------------------
    // MARK: - Redaction
    // -------------------------------------------------------------------------

    /// Returns `input` with any values matching the deny-list replaced by
    /// the corresponding redaction tokens.
    ///
    /// The deny-list covers patterns that MUST NOT appear in the visible log:
    ///
    /// | Pattern | Replacement |
    /// |---|---|
    /// | WalletConnect URIs (`wc:` prefix) | `[wc-uri:REDACTED]` |
    /// | Session topics / tx hashes (64-char hex, any case) | `[topic:REDACTED]` |
    /// | Stellar secret seeds (`S` + 55 base32 chars) | `[seed:REDACTED]` |
    /// | XDR blobs (bare base64 ≥ 200 chars) | `[xdr:REDACTED]` |
    /// | Signing payloads (bare base64 100-199 chars) | `[payload:REDACTED]` |
    /// | Auth digests / short payloads adjacent to payload-context keywords | `[payload:REDACTED]` |
    /// | Base64-like values (≥ 40 chars) adjacent to `contract_id` / `contractId` / `rule_name` / `ruleName` | `[payload:REDACTED]` |
    ///
    /// Callers that produce structured messages (e.g. "credential: <id>") should
    /// call `redactCredentialId(_:)` for the ID component rather than relying on
    /// this function to detect it in free-form text. Callers with known auth
    /// digests as `Data` should call `redactDigest(_:)` instead.
    public nonisolated static func redact(_ input: String) -> String {
        var result = input

        // WalletConnect URI: starts with "wc:" and contains base64-like payload.
        // Replace the full URI to avoid leaking the embedded topic or key material.
        result = replacePattern(
            in: result,
            pattern: #"wc:[A-Za-z0-9+/=@:?&%-]{10,}"#,
            replacement: "[wc-uri:REDACTED]"
        )

        // Stellar secret seed: 'S' followed by exactly 55 Stellar base32 characters
        // (A-Z and 2-7 only). The lookarounds prevent matching inside longer base32
        // sequences (XDR blobs, contract hashes, G-addresses, C-addresses).
        result = replacePattern(
            in: result,
            pattern: #"(?<![A-Z2-7])S[A-Z2-7]{55}(?![A-Z2-7])"#,
            replacement: "[seed:REDACTED]"
        )

        // Session topic / tx hash: 64 hex characters (any case) standing alone.
        // Both lowercase (WalletConnect topics) and mixed/uppercase (raw key material)
        // are covered. The lookarounds prevent matching inside longer hex strings.
        result = replacePattern(
            in: result,
            pattern: #"(?<![A-Za-z0-9])[0-9a-fA-F]{64}(?![A-Za-z0-9])"#,
            replacement: "[topic:REDACTED]"
        )

        // Long base64 blobs (≥ 200 chars) are likely XDR transaction envelopes.
        result = replacePattern(
            in: result,
            pattern: #"(?<![A-Za-z0-9+/=])[A-Za-z0-9+/]{200,}={0,2}(?![A-Za-z0-9+/=])"#,
            replacement: "[xdr:REDACTED]"
        )

        // Mid-length base64 blobs (≥ 100 chars) are likely signing payloads.
        result = replacePattern(
            in: result,
            pattern: #"(?<![A-Za-z0-9+/=])[A-Za-z0-9+/]{100,199}={0,2}(?![A-Za-z0-9+/=])"#,
            replacement: "[payload:REDACTED]"
        )

        // Short base64-like values (≥ 40 chars) adjacent to payload-context keywords.
        // Only redacted when the keyword and the value appear within 30 characters of
        // each other to avoid false positives on benign short strings.
        result = redactWindowedPayload(in: result)

        return result
    }

    /// Returns a safe placeholder for a known auth digest.
    ///
    /// Callers that hold a 32-byte SHA-256 auth digest MUST use this method
    /// rather than logging the raw bytes or their base64 encoding. The return
    /// value records the byte count for debugging without exposing the preimage.
    ///
    /// - Parameter digest: The raw digest bytes (typically 32 bytes for SHA-256).
    /// - Returns: A string such as `"[digest:redacted (32B)]"`.
    public nonisolated static func redactDigest(_ digest: Data) -> String {
        "[digest:redacted (\(digest.count)B)]"
    }

    /// Returns a truncated credential ID safe for display.
    ///
    /// Format: `cred[<first 8 chars>]...[<last 8 chars>]`.
    /// If the credential ID is 16 characters or fewer the full value is
    /// returned unchanged — it cannot be meaningfully truncated.
    ///
    /// - Parameter credentialId: Raw credential ID string (base64url or hex).
    public nonisolated static func redactCredentialId(_ credentialId: String) -> String {
        guard credentialId.count > 16 else {
            return credentialId
        }
        let prefix = credentialId.prefix(8)
        let suffix = credentialId.suffix(8)
        return "cred[\(prefix)]...[\(suffix)]"
    }

    // -------------------------------------------------------------------------
    // MARK: - Private helpers
    // -------------------------------------------------------------------------

    /// Applies a regex replacement to `input`.
    ///
    /// Returns `input` unchanged if the pattern is invalid (defensive: regex
    /// errors here are programming errors, not runtime conditions, so silently
    /// skipping is safer than crashing in a logging path).
    private nonisolated static func replacePattern(
        in input: String,
        pattern: String,
        replacement: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return input
        }
        let range = NSRange(input.startIndex..., in: input)
        return regex.stringByReplacingMatches(
            in: input,
            options: [],
            range: range,
            withTemplate: replacement
        )
    }

    /// Scans `input` for payload-context keywords and redacts any base64-like
    /// substrings of 40–99 characters that appear within 30 characters of such
    /// a keyword. Values of 100+ characters are already handled by the wider
    /// patterns in `redact(_:)`.
    ///
    /// Context keywords (matched case-insensitively):
    /// `auth_digest`, `payload`, `signature`, `digest`, `credential_id` /
    /// `credentialId` / `credential id`, `credential`, `contract_id` /
    /// `contractId` / `contract id`, `rule_name` / `ruleName` / `rule name`.
    /// The optional `[_ ]?` separator covers snake_case, camelCase, and the
    /// space-separated free-form variant.
    private nonisolated static func redactWindowedPayload(in input: String) -> String {
        let keywordPattern =
            #"(?:auth_digest|payload|signature|digest|credential[_ ]?id|credential|"# +
            #"contract[_ ]?id|rule[_ ]?name)\b"#
        let valuePattern = #"[A-Za-z0-9+/]{40,}={0,2}"#
        guard
            let keywordRegex = try? NSRegularExpression(pattern: keywordPattern, options: [.caseInsensitive]),
            let valueRegex = try? NSRegularExpression(pattern: valuePattern, options: [])
        else {
            return input
        }
        let fullRange = NSRange(input.startIndex..., in: input)
        let keywordMatches = keywordRegex.matches(in: input, options: [], range: fullRange)
        guard !keywordMatches.isEmpty else { return input }
        let windows = buildWindowIndexSet(from: keywordMatches, in: input)
        let candidates = windowedCandidates(from: valueRegex, in: input, range: fullRange, windows: windows)
        return applyReplacements(candidates, in: input, replacement: "[payload:REDACTED]")
    }

    /// Builds an `IndexSet` covering the 30-character window after each keyword match.
    private nonisolated static func buildWindowIndexSet(
        from matches: [NSTextCheckingResult],
        in input: String
    ) -> IndexSet {
        let length = (input as NSString).length
        var indices = IndexSet()
        for match in matches {
            let start = max(0, match.range.location)
            let end = min(length, match.range.location + match.range.length + 30)
            indices.insert(integersIn: start ..< end)
        }
        return indices
    }

    /// Returns NSRange values for value matches of 40–99 chars that overlap `windows`.
    private nonisolated static func windowedCandidates(
        from regex: NSRegularExpression,
        in input: String,
        range: NSRange,
        windows: IndexSet
    ) -> [NSRange] {
        regex.matches(in: input, options: [], range: range).compactMap { match in
            guard match.range.length < 100 else { return nil }
            let matchEnd = match.range.location + match.range.length
            let overlaps = windows.intersects(integersIn: match.range.location ..< matchEnd)
            return overlaps ? match.range : nil
        }
    }

    /// Applies `replacement` at each NSRange in `ranges` (highest offset first)
    /// and returns the modified string.
    private nonisolated static func applyReplacements(
        _ ranges: [NSRange],
        in input: String,
        replacement: String
    ) -> String {
        guard !ranges.isEmpty else { return input }
        var result = input
        for nsRange in ranges.sorted(by: { $0.location > $1.location }) {
            guard let swiftRange = Range(nsRange, in: result) else { continue }
            result.replaceSubrange(swiftRange, with: replacement)
        }
        return result
    }
}
