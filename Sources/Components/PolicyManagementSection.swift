// PolicyManagementSection.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - StagedPolicy
// ============================================================================

/// A policy staged on the builder form, pre-encoded as `ScVal` at the moment
/// the user added it.
public struct StagedPolicy: Identifiable, Sendable {

    /// Stable id derived from the policy address. Each policy address is
    /// allowed at most once per rule, so the address suffices as identity.
    public var id: String { address }

    /// Descriptor for the policy contract.
    public let info: PolicyInfo

    /// Human-readable label shown in the staged-policies list (e.g.
    /// `"Threshold: 2-of-N"`).
    public let label: String

    /// Policy contract address (`C…`).
    public let address: String

    /// Install parameters encoded as `ScVal`.
    public let scVal: ScVal

    public init(info: PolicyInfo, label: String, address: String, scVal: ScVal) {
        self.info = info
        self.label = label
        self.address = address
        self.scVal = scVal
    }
}

// ============================================================================
// MARK: - PolicyManagementSection
// ============================================================================

/// Form sub-section that owns the "Policies" portion of the context rule
/// builder. Produces grouped `Section` blocks suitable to be placed inside a
/// parent `Form`. All staged state is owned by the parent
/// (`ContextRuleBuilderCore`).
///
/// Edit mode (`isEditing == true`) renders the on-chain / modified badges on
/// original entries and an inline `EditPolicyParamsForm` for each known
/// original policy. The parent supplies the parallel `policyEntries` list and
/// receives mutations through `onAddEntry`, `onRemoveEntry`, `onUpdateEntry`.
public struct PolicyManagementSection: View {

    @EnvironmentObject internal var activityLog: ActivityLogState

    @Binding internal var policies: [StagedPolicy]
    @Binding internal var signerWeights: [String: String]
    @Binding internal var fieldErrors: [String: String]

    internal let signers: [any SmartAccountSignerProtocol]
    internal let isSubmitting: Bool
    internal let isEditing: Bool
    internal let policyEntries: [EditPolicyEntry]
    internal let onAddEntry: ((EditPolicyEntry) -> Void)?
    internal let onRemoveEntry: ((Int) -> Void)?
    internal let onUpdateEntry: ((Int, EditPolicyEntry) -> Void)?

    @State internal var selectedPolicyType: PolicyInfo?
    @State internal var thresholdValue: String = ""
    @State internal var spendingLimitAmount: String = ""
    @State internal var spendingLimitPeriodDays: String = ""
    @State internal var weightedThresholdValue: String = ""

    public init(
        policies: Binding<[StagedPolicy]>,
        signerWeights: Binding<[String: String]>,
        fieldErrors: Binding<[String: String]>,
        signers: [any SmartAccountSignerProtocol],
        isSubmitting: Bool,
        isEditing: Bool = false,
        policyEntries: [EditPolicyEntry] = [],
        onAddEntry: ((EditPolicyEntry) -> Void)? = nil,
        onRemoveEntry: ((Int) -> Void)? = nil,
        onUpdateEntry: ((Int, EditPolicyEntry) -> Void)? = nil
    ) {
        self._policies = policies
        self._signerWeights = signerWeights
        self._fieldErrors = fieldErrors
        self.signers = signers
        self.isSubmitting = isSubmitting
        self.isEditing = isEditing
        self.policyEntries = policyEntries
        self.onAddEntry = onAddEntry
        self.onRemoveEntry = onRemoveEntry
        self.onUpdateEntry = onUpdateEntry
    }

    private var currentPolicyCount: Int {
        isEditing ? policyEntries.count : policies.count
    }

    public var body: some View {
        Group {
            currentPoliciesSection
            if !isSubmitting && currentPolicyCount < OZSmartAccountConstants.maxPolicies {
                addPolicySection
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Current policies section
    // -------------------------------------------------------------------------

    @ViewBuilder
    internal var currentPoliciesSection: some View {
        Section {
            currentPoliciesBody
        } header: {
            Text("Policies")
                .font(Typography.sectionHeader)
                .accessibilityAddTraits(.isHeader)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    "Attach policies to constrain how operations are authorized. " +
                    "Policies are optional. Maximum \(OZSmartAccountConstants.maxPolicies) per rule."
                )
                if isEditing {
                    Text("Each policy change requires a separate passkey authentication.")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .font(Typography.metadata)
            .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var currentPoliciesBody: some View {
        if isEditing {
            editPoliciesContent
        } else if policies.isEmpty {
            emptyPoliciesRow
        } else {
            policiesListContent
        }
    }

    @ViewBuilder
    private var editPoliciesContent: some View {
        if policyEntries.isEmpty {
            emptyPoliciesRow
        } else {
            ForEach(
                Array(policyEntries.enumerated()),
                id: \.element.address
            ) { index, entry in
                editPolicyRow(entry: entry, index: index)
            }
            Text(policyCountLabel(policyEntries.count) + " attached")
                .font(Typography.metadata)
                .foregroundStyle(.tertiary)
        }
    }

    private func editPolicyRow(entry: EditPolicyEntry, index: Int) -> some View {
        let chipColor = policyTypeColor(entry.info?.type ?? "default")
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                editPolicyBadges(entry: entry, chipColor: chipColor)
                Text(entry.label)
                    .font(Typography.metadata)
                    .lineLimit(2)
                Spacer()
                editPolicyRemoveButton(entry: entry, index: index)
            }
            Text(truncateAddress(entry.address, chars: 8))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            if entry.isOriginal, entry.originalParams != nil {
                EditPolicyParamsForm(
                    entry: entry,
                    signers: signers,
                    signerWeights: $signerWeights,
                    isSubmitting: isSubmitting
                ) { updated in
                    onUpdateEntry?(index, updated)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func editPolicyBadges(entry: EditPolicyEntry, chipColor: Color) -> some View {
        let typeName = entry.info?.name ?? "Policy"
        Pill(
            typeName,
            background: chipColor.opacity(Self.typeBadgeBackgroundAlpha),
            foreground: chipColor,
            textStyle: .caption2.weight(.semibold)
        )
        if entry.isOriginal {
            editPolicyTagBadge(
                text: "(on-chain)",
                background: Color.successContainer,
                foreground: Color.onSuccessContainer,
                accessibilityLabel: "On-chain"
            )
        }
        if entry.modified {
            editPolicyTagBadge(
                text: "(modified)",
                background: Color.warningContainer,
                foreground: Color.onWarningContainer,
                accessibilityLabel: "Modified"
            )
        }
    }

    private func editPolicyTagBadge(
        text: String,
        background: Color,
        foreground: Color,
        accessibilityLabel: String
    ) -> some View {
        Pill(
            text,
            background: background,
            foreground: foreground,
            textStyle: .caption2.weight(.semibold)
        )
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private func editPolicyRemoveButton(entry: EditPolicyEntry, index: Int) -> some View {
        if !isSubmitting {
            let typeName = entry.info?.name ?? "Policy"
            Button {
                onRemoveEntry?(index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.semanticError)
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(typeName) policy")
        }
    }

    private var emptyPoliciesRow: some View {
        ContentUnavailableView(
            "No Policies Attached",
            systemImage: "list.bullet.clipboard",
            description: Text("Policies are optional. Add one below if required for this rule.")
        )
        .symbolRenderingMode(.hierarchical)
    }

    private var policiesListContent: some View {
        Group {
            ForEach(policies, id: \.id) { policy in
                policyRow(policy: policy)
            }
            Text(policyCountLabel(policies.count) + " attached")
                .font(Typography.metadata)
                .foregroundStyle(.tertiary)
        }
    }

    private func policyRow(policy: StagedPolicy) -> some View {
        let chipColor = policyTypeColor(policy.info.type)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                policyTypeBadge(policy: policy, color: chipColor)
                Text(policy.label)
                    .font(Typography.metadata)
                    .lineLimit(2)
                    .accessibilityLabel("\(policy.info.name): \(policy.label)")
                Spacer()
                policyRemoveButton(policy: policy)
            }
            Text(truncateAddress(policy.address, chars: 8))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
    }

    private func policyTypeBadge(policy: StagedPolicy, color: Color) -> some View {
        Pill(
            policy.info.name,
            background: color.opacity(Self.typeBadgeBackgroundAlpha),
            foreground: color,
            textStyle: .caption2.weight(.semibold)
        )
    }

    @ViewBuilder
    private func policyRemoveButton(policy: StagedPolicy) -> some View {
        if !isSubmitting {
            Button {
                policies.removeAll(where: { $0.id == policy.id })
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.semanticError)
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(policy.info.name) policy")
        }
    }

    internal func policyTypeColor(_ type: String) -> Color {
        switch type {
        case "threshold":          return Color.contextRuleExpiryBadgeForeground
        case "spending_limit":     return Color.contextRuleSignerBadgeForeground
        case "weighted_threshold": return Self.weightedThresholdAccent
        default:                   return Self.defaultPolicyAccent
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Layout constants
    // -------------------------------------------------------------------------

    /// Alpha applied to a policy-type accent color to derive the soft pill
    /// background tint while keeping the same hue for the foreground glyph.
    fileprivate static let typeBadgeBackgroundAlpha: Double = 0.18

    /// Accent color identifying weighted-threshold policies in the staged list
    /// and the per-type add-policy form.
    private static let weightedThresholdAccent = Color(
        red: 0x6A / 255.0, green: 0x1B / 255.0, blue: 0x9A / 255.0
    )

    /// Fallback accent for any policy type the demo has not classified.
    private static let defaultPolicyAccent = Color(
        red: 0x60 / 255.0, green: 0x7D / 255.0, blue: 0x8B / 255.0
    )
}
