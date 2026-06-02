// ContextRuleBuilderCore+Validation.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ContextRuleBuilderCore: form validation
// ============================================================================

extension ContextRuleBuilderCore {

    /// Collects every field-level error reachable from the current form
    /// state. An empty result means the form is ready to submit.
    internal func validateForm() -> [String: String] {
        var errors: [String: String] = [:]
        let trimmedName = ruleName.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty {
            errors["ruleName"] = "Rule name is required"
        } else if trimmedName.utf8.count > ContextRuleBuilderCore.maxRuleNameBytes {
            errors["ruleName"] =
                "Rule name must be \(ContextRuleBuilderCore.maxRuleNameBytes) bytes or less"
        }
        if let contextError = validateContextType() {
            errors.merge(contextError) { lhs, _ in lhs }
        }
        if let expiryError = validateExpiry() {
            errors["expiryLedger"] = expiryError
        }
        if signers.isEmpty {
            errors["signers"] = "At least one signer is required"
        }
        return errors
    }

    private func validateContextType() -> [String: String]? {
        switch contextTypeOption {
        case .defaultRule:
            return nil
        case .callContract:
            let address = contractAddress.trimmingCharacters(in: .whitespaces)
            if address.isEmpty || !isValidContractAddress(address) {
                return ["contractAddress": "A contract must be selected"]
            }
            return nil
        case .createContract:
            return validateWasmHash()
        }
    }

    private func validateWasmHash() -> [String: String]? {
        let hex = wasmHashHex.trimmingCharacters(in: .whitespaces).lowercased()
        if hex.isEmpty {
            return ["wasmHash": "WASM hash is required"]
        }
        if hex.count != 64 {
            return ["wasmHash": "Must be 64 hex characters (32 bytes), got \(hex.count)"]
        }
        if !hex.allSatisfy(\.isHexDigit) {
            return ["wasmHash": "Invalid hex characters"]
        }
        return nil
    }

    private func validateExpiry() -> String? {
        guard hasExpiry else { return nil }
        let trimmed = expiryLedger.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == ContextRuleBuilderCore.customExpirySentinel {
            return "Please select an expiry duration"
        }
        guard let value = UInt32(trimmed) else {
            return "Must be a positive integer"
        }
        if value == 0 {
            return "Must be a positive integer"
        }
        return nil
    }
}
