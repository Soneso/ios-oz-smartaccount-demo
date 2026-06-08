// EditPolicyParamsForm+Mutations.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - EditPolicyParamsForm: mutation handlers
// ============================================================================

extension EditPolicyParamsForm {

    internal func prepopulateFromOriginal() {
        guard let params = entry.originalParams else { return }
        switch params.type {
        case "threshold":
            prepopulateThreshold(params: params)
        case "spending_limit":
            prepopulateSpendingLimit(params: params)
        case "weighted_threshold":
            prepopulateWeightedThreshold(params: params)
        default:
            break
        }
    }

    private func prepopulateThreshold(params: PolicyParams) {
        guard editThreshold.isEmpty else { return }
        editThreshold = params.threshold.map { String($0) } ?? ""
    }

    private func prepopulateSpendingLimit(params: PolicyParams) {
        if editAmount.isEmpty {
            editAmount = params.spendingLimit ?? ""
        }
        if editPeriodDays.isEmpty {
            editPeriodDays = params.periodDays.map { String($0) } ?? ""
        }
    }

    private func prepopulateWeightedThreshold(params: PolicyParams) {
        if editWeightedThreshold.isEmpty {
            editWeightedThreshold = params.threshold.map { String($0) } ?? ""
        }
        guard !didPrepopulateWeights, let orig = params.signerWeights else { return }
        var merged = signerWeights
        for signer in signers {
            let key = SmartAccountBuilders.getSignerKey(signer: signer)
            if let weight = orig[key], merged[key] == nil {
                merged[key] = String(weight)
            }
        }
        if merged != signerWeights {
            signerWeights = merged
        }
        didPrepopulateWeights = true
    }

    internal func handleThresholdChange(newValue: String, params: PolicyParams) {
        let filtered = newValue.filter(\.isNumber)
        if filtered != newValue {
            editThreshold = filtered
            return
        }
        if filtered.isEmpty {
            fieldErrors["threshold"] = "Threshold is required"
            return
        }
        guard let parsed = UInt32(filtered) else {
            fieldErrors["threshold"] = "Must be a positive integer"
            return
        }
        if parsed < 1 || parsed > 15 {
            fieldErrors["threshold"] = "Must be between 1 and 15"
            return
        }
        fieldErrors.removeValue(forKey: "threshold")
        let changed = parsed != params.threshold
        let spec = PolicyInstallSpec.simpleThreshold(threshold: parsed)
        let updated = entry.with(
            label: "Threshold: \(parsed)-of-N",
            installSpec: changed ? spec : nil,
            modified: changed
        )
        onEntryUpdated(updated)
    }

    internal func handleSpendingLimitChange(params: PolicyParams) {
        let amount = editAmount.trimmingCharacters(in: .whitespaces)
        let periodStr = editPeriodDays.trimmingCharacters(in: .whitespaces)
        if amount.isEmpty {
            fieldErrors["amount"] = "Amount is required"
            return
        }
        if amount.filter({ $0 == "." }).count > 1 {
            fieldErrors["amount"] = "Amount must contain at most one decimal point"
            return
        }
        guard let _ = Decimal(string: amount.replacingOccurrences(of: ",", with: ".")),
              !amount.hasPrefix("-") else {
            fieldErrors["amount"] = "Amount must be a positive number"
            return
        }
        fieldErrors.removeValue(forKey: "amount")
        guard let days = Int(periodStr), days > 0 else {
            fieldErrors["periodDays"] = "Period must be a positive integer (days)"
            return
        }
        fieldErrors.removeValue(forKey: "periodDays")
        let amountChanged = amount != params.spendingLimit
        let periodChanged = days != params.periodDays
        let changed = amountChanged || periodChanged
        let periodLedgers = UInt32(days * StellarProtocol.ledgersPerDay)
        let spec = PolicyInstallSpec.spendingLimit(
            amount: amount,
            decimals: spendingLimitDecimals,
            periodLedgers: periodLedgers
        )
        let updated = entry.with(
            label: "Limit: \(amount) / \(pluralize(days, "day", "days"))",
            installSpec: changed ? spec : nil,
            modified: changed
        )
        onEntryUpdated(updated)
    }

    // swiftlint:disable function_body_length cyclomatic_complexity
    internal func handleWeightedThresholdChange(params: PolicyParams) {
        let trimmed = editWeightedThreshold.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            fieldErrors["weightedThreshold"] = "Weight threshold is required"
            return
        }
        guard let threshold = UInt32(trimmed), threshold >= 1 else {
            fieldErrors["weightedThreshold"] = "Must be a positive integer"
            return
        }
        fieldErrors.removeValue(forKey: "weightedThreshold")
        if signers.isEmpty {
            fieldErrors["weightedSummary"] =
                "Add signers above to configure per-signer weights"
            return
        }
        fieldErrors.removeValue(forKey: "weightedSummary")
        var perSignerErrors: [String: String] = [:]
        var weightedEntries: [PolicyWeightedEntry] = []
        var totalWeight: UInt64 = 0
        var changed = threshold != params.threshold
        for signer in signers {
            let key = SmartAccountBuilders.getSignerKey(signer: signer)
            let raw = signerWeights[key]?.trimmingCharacters(in: .whitespaces) ?? ""
            guard let weight = UInt32(raw), weight >= 1 else {
                perSignerErrors[key] = "Weight is required (positive integer)"
                continue
            }
            let originalWeight = params.signerWeights?[key]
            if originalWeight != weight { changed = true }
            weightedEntries.append(PolicyWeightedEntry(signer: signer, weight: weight))
            totalWeight += UInt64(weight)
        }
        perSignerWeightErrors = perSignerErrors
        if !perSignerErrors.isEmpty { return }
        if totalWeight < UInt64(threshold) {
            fieldErrors["weightedSummary"] =
                "Total signer weight must be at least the threshold"
            return
        }
        fieldErrors.removeValue(forKey: "weightedSummary")
        let spec = PolicyInstallSpec.weightedThreshold(entries: weightedEntries, threshold: threshold)
        let updated = entry.with(
            label: "Weighted: threshold=\(threshold)",
            installSpec: changed ? spec : nil,
            modified: changed
        )
        onEntryUpdated(updated)
    }
    // swiftlint:enable function_body_length cyclomatic_complexity
}
