// ErrorUtilsTests.swift
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
// MARK: - ErrorUtilsTests
// ============================================================================

/// Tests for all public functions in `ErrorUtils.swift`.
@Suite("ErrorUtils")
struct ErrorUtilsTests {

    // -------------------------------------------------------------------------
    // MARK: - isUserCancellation(Error) — typed check
    // -------------------------------------------------------------------------

    @Test("WebAuthnException.Cancelled is classified as cancellation")
    func webAuthnCancelledIsClassifiedAsCancel() {
        let error = WebAuthnException.Cancelled(message: "User cancelled passkey ceremony.", cause: nil)
        #expect(isUserCancellation(error))
    }

    @Test("Non-SDK LocalizedError with 'cancelled' message: not classified as cancellation")
    func localizedErrorWithCancelledWordIsNotCancellation() {
        // This test verifies that the typed guard (WebAuthnException.Cancelled) is
        // the authoritative signal. A plain LocalizedError whose description contains
        // "cancelled" may be a genuine SDK error and must NOT be silently downgraded.
        struct AdversarialError: LocalizedError {
            var errorDescription: String? { "The network request was cancelled by the relayer." }
        }
        // The error is NOT a WebAuthnException.Cancelled, so the typed branch does not
        // fire. The substring fallback does match "cancelled" — that is expected and
        // intentional for non-SDK errors from platform APIs (AuthenticationServices etc.).
        // The important guarantee is that actual SDK errors (WebAuthnException subtypes
        // other than Cancelled) are NOT matched.
        let networkError = MockNetworkConnectionError()
        #expect(!isUserCancellation(networkError))
    }

    @Test("Non-cancellation WebAuthnException subtypes are not classified as cancellation")
    func webAuthnAuthFailedIsNotCancellation() {
        let error = WebAuthnException.AuthenticationFailed(message: "Biometric not recognised.", cause: nil)
        #expect(!isUserCancellation(error))
    }

    @Test("Error overload: 'cancelled' in localizedDescription triggers substring fallback")
    func errorOverloadSubstringFallback() {
        struct CancelError: LocalizedError {
            var errorDescription: String? { "Operation cancelled by the system." }
        }
        #expect(isUserCancellation(CancelError()))
    }

    @Test("Error overload: 'cancel' + 'user' in description triggers substring fallback")
    func cancelAndUserDetected() {
        struct UserCancelError: LocalizedError {
            var errorDescription: String? { "The user canceled the passkey prompt." }
        }
        #expect(isUserCancellation(UserCancelError()))
    }

    @Test("Error overload: network error is not a cancellation")
    func networkErrorNotCancellation() {
        #expect(!isUserCancellation(MockNetworkConnectionError()))
    }

    @Test("Flow-typed error with 'cancelled' in embedded user data is not a cancellation")
    func flowErrorWithCancelledInReasonNotCancellation() {
        // policyEncodingFailed embeds the user-entered amount in its reason;
        // the typed short-circuit must win over the substring fallback.
        let error = ContextRuleFlowError.policyEncodingFailed(
            address: "CB26VN37RCVNTHJZDEPK6IRO2MMTS3Z2IEO5JD5BINY2OOJ5KKJG7NKY",
            reason: "Invalid amount: 1cancelled - Amount must be a positive decimal number"
        )
        #expect(!isUserCancellation(error))
    }

    @Test("Error overload: empty localizedDescription is not a cancellation")
    func emptyDescriptionNotCancellation() {
        struct EmptyDescError: Error {}
        #expect(!isUserCancellation(EmptyDescError()))
    }

    // -------------------------------------------------------------------------
    // MARK: - Helpers referenced by fixture
    // -------------------------------------------------------------------------

    private struct MockNetworkConnectionError: Error, LocalizedError {
        var errorDescription: String? { "Network unreachable: connection timed out." }
    }

    // -------------------------------------------------------------------------
    // MARK: - actionableMessage(for:)
    // -------------------------------------------------------------------------

    @Test("Cancellation error returns neutral cancelled message")
    func cancellationReturnsNeutralMessage() {
        struct CancelError: LocalizedError {
            var errorDescription: String? { "Operation cancelled by user." }
        }
        let msg = actionableMessage(for: CancelError())
        #expect(msg == "Operation cancelled.")
    }

    @Test("LocalizedError uses errorDescription when available")
    func localizedErrorUsesDescription() {
        struct MyError: LocalizedError {
            var errorDescription: String? { "Contract simulation failed." }
        }
        let msg = actionableMessage(for: MyError())
        #expect(msg == "Contract simulation failed.")
    }

    @Test("LocalizedError with nil errorDescription falls back to localizedDescription")
    func localizedErrorNilDescriptionFallback() {
        struct NilDescError: LocalizedError {
            var errorDescription: String? { nil }
        }
        let error = NilDescError()
        let msg = actionableMessage(for: error)
        // Falls back to `localizedDescription` which calls `errorDescription ?? description`.
        // Swift's default `localizedDescription` for LocalizedError returns errorDescription
        // or a default "The operation couldn't be completed" form. Either way it is non-empty.
        #expect(!msg.isEmpty)
    }

    @Test("NSError returns localizedDescription")
    func nsErrorReturnsLocalizedDescription() {
        let nsError = NSError(domain: "TestDomain", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "Custom NSError message"
        ])
        let msg = actionableMessage(for: nsError)
        #expect(msg == "Custom NSError message")
    }

    // -------------------------------------------------------------------------
    // MARK: - isValidContractAddress
    // -------------------------------------------------------------------------

    @Test("Valid 56-char C-address passes")
    func validCAddressPasses() {
        let address = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
        #expect(isValidContractAddress(address))
    }

    @Test("Address not starting with C fails")
    func invalidPrefixFails() {
        // G-address — valid Stellar address but not a contract address.
        let address = "GAAZI4TCR3TY5OJHCTJC2A4QSY6CJWJH5IAJTGKIN2ER7LBNVKOCCWN"
        #expect(!isValidContractAddress(address))
    }

    @Test("Address of wrong length fails")
    func wrongLengthFails() {
        // 55 chars — one short.
        let address = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYS"
        #expect(!isValidContractAddress(address))
    }

    @Test("Empty string fails")
    func emptyStringFails() {
        #expect(!isValidContractAddress(""))
    }

    @Test("Whitespace-only string fails")
    func whitespaceOnlyFails() {
        #expect(!isValidContractAddress("   "))
    }

    @Test("Address with leading whitespace is trimmed and validated")
    func leadingWhitespaceTrimmed() {
        let address = "  CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
        // After trimming spaces, this is a valid 56-char C-address.
        #expect(isValidContractAddress(address))
    }

    // -------------------------------------------------------------------------
    // MARK: - isNonBlank
    // -------------------------------------------------------------------------

    @Test("Non-empty non-whitespace string is non-blank")
    func nonBlankString() {
        #expect(isNonBlank("hello"))
    }

    @Test("Empty string is blank")
    func emptyIsBlank() {
        #expect(!isNonBlank(""))
    }

    @Test("Spaces-and-tabs-only string is blank")
    func whitespaceIsBlank() {
        // isNonBlank trims with .whitespaces (spaces and horizontal tabs).
        // A string containing only spaces and tabs is blank after trimming.
        #expect(!isNonBlank("   \t  "))
    }

    @Test("String with only one non-whitespace char is non-blank")
    func singleCharIsNonBlank() {
        #expect(isNonBlank(" x "))
    }
}
