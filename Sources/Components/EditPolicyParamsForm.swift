// EditPolicyParamsForm.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - EditPolicyParamsForm
// ============================================================================

/// Inline form that lets the user edit an existing on-chain policy's
/// installation parameters during edit mode.
///
/// Pre-populates each field from ``EditPolicyEntry/originalParams``. When the
/// user changes any value the form rebuilds the `ScVal` install parameters,
/// updates the `modified` flag, and forwards the new entry through
/// `onEntryUpdated`.
///
/// Hosted inside a parent `Form { Section }`; the form lays out as native
/// rows (no extra container chrome). Field errors render through
/// `FieldErrorText` rows directly beneath each input.
struct EditPolicyParamsForm: View {

    let entry: EditPolicyEntry
    let signers: [any SmartAccountSignerProtocol]
    @Binding var signerWeights: [String: String]
    let isSubmitting: Bool

    /// Decimal scale for the rule's guarded token, used to convert the edited
    /// spending-limit amount to base units. Resolved by the parent.
    var spendingLimitDecimals: Int = nativeTokenDecimals

    let onEntryUpdated: (EditPolicyEntry) -> Void

    @State internal var editThreshold: String = ""
    @State internal var editAmount: String = ""
    @State internal var editPeriodDays: String = ""
    @State internal var editWeightedThreshold: String = ""
    @State internal var didPrepopulateWeights: Bool = false

    /// Per-field validation errors keyed by a stable field identifier. The
    /// mutation handlers update this map so the user receives a visible (and
    /// VoiceOver-announced) error rather than a silent return.
    @State internal var fieldErrors: [String: String] = [:]
    @State internal var perSignerWeightErrors: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Edit \(entry.info?.name ?? "Policy") Parameters")
                .font(Typography.metadata)
                .fontWeight(.bold)
                .foregroundStyle(Color.accentColor)
                .accessibilityAddTraits(.isHeader)
            if entry.modified {
                Text("Parameters modified (will be updated on submit)")
                    .font(Typography.metadata)
                    .foregroundStyle(Color.contextRuleExpiryBadgeForeground)
            }
            content
        }
        .onAppear(perform: prepopulateFromOriginal)
        .onChange(of: entry.modified) { _, modified in
            guard modified else { return }
            let policyName = entry.info?.name ?? "Policy"
            let message = "\(policyName) parameters modified. Will be updated on submit."
            postAccessibilityAnnouncement(message)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Per-type forms
    // -------------------------------------------------------------------------

    @ViewBuilder
    private var content: some View {
        if let params = entry.originalParams {
            forms(params: params)
        }
    }

    @ViewBuilder
    private func forms(params: PolicyParams) -> some View {
        switch params.type {
        case "threshold":
            thresholdField(params: params)
        case "spending_limit":
            spendingLimitFields(params: params)
        case "weighted_threshold":
            weightedThresholdFields(params: params)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func thresholdField(params: PolicyParams) -> some View {
        TextField(params.threshold.map { String($0) } ?? "1", text: $editThreshold)
            .font(Typography.mono)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.numberPad)
            #endif
            .accessibilityLabel("Threshold (required signers)")
            .onChange(of: editThreshold) { _, newValue in
                handleThresholdChange(newValue: newValue, params: params)
            }
        FieldErrorText(error: fieldErrors["threshold"])
        Text("Current on-chain value: \(params.threshold.map { String($0) } ?? "unknown")")
            .font(Typography.metadata)
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private func spendingLimitFields(params: PolicyParams) -> some View {
        spendingLimitAmountField(params: params)
            .onChange(of: editAmount) { _, _ in
                handleSpendingLimitChange(params: params)
            }
        spendingLimitPeriodField(params: params)
            .onChange(of: editPeriodDays) { _, _ in
                handleSpendingLimitChange(params: params)
            }
    }

    @ViewBuilder
    private func spendingLimitAmountField(params: PolicyParams) -> some View {
        TextField(params.spendingLimit ?? "100.0", text: $editAmount)
            .font(Typography.mono)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.decimalPad)
            #endif
            .accessibilityLabel("Amount")
        FieldErrorText(error: fieldErrors["amount"])
        Text("Current on-chain value: \(params.spendingLimit ?? "unknown")")
            .font(Typography.metadata)
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private func spendingLimitPeriodField(params: PolicyParams) -> some View {
        TextField(params.periodDays.map { String($0) } ?? "1", text: $editPeriodDays)
            .font(Typography.mono)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.numberPad)
            #endif
            .accessibilityLabel("Period (days)")
        FieldErrorText(error: fieldErrors["periodDays"])
        Text(
            "Current on-chain value: " +
            (params.periodDays.map { pluralize($0, "day", "days") } ?? "unknown days")
        )
        .font(Typography.metadata)
        .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private func weightedThresholdFields(params: PolicyParams) -> some View {
        TextField(params.threshold.map { String($0) } ?? "1", text: $editWeightedThreshold)
            .font(Typography.mono)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.numberPad)
            #endif
            .accessibilityLabel("Weight Threshold")
            .onChange(of: editWeightedThreshold) { _, _ in
                handleWeightedThresholdChange(params: params)
            }
        FieldErrorText(error: fieldErrors["weightedThreshold"])
        Text("Current on-chain value: \(params.threshold.map { String($0) } ?? "unknown")")
            .font(Typography.metadata)
            .foregroundStyle(.tertiary)
        weightedThresholdRows(params: params)
        FieldErrorText(error: fieldErrors["weightedSummary"])
    }

    @ViewBuilder
    private func weightedThresholdRows(params: PolicyParams) -> some View {
        if signers.isEmpty {
            Text("Add signers above to configure per-signer weights.")
                .font(Typography.metadata)
                .foregroundStyle(.tertiary)
        } else {
            Text("Per-Signer Weights")
                .font(Typography.metadata)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
            ForEach(
                Array(signers.enumerated()),
                id: \.element.uniqueKey
            ) { _, signer in
                weightedThresholdRow(for: signer, params: params)
            }
        }
    }

    private func weightedThresholdRow(
        for signer: any SmartAccountSignerProtocol,
        params: PolicyParams
    ) -> some View {
        let key = SmartAccountBuilders.getSignerKey(signer: signer)
        let type = signerTypeLabel(for: signer)
        let identifier = signerDisplayIdentifier(for: signer)
        let onChain = params.signerWeights?[key]
        let binding = weightedThresholdBinding(key: key, params: params)
        let rowError = perSignerWeightErrors[key]
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Tokens.iconLabelSpacing) {
                weightedThresholdRowLabel(type: type, identifier: identifier, onChain: onChain)
                weightedThresholdRowField(
                    binding: binding,
                    accessibilityIdentifier: "\(type) \(identifier)"
                )
            }
            FieldErrorText(error: rowError)
        }
    }

    private func weightedThresholdBinding(
        key: String,
        params: PolicyParams
    ) -> Binding<String> {
        Binding<String>(
            get: { signerWeights[key] ?? "" },
            set: { newValue in
                let filtered = newValue.filter(\.isNumber)
                if filtered.isEmpty {
                    signerWeights.removeValue(forKey: key)
                } else {
                    signerWeights[key] = filtered
                }
                handleWeightedThresholdChange(params: params)
            }
        )
    }

    private func weightedThresholdRowLabel(
        type: String,
        identifier: String,
        onChain: UInt32?
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(type): \(identifier)")
                .font(Typography.metadata)
                .lineLimit(1)
                .truncationMode(.middle)
            if let onChain {
                Text("On-chain: \(onChain)")
                    .font(Typography.metadata)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weightedThresholdRowField(
        binding: Binding<String>,
        accessibilityIdentifier: String
    ) -> some View {
        TextField("Weight", text: binding)
            .font(.system(.caption, design: .monospaced))
            .frame(width: Self.weightFieldWidth)
            .multilineTextAlignment(.trailing)
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
            .accessibilityLabel("Weight for \(accessibilityIdentifier)")
            .disabled(isSubmitting)
    }

    // -------------------------------------------------------------------------
    // MARK: - Layout constants
    // -------------------------------------------------------------------------

    /// Fixed width assigned to each numeric weight input so the per-signer
    /// rows align cleanly regardless of digit count.
    fileprivate static let weightFieldWidth: CGFloat = 80
}
