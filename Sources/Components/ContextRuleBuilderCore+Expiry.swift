// ContextRuleBuilderCore+Expiry.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ContextRuleBuilderCore: expiry section
// ============================================================================

extension ContextRuleBuilderCore {

    /// Sentinel ledger string used by the expiry dropdown when the user picks
    /// `Custom`. The submission pipeline reads `expiryLedger` directly, so any
    /// numeric string fed into the Custom field overwrites this sentinel as
    /// soon as the user types — at submit time the sentinel is treated as
    /// "not yet entered" and surfaces the standard validation error.
    internal static var customExpirySentinel: String { "custom" }

    /// Maximum number of bytes allowed for a context rule name.
    ///
    /// Enforced on-chain by the OpenZeppelin smart-account contract via
    /// `SmartAccountError::NameTooLong` (error code 3015). Hardcoded here
    /// because the SDK's `OZConstants` does not expose this value;
    /// without client-side validation the user would only learn of the
    /// rejection after completing the passkey ceremony and triggering a
    /// simulation, which is poor UX.
    internal static var maxRuleNameBytes: Int { 20 }

    internal var expirySection: some View {
        Section {
            Toggle(isOn: $hasExpiry) {
                Text("Set Expiry")
                    .font(Typography.body)
            }
            .onChange(of: hasExpiry) { _, newValue in
                if !newValue {
                    expiryLedger = ""
                    fieldErrors.removeValue(forKey: "expiryLedger")
                }
                if isEditing {
                    expiryModified = true
                }
            }
            if hasExpiry {
                expiryDurationPicker
                if isCustomExpirySelected {
                    customExpiryField
                }
                FieldErrorText(error: fieldErrors["expiryLedger"])
                Text("The rule will expire after the selected duration from the current ledger.")
                    .font(Typography.metadata)
                    .foregroundStyle(.tertiary)
                if isEditing, let current = existingExpiryLedger {
                    Text(
                        "Current on-chain expiry: ledger \(current). " +
                        "Select a duration above to replace it."
                    )
                    .font(Typography.metadata)
                    .foregroundStyle(.tertiary)
                }
            }
        } header: {
            Text("Expiry")
                .font(Typography.sectionHeader)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var isCustomExpirySelected: Bool {
        guard hasExpiry else { return false }
        if expiryLedger == Self.customExpirySentinel { return true }
        if expiryLedger.isEmpty { return false }
        let presets = expiryOptions().map { String($0.ledgers) }
        return !presets.contains(expiryLedger)
    }

    private var expiryDurationPicker: some View {
        let options = expiryOptions()
        return Picker("Time from now", selection: expirySelectionBinding(options: options)) {
            Text("Select duration...").tag("")
            ForEach(options, id: \.ledgers) { option in
                Text(option.label).tag(String(option.ledgers))
            }
            Text("Custom").tag(Self.customExpirySentinel)
        }
        .pickerStyle(.menu)
        .disabled(isSubmitting)
        .accessibilityLabel("Time from now")
    }

    private func expirySelectionBinding(
        options: [(label: String, ledgers: UInt32)]
    ) -> Binding<String> {
        Binding<String>(
            get: {
                if expiryLedger.isEmpty { return "" }
                if expiryLedger == Self.customExpirySentinel { return Self.customExpirySentinel }
                if options.contains(where: { String($0.ledgers) == expiryLedger }) {
                    return expiryLedger
                }
                return Self.customExpirySentinel
            },
            set: { newValue in
                expiryLedger = newValue
                fieldErrors.removeValue(forKey: "expiryLedger")
                if isEditing { expiryModified = true }
            }
        )
    }

    @ViewBuilder
    private var customExpiryField: some View {
        // Bind the numeric input through a derived Binding so the sentinel value
        // ("custom") is hidden from the user as an empty field while the user
        // enters their own number; typing replaces the sentinel with the typed
        // digits.
        let binding = Binding<String>(
            get: {
                expiryLedger == Self.customExpirySentinel ? "" : expiryLedger
            },
            set: { newValue in
                let filtered = newValue.filter(\.isNumber)
                if filtered.isEmpty {
                    expiryLedger = Self.customExpirySentinel
                } else {
                    expiryLedger = filtered
                }
                fieldErrors.removeValue(forKey: "expiryLedger")
                if isEditing { expiryModified = true }
            }
        )
        TextField("e.g., 100000", text: binding)
            .font(Typography.mono)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.numberPad)
            #endif
            .accessibilityLabel("Custom Ledger Offset")
    }

    private func expiryOptions() -> [(label: String, ledgers: UInt32)] {
        let perHour = StellarProtocol.ledgersPerHour
        let perDay = StellarProtocol.ledgersPerDay
        return [
            ("5 min", UInt32(perHour / 12)),
            ("30 min", UInt32(perHour / 2)),
            ("1 hour", UInt32(perHour)),
            ("1 day", UInt32(perDay)),
            ("10 days", UInt32(perDay * 10))
        ]
    }
}
