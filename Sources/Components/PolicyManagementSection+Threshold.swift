// PolicyManagementSection+Threshold.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - PolicyManagementSection: Simple-threshold form
// ============================================================================

extension PolicyManagementSection {

    @ViewBuilder
    internal func thresholdForm(info: PolicyInfo) -> some View {
        let signerCount = max(signers.count, 1)
        TextField("e.g., 2", text: $thresholdValue)
            .font(Typography.mono)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.numberPad)
            #endif
            .accessibilityLabel("Threshold (required signers)")
            .onChange(of: thresholdValue) { _, _ in
                fieldErrors.removeValue(forKey: "threshold")
            }
        FieldErrorText(error: fieldErrors["threshold"])
        Text("Number of signers required to authorize (1 to \(signerCount))")
            .font(Typography.metadata)
            .foregroundStyle(.tertiary)
        Button {
            addThreshold(info: info)
        } label: {
            Text("Add Threshold Policy")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Self.addButtonVerticalPadding)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: Self.addButtonRadius))
        }
        .buttonStyle(.plain)
        .disabled(thresholdValue.trimmingCharacters(in: .whitespaces).isEmpty)
        .accessibilityLabel("Add Threshold Policy")
    }

    internal func addThreshold(info: PolicyInfo) {
        let trimmed = thresholdValue.trimmingCharacters(in: .whitespaces)
        guard let value = UInt32(trimmed), value >= 1, value <= 15 else {
            fieldErrors["threshold"] = "Must be between 1 and 15"
            return
        }
        if !signers.isEmpty && Int(value) > signers.count {
            fieldErrors["threshold"] = "Cannot exceed signer count (\(signers.count))"
            return
        }
        let scVal = PolicyScValBuilders.buildSimpleThresholdScVal(threshold: value)
        let label = "Threshold: \(value)-of-N"
        if isEditing {
            let entry = EditPolicyEntry(
                info: info,
                label: label,
                address: info.address,
                scVal: scVal,
                onChainId: nil,
                isOriginal: false
            )
            onAddEntry?(entry)
        } else {
            policies.append(
                StagedPolicy(
                    info: info,
                    label: label,
                    address: info.address,
                    scVal: scVal
                )
            )
        }
        thresholdValue = ""
        selectedPolicyType = nil
        activityLog.info("Added simple threshold policy (threshold=\(value))")
    }
}
