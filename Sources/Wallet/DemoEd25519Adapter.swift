// DemoEd25519Adapter.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

fileprivate let demoLogPrefixCount = 8

// ============================================================================
// MARK: - DemoEd25519Adapter
// ============================================================================

/// Demonstrates the ``OZExternalEd25519SignerAdapter`` callback path for Ed25519
/// signing.
///
/// Stores verified 32-byte Ed25519 secrets in an in-memory registry keyed by the
/// `(verifierAddress, publicKey)` tuple carried by ``Ed25519SecretKey``. The
/// signing secret lives inside this adapter and is never handed to the kit's
/// ``OZExternalSignerManager`` in-process keypair registry. The SDK's
/// multi-signer pipeline calls ``canSignFor(verifierAddress:publicKey:)`` first;
/// when it returns `true`, it awaits ``signAuthDigest(authDigest:publicKey:)`` on
/// this adapter instead of consulting the manager's keypair registry. Secrets
/// registered in-process through
/// ``OZExternalSignerManager/addEd25519FromRawKey(secretKeyBytes:verifierAddress:)``
/// are deliberately absent here, so they route through the in-process path rather
/// than this adapter.
///
/// Usage pattern:
/// 1. After the user verifies secrets in the signer picker, call ``add(_:seedBytes:)``
///    for each secret before submission.
/// 2. Submit the multi-signer operation; the manager invokes ``signAuthDigest(authDigest:publicKey:)``
///    for covered keys.
/// 3. After submission (success or failure), call ``clearAll()`` so raw seed
///    material is not retained beyond its needed lifetime.
///
/// Thread safety: all mutable state is protected by a single `NSLock`. Both
/// ``canSignFor(verifierAddress:publicKey:)`` (sync, called from any thread) and
/// ``signAuthDigest(authDigest:publicKey:)`` (async, but never holding the lock
/// across a suspension boundary) access the keypair dictionaries only under the
/// lock.
// @unchecked-justified: all mutable state (`keypairs`, `keypairsByPublicKey`) is
// protected by `stateLock` (NSLock) throughout; no mutable state escapes the lock.
public final class DemoEd25519Adapter: OZExternalEd25519SignerAdapter, @unchecked Sendable {

    // -------------------------------------------------------------------------
    // MARK: - Storage key
    // -------------------------------------------------------------------------

    /// Composite key for the adapter's keypair registry.
    ///
    /// Two entries with the same public key under different verifier addresses are
    /// distinct on-chain signers and are stored separately.
    private struct StorageKey: Hashable {
        let verifierAddress: String
        let publicKey: Data
    }

    // -------------------------------------------------------------------------
    // MARK: - State (protected by stateLock)
    // -------------------------------------------------------------------------

    private let stateLock = NSLock()

    /// Full keypair registry. Keys: `(verifierAddress, publicKey)` tuples.
    private var keypairs: [StorageKey: KeyPair] = [:]

    /// Reverse index: publicKey bytes → keypair. Lets
    /// ``signAuthDigest(authDigest:publicKey:)`` locate the keypair by public
    /// key alone (the protocol does not pass `verifierAddress` to the sign step).
    private var keypairsByPublicKey: [Data: KeyPair] = [:]

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates an empty adapter with no registered secrets.
    public init() {}

    // -------------------------------------------------------------------------
    // MARK: - Registration
    // -------------------------------------------------------------------------

    /// Registers an Ed25519 signing secret for the given signer identity.
    ///
    /// The secret bytes never leave the adapter; the kit's
    /// ``OZExternalSignerManager`` in-process keypair registry does not see them.
    /// Registering a second secret for the same `(verifierAddress, publicKey)`
    /// tuple overwrites the previous entry.
    ///
    /// - Parameters:
    ///   - identity: The `(verifierAddress, publicKey)` pair identifying the
    ///     on-chain signer slot.
    ///   - seedBytes: The 32 raw Ed25519 seed bytes for this signer.
    /// - Throws: ``DemoAdapterError/invalidSecretKeyLength(_:)`` when
    ///   `seedBytes.count != 32`; any `KeyPair` construction error for invalid
    ///   key material.
    public func add(_ identity: Ed25519SecretKey, seedBytes: Data) throws {
        guard seedBytes.count == SmartAccountConstants.ed25519SecretSeedSize else {
            throw DemoAdapterError.invalidSecretKeyLength(seedBytes.count)
        }
        let keypair = try Ed25519KeyDerivation.deriveKeypair(fromSecretBytes: seedBytes).keypair
        let key = StorageKey(verifierAddress: identity.verifierAddress, publicKey: identity.publicKey)
        stateLock.withLock {
            keypairs[key] = keypair
            keypairsByPublicKey[identity.publicKey] = keypair
        }
    }

    /// Removes all registered secrets.
    ///
    /// Must be called after submission (success or failure) so raw seed material
    /// is not retained across operations.
    public func clearAll() {
        stateLock.withLock {
            keypairs.removeAll()
            keypairsByPublicKey.removeAll()
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - OZExternalEd25519SignerAdapter
    // -------------------------------------------------------------------------

    /// Returns whether this adapter holds a secret for the given
    /// `(verifierAddress, publicKey)` pair.
    ///
    /// This method is synchronous as required by the protocol. The lock is held
    /// for the minimum time needed to read the dictionary; it is never held
    /// across any async boundary.
    public func canSignFor(verifierAddress: String, publicKey: Data) -> Bool {
        let key = StorageKey(verifierAddress: verifierAddress, publicKey: publicKey)
        return stateLock.withLock { keypairs[key] != nil }
    }

    /// Signs `authDigest` with the keypair registered for `publicKey`.
    ///
    /// The lock is acquired briefly to read the keypair reference and released
    /// before any cryptographic work begins, so the lock is never held across the
    /// async suspension boundary.
    ///
    /// - Parameters:
    ///   - authDigest: 32-byte digest computed by the multi-signer pipeline.
    ///   - publicKey: 32-byte Ed25519 public key identifying the signer slot.
    /// - Returns: 64-byte raw Ed25519 signature over `authDigest`.
    /// - Throws: ``DemoAdapterError/keypairNotFound(publicKey:)`` when no keypair
    ///   matches `publicKey`.
    public func signAuthDigest(authDigest: Data, publicKey: Data) async throws -> Data {
        let keypair: KeyPair? = stateLock.withLock { keypairsByPublicKey[publicKey] }
        guard let keypair else {
            throw DemoAdapterError.keypairNotFound(publicKey: publicKey)
        }
        // KeyPair.sign(_:) returns a 64-byte Ed25519 signature and does not throw.
        let signature = keypair.sign([UInt8](authDigest))
        return Data(signature)
    }
}

// ============================================================================
// MARK: - DemoAdapterError
// ============================================================================

/// Errors thrown by ``DemoEd25519Adapter``.
public enum DemoAdapterError: Error, Sendable {

    /// The supplied secret key was not 32 bytes.
    case invalidSecretKeyLength(Int)

    /// No keypair is registered for the requested public key.
    case keypairNotFound(publicKey: Data)
}

extension DemoAdapterError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .invalidSecretKeyLength(let count):
            return "Ed25519 secret key must be \(SmartAccountConstants.ed25519SecretSeedSize) bytes; received \(count) bytes."
        case .keypairNotFound(let publicKey):
            return "No keypair registered for public key \(publicKey.prefix(demoLogPrefixCount).map { String(format: "%02x", $0) }.joined())…"
        }
    }
}
