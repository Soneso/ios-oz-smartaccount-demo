// ErrorUtils.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - User Cancellation Detection
// ============================================================================

/// Returns true if the error represents a user-initiated cancellation of a
/// passkey or wallet-signing ceremony.
///
/// The primary check is a typed match against `WebAuthnException.Cancelled`,
/// the concrete cancellation type thrown by the iOS SDK's smart-account layer.
/// A substring fallback covers non-SDK errors (e.g. system AuthenticationServices
/// cancellations) whose descriptions contain common cancellation phrases.
///
/// Using this overload is preferred over the `String`-based overload because
/// typed matching cannot be fooled by adversarial error messages that happen to
/// contain the word "cancelled".
///
/// - Parameter error: The error to classify.
public func isUserCancellation(_ error: Error) -> Bool {
    if error is WebAuthnException.Cancelled {
        return true
    }
    // Flow-typed errors are never user cancellations. Their descriptions can
    // embed user-entered data (e.g. an amount string containing "cancelled"),
    // which the substring fallback would misclassify.
    if error is ContextRuleFlowError {
        return false
    }
    return isUserCancellationByMessage(error.localizedDescription)
}

/// Returns true if the error message indicates the user deliberately cancelled
/// a passkey or wallet-signing ceremony.
///
/// Substring matching is a fallback for non-SDK errors. Prefer the `Error`
/// overload when the thrown type is known.
///
/// - Parameter message: An error message string (typically lowercased on entry).
private func isUserCancellationByMessage(_ message: String) -> Bool {
    let lower = message.lowercased()
    if lower.contains("cancelled") { return true }
    if lower.contains("cancel") && lower.contains("user") { return true }
    if lower.contains("abort") && lower.contains("user") { return true }
    return false
}

// ============================================================================
// MARK: - Actionable Error Messages
// ============================================================================

/// Converts an arbitrary thrown error to a human-readable string suitable for
/// displaying in the activity log or an error banner.
///
/// Rules:
/// - User cancellations return "Operation cancelled." (neutral tone).
/// - Errors conforming to `LocalizedError` return `errorDescription` if non-nil.
/// - All others return `localizedDescription`.
/// - The message is never a raw stack trace or full XDR payload.
///
/// - Parameter error: The error that was caught.
public func actionableMessage(for error: Error) -> String {
    if isUserCancellation(error) {
        return "Operation cancelled."
    }
    // SDK-typed smart-account errors carry a curated `message` field
    // identifying the specific failure (contract error code, simulation
    // failure, signature gating, etc.). Surface it directly so the UI shows
    // an actionable message instead of falling through to the generic
    // `localizedDescription` which collapses non-`LocalizedError` types to
    // an opaque "The operation couldn't be completed" placeholder.
    if let sdkException = error as? SmartAccountException {
        return sdkException.message
    }
    if let urlError = error as? URLError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return "Network unavailable. Check your connection and retry."
        case .timedOut:
            return "Request timed out. Retry, or check the network."
        case .cannotFindHost, .cannotConnectToHost:
            return "Could not reach the server. Check the RPC endpoint."
        default:
            return urlError.localizedDescription
        }
    }
    if let localized = error as? LocalizedError, let desc = localized.errorDescription {
        return desc
    }
    return error.localizedDescription
}

// ============================================================================
// MARK: - Validation Helpers
// ============================================================================

/// Returns true if `input` is a syntactically valid Stellar contract address.
///
/// Delegates to `String.isValidContractId()` from the iOS SDK, which performs
/// full StrKey base32 decoding and CRC-16 checksum verification (the same check
/// used internally by `OZValidation`). Whitespace is trimmed before the check.
///
/// - Parameter input: The raw string from user input or a stored value.
public func isValidContractAddress(_ input: String) -> Bool {
    input.trimmingCharacters(in: .whitespaces).isValidContractId()
}

/// Returns true if `input` is a non-blank, non-whitespace-only string.
public func isNonBlank(_ input: String) -> Bool {
    !input.trimmingCharacters(in: .whitespaces).isEmpty
}
