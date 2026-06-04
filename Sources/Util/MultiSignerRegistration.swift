// MultiSignerRegistration.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - MultiSignerRegistrationError
// ============================================================================

/// Errors raised by ``MultiSignerRegistration`` shared helpers.
///
/// Flows wrap or rethrow these as their own typed error cases to keep the
/// flow-level error surface stable for callers and tests. The shared helper
/// throws a single typed error so the call site can decide whether to wrap
/// (preserving its own error enum) or to allow the original to propagate.
public enum MultiSignerRegistrationError: Error, LocalizedError, Sendable {

    /// The registered keypair for a delegated signer derived a different
    /// G-address than the one recorded in the signer picker. Indicates either
    /// a user entry error or a corrupted secret key. Carries the expected
    /// G-address so the call site can surface an actionable message.
    case invalidDelegatedSigner(expectedAddress: String)

    /// A signer kind was supplied that the flow's multi-signer path does not
    /// support. Distinct from ``invalidDelegatedSigner`` so the call site can
    /// surface a separate, actionable message. The associated `description`
    /// is a short human-readable description of the unsupported shape.
    case unsupportedSignerKind(description: String)

    public var errorDescription: String? {
        switch self {
        case .invalidDelegatedSigner(let address):
            return "The secret key does not match the expected signer address (\(truncateAddress(address)))."
        case .unsupportedSignerKind(let description):
            return "Unsupported signer kind: \(description)."
        }
    }
}

// ============================================================================
// MARK: - MultiSignerRegistration
// ============================================================================

/// Cross-flow helpers for multi-signer submission setup.
///
/// Three steps recur in every multi-signer submission path across the demo
/// (token transfer, context-rule mutation, allowance approval):
///
/// 1. Clear stale delegated keypairs from `kit.externalSigners` and register
///    the secret keys supplied by the signer picker, asserting that each
///    derived address matches the address the picker reported.
/// 2. Convert the user-selected ``OZSmartAccountSigner`` objects to the
///    SDK's ``OZSelectedSigner`` value type, accepting WebAuthn passkeys and
///    delegated G-address signers.
/// 3. Load the union of signers across every on-chain context rule (used by
///    the screen to decide between the single-signer fast path and the
///    multi-signer picker).
///
/// These helpers centralise all three so the rules for each operation stay
/// in one place. Flows are expected to call these directly and translate
/// ``MultiSignerRegistrationError`` into their own typed errors when needed.
///
/// Thread safety: every method is `@MainActor` because the underlying
/// ``ContextRuleManagerType``, ``ActivityLogState``, and
/// ``OZSmartAccountKit`` are themselves main-actor bound.
@MainActor
public enum MultiSignerRegistration {

    // -------------------------------------------------------------------------
    // MARK: - Public: registerDelegatedKeypairs
    // -------------------------------------------------------------------------

    /// Registers the supplied `secrets` (G-address → secret-key) on `manager`.
    ///
    /// Each entry's derived address is compared against the expected G-address;
    /// any mismatch throws
    /// ``MultiSignerRegistrationError/invalidDelegatedSigner(expectedAddress:)``.
    ///
    /// This is a register-only primitive: it performs no cleanup of its own. It
    /// is intended to run inside
    /// ``registerInProcessSignersWithCleanup(delegatedSecrets:ed25519Secrets:manager:body:)``
    /// or
    /// ``registerAdapterSignersWithCleanup(delegatedSecrets:ed25519Secrets:manager:adapter:body:)``,
    /// which own the cleanup wrapper and clear everything (delegated keypairs and
    /// any Ed25519 material) on both success and throw. Calling it standalone
    /// requires the caller to provide its own cleanup.
    ///
    /// - Parameters:
    ///   - secrets: G-address → secret-key map for delegated Stellar account
    ///     signers. An empty map is a no-op.
    ///   - manager: The external signer manager that holds the keypair registry.
    ///     `nil` is permitted (test paths without a manager); the call
    ///     short-circuits to a no-op in that case.
    /// - Throws: ``MultiSignerRegistrationError/invalidDelegatedSigner(expectedAddress:)``
    ///   on derived-address mismatch, or any error thrown by the underlying
    ///   register call.
    public static func registerDelegatedKeypairs(
        _ secrets: [String: String],
        manager: OZExternalSignerManager?
    ) async throws {
        guard let manager, !secrets.isEmpty else { return }
        for (address, secret) in secrets {
            let registered = try await manager.addFromSecret(secretKey: secret)
            guard registered == address else {
                throw MultiSignerRegistrationError.invalidDelegatedSigner(expectedAddress: address)
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Public: registerEd25519Keypairs (in-process custody)
    // -------------------------------------------------------------------------

    /// Registers the supplied `ed25519Secrets` in-process on `manager`.
    ///
    /// Each entry's raw 32-byte secret is registered via
    /// `manager.addEd25519FromRawKey(secretKeyBytes:verifierAddress:)`. The
    /// manager resolves these keys through its own in-memory keypair registry —
    /// the demo's ``DemoEd25519Adapter`` holds no secret for them, so its
    /// `canSignFor` returns `false`. This is the in-process custody path used by
    /// the transfer and context-rule flows.
    ///
    /// This is a register-only primitive: it performs no cleanup of its own. It
    /// is intended to run inside
    /// ``registerInProcessSignersWithCleanup(delegatedSecrets:ed25519Secrets:manager:body:)``,
    /// which owns the cleanup wrapper and clears the whole registry (delegated and
    /// Ed25519 keypairs alike) on both success and throw. Keeping cleanup solely
    /// in the wrapper is what lets the wrapper guarantee that a delegated keypair
    /// registered before an Ed25519 throw is still removed.
    ///
    /// - Parameters:
    ///   - ed25519Secrets: Map of `Ed25519SecretKey` to 32 raw secret bytes for
    ///     Ed25519 external signers. An empty map is a no-op.
    ///   - manager: The external signer manager that holds the Ed25519 in-process
    ///     keypair registry. `nil` is permitted (test paths without a manager);
    ///     the call short-circuits to a no-op.
    /// - Throws: Any error thrown by `OZExternalSignerManager.addEd25519FromRawKey(...)`.
    public static func registerEd25519Keypairs(
        _ ed25519Secrets: [Ed25519SecretKey: Data],
        manager: OZExternalSignerManager?
    ) async throws {
        guard let manager, !ed25519Secrets.isEmpty else { return }
        for (key, secretBytes) in ed25519Secrets {
            _ = try await manager.addEd25519FromRawKey(
                secretKeyBytes: secretBytes,
                verifierAddress: key.verifierAddress
            )
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Public: registerEd25519ViaAdapter (adapter custody)
    // -------------------------------------------------------------------------

    /// Registers the supplied `ed25519Secrets` on the demo's Ed25519 `adapter`.
    ///
    /// Each entry's raw 32-byte secret is registered via
    /// ``DemoEd25519Adapter/add(_:seedBytes:)``. The secret lives inside the
    /// adapter, not the manager's in-process registry. The kit consults the
    /// adapter (via ``DemoEd25519Adapter/canSignFor(verifierAddress:publicKey:)``)
    /// ahead of its in-process registry, so these keys resolve through the
    /// adapter custody path. This is the path used by the approve flow.
    ///
    /// This is a register-only primitive: it performs no cleanup of its own. It
    /// is intended to run inside
    /// ``registerAdapterSignersWithCleanup(delegatedSecrets:ed25519Secrets:manager:adapter:body:)``,
    /// which owns the cleanup wrapper and clears both the delegated keypairs and
    /// the adapter on both success and throw.
    ///
    /// - Parameters:
    ///   - ed25519Secrets: Map of `Ed25519SecretKey` to 32 raw secret bytes for
    ///     Ed25519 external signers. An empty map is a no-op.
    ///   - adapter: The demo Ed25519 adapter wired into the kit. `nil` is
    ///     permitted (test paths without a kit); the call short-circuits to a
    ///     no-op.
    /// - Throws: Any error thrown by ``DemoEd25519Adapter/add(_:seedBytes:)``.
    public static func registerEd25519ViaAdapter(
        _ ed25519Secrets: [Ed25519SecretKey: Data],
        adapter: DemoEd25519Adapter?
    ) throws {
        guard let adapter, !ed25519Secrets.isEmpty else { return }
        for (key, secretBytes) in ed25519Secrets {
            try adapter.add(key, seedBytes: secretBytes)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Public: registerInProcessSignersWithCleanup
    // -------------------------------------------------------------------------

    /// Registers delegated and in-process Ed25519 signing material, runs `body`,
    /// and clears all registered material on every exit path — success,
    /// registration failure, or any throw from `body`.
    ///
    /// Both registrations and `body` run inside one cleanup wrapper. If Ed25519
    /// registration throws after delegated registration succeeded, the cleanup in
    /// the `defer` still removes the already-registered delegated keypairs, so no
    /// signing material leaks across screens. The cleanup clears the in-process
    /// keypair registry via `manager.removeAll()`.
    ///
    /// This is the in-process custody entry point used by the transfer and
    /// context-rule flows. The demo's Ed25519 adapter holds no secret for these
    /// keys, so they route through the manager's in-memory registry rather than
    /// the adapter.
    ///
    /// - Parameters:
    ///   - delegatedSecrets: G-address → secret-key map for delegated signers.
    ///   - ed25519Secrets: `Ed25519SecretKey` → 32 raw secret bytes for Ed25519
    ///     signers, registered in-process.
    ///   - manager: External signer manager holding both registries. `nil`
    ///     short-circuits registration and cleanup to no-ops.
    ///   - body: The operation to run while the signing material is registered.
    /// - Returns: The value returned by `body`.
    /// - Throws: Any error from delegated registration, Ed25519 registration, or
    ///   `body`. Cleanup always runs first regardless.
    public static func registerInProcessSignersWithCleanup<R>(
        delegatedSecrets: [String: String],
        ed25519Secrets: [Ed25519SecretKey: Data],
        manager: OZExternalSignerManager?,
        body: () async throws -> R
    ) async throws -> R {
        do {
            try await registerDelegatedKeypairs(delegatedSecrets, manager: manager)
            try await registerEd25519Keypairs(ed25519Secrets, manager: manager)
            let result = try await body()
            try? await manager?.removeAll()
            return result
        } catch {
            try? await manager?.removeAll()
            throw error
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Public: registerAdapterSignersWithCleanup
    // -------------------------------------------------------------------------

    /// Registers delegated keypairs in-process and Ed25519 secrets on the demo
    /// `adapter`, runs `body`, and clears both stores on every exit path —
    /// success, registration failure, or any throw from `body`.
    ///
    /// Both registrations and `body` run inside one cleanup wrapper. If Ed25519
    /// adapter registration throws after delegated registration succeeded, the
    /// cleanup still removes the already-registered delegated keypairs and clears
    /// the adapter, so no signing material leaks across screens. The cleanup
    /// clears delegated keypairs via `manager.removeAll()` and adapter secrets via
    /// ``DemoEd25519Adapter/clearAll()`` — `manager.removeAll()` does not touch
    /// the adapter, so the adapter must be cleared explicitly.
    ///
    /// This is the adapter custody entry point used by the approve flow.
    ///
    /// - Parameters:
    ///   - delegatedSecrets: G-address → secret-key map for delegated signers.
    ///   - ed25519Secrets: `Ed25519SecretKey` → 32 raw secret bytes for Ed25519
    ///     signers, registered on the adapter.
    ///   - manager: External signer manager holding delegated keypairs. `nil`
    ///     short-circuits delegated registration and cleanup to no-ops.
    ///   - adapter: Demo Ed25519 adapter. `nil` short-circuits Ed25519
    ///     registration and cleanup to no-ops.
    ///   - body: The operation to run while the signing material is registered.
    /// - Returns: The value returned by `body`.
    /// - Throws: Any error from delegated registration, Ed25519 adapter
    ///   registration, or `body`. Cleanup always runs first regardless.
    public static func registerAdapterSignersWithCleanup<R>(
        delegatedSecrets: [String: String],
        ed25519Secrets: [Ed25519SecretKey: Data],
        manager: OZExternalSignerManager?,
        adapter: DemoEd25519Adapter?,
        body: () async throws -> R
    ) async throws -> R {
        do {
            try await registerDelegatedKeypairs(delegatedSecrets, manager: manager)
            try registerEd25519ViaAdapter(ed25519Secrets, adapter: adapter)
            let result = try await body()
            try? await manager?.removeAll()
            adapter?.clearAll()
            return result
        } catch {
            try? await manager?.removeAll()
            adapter?.clearAll()
            throw error
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Public: buildSelectedSigners
    // -------------------------------------------------------------------------

    /// Converts user-selected ``OZSmartAccountSigner`` objects to the SDK's
    /// ``OZSelectedSigner`` representation.
    ///
    /// Accepted shapes:
    /// - ``OZExternalSigner`` carrying a WebAuthn credential ID →
    ///   ``OZSelectedSigner/passkey(credentialId:credentialIdBytes:keyData:transports:)``.
    ///   The stored credential's WebAuthn `transports` are looked up by
    ///   credential ID through `credentialManager` and forwarded as transport
    ///   hints (used to drive cross-device / hybrid passkey selection on
    ///   platforms that honour the hint).
    /// - ``OZDelegatedSigner`` → ``OZSelectedSigner/wallet(accountId:)``.
    ///
    /// Other shapes are handled per the supplied
    /// ``MultiSignerRegistration/UnsupportedShapePolicy``:
    /// - ``UnsupportedShapePolicy/skip``: silently dropped (used where the
    ///   picker UI already prevents the user from selecting them).
    /// - ``UnsupportedShapePolicy/throwError``: throws
    ///   ``MultiSignerRegistrationError/unsupportedSignerKind(description:)``
    ///   carrying a short description of the offending shape (used where the
    ///   picker may not yet enforce the constraint).
    ///
    /// - Parameters:
    ///   - signers: User-selected signers in the picker order.
    ///   - credentialManager: Source of stored credential records, used to look
    ///     up WebAuthn transport hints by credential ID. `nil` (or a credential
    ///     not present in storage) yields `nil` transports, which is the correct
    ///     fallback.
    ///   - unsupportedShapePolicy: What to do with shapes that match neither
    ///     accepted case. Defaults to ``UnsupportedShapePolicy/skip``.
    /// - Returns: ``OZSelectedSigner`` list in the same order as `signers`,
    ///   minus any entries that were skipped per the policy.
    /// - Throws: ``MultiSignerRegistrationError/unsupportedSignerKind(description:)``
    ///   when an unsupported shape is encountered and `unsupportedShapePolicy`
    ///   is ``UnsupportedShapePolicy/throwError``.
    public static func buildSelectedSigners(
        _ signers: [any OZSmartAccountSigner],
        credentialManager: OZCredentialManager?,
        unsupportedShapePolicy: UnsupportedShapePolicy = .skip
    ) async throws -> [OZSelectedSigner] {
        var result: [OZSelectedSigner] = []
        result.reserveCapacity(signers.count)
        for signer in signers {
            if let converted = try await convertSigner(
                signer,
                credentialManager: credentialManager,
                unsupportedShapePolicy: unsupportedShapePolicy
            ) {
                result.append(converted)
            }
        }
        return result
    }

    /// Converts a single ``OZSmartAccountSigner`` to its ``OZSelectedSigner``
    /// representation, applying `unsupportedShapePolicy` for shapes that
    /// match neither accepted case. Returns `nil` to signal that the entry
    /// should be skipped (when policy is ``UnsupportedShapePolicy/skip``);
    /// throws ``MultiSignerRegistrationError/unsupportedSignerKind(description:)``
    /// when the policy is ``UnsupportedShapePolicy/throwError``.
    private static func convertSigner(
        _ signer: any OZSmartAccountSigner,
        credentialManager: OZCredentialManager?,
        unsupportedShapePolicy: UnsupportedShapePolicy
    ) async throws -> OZSelectedSigner? {
        if let external = signer as? OZExternalSigner {
            // Distinguish passkey (keyData > 65 bytes — has embedded credential ID)
            // from Ed25519 (keyData == 32 bytes).
            if let credIdStr = OZSmartAccountBuilders.getCredentialIdStringFromSigner(signer: external) {
                let credIdBytes = OZSmartAccountBuilders.getCredentialIdFromSigner(signer: external)
                // Look up the stored credential's WebAuthn transport hints.
                // A credential that is not in local storage (or a read failure)
                // yields nil transports, which is the correct fallback.
                let transports = try? await credentialManager?
                    .getCredential(credentialId: credIdStr)?.transports
                return .passkey(
                    credentialId: credIdStr,
                    credentialIdBytes: credIdBytes,
                    keyData: external.keyData,
                    transports: transports ?? nil
                )
            }
            // No credential ID: bare 32-byte Ed25519 public key.
            if external.keyData.count == SmartAccountConstants.ed25519PublicKeySize {
                return .ed25519(
                    verifierAddress: external.verifierAddress,
                    publicKey: external.keyData
                )
            }
            return try handleUnsupported(
                description: "external signer with unrecognised key data length (\(external.keyData.count) bytes)",
                policy: unsupportedShapePolicy
            )
        }
        if let delegated = signer as? OZDelegatedSigner {
            return .wallet(accountId: delegated.address)
        }
        return try handleUnsupported(
            description: String(describing: type(of: signer)),
            policy: unsupportedShapePolicy
        )
    }

    /// Branch shared by ``convertSigner(_:unsupportedShapePolicy:)`` between
    /// the "no credential ID" and "unknown concrete type" rejection paths.
    private static func handleUnsupported(
        description: String,
        policy: UnsupportedShapePolicy
    ) throws -> OZSelectedSigner? {
        switch policy {
        case .skip:
            return nil
        case .throwError:
            throw MultiSignerRegistrationError.unsupportedSignerKind(description: description)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Public: loadAvailableSigners
    // -------------------------------------------------------------------------

    /// Loads the union of unique signers across every context rule of the
    /// connected smart account, annotating each with its current `canSign`
    /// availability (see ``SignerAvailability``).
    ///
    /// Returns an empty list when the wallet is not connected, the manager is
    /// `nil`, or any call to `manager.listContextRules()` throws — in which
    /// case the call-site renders the picker as if no signers were available.
    /// The provided activity log records the failure with a sanitised message
    /// so the user sees a single, actionable line.
    ///
    /// - Parameters:
    ///   - demoState: Shared demo state; the union is empty unless
    ///     ``DemoState/isConnected`` is true.
    ///   - activityLog: Activity log used to record any fetch failure.
    ///   - contextRuleManager: Source of on-chain context rules. `nil` causes
    ///     an empty list to be returned without logging.
    ///   - failureLogPrefix: Prefix attached to the sanitised error reason in
    ///     the activity log. Defaults to `"Could not load signers"`.
    /// - Returns: ``TransferSignerInfo`` list ordered by first appearance.
    public static func loadAvailableSigners(
        demoState: DemoState,
        activityLog: ActivityLogState,
        contextRuleManager: (any ContextRuleManagerType)?,
        failureLogPrefix: String = "Could not load signers"
    ) async -> [TransferSignerInfo] {
        guard demoState.isConnected, let manager = contextRuleManager else { return [] }
        do {
            let rules = try await manager.listContextRules()
            return await SignerAvailability.extractSigners(
                rules: rules,
                connectedCredentialId: demoState.credentialId,
                manager: demoState.externalSigners
            )
        } catch {
            let detail = ActivityLogState.redact(actionableMessage(for: error))
            activityLog.info("\(failureLogPrefix): \(detail)")
            return []
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Public: isSinglePasskey
    // -------------------------------------------------------------------------

    /// Returns `true` when exactly one signer was chosen, that signer is a
    /// WebAuthn passkey, and its credential ID matches `connectedCredentialId`.
    ///
    /// This is the canonical test for "the single-passkey fast path applies"
    /// across every multi-signer entry point. All other combinations —
    /// including a single delegated signer or any passkey whose credential ID
    /// does not match the currently connected credential — return `false`.
    ///
    /// - Parameters:
    ///   - chosenSigners: Signers chosen in the picker, in selection order.
    ///   - connectedCredentialId: Currently connected passkey credential ID,
    ///     or `nil` if no passkey is connected.
    /// - Returns: `true` if the single-passkey fast path applies.
    public static func isSinglePasskey(
        _ chosenSigners: [any OZSmartAccountSigner],
        connectedCredentialId: String?
    ) -> Bool {
        guard chosenSigners.count == 1, let connectedCredentialId else { return false }
        guard let credIdStr = OZSmartAccountBuilders.getCredentialIdStringFromSigner(
            signer: chosenSigners[0]
        ) else {
            return false
        }
        return credIdStr == connectedCredentialId
    }

    // -------------------------------------------------------------------------
    // MARK: - Public: collapseForSinglePasskey
    // -------------------------------------------------------------------------

    /// Reduces picker output to the empty fast-path triple when the selected
    /// signers consist solely of the connected passkey; otherwise returns the
    /// inputs unchanged.
    ///
    /// The SDK's `OZContextRuleManager` is wired without a multi-signer
    /// submitter. An empty `selectedSigners` list takes the connected-passkey
    /// path; a non-empty list (even a single connected passkey) triggers the
    /// multi-signer routing path and fails. This helper centralises that
    /// branching so each call site stays a single statement.
    ///
    /// - Parameters:
    ///   - chosenSigners: Signers returned by the picker `onConfirm` callback.
    ///   - delegatedSecrets: Verified delegated-signer secret map from the picker.
    ///   - ed25519Secrets: Verified Ed25519 secret bytes map from the picker.
    ///   - connectedCredentialId: Currently connected passkey credential ID.
    /// - Returns: A `CollapsedSignerSelection` with empty collections when the
    ///   single-passkey fast path applies, or the original inputs otherwise.
    public static func collapseForSinglePasskey(
        chosenSigners: [any OZSmartAccountSigner],
        delegatedSecrets: [String: String],
        ed25519Secrets: [Ed25519SecretKey: Data],
        connectedCredentialId: String?
    ) -> CollapsedSignerSelection {
        if isSinglePasskey(chosenSigners, connectedCredentialId: connectedCredentialId) {
            return CollapsedSignerSelection(chosen: [], delegatedSecrets: [:], ed25519Secrets: [:])
        }
        return CollapsedSignerSelection(
            chosen: chosenSigners,
            delegatedSecrets: delegatedSecrets,
            ed25519Secrets: ed25519Secrets
        )
    }
}

// ============================================================================
// MARK: - CollapsedSignerSelection
// ============================================================================

/// Result produced by ``MultiSignerRegistration/collapseForSinglePasskey(chosenSigners:delegatedSecrets:ed25519Secrets:connectedCredentialId:)``.
///
/// Either carries the original picker output unchanged, or carries empty
/// collections when the single-passkey fast path applies.
public struct CollapsedSignerSelection {

    /// Signers to pass to the SDK operation (empty on the fast path).
    public let chosen: [any OZSmartAccountSigner]

    /// Delegated-signer verified secrets (empty on the fast path).
    public let delegatedSecrets: [String: String]

    /// Ed25519 verified secret bytes (empty on the fast path).
    public let ed25519Secrets: [Ed25519SecretKey: Data]
}

// ============================================================================
// MARK: - UnsupportedShapePolicy
// ============================================================================

public extension MultiSignerRegistration {

    /// Strategy for handling ``OZSmartAccountSigner`` shapes that the
    /// multi-signer path cannot honour.
    ///
    /// - ``skip``: drop the entry from the result; used when the picker UI
    ///   guarantees the unsupported shapes never reach the conversion.
    /// - ``throwError``: throw ``MultiSignerRegistrationError/unsupportedSignerKind(description:)``;
    ///   used when the picker may admit shapes that the flow needs to reject
    ///   with a typed, surface-able error.
    enum UnsupportedShapePolicy: Sendable {
        case skip
        case throwError
    }
}
