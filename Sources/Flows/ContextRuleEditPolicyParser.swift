// ContextRuleEditPolicyParser.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - ContextRuleFlow: policy storage reading
// ============================================================================

extension ContextRuleFlow {

    /// Builds the storage key for an OZ policy contract:
    /// `Vec([Symbol("AccountContext"), Address(smartAccount), U32(ruleId)])`.
    private func policyStorageKey(
        smartAccountContractId: String,
        ruleId: UInt32
    ) throws -> SCValXDR {
        return .vec([
            .symbol("AccountContext"),
            .address(try SCAddressXDR(contractId: smartAccountContractId)),
            .u32(ruleId)
        ])
    }

    /// Fetches the raw stored `SCValXDR` for a policy's per-account/per-rule
    /// entry, or `nil` on any read failure.
    internal func fetchPolicyStorageValue(
        rpcUrl: String,
        smartAccountContractId: String,
        policyAddress: String,
        ruleId: UInt32
    ) async -> SCValXDR? {
        let key: SCValXDR
        do {
            key = try policyStorageKey(
                smartAccountContractId: smartAccountContractId,
                ruleId: ruleId
            )
        } catch {
            return nil
        }
        let server = SorobanServer(endpoint: rpcUrl)
        let response = await server.getContractData(
            contractId: policyAddress,
            key: key,
            durability: .persistent
        )
        switch response {
        case .success(let entry):
            guard let data = entry.valueXdr,
                  case .contractData(let contractData) = data else {
                return nil
            }
            return contractData.val
        case .failure:
            return nil
        }
    }
}

// ============================================================================
// MARK: - ContextRuleFlow: policy parameter parsers
// ============================================================================

extension ContextRuleFlow {

    /// Decodes a bare `U32` threshold value.
    internal func parseThresholdParams(_ scVal: SCValXDR) -> PolicyParams? {
        guard case .u32(let threshold) = scVal else { return nil }
        return PolicyParams(
            type: "threshold",
            threshold: threshold,
            spendingLimit: nil,
            periodDays: nil,
            signerWeights: nil
        )
    }

    /// Decodes a spending-limit struct map.
    internal func parseSpendingLimitParams(_ scVal: SCValXDR) -> PolicyParams? {
        guard case .map(let entries) = scVal, let entries else { return nil }
        var baseUnits: Int64?
        var periodLedgers: UInt32?
        for entry in entries {
            applySpendingLimitField(entry: entry, baseUnits: &baseUnits, periodLedgers: &periodLedgers)
        }
        guard let baseUnits, let periodLedgers else { return nil }
        let amountString = formatBaseUnitsAsDecimal(baseUnits)
        let days = max(1, Int(periodLedgers) / StellarProtocolConstants.ledgersPerDay)
        return PolicyParams(
            type: "spending_limit",
            threshold: nil,
            spendingLimit: amountString,
            periodDays: days,
            signerWeights: nil
        )
    }

    private func applySpendingLimitField(
        entry: SCMapEntryXDR,
        baseUnits: inout Int64?,
        periodLedgers: inout UInt32?
    ) {
        guard case .symbol(let key) = entry.key else { return }
        switch key {
        case "spending_limit":
            if case .i128(let parts) = entry.val {
                // OZ contract stores positive amounts only. The full i128 is
                // not representable as Int64, so reject any value whose high
                // word is non-zero or whose low word exceeds Int64.max. The
                // inline editor is omitted for these out-of-range values; the
                // user must remove and re-add the policy to replace it.
                let maxLo = UInt64(Int64.max)
                if parts.hi == 0 && parts.lo <= maxLo {
                    baseUnits = Int64(parts.lo)
                }
            }
        case "period_ledgers":
            if case .u32(let value) = entry.val {
                periodLedgers = value
            }
        default:
            break
        }
    }

    /// Decodes a weighted-threshold struct map.
    internal func parseWeightedThresholdParams(_ scVal: SCValXDR) -> PolicyParams? {
        guard case .map(let entries) = scVal, let entries else { return nil }
        var threshold: UInt32?
        var weights: [String: UInt32]?
        for entry in entries {
            applyWeightedThresholdField(entry: entry, threshold: &threshold, weights: &weights)
        }
        guard let threshold else { return nil }
        return PolicyParams(
            type: "weighted_threshold",
            threshold: threshold,
            spendingLimit: nil,
            periodDays: nil,
            signerWeights: weights
        )
    }

    private func applyWeightedThresholdField(
        entry: SCMapEntryXDR,
        threshold: inout UInt32?,
        weights: inout [String: UInt32]?
    ) {
        guard case .symbol(let key) = entry.key else { return }
        switch key {
        case "threshold":
            if case .u32(let value) = entry.val {
                threshold = value
            }
        case "signer_weights":
            if case .map(let inner) = entry.val, let inner {
                weights = decodeSignerWeights(entries: inner)
            }
        default:
            break
        }
    }

    /// Converts a weighted-threshold inner map (signer SCVal → U32 weight) into
    /// a `[String: UInt32]` keyed by the same identity string the staged-signer
    /// flow uses (`OZSmartAccountBuilders.getSignerKey(...)`). Unknown signer
    /// shapes are dropped.
    private func decodeSignerWeights(entries: [SCMapEntryXDR]) -> [String: UInt32] {
        var result: [String: UInt32] = [:]
        for entry in entries {
            decodeSignerWeightEntry(entry: entry, into: &result)
        }
        return result
    }

    private func decodeSignerWeightEntry(
        entry: SCMapEntryXDR,
        into result: inout [String: UInt32]
    ) {
        guard case .u32(let weight) = entry.val,
              case .vec(let vec) = entry.key,
              let vec,
              vec.count >= 2,
              case .symbol(let kind) = vec[0] else {
            return
        }
        switch kind {
        case "Delegated":
            if let key = decodeDelegatedSignerKey(from: vec) {
                result[key] = weight
            }
        case "External":
            if let key = decodeExternalSignerKey(from: vec) {
                result[key] = weight
            }
        default:
            return
        }
    }

    private func decodeDelegatedSignerKey(from vec: [SCValXDR]) -> String? {
        guard case .address(let address) = vec[1] else { return nil }
        let addressStr: String
        if let contractId = address.contractId,
           let strkey = try? contractId.encodeContractIdHex() {
            addressStr = strkey
        } else if let accountId = address.accountId {
            addressStr = accountId
        } else {
            return nil
        }
        guard let signer = try? OZDelegatedSigner(address: addressStr) else { return nil }
        return OZSmartAccountBuilders.getSignerKey(signer: signer)
    }

    private func decodeExternalSignerKey(from vec: [SCValXDR]) -> String? {
        guard vec.count >= 3,
              case .address(let verifierAddress) = vec[1],
              case .bytes(let keyData) = vec[2],
              let verifierContract = verifierAddress.contractId,
              let verifierStr = try? verifierContract.encodeContractIdHex() else {
            return nil
        }
        guard let signer = try? OZExternalSigner(
            verifierAddress: verifierStr,
            keyData: keyData
        ) else {
            return nil
        }
        return OZSmartAccountBuilders.getSignerKey(signer: signer)
    }
}
