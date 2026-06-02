// DemoTokenService.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// MARK: - DemoTokenServiceType

/// Abstraction over `DemoTokenService` used by the demo flows.
///
/// Exists as a protocol so unit tests can inject a mock without running real
/// network operations. The production implementation is `DemoTokenService`
/// itself via the conformance declared below.
public protocol DemoTokenServiceType: Sendable {

    /// Ensures the DEMO token contract is deployed and mints DEMO tokens to the
    /// recipient contract.
    func ensureTokenAndMint(recipientContractId: String) async throws -> DemoTokenResult
}

// MARK: - DemoTokenService

/// Manages the deterministic DEMO token for the Smart Account Demo.
///
/// The contract address is fully deterministic from the deployer keypair and salt.
/// Deploy is idempotent; mint is additive. Refuses to operate on non-testnet networks.
public final class DemoTokenService: Sendable {

    // MARK: - Configuration

    let rpcURL: String
    let networkPassphrase: String

    // MARK: - Init

    /// Creates a `DemoTokenService`.
    /// - Throws: `DemoTokenServiceError.notTestnet` when the passphrase does not match testnet.
    public init(rpcURL: String, networkPassphrase: String) throws {
        guard networkPassphrase == "Test SDF Network ; September 2015" else {
            throw DemoTokenServiceError.notTestnet
        }
        self.rpcURL = rpcURL
        self.networkPassphrase = networkPassphrase
    }

    // MARK: - Public API

    /// Ensures the DEMO token contract is deployed and mints DEMO to the recipient contract.
    /// Deploy is idempotent; mint is additive. Throws `DemoTokenServiceError` on failure.
    public func ensureTokenAndMint(recipientContractId: String) async throws -> DemoTokenResult {

        let adminKeyPair = try deriveAdminKeyPair()
        let salt = deriveSalt()
        let server = SorobanServer(endpoint: rpcURL)
        let tokenContractId = try deriveContractAddress(
            deployerPublicKey: adminKeyPair.accountId,
            salt: salt
        )
        await fundAdminIfNeeded(adminId: adminKeyPair.accountId, server: server)
        let alreadyExisted = await contractExists(contractId: tokenContractId, server: server)
        if !alreadyExisted {
            try await uploadWasm(adminKeyPair: adminKeyPair, server: server)
            try await deployContract(
                adminKeyPair: adminKeyPair,
                salt: salt,
                expectedAddress: tokenContractId,
                server: server
            )
        }
        try await mintTokens(
            to: recipientContractId,
            adminKeyPair: adminKeyPair,
            tokenContractId: tokenContractId,
            server: server
        )

        return DemoTokenResult(
            tokenContractId: tokenContractId,
            amountMinted: DemoConfig.demoTokenMintAmount,
            alreadyExisted: alreadyExisted
        )
    }

    // MARK: - Deterministic derivation (public for tests)

    /// Derives the deterministic DEMO token contract C-address.
    ///
    /// Pure computation — no network call. Identical inputs always produce the
    /// same output on every platform.
    public static func deriveContractAddress() throws -> String {
        let service = try DemoTokenService(
            rpcURL: DemoConfig.rpcURL,
            networkPassphrase: DemoConfig.networkPassphrase
        )
        let adminKeyPair = try service.deriveAdminKeyPair()
        let salt = service.deriveSalt()
        return try service.deriveContractAddress(
            deployerPublicKey: adminKeyPair.accountId,
            salt: salt
        )
    }

    /// Derives the DEMO token admin keypair via SHA-256(`DemoConfig.demoTokenAdminSeed`).
    public func deriveAdminKeyPair() throws -> KeyPair {
        let seedData = Data(DemoConfig.demoTokenAdminSeed.utf8)
        let hashBytes = seedData.sha256Hash
        do {
            return try KeyPair(seed: Seed(bytes: [UInt8](hashBytes)))
        } catch {
            throw DemoTokenServiceError.adminKeyDerivationFailed(
                reason: error.localizedDescription
            )
        }
    }

    /// Returns the 32-byte deployment salt: SHA-256(`DemoConfig.demoTokenSaltSeed`).
    public func deriveSalt() -> Data {
        let saltData = Data(DemoConfig.demoTokenSaltSeed.utf8)
        return saltData.sha256Hash
    }

    /// Derives the deterministic Soroban C-address for the given deployer and salt.
    /// Protocol: networkId = SHA-256(passphrase), preimage = ContractID XDR, contractId = SHA-256(preimage).
    public func deriveContractAddress(deployerPublicKey: String, salt: Data) throws -> String {

        let networkIdBytes = Data(networkPassphrase.utf8).sha256Hash
        let deployerAddress: SCAddressXDR
        do {
            deployerAddress = try SCAddressXDR(accountId: deployerPublicKey)
        } catch {
            throw DemoTokenServiceError.adminKeyDerivationFailed(
                reason: "Invalid deployer key \(deployerPublicKey): \(error.localizedDescription)"
            )
        }
        let fromAddress = ContractIDPreimageFromAddressXDR(
            address: deployerAddress,
            salt: Uint256XDR(salt)
        )
        let preimage = HashIDPreimageXDR.contractID(HashIDPreimageContractIDXDR(
            networkID: HashXDR(networkIdBytes),
            contractIDPreimage: ContractIDPreimageXDR.fromAddress(fromAddress)
        ))
        let encodedPreimage: Data
        do {
            encodedPreimage = Data(try XDREncoder.encode(preimage))
        } catch {
            throw DemoTokenServiceError.deployFailed(
                reason: "Failed to XDR-encode contract ID preimage: \(error.localizedDescription)"
            )
        }
        do {
            return try encodedPreimage.sha256Hash.encodeContractId()
        } catch {
            throw DemoTokenServiceError.deployFailed(
                reason: "Failed to StrKey-encode contract ID: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Private helpers

    /// Funds the admin via FriendBot if it does not exist on testnet.
    private func fundAdminIfNeeded(adminId: String, server: SorobanServer) async {
        let accountResponse = await server.getAccount(accountId: adminId)
        guard case .failure = accountResponse else { return }
        let funded = await Self.friendbotFund(accountId: adminId)
        if funded {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    /// Returns `true` if FriendBot responded with a 2xx status.
    private static func friendbotFund(accountId: String) async -> Bool {
        guard let escaped = accountId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://friendbot.stellar.org/?addr=\(escaped)") else {
            return false
        }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    /// Returns true if the contract instance ledger entry exists on-chain.
    private func contractExists(contractId: String, server: SorobanServer) async -> Bool {
        let result = await server.getContractData(
            contractId: contractId,
            key: .ledgerKeyContractInstance,
            durability: .persistent
        )
        switch result {
        case .success:
            return true
        case .failure:
            return false
        }
    }

    /// Uploads the token WASM binary to the network (install step). Idempotent.
    private func uploadWasm(adminKeyPair: KeyPair, server: SorobanServer) async throws {
        let wasmBytes: Data
        do {
            wasmBytes = try WasmResource.load(named: "soroban_token_contract")
        } catch {
            throw DemoTokenServiceError.deployFailed(
                reason: "Could not load soroban_token_contract.wasm from bundle: \(error.localizedDescription)"
            )
        }
        let uploadOp: InvokeHostFunctionOperation
        do {
            uploadOp = try InvokeHostFunctionOperation.forUploadingContractWasm(contractCode: wasmBytes)
        } catch {
            throw DemoTokenServiceError.deployFailed(
                reason: "Failed to build WASM upload operation: \(error.localizedDescription)"
            )
        }
        try await simulateSignSubmit(
            operation: uploadOp,
            adminKeyPair: adminKeyPair,
            server: server,
            errorContext: "WASM upload"
        )
    }

    /// Deploys the token contract via `CreateContractV2` with SEP-41 constructor args.
    private func deployContract(
        adminKeyPair: KeyPair,
        salt: Data,
        expectedAddress: String,
        server: SorobanServer
    ) async throws {
        let wasmBytes = try WasmResource.load(named: "soroban_token_contract")
        let wasmIdHex = wasmBytes.sha256Hash.map { String(format: "%02x", $0) }.joined()
        let adminAddress = try SCAddressXDR(accountId: adminKeyPair.accountId)
        let constructorArgs: [SCValXDR] = [
            .address(adminAddress),
            .u32(UInt32(DemoConfig.demoTokenDecimals)),
            .string(DemoConfig.demoTokenName),
            .string(DemoConfig.demoTokenSymbol)
        ]
        let deployOp: InvokeHostFunctionOperation
        do {
            deployOp = try InvokeHostFunctionOperation.forCreatingContractWithConstructor(
                wasmId: wasmIdHex,
                address: adminAddress,
                constructorArguments: constructorArgs,
                salt: WrappedData32(salt)
            )
        } catch {
            throw DemoTokenServiceError.deployFailed(
                reason: "Failed to build deploy operation: \(error.localizedDescription)"
            )
        }
        try await simulateSignSubmit(
            operation: deployOp,
            adminKeyPair: adminKeyPair,
            server: server,
            errorContext: "contract deploy"
        )
    }

    /// Mints DEMO tokens to the given recipient contract via SEP-41 `mint(to, amount)`.
    private func mintTokens(
        to recipientContractId: String,
        adminKeyPair: KeyPair,
        tokenContractId: String,
        server: SorobanServer
    ) async throws {
        let toAddress: SCAddressXDR
        do {
            toAddress = try SCAddressXDR(contractId: recipientContractId)
        } catch {
            throw DemoTokenServiceError.mintFailed(
                reason: "Invalid recipient contract address \(recipientContractId): \(error.localizedDescription)"
            )
        }
        let mintArgs: [SCValXDR] = [
            .address(toAddress),
            .i128(Int128PartsXDR(hi: 0, lo: UInt64(DemoConfig.demoTokenMintAmount)))
        ]
        let mintOp: InvokeHostFunctionOperation
        do {
            mintOp = try InvokeHostFunctionOperation.forInvokingContract(
                contractId: tokenContractId,
                functionName: "mint",
                functionArguments: mintArgs
            )
        } catch {
            throw DemoTokenServiceError.mintFailed(
                reason: "Failed to build mint operation: \(error.localizedDescription)"
            )
        }
        try await simulateSignSubmit(
            operation: mintOp,
            adminKeyPair: adminKeyPair,
            server: server,
            errorContext: "mint"
        )
    }

}

// MARK: - DemoTokenService transaction helpers

private extension DemoTokenService {

    /// Fetches account, builds transaction, simulates, applies, signs, and submits.
    func simulateSignSubmit(
        operation: stellarsdk.Operation,
        adminKeyPair: KeyPair,
        server: SorobanServer,
        errorContext: String
    ) async throws {
        let account = try await fetchAccount(adminKeyPair.accountId, server: server)
        let transaction = try buildTransaction(sourceAccount: account, operation: operation)
        let simulation = try await simulate(transaction: transaction, server: server)
        try applySimulation(simulation, to: transaction)
        try transaction.sign(keyPair: adminKeyPair, network: .custom(passphrase: networkPassphrase))
        try await submitAndWait(transaction: transaction, server: server, errorContext: errorContext)
    }

    func fetchAccount(_ accountId: String, server: SorobanServer) async throws -> Account {
        let result = await server.getAccount(accountId: accountId)
        switch result {
        case .success(let account):
            return account
        case .failure(let error):
            throw DemoTokenServiceError.deployFailed(
                reason: "Could not fetch account \(accountId): \(error.localizedDescription)"
            )
        }
    }

    func buildTransaction(
        sourceAccount: Account,
        operation: stellarsdk.Operation
    ) throws -> Transaction {
        do {
            return try Transaction(
                sourceAccount: sourceAccount,
                operations: [operation],
                memo: Memo.none,
                maxOperationFee: StellarProtocolConstants.MIN_BASE_FEE
            )
        } catch {
            throw DemoTokenServiceError.deployFailed(
                reason: "Failed to build transaction: \(error.localizedDescription)"
            )
        }
    }

    func simulate(
        transaction: Transaction,
        server: SorobanServer
    ) async throws -> SimulateTransactionResponse {
        let request = SimulateTransactionRequest(transaction: transaction)
        let result = await server.simulateTransaction(simulateTxRequest: request)
        switch result {
        case .success(let response):
            if let simError = response.error {
                throw DemoTokenServiceError.deployFailed(reason: "Simulation error: \(simError)")
            }
            return response
        case .failure(let error):
            throw DemoTokenServiceError.deployFailed(
                reason: "Simulation failed: \(error.localizedDescription)"
            )
        }
    }

    /// Applies simulation results to a transaction: footprint, auth entries, resource fee.
    func applySimulation(
        _ simulation: SimulateTransactionResponse,
        to transaction: Transaction
    ) throws {
        if let data = simulation.transactionData {
            transaction.setSorobanTransactionData(data: data)
        }
        transaction.setSorobanAuth(auth: simulation.sorobanAuth ?? [])
        if let minResourceFee = simulation.minResourceFee {
            transaction.addResourceFee(resourceFee: minResourceFee)
        }
    }

    /// Submits a signed transaction and polls until confirmed or failed.
    func submitAndWait(
        transaction: Transaction,
        server: SorobanServer,
        errorContext: String
    ) async throws {
        let txHash = try await sendTransaction(transaction, server: server, errorContext: errorContext)
        try await pollForConfirmation(txHash: txHash, server: server, errorContext: errorContext)
    }

    /// Sends a transaction and returns the transaction hash on success.
    func sendTransaction(
        _ transaction: Transaction,
        server: SorobanServer,
        errorContext: String
    ) async throws -> String {
        let sendResult = await server.sendTransaction(transaction: transaction)
        switch sendResult {
        case .success(let response):
            if let errorXdr = response.errorResultXdr {
                throw DemoTokenServiceError.deployFailed(
                    reason: "\(errorContext) rejected by network: \(errorXdr)"
                )
            }
            return response.transactionId
        case .failure(let error):
            throw DemoTokenServiceError.deployFailed(
                reason: "\(errorContext) submission failed: \(error.localizedDescription)"
            )
        }
    }

    /// Polls every 2 seconds for up to 30 attempts until the transaction is confirmed.
    func pollForConfirmation(
        txHash: String,
        server: SorobanServer,
        errorContext: String
    ) async throws {
        let maxAttempts = 30
        for _ in 0..<maxAttempts {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            let txResult = await server.getTransaction(transactionHash: txHash)
            guard case .success(let status) = txResult else { continue }
            switch status.status {
            case GetTransactionResponse.STATUS_SUCCESS:
                return
            case GetTransactionResponse.STATUS_FAILED:
                throw DemoTokenServiceError.deployFailed(
                    reason: "\(errorContext) failed on-chain: \(status.resultXdr ?? "no detail")"
                )
            default:
                continue
            }
        }
        throw DemoTokenServiceError.deployFailed(
            reason: "\(errorContext) confirmation timed out after \(maxAttempts * 2) seconds"
        )
    }
}

// MARK: - DemoTokenService + DemoTokenServiceType conformance

extension DemoTokenService: DemoTokenServiceType {}

// ============================================================================
// MARK: - Shared service factory
// ============================================================================

/// Builds a `DemoTokenServiceType` from `DemoConfig`.
///
/// Used at every `MainScreenFlow(...)` and `WalletCreationFlow(...)`
/// construction site so all three deploy entry points (auto-deploy creation
/// path, main-screen Deploy Now, retry pending deploy) operate on a single
/// `DemoTokenService` configuration. Returns `nil` when the configured network
/// passphrase is not Stellar testnet — the service refuses to instantiate
/// outside testnet to keep the publicly-derivable admin keypair from being
/// used on a network with real value. A non-fatal info entry is appended to
/// `activityLog` when the service cannot be built, so the demo screens fall
/// back to the deploy-only path without surfacing an error banner.
///
/// - Parameter activityLog: Log to receive the non-fatal info entry when the
///   service cannot be constructed. Pass the screen's shared `ActivityLogState`.
/// - Returns: A `DemoTokenServiceType` on success, or `nil` when the service
///   cannot be built (non-testnet or other configuration failure).
@MainActor
public func makeDemoTokenService(activityLog: ActivityLogState) -> (any DemoTokenServiceType)? {
    do {
        return try DemoTokenService(
            rpcURL: DemoConfig.rpcURL,
            networkPassphrase: DemoConfig.networkPassphrase
        )
    } catch {
        activityLog.info("Demo token service unavailable: \(ActivityLogState.redact(actionableMessage(for: error)))")
        return nil
    }
}

// ============================================================================
// MARK: - provisionDemoTokens
// ============================================================================

/// Orchestrates the DEMO-token deploy + mint for `recipientContractId`.
///
/// Shared by all deploy entry points so each one reports identical activity-log
/// lines, writes the same `DemoState` updates, and chains the same balance
/// refresh on success:
/// - Auto-deploy path in `WalletCreationFlow.createWallet(autoSubmit: true)`.
/// - Main-screen Deploy Now in `MainScreenFlow.deployPendingAndProvision`.
/// - Retry pending deploy in `WalletConnectionFlow.retryPendingDeploy`.
///
/// Behaviour:
/// - When `service` is `nil` the function returns immediately with `nil`. The
///   caller chose not to provision (e.g. service unavailable on a non-testnet
///   build).
/// - On entry an info line `"Minting DEMO tokens..."` is appended.
/// - On success the DEMO token contract id is recorded via
///   `DemoState.setDemoTokenContractId(_:)`, `onRefreshBalances()` is awaited
///   so the DEMO balance label populates immediately, and the post-refresh
///   value of `DemoState.demoTokenBalance` is returned.
/// - On failure an error line `"DEMO mint failed: <detail>"` is appended where
///   `<detail>` is derived from `actionableMessage(for:)` and passed through
///   `ActivityLogState.redact(_:)`. The function returns `nil`; the failure is
///   non-fatal — the deploy success the caller already reported is preserved.
///
/// - Parameters:
///   - service: Optional shared `DemoTokenServiceType`. When `nil` the function
///     is a no-op.
///   - demoState: Shared observable demo state mutated on success.
///   - activityLog: Shared append-only log receiving the entry lines.
///   - onRefreshBalances: Async callback invoked on success after the contract
///     id is written. Pass `MainScreenFlow.refreshBalances` or an equivalent.
///   - recipientContractId: C-address of the freshly deployed smart account
///     that should receive the minted DEMO tokens.
/// - Returns: The DEMO balance display string after the post-mint refresh, or
///   `nil` when `service` is `nil` or the mint fails.
@MainActor
@discardableResult
public func provisionDemoTokens(
    service: (any DemoTokenServiceType)?,
    demoState: DemoState,
    activityLog: ActivityLogState,
    onRefreshBalances: () async -> Void,
    recipientContractId: String
) async -> String? {
    guard let service else { return nil }

    activityLog.info("Minting DEMO tokens...")
    do {
        let tokenResult = try await service.ensureTokenAndMint(
            recipientContractId: recipientContractId
        )
        demoState.setDemoTokenContractId(tokenResult.tokenContractId)
        let shortAddr = truncateAddress(recipientContractId)
        let shortToken = truncateAddress(tokenResult.tokenContractId)
        activityLog.success(
            "DEMO tokens minted to \(shortAddr). Contract: \(shortToken)"
        )
        await onRefreshBalances()
        return demoState.demoTokenBalance
    } catch {
        let redacted = ActivityLogState.redact(actionableMessage(for: error))
        activityLog.error("DEMO mint failed: \(redacted)")
        return nil
    }
}
