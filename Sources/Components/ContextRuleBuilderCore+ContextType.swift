// ContextRuleBuilderCore+ContextType.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ContextTypeOption
// ============================================================================

/// Options exposed in the "Context Type" dropdown of the builder.
public enum ContextTypeOption: String, CaseIterable, Sendable {

    /// Default fallback rule that matches any operation.
    case defaultRule

    /// Rule matching invocations of a specific contract address.
    case callContract

    /// Rule matching contract deployments using a specific WASM hash.
    case createContract

    /// Rule matching contract deployments from the executable reference that an
    /// owner contract stores under a tag.
    case createContractExternalRef

    /// Human-readable label shown in the dropdown header and selected row.
    public var displayName: String {
        switch self {
        case .defaultRule:               return "Default (Any Operation)"
        case .callContract:              return "Call Contract"
        case .createContract:            return "Create Contract"
        case .createContractExternalRef: return "Create Contract from Reference"
        }
    }

    /// One-sentence sub-label shown below the option in the dropdown menu.
    public var description: String {
        switch self {
        case .defaultRule:
            return "Matches any operation that does not match a more specific rule"
        case .callContract:
            return "Matches invocations to a specific contract address"
        case .createContract:
            return "Matches contract deployments using a specific WASM hash"
        case .createContractExternalRef:
            return "Matches contract deployments from the code an owner contract stores under a tag"
        }
    }
}

// ============================================================================
// MARK: - ContextTypeFormFields
// ============================================================================

/// Values of the builder's context type section: the selected option and the
/// input fields of every option.
internal struct ContextTypeFormFields: Equatable, Sendable {

    /// The selected context type option.
    var option: ContextTypeOption

    /// Target contract of a "Call Contract" rule.
    var contractAddress: String = ""

    /// WASM hash, as hex, of a "Create Contract" rule.
    var wasmHashHex: String = ""

    /// Executable owner of a "Create Contract from Reference" rule.
    var refOwner: String = ""

    /// Executable tag of a "Create Contract from Reference" rule.
    var refTag: String = ""
}

// ============================================================================
// MARK: - ContextRuleBuilderCore: context type form section
// ============================================================================

extension ContextRuleBuilderCore {

    /// `true` while the context type picker and the owner and tag fields accept no input:
    /// during a submission, and in edit mode, because the context type of an
    /// existing rule cannot change.
    internal var contextTypeLocked: Bool {
        isSubmitting || isEditing
    }

    internal var contextTypeSection: some View {
        Section {
            contextTypePicker
            if isEditing {
                Text("Context type cannot be changed after creation.")
                    .font(Typography.metadata)
                    .foregroundStyle(.tertiary)
            }
            if contextTypeOption == .callContract {
                callContractRows
            } else if contextTypeOption == .createContract {
                createContractRow
            } else if contextTypeOption == .createContractExternalRef {
                createContractExternalRefRows
            }
        } header: {
            Text("Context Type")
                .font(Typography.sectionHeader)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var contextTypePicker: some View {
        Picker("Context Type", selection: $contextTypeOption) {
            ForEach(ContextTypeOption.allCases, id: \.rawValue) { option in
                Text(option.displayName).tag(option)
            }
        }
        .pickerStyle(.menu)
        .disabled(contextTypeLocked)
        .accessibilityLabel("Context Type")
        .onChange(of: contextTypeOption) { _, newValue in
            applyContextTypeSelection(newValue)
        }
    }

    private func applyContextTypeSelection(_ option: ContextTypeOption) {
        if option == .callContract && contractAddress.isEmpty {
            contractAddress = DemoConfig.nativeTokenContract
        }
        fieldErrors.removeValue(forKey: "contractAddress")
        fieldErrors.removeValue(forKey: "wasmHash")
        fieldErrors.removeValue(forKey: "refOwner")
    }

    // -------------------------------------------------------------------------
    // MARK: - Call contract rows
    // -------------------------------------------------------------------------

    @ViewBuilder
    private var callContractRows: some View {
        contractPicker
        TextField("CABC...", text: $contractAddress)
            .font(Typography.mono)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .accessibilityLabel("Contract Address (C-address)")
            .onChange(of: contractAddress) { _, _ in
                fieldErrors.removeValue(forKey: "contractAddress")
            }
        FieldErrorText(error: fieldErrors["contractAddress"])
    }

    private var contractPicker: some View {
        let options = contractOptions()
        return Picker("Contract", selection: contractPickerBinding(options: options)) {
            ForEach(options, id: \.address) { option in
                Text(option.label).tag(option.address)
            }
            if !options.contains(where: { $0.address == contractAddress }) && !contractAddress.isEmpty {
                Text(truncateAddress(contractAddress, chars: 8)).tag(contractAddress)
            }
        }
        .pickerStyle(.menu)
        .disabled(isSubmitting || isEditing)
        .accessibilityLabel("Contract")
    }

    private func contractPickerBinding(
        options: [(label: String, address: String)]
    ) -> Binding<String> {
        Binding<String>(
            get: {
                if contractAddress.isEmpty {
                    return options.first?.address ?? ""
                }
                return contractAddress
            },
            set: { newValue in
                contractAddress = newValue
                fieldErrors.removeValue(forKey: "contractAddress")
            }
        )
    }

    private func contractOptions() -> [(label: String, address: String)] {
        var options: [(label: String, address: String)] = [
            (label: "XLM Native Contract", address: DemoConfig.nativeTokenContract)
        ]
        if let demoToken = demoState.demoTokenContractId {
            options.append((label: "Demo Token Contract", address: demoToken))
        }
        return options
    }

    // -------------------------------------------------------------------------
    // MARK: - Create contract row
    // -------------------------------------------------------------------------

    @ViewBuilder
    private var createContractRow: some View {
        TextField("64 hex characters", text: $wasmHashHex)
            .font(Typography.mono)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .accessibilityLabel("WASM Hash (hex)")
            .onChange(of: wasmHashHex) { _, _ in
                fieldErrors.removeValue(forKey: "wasmHash")
            }
        FieldErrorText(error: fieldErrors["wasmHash"])
    }

    // -------------------------------------------------------------------------
    // MARK: - Create contract from reference rows
    // -------------------------------------------------------------------------

    @ViewBuilder
    private var createContractExternalRefRows: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Executable Owner (C...)")
                .font(Typography.metadata)
                .foregroundStyle(.secondary)
            TextField("Owner contract address", text: $refOwner)
                .font(Typography.mono)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .disabled(contextTypeLocked)
                .accessibilityLabel("Executable Owner (C...)")
                .onChange(of: refOwner) { _, _ in
                    fieldErrors.removeValue(forKey: "refOwner")
                }
            FieldErrorText(error: fieldErrors["refOwner"])
        }
        VStack(alignment: .leading, spacing: 4) {
            Text("Executable Tag")
                .font(Typography.metadata)
                .foregroundStyle(.secondary)
            TextField("Tag the owner stores the code under", text: $refTag)
                .font(Typography.mono)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .disabled(contextTypeLocked)
                .accessibilityLabel("Executable Tag")
        }
        Text("The owner contract can change the code this reference resolves to.")
            .font(Typography.metadata)
            .foregroundStyle(.tertiary)
    }
}
