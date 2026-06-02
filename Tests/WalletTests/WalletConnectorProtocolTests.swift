// WalletConnectorProtocolTests.swift
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
// MARK: - WalletConnectorProtocolTests
// ============================================================================

/// Compile-time shape tests for the `WalletConnector` protocol.
///
/// Verifies that:
/// - `WalletMetadata` and `SignedAuthEntry` are concrete Sendable value types.
/// - `WalletConnectorError` cases compile and their `LocalizedError` descriptions are non-empty.
/// - A `WalletConnector` conformance can be expressed without referencing any Reown types.
/// - The protocol surface (method signatures, property types) is stable.
///
/// These tests have no network dependencies and never leave the process boundary.
@Suite("WalletConnectorProtocol")
struct WalletConnectorProtocolTests {

    // -------------------------------------------------------------------------
    // MARK: - WalletMetadata
    // -------------------------------------------------------------------------

    @Test("WalletMetadata initialises with all optional fields nil")
    func walletMetadataMinimal() {
        let meta = WalletMetadata(name: "Test Wallet")
        #expect(meta.name == "Test Wallet")
        #expect(meta.url == nil)
        #expect(meta.iconUrl == nil)
    }

    @Test("WalletMetadata initialises with all fields set")
    func walletMetadataFull() {
        let meta = WalletMetadata(
            name: "Freighter",
            url: "https://freighter.app",
            iconUrl: "https://freighter.app/icon.png"
        )
        #expect(meta.name == "Freighter")
        #expect(meta.url == "https://freighter.app")
        #expect(meta.iconUrl == "https://freighter.app/icon.png")
    }

    @Test("WalletMetadata equality works correctly")
    func walletMetadataEquality() {
        let alpha = WalletMetadata(name: "Wallet A", url: "https://a.com")
        let beta = WalletMetadata(name: "Wallet A", url: "https://a.com")
        let gamma = WalletMetadata(name: "Wallet B")
        #expect(alpha == beta)
        #expect(alpha != gamma)
    }

    // -------------------------------------------------------------------------
    // MARK: - SignedAuthEntry
    // -------------------------------------------------------------------------

    @Test("SignedAuthEntry initialises and stores values")
    func signedAuthEntryInit() {
        let entry = SignedAuthEntry(
            signedAuthEntry: "base64payload==",
            signerAddress: "GABC1234567890ABCDEF"
        )
        #expect(entry.signedAuthEntry == "base64payload==")
        #expect(entry.signerAddress == "GABC1234567890ABCDEF")
    }

    @Test("SignedAuthEntry equality is field-by-field")
    func signedAuthEntryEquality() {
        let alpha = SignedAuthEntry(signedAuthEntry: "abc", signerAddress: "GABC")
        let beta = SignedAuthEntry(signedAuthEntry: "abc", signerAddress: "GABC")
        let gamma = SignedAuthEntry(signedAuthEntry: "xyz", signerAddress: "GABC")
        #expect(alpha == beta)
        #expect(alpha != gamma)
    }

    // -------------------------------------------------------------------------
    // MARK: - WalletConnectorError
    // -------------------------------------------------------------------------

    @Test("notSupportedOnPlatform has non-empty description")
    func errorNotSupportedOnPlatform() {
        let error = WalletConnectorError.notSupportedOnPlatform(reason: "UIKit unavailable")
        #expect(error.errorDescription?.isEmpty == false)
        #expect(error.errorDescription?.contains("UIKit unavailable") == true)
    }

    @Test("notSupportedInSimulator has non-empty description")
    func errorNotSupportedInSimulator() {
        let error = WalletConnectorError.notSupportedInSimulator
        #expect(error.errorDescription?.isEmpty == false)
        #expect(error.errorDescription?.contains("Simulator") == true)
    }

    @Test("connectionTimeout has non-empty description")
    func errorConnectionTimeout() {
        let error = WalletConnectorError.connectionTimeout
        #expect(error.errorDescription?.isEmpty == false)
    }

    @Test("signingTimeout has non-empty description")
    func errorSigningTimeout() {
        let error = WalletConnectorError.signingTimeout
        #expect(error.errorDescription?.isEmpty == false)
    }

    @Test("noActiveSession has non-empty description")
    func errorNoActiveSession() {
        let error = WalletConnectorError.noActiveSession
        #expect(error.errorDescription?.isEmpty == false)
    }

    @Test("malformedWalletResponse carries detail in description")
    func errorMalformedWalletResponse() {
        let error = WalletConnectorError.malformedWalletResponse(detail: "not a string")
        #expect(error.errorDescription?.contains("not a string") == true)
    }

    @Test("signingRejected carries reason in description")
    func errorSigningRejected() {
        let error = WalletConnectorError.signingRejected(reason: "User declined")
        #expect(error.errorDescription?.contains("User declined") == true)
    }

    // -------------------------------------------------------------------------
    // MARK: - Protocol conformance via mock (compile-time check)
    // -------------------------------------------------------------------------

    /// Verifies that a local mock struct can conform to `WalletConnector` without
    /// referencing any Reown or UIKit types. Proves the protocol is platform-agnostic.
    @Test("WalletConnector protocol does not require Reown types")
    func walletConnectorIsReownFree() async {
        let mock = MockWalletConnectorImpl()

        // connect() is callable and throws the expected sentinel.
        do {
            try await mock.connect()
            Issue.record("Expected connect() to throw, but it did not")
        } catch let error as WalletConnectorError {
            if case .noActiveSession = error {
                // Expected.
            } else {
                Issue.record("Unexpected WalletConnectorError case: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }

        // connectedAddress and walletMetadata are accessible without UIKit.
        #expect(mock.connectedAddress == nil)
        #expect(mock.walletMetadata == nil)
    }
}

// ============================================================================
// MARK: - MockWalletConnectorImpl (test double, no Reown dependency)
// ============================================================================

/// Minimal `WalletConnector` implementation for compile-time protocol shape validation.
///
/// Used by `walletConnectorIsReownFree` to prove the protocol compiles and is callable
/// without importing any Reown / UIKit types. The mock always throws a sentinel error
/// from `connect()` so tests can assert the error path.
private final class MockWalletConnectorImpl: WalletConnector {

    var connectedAddress: String? { nil }
    var walletMetadata: WalletMetadata? { nil }

    func connect() async throws {
        throw WalletConnectorError.noActiveSession
    }

    func disconnect() async {}

    func signAuthEntry(authEntryXdr: String, contextRuleIds: [UInt32]) async throws -> SignedAuthEntry {
        throw WalletConnectorError.noActiveSession
    }
}
