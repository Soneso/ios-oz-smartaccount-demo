// ContextRuleEditFlow+Steps.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - Step outcome types
// ============================================================================

/// Outcome of a single edit step. Tracked at flow scope so the orchestrator
/// can assemble multi-step pipelines (for example the modified-policy
/// remove + re-add pair) without bubbling the underlying `OZTransactionResult`.
internal enum EditStepOutcome {
    /// Step succeeded; carries the optional transaction hash.
    case ok(String?)
    /// Step failed; carries the underlying failure record.
    case failed(EditStepFailure)
}

/// Describes a failed edit step. Carries both the step label (for the result
/// card's `Failed at:` line) and the sanitised error message.
internal struct EditStepFailure {

    let step: String
    let error: String

    /// Builds a ``ContextRuleEditResult`` representing the failure with the
    /// supplied progress counters and hashes captured by prior steps.
    func toEditResult(
        completed: Int,
        total: Int,
        hashes: [String]
    ) -> ContextRuleEditResult {
        return ContextRuleEditResult(
            success: false,
            completedOperations: completed,
            totalOperations: total,
            partialDueToAuthGuard: false,
            authGuardMessage: nil,
            error: error,
            failedStep: step,
            transactionHashes: hashes
        )
    }
}

/// Outcome of the per-policy modify pipeline. Threshold-only modifications
/// run a single `set_threshold` step (1 op). All other modifications run a
/// remove + re-add pair (2 ops); a partial-failure carries the completed
/// count and any hashes captured before the failing sub-step.
internal enum ModifyPolicyOutcome {
    case ok(stepCount: Int, hashes: [String])
    case partialFailure(
        stepCount: Int,
        hashes: [String],
        result: EditStepFailure,
        failedStep: String
    )
}

// ============================================================================
// MARK: - ContextRuleFlow: per-step helpers
// ============================================================================

extension ContextRuleFlow {

    /// Dispatches an `add_signer` call to the appropriate type-specific SDK
    /// method based on the signer's shape. Throws when the signer carries a
    /// verifier address neither the WebAuthn nor the Ed25519 verifier matches.
    internal func dispatchAddSigner(
        manager: any ContextRuleManagerFullType,
        ruleId: UInt32,
        entry: EditSignerEntry,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        if let delegated = entry.signer as? OZDelegatedSigner {
            return try await manager.addDelegatedSignerToRule(
                ruleId: ruleId,
                address: delegated.address,
                selectedSigners: selectedSigners
            )
        }
        if let external = entry.signer as? OZExternalSigner {
            return try await dispatchExternalAddSigner(
                manager: manager,
                ruleId: ruleId,
                external: external,
                selectedSigners: selectedSigners
            )
        }
        throw ContextRuleFlowError.unsupportedSignerKind(
            description: String(describing: type(of: entry.signer))
        )
    }

    private func dispatchExternalAddSigner(
        manager: any ContextRuleManagerFullType,
        ruleId: UInt32,
        external: OZExternalSigner,
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        if external.verifierAddress == webAuthnVerifierAddress {
            // keyData layout: 65-byte SEC1 public key + credential ID bytes.
            let pkSize = SmartAccountConstants.secp256r1PublicKeySize
            guard external.keyData.count > pkSize else {
                throw ContextRuleFlowError.editStepFailed(
                    step: "Adding passkey signer",
                    reason: "Passkey signer keyData too short to contain public key and credential ID"
                )
            }
            let publicKey = external.keyData.subdata(in: 0..<pkSize)
            let credentialId = external.keyData.subdata(in: pkSize..<external.keyData.count)
            return try await manager.addPasskeySignerToRule(
                ruleId: ruleId,
                publicKey: publicKey,
                credentialId: credentialId,
                selectedSigners: selectedSigners
            )
        }
        guard let ed25519Verifier = ed25519VerifierAddress,
              external.verifierAddress == ed25519Verifier else {
            throw ContextRuleFlowError.editStepFailed(
                step: "Adding external signer",
                reason: "Unknown verifier address: \(external.verifierAddress)"
            )
        }
        return try await manager.addEd25519SignerToRule(
            ruleId: ruleId,
            verifierAddress: ed25519Verifier,
            publicKey: external.keyData,
            selectedSigners: selectedSigners
        )
    }

    /// Runs a single edit step. Cancellations are caught and converted to a
    /// failure outcome carrying the canonical "Passkey authentication
    /// cancelled" copy so the result card renders the same wording across the
    /// app.
    internal func runStep(
        step: String,
        _ body: () async throws -> OZTransactionResult
    ) async -> EditStepOutcome {
        do {
            let result = try await body()
            if result.success {
                return .ok(result.hash)
            }
            let message = ActivityLogState.redact(result.error ?? "Unknown error")
            activityLog.error("\(step) failed: \(message)")
            return .failed(EditStepFailure(step: step, error: message))
        } catch {
            if isUserCancellation(error) {
                activityLog.info("Passkey authentication cancelled")
                return .failed(
                    EditStepFailure(step: step, error: "Passkey authentication cancelled")
                )
            }
            let message = ActivityLogState.redact(actionableMessage(for: error))
            activityLog.error("\(step) failed: \(message)")
            return .failed(EditStepFailure(step: step, error: message))
        }
    }

    // swiftlint:disable function_parameter_count function_body_length

    /// Runs the modify-policy step. Splits on the policy type: threshold-only
    /// is a single `set_threshold` call; all other shapes are remove + re-add.
    internal func runModifyPolicy(
        manager: any ContextRuleManagerFullType,
        ruleId: UInt32,
        entry: EditPolicyEntry,
        step: String,
        selectedSigners: [OZSelectedSigner],
        onProgress: @MainActor @Sendable (String) -> Void
    ) async -> ModifyPolicyOutcome {
        if entry.info?.type == "threshold" {
            return await runModifyThreshold(
                manager: manager,
                ruleId: ruleId,
                entry: entry,
                step: step,
                selectedSigners: selectedSigners,
                onProgress: onProgress
            )
        }
        guard let onChainId = entry.onChainId else {
            return .partialFailure(
                stepCount: 0,
                hashes: [],
                result: EditStepFailure(
                    step: step,
                    error: "Cannot update policy without on-chain ID"
                ),
                failedStep: step
            )
        }
        guard let installParams = entry.scVal else {
            return .partialFailure(
                stepCount: 0,
                hashes: [],
                result: EditStepFailure(
                    step: step,
                    error: "Cannot re-add policy without install parameters"
                ),
                failedStep: step
            )
        }
        return await runRemoveAndReAddPolicy(
            manager: manager,
            ruleId: ruleId,
            entry: entry,
            onChainId: onChainId,
            installParams: installParams,
            step: step,
            selectedSigners: selectedSigners,
            onProgress: onProgress
        )
    }
    // swiftlint:enable function_parameter_count function_body_length

    // swiftlint:disable function_parameter_count function_body_length
    private func runRemoveAndReAddPolicy(
        manager: any ContextRuleManagerFullType,
        ruleId: UInt32,
        entry: EditPolicyEntry,
        onChainId: UInt32,
        installParams: SCValXDR,
        step: String,
        selectedSigners: [OZSelectedSigner],
        onProgress: @MainActor @Sendable (String) -> Void
    ) async -> ModifyPolicyOutcome {
        let removeStep = "\(step) (remove)"
        onProgress("\(step) (removing old)...")
        let removeOutcome = await runStep(step: removeStep) {
            try await manager.removePolicyFromRule(
                ruleId: ruleId,
                policyId: onChainId,
                selectedSigners: selectedSigners
            )
        }
        let removeHash: String?
        switch removeOutcome {
        case .ok(let hash):
            removeHash = hash
        case .failed(let failure):
            return .partialFailure(
                stepCount: 0,
                hashes: [],
                result: failure,
                failedStep: removeStep
            )
        }
        var midHashes: [String] = []
        if let removeHash { midHashes.append(removeHash) }

        let reAddStep = "\(step) (re-add)"
        onProgress("\(step) (adding new)...")
        let addOutcome = await runStep(step: reAddStep) {
            try await manager.addPolicyToRule(
                ruleId: ruleId,
                policyAddress: entry.address,
                installParams: installParams,
                selectedSigners: selectedSigners
            )
        }
        switch addOutcome {
        case .ok(let hash):
            var hashes = midHashes
            if let hash { hashes.append(hash) }
            return .ok(stepCount: 2, hashes: hashes)
        case .failed(let failure):
            return .partialFailure(
                stepCount: 1,
                hashes: midHashes,
                result: failure,
                failedStep: reAddStep
            )
        }
    }
    // swiftlint:enable function_parameter_count function_body_length

    /// Decodes the threshold value from an encoded simple-threshold map
    /// (`Map { Symbol("threshold"): U32 }`). Returns `nil` when the shape is
    /// not recognised.
    internal func decodeThresholdFromMap(_ scVal: SCValXDR) -> UInt32? {
        guard case .map(let entries) = scVal, let entries else { return nil }
        for entry in entries where isThresholdSymbol(entry.key) {
            if case .u32(let value) = entry.val {
                return value
            }
        }
        return nil
    }

    private func isThresholdSymbol(_ scVal: SCValXDR) -> Bool {
        if case .symbol(let key) = scVal, key == "threshold" {
            return true
        }
        return false
    }
}
