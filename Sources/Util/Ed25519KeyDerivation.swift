// Ed25519KeyDerivation.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - Ed25519KeyDerivation
// ============================================================================

/// Stateless helper for deriving Ed25519 key material from a 32-byte raw seed.
///
/// Returns both the `KeyPair` and its 32-byte public key so callers that need
/// only the public key (e.g. a mismatch check) can discard the keypair, while
/// callers that need to store and use the keypair (e.g. adapter registration)
/// avoid reconstructing it a second time.
enum Ed25519KeyDerivation {

    /// Derives the full keypair and the 32-byte public key from a 32-byte Ed25519 seed.
    ///
    /// - Parameter secretKeyBytes: Exactly 32 raw seed bytes.
    /// - Returns: A tuple of the derived `KeyPair` and its 32-byte public key `Data`.
    /// - Throws: When `Seed(bytes:)` or `KeyPair(seed:)` reject the input.
    ///
    /// Callers should validate `secretKeyBytes.count == SmartAccountConstants.ed25519SecretSeedSize`
    /// before invoking; this helper does not repeat that guard.
    static func deriveKeypair(fromSecretBytes secretKeyBytes: Data) throws -> (keypair: KeyPair, publicKey: Data) {
        let seed = try Seed(bytes: [UInt8](secretKeyBytes))
        let keypair = KeyPair(seed: seed)
        return (keypair: keypair, publicKey: Data(keypair.publicKey.bytes))
    }
}
