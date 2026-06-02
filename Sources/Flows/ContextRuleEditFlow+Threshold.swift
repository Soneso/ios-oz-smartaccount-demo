// ContextRuleEditFlow+Threshold.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - ContextRuleFlow: threshold-fast-path helpers
// ============================================================================

extension ContextRuleFlow {

    /// Bundle of resolved inputs the threshold fast-path needs to execute.
    internal struct ThresholdPreflight {
        let executor: any SmartAccountExecutorType
        let newThreshold: UInt32
        let freshRule: SCValXDR
        let smartAccountScVal: SCValXDR
    }

    /// Outcome of the threshold-modification preflight step. Either resolves
    /// to the inputs required to build `set_threshold`, or surfaces a
    /// ``ModifyPolicyOutcome/partialFailure`` carrying the sanitised error
    /// the caller can return verbatim.
    internal enum ThresholdPreflightOutcome {
        case ready(ThresholdPreflight)
        case rejected(ModifyPolicyOutcome)
    }

    // swiftlint:disable function_parameter_count
    /// Drives the threshold-only modification fast-path: validates the staged
    /// inputs against the freshly-fetched on-chain rule and submits a single
    /// `set_threshold` call (1 op).
    internal func runModifyThreshold(
        manager: any ContextRuleManagerFullType,
        ruleId: UInt32,
        entry: EditPolicyEntry,
        step: String,
        selectedSigners: [SelectedSigner],
        onProgress: @MainActor @Sendable (String) -> Void
    ) async -> ModifyPolicyOutcome {
        onProgress("\(step) (set_threshold)...")
        let preflightOutcome = await preflightThresholdModification(
            manager: manager,
            ruleId: ruleId,
            entry: entry,
            step: step
        )
        switch preflightOutcome {
        case .ready(let preflight):
            return await executeSetThreshold(
                entry: entry,
                step: step,
                preflight: preflight,
                selectedSigners: selectedSigners
            )
        case .rejected(let outcome):
            return outcome
        }
    }
    // swiftlint:enable function_parameter_count

    private func executeSetThreshold(
        entry: EditPolicyEntry,
        step: String,
        preflight: ThresholdPreflight,
        selectedSigners: [SelectedSigner]
    ) async -> ModifyPolicyOutcome {
        let targetArgs: [SCValXDR] = [
            .u32(preflight.newThreshold),
            preflight.freshRule,
            preflight.smartAccountScVal
        ]
        let outcome = await runStep(step: step) {
            if selectedSigners.isEmpty {
                return try await preflight.executor.executeAndSubmit(
                    target: entry.address,
                    targetFn: "set_threshold",
                    targetArgs: targetArgs
                )
            }
            return try await preflight.executor.multiSignerExecuteAndSubmit(
                target: entry.address,
                targetFn: "set_threshold",
                targetArgs: targetArgs,
                selectedSigners: selectedSigners
            )
        }
        switch outcome {
        case .ok(let hash):
            return .ok(stepCount: 1, hashes: hash.map { [$0] } ?? [])
        case .failed(let failure):
            return .partialFailure(
                stepCount: 0,
                hashes: [],
                result: failure,
                failedStep: step
            )
        }
    }

    private func preflightThresholdModification(
        manager: any ContextRuleManagerFullType,
        ruleId: UInt32,
        entry: EditPolicyEntry,
        step: String
    ) async -> ThresholdPreflightOutcome {
        guard let scVal = entry.scVal,
              let newThreshold = decodeThresholdFromMap(scVal) else {
            return .rejected(thresholdPreflightFailure(
                step: step,
                error: "Threshold value not found in policy params"
            ))
        }
        guard let executor = smartAccountExecutor else {
            return .rejected(thresholdPreflightFailure(
                step: step,
                error: "Smart account executor is not configured."
            ))
        }
        guard let contractId = demoState.contractId else {
            return .rejected(thresholdPreflightFailure(
                step: step,
                error: "No wallet connected."
            ))
        }
        return await resolveThresholdInputs(
            manager: manager,
            ruleId: ruleId,
            entry: entry,
            step: step,
            executor: executor,
            contractId: contractId,
            newThreshold: newThreshold
        )
    }

    // swiftlint:disable:next function_parameter_count
    private func resolveThresholdInputs(
        manager: any ContextRuleManagerFullType,
        ruleId: UInt32,
        entry: EditPolicyEntry,
        step: String,
        executor: any SmartAccountExecutorType,
        contractId: String,
        newThreshold: UInt32
    ) async -> ThresholdPreflightOutcome {
        let freshRule: SCValXDR
        do {
            freshRule = try await manager.getContextRuleRaw(ruleId: ruleId)
        } catch {
            let message = ActivityLogState.redact(actionableMessage(for: error))
            return .rejected(thresholdPreflightFailure(step: step, error: message))
        }
        if let mismatch = detectStaleRuleMismatch(
            ruleId: ruleId,
            policyAddress: entry.address,
            freshRule: freshRule,
            entry: entry
        ) {
            return .rejected(thresholdPreflightFailure(step: step, error: mismatch))
        }
        let smartAccountScVal: SCValXDR
        do {
            smartAccountScVal = SCValXDR.address(try SCAddressXDR(contractId: contractId))
        } catch {
            let message = ActivityLogState.redact(actionableMessage(for: error))
            return .rejected(thresholdPreflightFailure(step: step, error: message))
        }
        return .ready(ThresholdPreflight(
            executor: executor,
            newThreshold: newThreshold,
            freshRule: freshRule,
            smartAccountScVal: smartAccountScVal
        ))
    }

    private func thresholdPreflightFailure(
        step: String,
        error: String
    ) -> ModifyPolicyOutcome {
        return .partialFailure(
            stepCount: 0,
            hashes: [],
            result: EditStepFailure(step: step, error: error),
            failedStep: step
        )
    }
}
