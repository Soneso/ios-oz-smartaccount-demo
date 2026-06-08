// ContextRuleBuilderFlow.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import Security
import stellarsdk

// ============================================================================
// MARK: - ContextRuleResult
// ============================================================================

/// Outcome of a context rule mutation (add, remove, update).
///
/// `success`, `hash`, and `error` match the SDK's `OZTransactionResult` shape so
/// the screen can render success / failure cards from a single value.
public struct ContextRuleResult: Sendable, Equatable {

    /// `true` when the on-chain transaction was submitted and confirmed.
    public let success: Bool

    /// Confirmed Stellar transaction hash on success, otherwise `nil`.
    public let hash: String?

    /// Sanitised error message when `success` is `false`, otherwise `nil`.
    public let error: String?

    public init(success: Bool, hash: String?, error: String?) {
        self.success = success
        self.hash = hash
        self.error = error
    }
}

// ============================================================================
// MARK: - FlowPolicyEntry
// ============================================================================

/// A staged policy entry passed to `addContextRule(...)`, built by the screen
/// from its form state.
public struct FlowPolicyEntry: Sendable {

    /// Policy contract address (`C…`).
    public let address: String

    /// Typed install parameters, or `nil` when re-using an on-chain policy
    /// without parameter changes.
    public let installSpec: PolicyInstallSpec?

    public init(address: String, installSpec: PolicyInstallSpec?) {
        self.address = address
        self.installSpec = installSpec
    }
}

// ============================================================================
// MARK: - LatestLedgerSource
// ============================================================================

/// Abstraction over the Soroban RPC `getLatestLedger` call used by
/// ``ContextRuleFlow/resolveAbsoluteLedger(offset:)``.
///
/// Tests inject `MockLatestLedgerSource` returning a deterministic sequence.
public protocol LatestLedgerSource: Sendable {

    /// Returns the most recently closed Soroban ledger sequence number.
    ///
    /// - Throws: ``ContextRuleFlowError/latestLedgerFetchFailed(reason:)`` on
    ///   RPC failure.
    func latestLedgerSequence() async throws -> UInt32
}

// ============================================================================
// MARK: - SorobanLatestLedgerSource
// ============================================================================

/// Production `LatestLedgerSource` backed by `SorobanServer.getLatestLedger`.
///
/// Created on demand by the production wiring; one instance is held by the
/// screen for the lifetime of a builder session.
public struct SorobanLatestLedgerSource: LatestLedgerSource, Sendable {

    private let rpcUrl: String

    public init(rpcUrl: String) {
        self.rpcUrl = rpcUrl
    }

    public func latestLedgerSequence() async throws -> UInt32 {
        let server = SorobanServer(endpoint: rpcUrl)
        let response = await server.getLatestLedger()
        switch response {
        case .success(let payload):
            return payload.sequence
        case .failure(let error):
            throw ContextRuleFlowError.latestLedgerFetchFailed(
                reason: ActivityLogState.redact(error.localizedDescription)
            )
        }
    }
}

// ============================================================================
// MARK: - ContextRuleFlow add-context-rule helpers
// ============================================================================

extension ContextRuleFlow {

    /// Returns the available passkey signers across all on-chain context rules,
    /// excluding the connected wallet's own credential.
    ///
    /// Filtering rules:
    /// - Only external signers whose verifier address matches the configured
    ///   WebAuthn verifier are returned.
    /// - Signers are de-duplicated by ``OZSmartAccountSigner/uniqueKey``.
    /// - The signer whose credential id matches `excludeCredentialId` is dropped.
    ///
    /// On any failure (including a missing kit) the function returns an empty
    /// list and logs a single info-level activity entry.
    ///
    /// - Parameter excludeCredentialId: Base64URL credential id of the active
    ///   passkey to omit, typically `demoState.credentialId`.
    public func loadAvailablePasskeySigners(
        excludeCredentialId: String?
    ) async -> [any OZSmartAccountSigner] {
        guard demoState.isConnected,
              let manager = contextRuleManager,
              let verifier = webAuthnVerifierAddress else {
            return []
        }
        do {
            let rules = try await manager.listContextRules()
            let externals = rules
                .flatMap { $0.signers }
                .compactMap { $0 as? OZExternalSigner }
                .filter { $0.verifierAddress == verifier }
                .filter { $0.keyData.count > SmartAccountConstants.secp256r1PublicKeySize }
            let unique = OZSmartAccountBuilders
                .collectUniqueSigners(signers: externals)
            return unique.filter { signer in
                let credId = OZSmartAccountBuilders
                    .getCredentialIdStringFromSigner(signer: signer)
                guard let credId, let excludeCredentialId else { return credId != nil }
                return credId != excludeCredentialId
            }
        } catch {
            activityLog.info(
                "Failed to load passkeys: \(ActivityLogState.redact(actionableMessage(for: error)))"
            )
            return []
        }
    }

    /// Registers a fresh WebAuthn credential and returns the corresponding
    /// ``OZExternalSigner`` configured for the WebAuthn verifier contract.
    ///
    /// Generates a 32-byte challenge and a 16-byte user id (WebAuthn protocol
    /// fields — neither is persisted on-chain), calls the platform provider's
    /// `register(...)`, then constructs the signer from the returned public
    /// key and credential id.
    ///
    /// - Parameter name: User-friendly display name surfaced by the platform
    ///   passkey ceremony.
    /// - Returns: The constructed ``OZExternalSigner`` ready to be staged on
    ///   the builder form.
    /// - Throws:
    ///   - ``WebAuthnException/Cancelled`` when the user dismisses the ceremony.
    ///   - ``ContextRuleFlowError/webAuthnProviderUnavailable`` when no
    ///     provider was injected.
    ///   - SDK / verifier errors thrown by the underlying provider.
    public func registerPasskeySigner(name: String) async throws -> any OZSmartAccountSigner {
        guard let provider = webAuthnProvider,
              let verifier = webAuthnVerifierAddress else {
            throw ContextRuleFlowError.webAuthnProviderUnavailable
        }
        activityLog.info("Starting passkey registration...")
        let challenge = ContextRuleBuilderRandom.bytes(32)
        let userId = ContextRuleBuilderRandom.bytes(16)
        let registration = try await provider.register(
            challenge: challenge,
            userId: userId,
            userName: name
        )
        return try OZExternalSigner.webAuthn(
            verifierAddress: verifier,
            publicKey: registration.publicKey,
            credentialId: registration.credentialId
        )
    }

    /// Resolves a relative ledger offset to an absolute ledger sequence by
    /// adding the current Soroban ledger.
    ///
    /// - Parameter offset: Number of ledgers from "now" (e.g. `720` ≈ one hour).
    /// - Returns: `current + offset`, or `nil` when no ledger source is bound.
    /// - Throws: ``ContextRuleFlowError/latestLedgerFetchFailed(reason:)`` on
    ///   RPC failure.
    public func resolveAbsoluteLedger(offset: UInt32) async throws -> UInt32? {
        guard let source = ledgerSource else { return nil }
        let current = try await source.latestLedgerSequence()
        return current &+ offset
    }

    // swiftlint:disable function_parameter_count

    /// Submits a fully-staged new context rule via the SDK and returns a
    /// flattened ``ContextRuleResult``.
    ///
    /// - Parameters:
    ///   - contextType: Operation-matching context.
    ///   - name: Human-readable rule name (already trimmed by the caller).
    ///   - validUntil: Optional absolute expiry ledger.
    ///   - signers: Signers to attach to the new rule.
    ///   - policies: Staged policy entries (address + optional typed install spec).
    ///   - selectedSigners: Multi-signer participants. Empty triggers the
    ///     single-passkey fast-path.
    ///   - delegatedSecrets: Map of G-address → S-secret for any delegated
    ///     entries included in `selectedSigners`.
    ///   - ed25519Secrets: Map of `Ed25519SecretKey` → 32 raw secret bytes for
    ///     any Ed25519 entries included in `selectedSigners`.
    /// - Returns: ``ContextRuleResult`` carrying success / hash / error.
    /// - Throws: ``ContextRuleFlowError/alreadyInProgress`` when reentered,
    ///   ``SmartAccountWalletException/NotConnected`` when no wallet is connected, or any
    ///   error thrown by the SDK.
    public func addContextRule(
        contextType: OZContextRuleType,
        name: String,
        validUntil: UInt32?,
        signers: [any OZSmartAccountSigner],
        policies: [FlowPolicyEntry],
        selectedSigners: [any OZSmartAccountSigner],
        delegatedSecrets: [String: String],
        ed25519Secrets: [Ed25519SecretKey: Data] = [:]
    ) async throws -> ContextRuleResult {
        guard !isAdding else { throw ContextRuleFlowError.alreadyInProgress }
        guard demoState.isConnected, let manager = contextRuleManager else {
            throw SmartAccountWalletException.NotConnected(message: "No wallet connected.")
        }
        isAdding = true
        defer { isAdding = false }

        activityLog.info("Submitting new context rule...")

        let policiesMap = buildPoliciesMap(policies)
        let built: [OZSelectedSigner]
        do {
            built = try await MultiSignerRegistration.buildSelectedSigners(
                selectedSigners,
                credentialManager: demoState.kit?.credentialManager,
                unsupportedShapePolicy: .throwError
            )
        } catch let MultiSignerRegistrationError.unsupportedSignerKind(description) {
            throw ContextRuleFlowError.unsupportedSignerKind(description: description)
        }
        let sdkResult: OZTransactionResult
        do {
            sdkResult = try await MultiSignerRegistration.registerInProcessSignersWithCleanup(
                delegatedSecrets: delegatedSecrets,
                ed25519Secrets: ed25519Secrets,
                manager: demoState.externalSigners
            ) {
                try await manager.addContextRule(
                    contextType: contextType,
                    name: name,
                    validUntil: validUntil,
                    signers: signers,
                    policies: policiesMap,
                    selectedSigners: built
                )
            }
        } catch let MultiSignerRegistrationError.invalidDelegatedSigner(expected) {
            throw ContextRuleFlowError.invalidDelegatedSigner(expected)
        }
        return handleAddResult(sdkResult)
    }

    // -------------------------------------------------------------------------
    // MARK: - Private helpers
    // -------------------------------------------------------------------------

    private func buildPoliciesMap(_ policies: [FlowPolicyEntry]) -> [String: SCValXDR] {
        var policiesMap: [String: SCValXDR] = [:]
        for entry in policies {
            guard let spec = entry.installSpec else {
                let truncated = truncateAddress(entry.address)
                activityLog.info(
                    "Policy \(truncated) has no install params and will be skipped " +
                    "(params already on-chain)"
                )
                continue
            }
            do {
                policiesMap[entry.address] = try buildInstallParamsScVal(spec: spec)
            } catch {
                let truncated = truncateAddress(entry.address)
                let reason = ActivityLogState.redact(error.localizedDescription)
                activityLog.error("Policy \(truncated) encoding failed: \(reason)")
            }
        }
        return policiesMap
    }

    /// Converts a ``PolicyInstallSpec`` to the on-chain `SCValXDR` encoding by
    /// mapping it to the matching ``OZPolicyInstallParams`` variant and calling
    /// `toScVal()`. The weighted-threshold path maps each ``PolicyWeightedEntry``
    /// to an ``OZSignerWeightEntry`` in the flow layer.
    internal func buildInstallParamsScVal(spec: PolicyInstallSpec) throws -> SCValXDR {
        let params: OZPolicyInstallParams
        switch spec {
        case .simpleThreshold(let threshold):
            params = .simpleThreshold(threshold: threshold)
        case .weightedThreshold(let entries, let threshold):
            let signerWeights = entries.map {
                OZSignerWeightEntry(signer: $0.signer, weight: $0.weight)
            }
            params = .weightedThreshold(signerWeights: signerWeights, threshold: threshold)
        case .spendingLimit(let amount, let decimals, let periodLedgers):
            let baseUnits = try OZTransactionOperations.amountToBaseUnits(amount, decimals: decimals)
            params = .spendingLimit(spendingLimit: baseUnits, periodLedgers: periodLedgers)
        }
        return try params.toScVal()
    }

    private func handleAddResult(_ sdkResult: OZTransactionResult) -> ContextRuleResult {
        if sdkResult.success {
            let hashFragment = sdkResult.hash.map { truncateAddress($0, chars: 8) } ?? "N/A"
            activityLog.success("Context rule created successfully. Hash: \(hashFragment)")
            return ContextRuleResult(success: true, hash: sdkResult.hash, error: nil)
        }
        let msg = ActivityLogState.redact(sdkResult.error ?? "Unknown error")
        activityLog.error("Failed to create context rule: \(msg)")
        return ContextRuleResult(success: false, hash: nil, error: msg)
    }

    // swiftlint:enable function_parameter_count
}

// ============================================================================
// MARK: - ContextRuleBuilderRandom
// ============================================================================

/// Generates cryptographically random bytes for the WebAuthn ceremony fields.
///
/// `SecRandomCopyBytes` is the supported entropy source on Apple platforms.
/// The fallback path uses `Foundation.UInt8.random(in:)` only if the security
/// framework reports a non-success status — that path should not be reachable
/// on production hardware but keeps the helper safe in degraded environments.
internal enum ContextRuleBuilderRandom {

    /// Returns `count` cryptographically random bytes.
    static func bytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = bytes.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let baseAddress = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, buffer.count, baseAddress)
        }
        if status != errSecSuccess {
            for index in 0..<count {
                bytes[index] = UInt8.random(in: 0...UInt8.max)
            }
        }
        return Data(bytes)
    }
}
