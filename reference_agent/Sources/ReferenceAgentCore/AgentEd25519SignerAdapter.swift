// Copyright 2026 Soneso. Reference agent for the OZ smart-account demo.

import Foundation
import stellarsdk

/// Thrown by `AgentEd25519SignerAdapter.signAuthDigest` when no keypair is
/// registered for the requested public key.
public struct AgentSignerError: Error, CustomStringConvertible, Sendable {

    /// Short, actionable description of the error.
    public let message: String

    /// Constructs a signer error with a [message].
    public init(_ message: String) {
        self.message = message
    }

    public var description: String { "AgentSignerError: \(message)" }
}

/// Thrown when a public-only keypair is registered for signing.
public struct AgentSignerKeyError: Error, CustomStringConvertible, Sendable {

    /// Short, actionable description of the error.
    public let message: String

    /// Constructs a key error with a [message].
    public init(_ message: String) {
        self.message = message
    }

    public var description: String { "AgentSignerKeyError: \(message)" }
}

/// `OZExternalEd25519SignerAdapter` that signs with in-process Ed25519
/// keypairs, keyed by the on-chain `(verifierAddress, publicKey)` signer slot.
///
/// This mirrors the demo app's Ed25519 adapter: the signing keypair lives inside
/// the adapter, never in the SDK manager's in-process registry. The kit's
/// multi-signer pipeline calls `canSignFor` first; when it returns `true` the
/// pipeline calls `signAuthDigest` on this adapter (adapter-first precedence)
/// rather than its own keypair registry.
///
/// Supply one instance to `OZSmartAccountConfig.externalEd25519Adapter` at kit
/// construction. Register the agent's keypair via `add` before submitting a
/// multi-signer call, and `clearAll` afterwards so the adapter does not retain
/// the key reference beyond its needed lifetime.
///
/// Thread-safety: an `NSLock` guards the keypair registry, so `canSignFor`
/// (synchronous) and `signAuthDigest` (async) may be consulted from the
/// multi-signer pipeline on any executor without a data race.
public final class AgentEd25519SignerAdapter: OZExternalEd25519SignerAdapter, @unchecked Sendable {

    private let lock = NSLock()
    private var keypairs: [SignerSlot: KeyPair] = [:]

    /// Creates an empty adapter with no registered keypair.
    public init() {}

    /// Registers [keypair] for the on-chain signer slot identified by
    /// [verifierAddress] and the keypair's public key.
    ///
    /// Registering a second keypair for the same slot overwrites the previous
    /// entry. [keypair] must be able to sign (constructed from a secret seed),
    /// otherwise `signAuthDigest` would later fail.
    public func add(verifierAddress: String, keypair: KeyPair) throws {
        guard keypair.privateKey != nil else {
            throw AgentSignerKeyError("Ed25519 signer keypair is public-only and cannot sign")
        }
        let publicKey = Data(keypair.publicKey.bytes)
        lock.withLock {
            keypairs[SignerSlot(verifierAddress: verifierAddress, publicKey: publicKey)] = keypair
        }
    }

    /// Removes every registered keypair.
    public func clearAll() {
        lock.withLock {
            keypairs.removeAll()
        }
    }

    public func canSignFor(verifierAddress: String, publicKey: Data) -> Bool {
        lock.withLock {
            keypairs[SignerSlot(verifierAddress: verifierAddress, publicKey: publicKey)] != nil
        }
    }

    public func signAuthDigest(authDigest: Data, publicKey: Data) async throws -> Data {
        // signAuthDigest receives only the publicKey (not the verifier address),
        // so locate by public key. A single agent registers one slot, so the
        // first match is unambiguous.
        let keypair: KeyPair? = lock.withLock {
            for (slot, candidate) in keypairs where slot.publicKey == publicKey {
                return candidate
            }
            return nil
        }
        guard let keypair else {
            let prefix = Hex.encode([UInt8](publicKey.prefix(8)))
            throw AgentSignerError("No Ed25519 keypair registered for public key \(prefix)...")
        }
        return Data(keypair.sign([UInt8](authDigest)))
    }
}

/// Composite key mirroring the on-chain `External(verifierAddress, publicKey)`
/// signer identity.
private struct SignerSlot: Hashable {
    let verifierAddress: String
    let publicKey: Data
}
