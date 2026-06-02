// SorobanAllowanceFetcher.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - SorobanAllowanceFetcher
// ============================================================================

/// Production `AllowanceFetcherType` backed by `SorobanServer.simulateTransaction`.
///
/// Calls SEP-41 `allowance(from, spender)` against the supplied token contract
/// using a deterministic well-known testnet source account as the simulation
/// envelope source. The on-chain entry returns an `i128`; the result is
/// formatted as a decimal string via ``formatSmallestUnitsAsDecimal(_:)`` —
/// a token-agnostic alias used here so the formatting call reads correctly
/// at the DEMO-token call site (the allowance is expressed in the token's
/// smallest unit, not in XLM). Simulation failures are surfaced to the
/// caller as a thrown `BalanceFetchError`.
public struct SorobanAllowanceFetcher: AllowanceFetcherType, Sendable {

    private let kit: OZSmartAccountKit

    /// Creates a fetcher bound to the given kit. The kit's `sorobanServer` is
    /// reused so the same network and RPC endpoint are queried.
    public init(kit: OZSmartAccountKit) {
        self.kit = kit
    }

    public func fetchAllowance(
        tokenContract: String,
        smartAccountContractId: String,
        spenderAddress: String
    ) async -> String? {
        let stroops: Int128
        do {
            stroops = try await simulate(
                tokenContract: tokenContract,
                smartAccountContractId: smartAccountContractId,
                spenderAddress: spenderAddress
            )
        } catch {
            return nil
        }
        return formatSmallestUnitsAsDecimal(stroops)
    }

    // -------------------------------------------------------------------------
    // MARK: - Private
    // -------------------------------------------------------------------------

    private func simulate(
        tokenContract: String,
        smartAccountContractId: String,
        spenderAddress: String
    ) async throws -> Int128 {
        let transaction = try buildSimulationTransaction(
            tokenContract: tokenContract,
            smartAccountContractId: smartAccountContractId,
            spenderAddress: spenderAddress
        )
        let simResponse = await kit.sorobanServer.simulateTransaction(
            simulateTxRequest: SimulateTransactionRequest(transaction: transaction)
        )
        switch simResponse {
        case .failure(let rpcError):
            throw BalanceFetchError.simulationFailed(reason: rpcError.localizedDescription)
        case .success(let simulation):
            if let simError = simulation.error {
                throw BalanceFetchError.simulationFailed(reason: simError)
            }
            guard let firstResult = simulation.results?.first, let scVal = firstResult.value else {
                return 0
            }
            return try SACBalanceFetcher.extractI128AsInt128(from: scVal)
        }
    }

    private func buildSimulationTransaction(
        tokenContract: String,
        smartAccountContractId: String,
        spenderAddress: String
    ) throws -> Transaction {
        let trimmedSpender = spenderAddress.trimmingCharacters(in: .whitespaces)
        let spenderAddr: SCAddressXDR = try trimmedSpender.isValidEd25519PublicKey()
            ? SCAddressXDR(accountId: trimmedSpender)
            : SCAddressXDR(contractId: trimmedSpender)
        let fromAddr = try SCAddressXDR(contractId: smartAccountContractId)
        let invokeArgs = InvokeContractArgsXDR(
            contractAddress: try SCAddressXDR(contractId: tokenContract),
            functionName: "allowance",
            args: [.address(fromAddr), .address(spenderAddr)]
        )
        let invokeOp = InvokeHostFunctionOperation(
            hostFunction: HostFunctionXDR.invokeContract(invokeArgs),
            auth: []
        )
        let sourceAccount = try Account(
            accountId: SACBalanceFetcher.simulationSourceAddress,
            sequenceNumber: 0
        )
        let nowSeconds = UInt64(Date().timeIntervalSince1970)
        let timeBounds = TimeBounds(
            minTime: 0,
            maxTime: nowSeconds + UInt64(kit.config.timeoutInSeconds)
        )
        return try Transaction(
            sourceAccount: sourceAccount,
            operations: [invokeOp],
            memo: Memo.none,
            preconditions: TransactionPreconditions(timeBounds: timeBounds)
        )
    }

}
