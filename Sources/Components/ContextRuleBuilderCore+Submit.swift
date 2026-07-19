// ContextRuleBuilderCore+Submit.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ContextRuleBuilderCore: submit button and edit submission pipeline
// ============================================================================

extension ContextRuleBuilderCore {

    @ViewBuilder
    internal var submitButton: some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            Button(action: handleSubmitTap) {
                HStack(spacing: Tokens.iconLabelSpacing) {
                    if isSubmitting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(0.8)
                    }
                    ButtonLabel(isSubmitting ? "Submitting..." : primaryButtonLabel)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Self.submitVerticalPadding)
            }
            .buttonStyle(.glassProminent)
            .disabled(!submitEnabled)
            .accessibilityLabel(isSubmitting ? "Submitting" : primaryButtonLabel)
            .accessibilityHint(submitHint)
        } else {
            Button(action: handleSubmitTap) {
                HStack(spacing: Tokens.iconLabelSpacing) {
                    if isSubmitting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(0.8)
                    }
                    ButtonLabel(isSubmitting ? "Submitting..." : primaryButtonLabel)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Self.submitVerticalPadding)
                .background(submitEnabled ? Color.accentColor : Color.gray.opacity(Self.submitDisabledAlpha))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: Self.submitRadius))
            }
            .buttonStyle(.plain)
            .disabled(!submitEnabled)
            .accessibilityLabel(isSubmitting ? "Submitting" : primaryButtonLabel)
            .accessibilityHint(submitHint)
        }
        #else
        Button(action: handleSubmitTap) {
            HStack(spacing: Tokens.iconLabelSpacing) {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(0.8)
                }
                ButtonLabel(isSubmitting ? "Submitting..." : primaryButtonLabel)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Self.submitVerticalPadding)
            .background(submitEnabled ? Color.accentColor : Color.gray.opacity(Self.submitDisabledAlpha))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: Self.submitRadius))
        }
        .buttonStyle(.plain)
        .disabled(!submitEnabled)
        .accessibilityLabel(isSubmitting ? "Submitting" : primaryButtonLabel)
        .accessibilityHint(submitHint)
        .keyboardShortcut(.defaultAction)
        #endif
    }

    /// Vertical padding applied to the submit button so it lines up with the
    /// other primary actions in the form (matches ``LoadingButton``).
    fileprivate static let submitVerticalPadding: CGFloat = 12

    /// Background alpha applied to the submit button while disabled.
    fileprivate static let submitDisabledAlpha: Double = 0.3

    /// Corner radius applied to the submit button surface.
    fileprivate static let submitRadius: CGFloat = 10

    internal var primaryButtonLabel: String {
        isEditing ? "Apply Changes" : "Create Context Rule"
    }

    private var submitHint: String {
        if isSubmitting { return "Transaction in progress." }
        if !demoState.isConnected { return "Wallet not connected." }
        if ruleName.trimmingCharacters(in: .whitespaces).isEmpty { return "Form is incomplete." }
        if isEditing {
            if let diff = currentEditDiff, diff.isEmpty {
                return "No changes to apply."
            }
            return "Submits the queued changes for on-chain authorization."
        }
        if signers.isEmpty { return "Add at least one signer." }
        return "Submits the context rule for on-chain authorization."
    }

    internal func handleSubmitTap() {
        if isEditing {
            handleEditSubmitTap()
        } else {
            handleCreateSubmitTap()
        }
    }

    private func handleCreateSubmitTap() {
        let errors = validateForm()
        if !errors.isEmpty {
            fieldErrors = errors
            errorMessage = "Please fix the validation errors above."
            scrollTarget = Self.errorBannerAnchor
            return
        }
        fieldErrors = [:]
        errorMessage = nil
        submissionResult = nil

        let needsPicker = createSignersLoaded &&
            createAvailableSigners.count > 1 &&
            !isSinglePasskeyTransfer(signersFor: createAvailableSigners)

        if needsPicker {
            showCreateSignerPicker = true
            return
        }
        Task { await performSubmit(selectedSigners: [], delegatedSecrets: [:]) }
    }

    private func handleEditSubmitTap() {
        let errors = validateEditForm()
        if !errors.isEmpty {
            fieldErrors = errors
            errorMessage = "Please fix the validation errors above."
            scrollTarget = Self.errorBannerAnchor
            return
        }
        fieldErrors = [:]
        errorMessage = nil
        editResult = nil

        guard let diff = currentEditDiff, !diff.isEmpty else {
            errorMessage = "No changes to apply"
            scrollTarget = Self.errorBannerAnchor
            return
        }

        // Multi-signer decision: based on original on-chain signers.
        let onChainSigners = originalSignerEntries.map(\.signer)
        let needsPicker: Bool
        if onChainSigners.count > 1 {
            needsPicker = !isSinglePasskeyOperation(originalSigners: onChainSigners)
        } else {
            needsPicker = false
        }
        if needsPicker {
            showEditSignerPicker = true
            return
        }
        Task { await performEditSubmit(chosenSigners: [], delegatedSecrets: [:], ed25519Secrets: [:]) }
    }

    private func isSinglePasskeyOperation(
        originalSigners: [any SmartAccountSignerProtocol]
    ) -> Bool {
        guard originalSigners.count == 1 else { return false }
        guard let credId = SmartAccountBuilders.getCredentialIdStringFromSigner(
            signer: originalSigners[0]
        ) else { return false }
        return credId == demoState.credentialId
    }

    internal func validateEditForm() -> [String: String] {
        var errors: [String: String] = [:]
        let trimmedName = ruleName.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty {
            errors["ruleName"] = "Rule name is required"
        } else if trimmedName.utf8.count > ContextRuleBuilderCore.maxRuleNameBytes {
            errors["ruleName"] =
                "Rule name must be \(ContextRuleBuilderCore.maxRuleNameBytes) bytes or less"
        }
        if signerEntries.isEmpty && policyEntries.isEmpty {
            errors["signers"] = "At least one signer or policy must remain"
        }
        if signerEntries.count > OZSmartAccountConstants.maxSigners {
            errors["signers"] = "Maximum \(OZSmartAccountConstants.maxSigners) signers allowed"
        }
        if policyEntries.count > OZSmartAccountConstants.maxPolicies {
            errors["policies"] = "Maximum \(OZSmartAccountConstants.maxPolicies) policies allowed"
        }
        // Duplicate signers
        for outerIndex in signerEntries.indices {
            for innerIndex in (outerIndex + 1)..<signerEntries.count
            where SmartAccountBuilders.signersEqual(
                signerEntries[outerIndex].signer,
                signerEntries[innerIndex].signer
            ) {
                errors["signers"] = "Duplicate signers detected"
            }
        }
        if let expiryError = validateExpiryEdit() {
            errors["expiryLedger"] = expiryError
        }
        return errors
    }

    private func validateExpiryEdit() -> String? {
        guard expiryModified, hasExpiry else { return nil }
        let trimmed = expiryLedger.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == ContextRuleBuilderCore.customExpirySentinel {
            return "Please select an expiry duration"
        }
        guard let value = UInt32(trimmed), value > 0 else {
            return "Must be a positive integer"
        }
        return nil
    }

    @MainActor
    internal func performEditSubmit(
        chosenSigners: [any SmartAccountSignerProtocol],
        delegatedSecrets: [String: String],
        ed25519Secrets: [Ed25519SecretKey: Data]
    ) async {
        guard let editRuleId else { return }
        guard !editSubmitting else { return }
        editSubmitting = true
        isSubmitting = true
        editProgressMessage = ""
        let flow = resolvedFlow()
        let totalsHint = currentEditDiff?.totalOperations ?? 0

        // Both registrations and the multi-step edit submission run inside one
        // cleanup wrapper so neither delegated keypairs nor in-process Ed25519
        // keys leak if any step throws or an early-return path is taken. The
        // context-rule flow uses the in-process Ed25519 custody path, so the
        // demo adapter holds no secret for these keys.
        do {
            try await MultiSignerRegistration.registerInProcessSignersWithCleanup(
                delegatedSecrets: delegatedSecrets,
                ed25519Secrets: ed25519Secrets,
                manager: flow.demoState.externalSigners
            ) {
                await runEditSubmissionBody(
                    flow: flow,
                    editRuleId: editRuleId,
                    chosenSigners: chosenSigners,
                    totalsHint: totalsHint
                )
            }
        } catch let MultiSignerRegistrationError.invalidDelegatedSigner(expected) {
            editResult = makeEditFailureResult(
                error: ContextRuleFlowError.invalidDelegatedSigner(expected),
                failedStep: "Register delegated keypairs",
                totalOperations: totalsHint
            )
        } catch {
            editResult = makeEditFailureResult(
                error: error,
                failedStep: "Register signers",
                totalOperations: totalsHint
            )
        }
        editSubmitting = false
        isSubmitting = false
    }

    @MainActor
    private func runEditSubmissionBody(
        flow: ContextRuleFlow,
        editRuleId: UInt32,
        chosenSigners: [any SmartAccountSignerProtocol],
        totalsHint: Int
    ) async {
        guard let selectedSigners = await resolveSelectedSigners(
            flow: flow,
            chosenSigners: chosenSigners,
            totalsHint: totalsHint
        ) else { return }
        guard let resolvedDiff = await resolveEditDiff(
            flow: flow,
            ruleId: editRuleId
        ) else { return }
        logMultiSignerEdit(chosenSigners: chosenSigners, selectedSigners: selectedSigners)
        await runEditSubmission(
            flow: flow,
            diff: resolvedDiff,
            selectedSigners: selectedSigners,
            ruleId: editRuleId
        )
    }

    @MainActor
    private func resolveEditDiff(
        flow: ContextRuleFlow,
        ruleId: UInt32
    ) async -> ContextRuleEditDiff? {
        let baseDiff = computeEditDiff(ruleId: ruleId)
        do {
            return try await flow.resolveEditDiffExpiry(baseDiff)
        } catch {
            editResult = makeEditFailureResult(
                error: error,
                failedStep: "Resolve expiry",
                totalOperations: baseDiff.totalOperations
            )
            return nil
        }
    }

    @MainActor
    private func logMultiSignerEdit(
        chosenSigners: [any SmartAccountSignerProtocol],
        selectedSigners: [SelectedSignerEntry]
    ) {
        guard !chosenSigners.isEmpty else { return }
        activityLog.info(
            "Editing context rule with multi-signer authorization " +
"(\(pluralize(selectedSigners.count, "signer", "signers")))"
        )
    }

    @MainActor
    private func resolveSelectedSigners(
        flow: ContextRuleFlow,
        chosenSigners: [any SmartAccountSignerProtocol],
        totalsHint: Int
    ) async -> [SelectedSignerEntry]? {
        if chosenSigners.isEmpty {
            return []
        }
        if isSinglePasskeyOperation(originalSigners: chosenSigners) {
            return []
        }
        do {
            return try await flow.buildSelectedSigners(chosenSigners)
        } catch {
            // `flow.buildSelectedSigners` already maps unsupported signer shapes
            // to `ContextRuleFlowError.unsupportedSignerKind`, so the error is
            // surfaced as-is.
            editResult = makeEditFailureResult(
                error: error,
                failedStep: "Resolve signers",
                totalOperations: totalsHint
            )
            return nil
        }
    }

    @MainActor
    private func runEditSubmission(
        flow: ContextRuleFlow,
        diff: ContextRuleEditDiff,
        selectedSigners: [SelectedSignerEntry],
        ruleId: UInt32
    ) async {
        do {
            let result = try await flow.submitContextRuleEdits(
                diff: diff,
                selectedSigners: selectedSigners
            ) { message in
                editProgressMessage = message
            }
            editResult = result
            if !(result.success && !result.partialDueToAuthGuard) {
                try? await populateEditState(ruleId: ruleId)
            }
        } catch {
            handleEditSubmissionError(error: error, totalOperations: diff.totalOperations)
        }
    }

    @MainActor
    private func handleEditSubmissionError(error: Error, totalOperations: Int) {
        if isUserCancellation(error) {
            editResult = ContextRuleEditResult(
                success: false,
                completedOperations: 0,
                totalOperations: totalOperations,
                partialDueToAuthGuard: false,
                authGuardMessage: nil,
                error: "Passkey authentication cancelled",
                failedStep: nil,
                transactionHashes: []
            )
            activityLog.info("Edit cancelled by user")
        } else {
            let safe = ActivityLogState.redact(actionableMessage(for: error))
            editResult = ContextRuleEditResult(
                success: false,
                completedOperations: 0,
                totalOperations: totalOperations,
                partialDueToAuthGuard: false,
                authGuardMessage: nil,
                error: safe,
                failedStep: nil,
                transactionHashes: []
            )
            activityLog.error("Edit failed: \(safe)")
        }
    }

    @MainActor
    private func makeEditFailureResult(
        error: Error,
        failedStep: String,
        totalOperations: Int
    ) -> ContextRuleEditResult {
        let safe = ActivityLogState.redact(actionableMessage(for: error))
        return ContextRuleEditResult(
            success: false,
            completedOperations: 0,
            totalOperations: totalOperations,
            partialDueToAuthGuard: false,
            authGuardMessage: nil,
            error: safe,
            failedStep: failedStep,
            transactionHashes: []
        )
    }

}
