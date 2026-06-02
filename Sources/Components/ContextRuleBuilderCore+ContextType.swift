// ContextRuleBuilderCore+ContextType.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ContextRuleBuilderCore: context type form section
// ============================================================================

extension ContextRuleBuilderCore {

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
        .disabled(isSubmitting || isEditing)
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
}
