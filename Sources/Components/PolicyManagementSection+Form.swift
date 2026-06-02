// PolicyManagementSection+Form.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - PolicyManagementSection: Add-policy form scaffold
// ============================================================================

extension PolicyManagementSection {

    internal var addPolicySection: some View {
        Section {
            policyTypePicker
            policyTypeContent
        } header: {
            Text("Add Policy")
                .font(Typography.sectionHeader)
                .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private var policyTypeContent: some View {
        if let info = selectedPolicyType {
            Text("Contract: \(truncateAddress(info.address, chars: 8))")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            switch info.type {
            case "threshold":          thresholdForm(info: info)
            case "spending_limit":     spendingLimitForm(info: info)
            case "weighted_threshold": weightedThresholdForm(info: info)
            default: EmptyView()
            }
        } else {
            Text("Select a policy type above to configure parameters.")
                .font(Typography.metadata)
                .foregroundStyle(.tertiary)
        }
    }

    internal var availablePolicies: [PolicyInfo] {
        let usedAddresses: Set<String>
        if isEditing {
            usedAddresses = Set(policyEntries.map(\.address))
        } else {
            usedAddresses = Set(policies.map(\.address))
        }
        return knownPolicies.filter { !usedAddresses.contains($0.address) }
    }

    @ViewBuilder
    private var policyTypePicker: some View {
        // active picker constraint message — not an empty-state list
        if availablePolicies.isEmpty {
            Text("All policy types already added")
                .font(Typography.secondary)
                .foregroundStyle(.secondary)
        } else {
            Picker("Policy Type", selection: policyTypeBinding) {
                Text("Select policy type...").tag(Optional<String>.none)
                ForEach(availablePolicies, id: \.address) { info in
                    Text(info.name).tag(Optional<String>.some(info.address))
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Policy Type")
        }
    }

    private var policyTypeBinding: Binding<String?> {
        Binding<String?>(
            get: { selectedPolicyType?.address },
            set: { newValue in
                guard let address = newValue,
                      let info = availablePolicies.first(where: { $0.address == address }) else {
                    selectedPolicyType = nil
                    return
                }
                selectPolicyType(info)
            }
        )
    }

    internal func selectPolicyType(_ info: PolicyInfo) {
        selectedPolicyType = info
        thresholdValue = ""
        spendingLimitAmount = ""
        spendingLimitPeriodDays = ""
        weightedThresholdValue = ""
        signerWeights = [:]
        let keys = [
            "threshold", "spendingAmount", "spendingPeriod",
            "weightedThreshold", "signerWeights", "policy"
        ]
        for key in keys {
            fieldErrors.removeValue(forKey: key)
        }
    }
}
