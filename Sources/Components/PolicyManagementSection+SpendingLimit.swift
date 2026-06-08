// PolicyManagementSection+SpendingLimit.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - PolicyManagementSection: Spending-limit form
// ============================================================================

extension PolicyManagementSection {

    @ViewBuilder
    internal func spendingLimitForm(info: PolicyInfo) -> some View {
        TextField("e.g., 100.0", text: $spendingLimitAmount)
            .font(Typography.mono)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.decimalPad)
            #endif
            .accessibilityLabel("Amount")
            .onChange(of: spendingLimitAmount) { _, _ in
                fieldErrors.removeValue(forKey: "spendingAmount")
            }
        FieldErrorText(error: fieldErrors["spendingAmount"])
        Text("Maximum amount allowed per period")
            .font(Typography.metadata)
            .foregroundStyle(.tertiary)
        TextField("e.g., 1", text: $spendingLimitPeriodDays)
            .font(Typography.mono)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.numberPad)
            #endif
            .accessibilityLabel("Period (days)")
            .onChange(of: spendingLimitPeriodDays) { _, _ in
                fieldErrors.removeValue(forKey: "spendingPeriod")
            }
        FieldErrorText(error: fieldErrors["spendingPeriod"])
        spendingLimitHelperText
        addSpendingLimitButton(info: info)
    }

    @ViewBuilder
    private var spendingLimitHelperText: some View {
        let trimmed = spendingLimitPeriodDays.trimmingCharacters(in: .whitespaces)
        if let days = Int(trimmed), days > 0 {
            Text("\(pluralize(days, "day", "days")) = \(days * StellarProtocol.ledgersPerDay) ledgers")
                .font(Typography.metadata)
                .foregroundStyle(.tertiary)
        } else {
            Text(
                "The spending limit resets after this period. Example: amount 100 with " +
                "period 1 means max 100 tokens per day."
            )
            .font(Typography.metadata)
            .foregroundStyle(.tertiary)
        }
    }

    private func addSpendingLimitButton(info: PolicyInfo) -> some View {
        Button {
            addSpendingLimit(info: info)
        } label: {
            Text("Add Spending Limit Policy")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Self.addButtonVerticalPadding)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: Self.addButtonRadius))
        }
        .buttonStyle(.plain)
        .disabled(spendingLimitDisabled)
        .accessibilityLabel("Add Spending Limit Policy")
    }

    /// Vertical padding inside the per-form add-policy CTA button.
    internal static var addButtonVerticalPadding: CGFloat { 10 }

    /// Corner radius applied to the per-form add-policy CTA button.
    internal static var addButtonRadius: CGFloat { 10 }

    private var spendingLimitDisabled: Bool {
        spendingLimitAmount.trimmingCharacters(in: .whitespaces).isEmpty ||
        spendingLimitPeriodDays.trimmingCharacters(in: .whitespaces).isEmpty
    }

    internal func addSpendingLimit(info: PolicyInfo) {
        let amountStr = spendingLimitAmount.trimmingCharacters(in: .whitespaces)
        let periodStr = spendingLimitPeriodDays.trimmingCharacters(in: .whitespaces)
        if !isPositiveDecimal(amountStr) {
            fieldErrors["spendingAmount"] = "Must be a positive number"
            return
        }
        guard let days = Int(periodStr), days >= 1 else {
            fieldErrors["spendingPeriod"] = "Must be at least 1 day"
            return
        }
        guard let baseUnits = baseUnitsFromDecimalAmount(amountStr), baseUnits > 0 else {
            fieldErrors["spendingAmount"] = "Must be a positive number"
            return
        }
        let periodLedgers = UInt32(days * StellarProtocol.ledgersPerDay)
        let scVal = PolicyScValBuilders.buildSpendingLimitScVal(
            limit: baseUnits,
            periodLedgers: periodLedgers
        )
        let label = "Limit: \(amountStr) / \(pluralize(days, "day", "days"))"
        registerSpendingLimitPolicy(info: info, label: label, scVal: scVal)
        spendingLimitAmount = ""
        spendingLimitPeriodDays = ""
        selectedPolicyType = nil
        activityLog.info(
            "Added spending limit policy (\(amountStr) per \(pluralize(days, "day", "days")))"
        )
    }

    private func registerSpendingLimitPolicy(
        info: PolicyInfo,
        label: String,
        scVal: ScVal
    ) {
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
    }

    private func isPositiveDecimal(_ value: String) -> Bool {
        if value.isEmpty { return false }
        if value.filter({ $0 == "." }).count > 1 { return false }
        guard let decimal = Decimal(string: value), decimal > 0 else { return false }
        return true
    }
}
