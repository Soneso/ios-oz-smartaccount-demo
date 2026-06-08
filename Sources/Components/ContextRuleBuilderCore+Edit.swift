// ContextRuleBuilderCore+Edit.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ContextRuleBuilderCore: edit-mode helpers
// ============================================================================

extension ContextRuleBuilderCore {

    // -------------------------------------------------------------------------
    // MARK: - Rule loading
    // -------------------------------------------------------------------------

    @MainActor
    internal func loadRuleIfNeeded() async {
        guard let editRuleId else { return }
        guard demoState.isConnected else { return }
        guard !isLoadingRule else { return }
        isLoadingRule = true
        errorMessage = nil
        defer { isLoadingRule = false }
        do {
            try await populateEditState(ruleId: editRuleId)
        } catch {
            let safe = ActivityLogState.redact(actionableMessage(for: error))
            errorMessage = "Failed to load rule #\(editRuleId): \(safe)"
            activityLog.error("Failed to load rule: \(safe)")
        }
    }

    @MainActor
    internal func populateEditState(ruleId: UInt32) async throws {
        let flow = resolvedFlow()
        let parsed = try await flow.loadParsedContextRule(ruleId: ruleId)
        applyParsedRuleScalars(parsed: parsed)
        applyParsedSigners(parsed: parsed)
        await applyParsedPolicies(parsed: parsed, flow: flow)
        await loadExistingOnChainSigners(flow: flow)
        activityLog.info(
            "Loaded rule #\(ruleId) for editing: " +
            "\(pluralize(signerEntries.count, "signer", "signers")), " +
            "\(pluralize(policyEntries.count, "policy", "policies"))"
        )
    }

    @MainActor
    private func applyParsedRuleScalars(parsed: ParsedContextRuleInfo) {
        ruleName = parsed.name
        originalName = parsed.name
        switch parsed.contextType {
        case .defaultRule:
            contextTypeOption = .defaultRule
        case .callContract(let address):
            contextTypeOption = .callContract
            contractAddress = address
        case .createContract(let wasm):
            contextTypeOption = .createContract
            wasmHashHex = hexString(from: wasm)
        }
        if let validUntil = parsed.validUntil {
            hasExpiry = true
            existingExpiryLedger = validUntil
        } else {
            hasExpiry = false
            existingExpiryLedger = nil
        }
        expiryLedger = ""
        expiryModified = false
    }

    @MainActor
    private func applyParsedSigners(parsed: ParsedContextRuleInfo) {
        let loaded = parsed.signers.enumerated().map { index, signer in
            EditSignerEntry(
                signer: signer,
                onChainId: parsed.signerIds.indices.contains(index)
                    ? parsed.signerIds[index] : nil,
                isOriginal: true
            )
        }
        signerEntries = loaded
        originalSignerEntries = loaded
        signers = loaded.map(\.signer)
        signerWeights = [:]
    }

    @MainActor
    private func applyParsedPolicies(
        parsed: ParsedContextRuleInfo,
        flow: ContextRuleFlow
    ) async {
        var loaded: [EditPolicyEntry] = []
        loaded.reserveCapacity(parsed.policies.count)
        for (index, address) in parsed.policies.enumerated() {
            let entry = await buildEditPolicyEntry(
                address: address,
                index: index,
                parsed: parsed,
                flow: flow
            )
            loaded.append(entry)
        }
        policyEntries = loaded
        originalPolicyEntries = loaded
        policies = loaded.map(stagedPolicyForEntry)
    }

    @MainActor
    private func buildEditPolicyEntry(
        address: String,
        index: Int,
        parsed: ParsedContextRuleInfo,
        flow: ContextRuleFlow
    ) async -> EditPolicyEntry {
        let info = knownPolicies.first { $0.address == address }
        var originalParams: PolicyParams?
        if let info {
            originalParams = await flow.readPolicyParams(
                info: info,
                ruleId: parsed.id,
                guardedToken: guardedTokenContract(for: parsed)
            )
        }
        let label: String
        if let info {
            label = labelForExistingPolicy(info: info, params: originalParams)
        } else {
            label = "Unknown Policy"
        }
        return EditPolicyEntry(
            info: info,
            label: label,
            address: address,
            installSpec: nil,
            onChainId: parsed.policyIds.indices.contains(index)
                ? parsed.policyIds[index] : nil,
            isOriginal: true,
            modified: false,
            originalParams: originalParams
        )
    }

    private func stagedPolicyForEntry(_ entry: EditPolicyEntry) -> StagedPolicy {
        StagedPolicy(
            info: entry.info ?? PolicyInfo(
                type: "unknown",
                name: "Unknown",
                description: "",
                address: entry.address
            ),
            label: entry.label,
            address: entry.address,
            installSpec: entry.installSpec
        )
    }

    @MainActor
    private func loadExistingOnChainSigners(flow: ContextRuleFlow) async {
        let allRules = (try? await flow.listContextRules()) ?? []
        let allSigners = allRules.flatMap(\.signers)
        let unique = SmartAccountBuilders.collectUniqueSigners(signers: allSigners)
        allOnChainSigners = unique.filter { signer in
            if let cred = SmartAccountBuilders.getCredentialIdStringFromSigner(signer: signer),
               cred == demoState.credentialId {
                return false
            }
            return true
        }
    }

    private func labelForExistingPolicy(info: PolicyInfo, params: PolicyParams?) -> String {
        guard let params else { return info.name }
        switch params.type {
        case "threshold":
            if let value = params.threshold { return "Threshold: \(value)-of-N" }
            return info.name
        case "spending_limit":
            let amount = params.spendingLimit ?? "?"
            let daysStr = params.periodDays.map { pluralize($0, "day", "days") } ?? "? days"
            return "Limit: \(amount) / \(daysStr)"
        case "weighted_threshold":
            if let value = params.threshold { return "Weighted: threshold=\(value)" }
            return info.name
        default:
            return info.name
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Entry mutations
    // -------------------------------------------------------------------------

    @MainActor
    internal func appendSignerEntry(_ entry: EditSignerEntry) {
        signerEntries.append(entry)
        signers = signerEntries.map(\.signer)
    }

    @MainActor
    internal func removeSignerEntry(at index: Int) {
        guard signerEntries.indices.contains(index) else { return }
        let removed = signerEntries.remove(at: index)
        signers = signerEntries.map(\.signer)
        let key = SmartAccountBuilders.getSignerKey(signer: removed.signer)
        signerWeights.removeValue(forKey: key)
        fieldErrors.removeValue(forKey: "signers")
    }

    @MainActor
    internal func appendPolicyEntry(_ entry: EditPolicyEntry) {
        policyEntries.append(entry)
        syncPoliciesFromEntries()
    }

    @MainActor
    internal func removePolicyEntry(at index: Int) {
        guard policyEntries.indices.contains(index) else { return }
        policyEntries.remove(at: index)
        syncPoliciesFromEntries()
    }

    @MainActor
    internal func updatePolicyEntry(at index: Int, with entry: EditPolicyEntry) {
        guard policyEntries.indices.contains(index) else { return }
        policyEntries[index] = entry
        syncPoliciesFromEntries()
    }

    private func syncPoliciesFromEntries() {
        policies = policyEntries.map { entry in
            StagedPolicy(
                info: entry.info ?? PolicyInfo(
                    type: "unknown",
                    name: "Unknown",
                    description: "",
                    address: entry.address
                ),
                label: entry.label,
                address: entry.address,
                installSpec: entry.installSpec
            )
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Diff computation
    // -------------------------------------------------------------------------

    @MainActor
    internal func computeEditDiff(ruleId: UInt32) -> ContextRuleEditDiff {
        let trimmedName = ruleName.trimmingCharacters(in: .whitespaces)
        let nameChanged = trimmedName != originalName
        let newSigners = signerEntries.filter { !$0.isOriginal }
        let removedSigners = originalSignerEntries.filter { orig in
            !signerEntries.contains { entry in
                SmartAccountBuilders.signersEqual(entry.signer, orig.signer)
            }
        }
        let newPolicies = policyEntries.filter { !$0.isOriginal }
        let removedPolicies = originalPolicyEntries.filter { orig in
            !policyEntries.contains { $0.address == orig.address }
        }
        let modifiedPolicies = policyEntries.filter { $0.isOriginal && $0.modified }
        return ContextRuleEditDiff(
            ruleId: ruleId,
            nameChanged: nameChanged,
            newName: nameChanged ? trimmedName : nil,
            newSigners: newSigners,
            removedSigners: removedSigners,
            newPolicies: newPolicies,
            removedPolicies: removedPolicies,
            modifiedPolicies: modifiedPolicies,
            expiryChanged: expiryModified,
            newExpiry: resolveEditDiffExpiry()
        )
    }

    @MainActor
    private func resolveEditDiffExpiry() -> UInt32? {
        guard expiryModified, hasExpiry else { return nil }
        let trimmed = expiryLedger.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == Self.customExpirySentinel {
            // Surface as nil so the validator can gate the submission — never
            // silently fall back to the existing on-chain ledger value, which
            // would submit a no-op expiry update the user did not request.
            return nil
        }
        return UInt32(trimmed) ?? existingExpiryLedger
    }

    // -------------------------------------------------------------------------
    // MARK: - Operation summary section
    // -------------------------------------------------------------------------

    @ViewBuilder
    internal var editOperationSummarySection: some View {
        if let diff = currentEditDiff {
            let announcement = editOperationSummaryAnnouncement(diff)
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    if diff.isEmpty {
                        // active-flow diff summary inside an in-progress edit — not an empty-state
                        Text("No changes to apply")
                            .font(Typography.secondary)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Pending changes: \(editPendingChanges(diff: diff))")
                            .font(Typography.secondary)
                        Text("\(pluralize(diff.totalOperations, "passkey prompt", "passkey prompts")) required")
                            .font(Typography.metadata)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .modifier(AccessibilityAnnouncementModifier(text: announcement))
                .onChange(of: announcement) { _, newAnnouncement in
                    postAccessibilityAnnouncement(newAnnouncement)
                }
            } header: {
                Text("Pending Operations")
                    .font(Typography.sectionHeader)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }

    private func editPendingChanges(diff: ContextRuleEditDiff) -> String {
        var parts: [String] = []
        if diff.nameChanged { parts.append("name update") }
        if !diff.newSigners.isEmpty {
            parts.append(pluralize(diff.newSigners.count, "signer add", "signer adds"))
        }
        if !diff.removedSigners.isEmpty {
            parts.append(pluralize(diff.removedSigners.count, "signer removal", "signer removals"))
        }
        if !diff.newPolicies.isEmpty {
            parts.append(pluralize(diff.newPolicies.count, "policy add", "policy adds"))
        }
        if !diff.removedPolicies.isEmpty {
            parts.append(pluralize(diff.removedPolicies.count, "policy removal", "policy removals"))
        }
        if !diff.modifiedPolicies.isEmpty {
            parts.append(pluralize(diff.modifiedPolicies.count, "policy update", "policy updates"))
        }
        if diff.expiryChanged { parts.append("expiry update") }
        return parts.joined(separator: ", ")
    }

    private func editOperationSummaryAnnouncement(_ diff: ContextRuleEditDiff) -> String {
        if diff.isEmpty { return "No changes to apply" }
        return "Pending changes: \(editPendingChanges(diff: diff)). " +
               "\(pluralize(diff.totalOperations, "passkey prompt", "passkey prompts")) required."
    }

    // -------------------------------------------------------------------------
    // MARK: - Progress row
    // -------------------------------------------------------------------------

    @ViewBuilder
    internal var editProgressRow: some View {
        if editSubmitting && !editProgressMessage.isEmpty {
            HStack(spacing: Tokens.iconLabelSpacing) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
                Text(editProgressMessage)
                    .font(Typography.secondary)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(editProgressMessage)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(AccessibilityAnnouncementModifier(text: editProgressMessage))
            .onChange(of: editProgressMessage) { _, newMessage in
                guard !newMessage.isEmpty else { return }
                postAccessibilityAnnouncement(newMessage)
            }
        }
    }

}
