// PolicyManagementSection+Weighted.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - SignerWeightPair
// ============================================================================

/// Validated weight entry built by the weighted-threshold form.
internal struct SignerWeightPair {

    /// The signer that contributes `weight` votes.
    let signer: any SmartAccountSignerProtocol

    /// Per-signer weight in the weighted-threshold map.
    let weight: UInt32

    /// `SmartAccountBuilders.getSignerKey(signer:)` identity for the signer.
    let signerKey: String
}

/// Outcome of validating the per-signer weight rows.
internal enum SignerWeightCollection {
    case success([SignerWeightPair])
    case failure(String)
}

// ============================================================================
// MARK: - PolicyManagementSection: Weighted-threshold form
// ============================================================================

extension PolicyManagementSection {

    @ViewBuilder
    internal func weightedThresholdForm(info: PolicyInfo) -> some View {
        TextField("e.g., 100", text: $weightedThresholdValue)
            .font(Typography.mono)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.numberPad)
            #endif
            .accessibilityLabel("Weight Threshold")
            .onChange(of: weightedThresholdValue) { _, _ in
                fieldErrors.removeValue(forKey: "weightedThreshold")
            }
        FieldErrorText(error: fieldErrors["weightedThreshold"])
        Text("Minimum total weight required for authorization")
            .font(Typography.metadata)
            .foregroundStyle(.tertiary)
        weightRowsContent
        FieldErrorText(error: fieldErrors["signerWeights"])
        addWeightedButton(info: info)
    }

    @ViewBuilder
    private var weightRowsContent: some View {
        if signers.isEmpty {
            Text("Add signers above to configure per-signer weights.")
                .font(Typography.metadata)
                .foregroundStyle(.tertiary)
        } else {
            Text("Per-Signer Weights")
                .font(Typography.metadata)
                .fontWeight(.bold)
            ForEach(
                Array(signers.enumerated()),
                id: \.element.uniqueKey
            ) { _, signer in
                weightRow(for: signer)
            }
        }
    }

    private func addWeightedButton(info: PolicyInfo) -> some View {
        Button {
            addWeightedThreshold(info: info)
        } label: {
            Text("Add Weighted Threshold Policy")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Self.addButtonVerticalPadding)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: Self.addButtonRadius))
        }
        .buttonStyle(.plain)
        .disabled(weightedDisabled)
        .accessibilityLabel("Add Weighted Threshold Policy")
    }

    private var weightedDisabled: Bool {
        weightedThresholdValue.trimmingCharacters(in: .whitespaces).isEmpty || signers.isEmpty
    }

    private func weightRow(for signer: any SmartAccountSignerProtocol) -> some View {
        let key = SmartAccountBuilders.getSignerKey(signer: signer)
        let type = signerTypeLabel(for: signer)
        let identifier = signerDisplayIdentifier(for: signer)
        let binding = Binding<String>(
            get: { signerWeights[key] ?? "" },
            set: { newValue in
                let filtered = newValue.filter(\.isNumber)
                if filtered.isEmpty {
                    signerWeights.removeValue(forKey: key)
                } else {
                    signerWeights[key] = filtered
                }
                fieldErrors.removeValue(forKey: "signerWeights")
            }
        )
        return HStack(spacing: Tokens.iconLabelSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(type): \(identifier)")
                    .font(Typography.metadata)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            weightInput(binding: binding, type: type, identifier: identifier)
        }
    }

    private func weightInput(
        binding: Binding<String>,
        type: String,
        identifier: String
    ) -> some View {
        TextField("Weight", text: binding)
            .font(.system(.caption, design: .monospaced))
            .frame(width: Self.weightFieldWidth)
            .multilineTextAlignment(.trailing)
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
            .accessibilityLabel("Weight for \(type) \(identifier)")
    }

    /// Fixed width assigned to each numeric weight input so the per-signer
    /// rows align cleanly regardless of digit count.
    fileprivate static var weightFieldWidth: CGFloat { 80 }

    internal func addWeightedThreshold(info: PolicyInfo) {
        let trimmed = weightedThresholdValue.trimmingCharacters(in: .whitespaces)
        guard let threshold = UInt32(trimmed), threshold >= 1 else {
            fieldErrors["weightedThreshold"] = "Must be at least 1"
            return
        }
        if signers.isEmpty {
            fieldErrors["signerWeights"] = "Add signers before configuring weights"
            return
        }
        switch collectSignerWeights() {
        case .failure(let message):
            fieldErrors["signerWeights"] = message
        case .success(let pairs):
            applyWeightedThreshold(info: info, threshold: threshold, pairs: pairs)
        }
    }

    private func collectSignerWeights() -> SignerWeightCollection {
        var pairs: [SignerWeightPair] = []
        for signer in signers {
            let key = SmartAccountBuilders.getSignerKey(signer: signer)
            guard let raw = signerWeights[key]?.trimmingCharacters(in: .whitespaces),
                  let weight = UInt32(raw), weight >= 1 else {
                return .failure("All signers must have a weight >= 1")
            }
            pairs.append(SignerWeightPair(signer: signer, weight: weight, signerKey: key))
        }
        return .success(pairs)
    }

    private func applyWeightedThreshold(
        info: PolicyInfo,
        threshold: UInt32,
        pairs: [SignerWeightPair]
    ) {
        // Accumulate in `UInt64` so the weight sum cannot overflow `UInt32`.
        let total = pairs.reduce(UInt64(0)) { $0 + UInt64($1.weight) }
        if total < UInt64(threshold) {
            fieldErrors["signerWeights"] =
                "Total weight (\(total)) must be >= threshold (\(threshold))"
            return
        }
        let entries = pairs.map { PolicyWeightedEntry(signer: $0.signer, weight: $0.weight) }
        let spec = PolicyInstallSpec.weightedThreshold(entries: entries, threshold: threshold)
        let label = "Weighted: threshold=\(threshold)"
        registerWeightedThresholdPolicy(info: info, label: label, spec: spec)
        weightedThresholdValue = ""
        signerWeights = [:]
        selectedPolicyType = nil
        activityLog.info(
            "Added weighted threshold policy (threshold=\(threshold))"
        )
    }

    private func registerWeightedThresholdPolicy(
        info: PolicyInfo,
        label: String,
        spec: PolicyInstallSpec
    ) {
        if isEditing {
            let entry = EditPolicyEntry(
                info: info,
                label: label,
                address: info.address,
                installSpec: spec,
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
                    installSpec: spec
                )
            )
        }
    }
}
