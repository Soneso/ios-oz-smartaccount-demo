// SignerAvailability.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - SignerAvailability
// ============================================================================

/// Helpers that derive signer availability metadata from on-chain context rules.
///
/// Both `TransferFlow` and `ContextRuleFlow` need to render the same signer
/// picker, and that picker requires per-signer `canSign` annotations:
/// - For `OZExternalSigner` (WebAuthn): `canSign` is true when the signer's
///   credential ID matches the currently connected passkey credential.
/// - For `OZDelegatedSigner` (G-address): `canSign` is true when
///   `kit.externalSigners.canSignFor(address:)` returns true (a registered
///   in-memory keypair or active wallet connection exists for the address).
///
/// Both flows must extract the same unique signer set from a list of parsed
/// context rules. Co-locating these two operations in this helper keeps the
/// two flows trivially equivalent and prevents drift if the rules for either
/// availability check change in the future.
@MainActor
enum SignerAvailability {

    // -------------------------------------------------------------------------
    // MARK: - Public surface
    // -------------------------------------------------------------------------

    /// Returns one `TransferSignerInfo` per unique signer present in `rules`,
    /// annotated with `canSign` per the connected credential and external
    /// signer manager.
    ///
    /// Uniqueness is determined by `OZSmartAccountBuilders.collectUniqueSigners`,
    /// which de-duplicates by `uniqueKey`.
    ///
    /// - Parameters:
    ///   - rules: Parsed context rules whose `signers` arrays should be merged.
    ///   - connectedCredentialId: Base64URL credential ID of the connected
    ///     passkey, or `nil` if no passkey is connected.
    ///   - manager: External signer manager queried for delegated-signer
    ///     availability. `nil` means no delegated signer can sign.
    /// - Returns: One `TransferSignerInfo` per unique signer, preserving the
    ///   order produced by `collectUniqueSigners`.
    static func extractSigners(
        rules: [ParsedContextRule],
        connectedCredentialId: String?,
        manager: OZExternalSignerManager?
    ) async -> [TransferSignerInfo] {
        let allSigners = rules.flatMap { $0.signers }
        let unique = OZSmartAccountBuilders.collectUniqueSigners(signers: allSigners)
        var infos: [TransferSignerInfo] = []
        infos.reserveCapacity(unique.count)
        for signer in unique {
            let canSign = await computeCanSign(
                signer: signer,
                connectedCredentialId: connectedCredentialId,
                manager: manager
            )
            infos.append(TransferSignerInfo(signer: signer, canSign: canSign))
        }
        return infos
    }

    /// Returns `true` when the supplied signer can currently authorize a
    /// transaction from the connected wallet.
    ///
    /// Rules:
    /// - `OZExternalSigner` whose `keyData.count` exceeds the secp256r1
    ///   public-key size (i.e. a WebAuthn passkey with embedded credential ID)
    ///   is signable when its credential ID matches `connectedCredentialId`.
    /// - `OZExternalSigner` whose `keyData.count` equals the Ed25519 public-key
    ///   size is always considered potentially signable (the picker provides the
    ///   key-entry affordance regardless of prior registration state). The
    ///   `canSign` flag here is informational; the picker's `ed25519Auth` state
    ///   drives the actual toggle enablement.
    /// - `OZDelegatedSigner` is signable when `manager` reports a registered
    ///   keypair or wallet connection for the signer's G-address.
    /// - All other signer shapes (unknown key-data length, missing credential
    ///   ID, nil manager) return `false`.
    static func computeCanSign(
        signer: any OZSmartAccountSigner,
        connectedCredentialId: String?,
        manager: OZExternalSignerManager?
    ) async -> Bool {
        if let external = signer as? OZExternalSigner {
            // Bare Ed25519 key (32 bytes): always shown as potentially signable
            // so the picker row is included and the user can enter the secret key.
            if external.keyData.count == SmartAccountConstants.ed25519PublicKeySize {
                return true
            }
            // WebAuthn passkey: signable when credential ID matches connected credential.
            guard external.keyData.count > SmartAccountConstants.secp256r1PublicKeySize,
                  let credIdStr = OZSmartAccountBuilders.getCredentialIdStringFromSigner(signer: external),
                  let connectedCred = connectedCredentialId else {
                return false
            }
            return credIdStr == connectedCred
        }
        if let delegated = signer as? OZDelegatedSigner {
            guard let manager else { return false }
            return await manager.canSignFor(address: delegated.address)
        }
        return false
    }
}
