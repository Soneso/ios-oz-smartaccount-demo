// SACBalanceFetcher.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - SACBalanceFetcher
// ============================================================================

/// Invokes `balance(id:)` on a Stellar Asset Contract (SAC) token contract
/// and returns the result as an `Int128` stroop amount.
///
/// SAC token contracts expose the SEP-41 token interface. The `balance` function
/// accepts a `contract` address argument and returns the balance as an `i128`
/// signed 128-bit integer in the token's smallest unit (stroops for native XLM,
/// indivisible units for DEMO test tokens). The native Swift `Int128` type
/// holds the full signed 128-bit range losslessly, so no overflow sentinel or
/// narrowing conversion is needed.
///
/// Simulation only — no on-chain transaction is submitted. The call uses a
/// fixed well-known testnet source account (SDF faucet address) as the
/// simulation envelope source; the RPC does not validate on-chain sequence
/// numbers or balances for simulation calls.
///
/// Both `MainScreenFlow.refreshBalances()` and post-creation balance refresh in
/// `WalletCreationFlow` route through this fetcher so the encoding and decoding
/// logic is maintained in exactly one place.
public enum SACBalanceFetcher {

    // -------------------------------------------------------------------------
    // MARK: - Constants
    // -------------------------------------------------------------------------

    /// SDF testnet faucet account used as the simulation envelope source.
    ///
    /// This is a canonical 56-char G-address whose on-chain sequence number and
    /// balance are irrelevant for simulation — the RPC only validates host-function
    /// logic during simulation, not source-account state.
    static let simulationSourceAddress = "GAIH3ULLFQ4DGSECF2AR555KZ4KNDGEKN4AFI4SU2M7B43MGK3QJZNSR"

    // -------------------------------------------------------------------------
    // MARK: - Public API
    // -------------------------------------------------------------------------

    /// Fetches the SAC `balance(id: <account>)` for the given contract and account.
    ///
    /// Simulation is performed via the kit's `SorobanServer`. The time bounds on
    /// the simulation envelope use `kit.config.timeoutInSeconds` so the envelope
    /// remains valid for the same window used by all other kit operations.
    ///
    /// - Parameters:
    ///   - contract: SAC token contract address (C-strkey).
    ///   - account: Smart account contract address (C-strkey) whose balance to read.
    ///   - kit: Active `OZSmartAccountKit` providing the Soroban RPC server and config.
    /// - Returns: Balance as `Int128` stroops, preserving the full signed 128-bit
    ///   on-chain range without truncation or sentinel substitution. Pair with
    ///   ``formatStroopsAsXlm(_:)-(Int128)`` to render the value as a display string.
    /// - Throws:
    ///   - `BalanceFetchError.simulationFailed` when the RPC returns an error response.
    ///   - `BalanceFetchError.unexpectedReturnType` when the result cannot be decoded
    ///     as an `i128` SCVal.
    ///   - `StellarSDKError` variants from address/account construction on malformed inputs.
    public static func fetchBalance(
        contract: String,
        account: String,
        kit: OZSmartAccountKit
    ) async throws -> Int128 {
        let transaction = try buildBalanceTransaction(
            contractAddress: contract,
            accountAddress: account,
            kit: kit
        )
        let simulation = try await simulate(transaction: transaction, kit: kit)
        return try decodeI128Result(simulation)
    }

    // -------------------------------------------------------------------------
    // MARK: - Private: transaction construction
    // -------------------------------------------------------------------------

    /// Constructs an `InvokeHostFunction` transaction that calls `balance(id:)` on
    /// a SAC token contract.
    ///
    /// The `id` argument is a `contract`-variant `Address` SCVal wrapping the
    /// smart account's C-strkey. The time bounds are derived from
    /// `kit.config.timeoutInSeconds` to match the timeout window used by the kit's
    /// own transaction submissions.
    private static func buildBalanceTransaction(
        contractAddress: String,
        accountAddress: String,
        kit: OZSmartAccountKit
    ) throws -> Transaction {
        let accountAddrXDR = try SCAddressXDR(contractId: accountAddress)
        let addressArg = SCValXDR.address(accountAddrXDR)

        let invokeArgs = InvokeContractArgsXDR(
            contractAddress: try SCAddressXDR(contractId: contractAddress),
            functionName: "balance",
            args: [addressArg]
        )
        let hostFunction = HostFunctionXDR.invokeContract(invokeArgs)
        let invokeOp = InvokeHostFunctionOperation(hostFunction: hostFunction, auth: [])

        let sourceAccount = try Account(
            accountId: simulationSourceAddress,
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

    // -------------------------------------------------------------------------
    // MARK: - Private: simulation
    // -------------------------------------------------------------------------

    /// Sends the transaction to the Soroban RPC simulation endpoint and returns
    /// the unwrapped success result.
    ///
    /// - Throws: `BalanceFetchError.simulationFailed` on any RPC or contract error.
    private static func simulate(
        transaction: Transaction,
        kit: OZSmartAccountKit
    ) async throws -> SimulateTransactionResponse {
        let simRequest = SimulateTransactionRequest(transaction: transaction)
        let simResponse = await kit.sorobanServer.simulateTransaction(
            simulateTxRequest: simRequest
        )
        switch simResponse {
        case .failure(let rpcError):
            throw BalanceFetchError.simulationFailed(reason: rpcError.localizedDescription)
        case .success(let simulation):
            if let simError = simulation.error {
                throw BalanceFetchError.simulationFailed(reason: simError)
            }
            return simulation
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Private: i128 decoding
    // -------------------------------------------------------------------------

    /// Extracts an `Int128` stroop amount from the first result of a SAC
    /// `balance` simulation response.
    ///
    /// A missing or void first result is treated as zero balance (some
    /// implementations return void for uninitialised accounts).
    ///
    /// - Throws: `BalanceFetchError.unexpectedReturnType` when the result is not
    ///   an `i128` SCVal.
    private static func decodeI128Result(_ simulation: SimulateTransactionResponse) throws -> Int128 {
        guard let firstResult = simulation.results?.first else {
            return 0
        }
        guard let scVal = firstResult.value else {
            throw BalanceFetchError.unexpectedReturnType(
                detail: "Could not decode SCValXDR from simulation result"
            )
        }
        return try extractI128AsInt128(from: scVal)
    }

    /// Decodes an `i128` SCVal into an `Int128` losslessly.
    ///
    /// Reconstructs the signed 128-bit value as `(hi << 64) + lo`, preserving
    /// the full i128 range exactly. `Int128(Int64)` sign-extends so a negative
    /// `hi` produces the expected negative result; `Int128(UInt64)`
    /// zero-extends so `lo` contributes only to the low 64 bits.
    ///
    /// - Throws: `BalanceFetchError.unexpectedReturnType` when `scVal` is not
    ///   an `i128` SCVal.
    static func extractI128AsInt128(from scVal: SCValXDR) throws -> Int128 {
        switch scVal {
        case .i128(let i128Parts):
            return (Int128(i128Parts.hi) << 64) + Int128(i128Parts.lo)
        default:
            throw BalanceFetchError.unexpectedReturnType(
                detail: "Expected i128 SCVal, got \(scVal)"
            )
        }
    }
}
