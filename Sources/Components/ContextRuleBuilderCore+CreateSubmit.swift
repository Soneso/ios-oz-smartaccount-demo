// ContextRuleBuilderCore+CreateSubmit.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ExpiryResolution
// ============================================================================

/// Outcome of resolving the optional expiry field to an absolute ledger.
///
/// Models the three outcomes of resolving the optional expiry field: the user
/// did not request an expiry, expiry resolved to an absolute ledger (or stayed
/// nil because no ledger source was bound), and resolution failed.
internal enum ExpiryResolution {
    /// The user did not request an expiry.
    case skipped
    /// Expiry resolved to `value` (or stayed `nil` when no ledger source is bound).
    case resolved(UInt32?)
    /// Resolution failed; `submissionResult` has already been populated with the error.
    case failed
}

// ============================================================================
// MARK: - ContextRuleBuilderCore: create-mode submission pipeline
// ============================================================================

extension ContextRuleBuilderCore {

    @MainActor
    internal func performSubmit(
        selectedSigners chosen: [any SmartAccountSignerProtocol],
        delegatedSecrets: [String: String],
        ed25519Secrets: [Ed25519SecretKey: Data] = [:]
    ) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        guard let contextType = resolveContextType() else { return }
        let validUntil: UInt32?
        switch await resolveExpiry() {
        case .failed:
            return
        case .skipped:
            validUntil = nil
        case .resolved(let value):
            validUntil = value
        }

        let flowPolicies = policies.map {
            FlowPolicyEntry(address: $0.address, scVal: $0.scVal)
        }

        if !chosen.isEmpty {
            activityLog.info(
                "Creating context rule with multi-signer authorization (\(pluralize(chosen.count, "signer", "signers")))"
            )
        }

        await runAddContextRule(
            chosen: chosen,
            delegatedSecrets: delegatedSecrets,
            ed25519Secrets: ed25519Secrets,
            contextType: contextType,
            validUntil: validUntil,
            flowPolicies: flowPolicies
        )
    }

    private func resolveContextType() -> OZContextRuleType? {
        do {
            return try buildContextType()
        } catch {
            submissionResult = ContextRuleResult(
                success: false,
                hash: nil,
                error: ActivityLogState.redact(actionableMessage(for: error))
            )
            return nil
        }
    }

    /// Resolves the optional expiry field, populating `submissionResult` with
    /// a redacted error when resolution fails so the call site only has to
    /// branch on the three enum cases.
    private func resolveExpiry() async -> ExpiryResolution {
        guard hasExpiry,
              let offsetValue = UInt32(expiryLedger.trimmingCharacters(in: .whitespaces)) else {
            return .skipped
        }
        do {
            let ledger = try await resolvedFlow().resolveAbsoluteLedger(offset: offsetValue)
            return .resolved(ledger)
        } catch {
            submissionResult = ContextRuleResult(
                success: false,
                hash: nil,
                error: ActivityLogState.redact(actionableMessage(for: error))
            )
            return .failed
        }
    }

    private func runAddContextRule(
        chosen: [any SmartAccountSignerProtocol],
        delegatedSecrets: [String: String],
        ed25519Secrets: [Ed25519SecretKey: Data],
        contextType: OZContextRuleType,
        validUntil: UInt32?,
        flowPolicies: [FlowPolicyEntry]
    ) async {
        do {
            let result = try await resolvedFlow().addContextRule(
                contextType: contextType,
                name: ruleName.trimmingCharacters(in: .whitespaces),
                validUntil: validUntil,
                signers: signers,
                policies: flowPolicies,
                selectedSigners: chosen,
                delegatedSecrets: delegatedSecrets,
                ed25519Secrets: ed25519Secrets
            )
            submissionResult = result
        } catch {
            handleSubmissionError(error)
        }
    }

    private func handleSubmissionError(_ error: Error) {
        if isUserCancellation(error) {
            submissionResult = ContextRuleResult(
                success: false,
                hash: nil,
                error: "Passkey authentication cancelled"
            )
            activityLog.info("Passkey authentication cancelled")
        } else {
            let msg = ActivityLogState.redact(actionableMessage(for: error))
            submissionResult = ContextRuleResult(success: false, hash: nil, error: msg)
            activityLog.error("Transaction failed: \(msg)")
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Build context type
    // -------------------------------------------------------------------------

    internal func buildContextType() throws -> OZContextRuleType {
        switch contextTypeOption {
        case .defaultRule:
            return .defaultRule
        case .callContract:
            let address = contractAddress.trimmingCharacters(in: .whitespaces)
            return .callContract(contractAddress: address)
        case .createContract:
            let hex = wasmHashHex.trimmingCharacters(in: .whitespaces).lowercased()
            guard let bytes = data(fromHex: hex) else {
                throw ContextRuleFlowError.invalidContextType(reason: "Invalid WASM hash hex")
            }
            return .createContract(wasmHash: bytes)
        }
    }
}
