// ContextRuleFormat.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - Signer Type Labels
// ============================================================================

/// Returns the short type label for a smart account signer.
///
/// - Passkey (WebAuthn / OZExternalSigner with keyData): `"Passkey"`
/// - Delegated Stellar account: `"G-Address"`
/// - Raw Ed25519: `"Ed25519"`
/// - Any other / unknown: `"External"`
public func signerTypeLabel(for signer: any OZSmartAccountSigner) -> String {
    if let external = signer as? OZExternalSigner {
        if external.keyData.count > SmartAccountConstants.secp256r1PublicKeySize {
            return "Passkey"
        }
        return "Ed25519"
    }
    if signer is OZDelegatedSigner {
        return "G-Address"
    }
    return "External"
}

/// Returns the display identifier for a smart account signer, suitable for
/// showing in a compact chip or row alongside the type label.
///
/// - Passkey → base64url-encoded credential ID (full; the caller may truncate).
/// - G-Address → truncated to 6 chars at each end.
/// - Ed25519 → `"key:<first 8 hex chars>..."`.
/// - External → truncated verifier address (4 chars at each end).
public func signerDisplayIdentifier(for signer: any OZSmartAccountSigner) -> String {
    if let external = signer as? OZExternalSigner {
        if external.keyData.count > SmartAccountConstants.secp256r1PublicKeySize {
            // Passkey: extract and base64url-encode the credential ID bytes.
            if let credIdBytes = OZSmartAccountBuilders.getCredentialIdFromSigner(signer: external),
               !credIdBytes.isEmpty {
                return credIdBytes.base64URLEncodedString()
            }
            return "(unknown passkey)"
        }
        // Ed25519: hex of the key bytes, first 8 chars.
        let hexKey = hexString(from: external.keyData)
        return "key:\(hexKey.prefix(8))..."
    }
    if let delegated = signer as? OZDelegatedSigner {
        return truncateAddress(delegated.address, chars: 6)
    }
    return truncateAddress(signer.uniqueKey, chars: 4)
}

// ============================================================================
// MARK: - Context Type Labels
// ============================================================================

/// Returns a human-readable label for a `ContextRuleType`.
///
/// - `defaultRule` → `"Default (Any Operation)"`
/// - `callContract` → `"Call Contract: <truncated address>"`
/// - `createContract` → `"Create Contract: <first 8 hex chars>..."`
public func contextTypeLabel(for type: ContextRuleType) -> String {
    switch type {
    case .defaultRule:
        return "Default (Any Operation)"
    case .callContract(let contractAddress):
        let truncated = truncateAddress(contractAddress, chars: 6)
        return "Call Contract: \(truncated)"
    case .createContract(let wasmHash):
        let hexWasm = hexString(from: wasmHash)
        return "Create Contract: \(hexWasm.prefix(8))..."
    }
}

// ============================================================================
// MARK: - Plural Helpers
// ============================================================================

/// Returns `"N signer"` or `"N signers"` for the signer count badge.
public func signerCountLabel(_ count: Int) -> String {
    "\(count) signer\(count != 1 ? "s" : "")"
}

/// Returns `"N policy"` or `"N policies"` for the policy count badge.
public func policyCountLabel(_ count: Int) -> String {
    "\(count) polic\(count != 1 ? "ies" : "y")"
}
