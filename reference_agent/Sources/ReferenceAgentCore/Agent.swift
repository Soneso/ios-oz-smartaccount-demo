// Copyright 2026 Soneso. Reference agent for the OZ smart-account demo.

import Foundation
import stellarsdk

/// Production `WalletSession` that connects an `OZSmartAccountKit` headlessly.
///
/// Uses the contract-address-only `OZWalletOperations.connectToContract` path:
/// no passkey credential, no WebAuthn ceremony, no session restore. The agent
/// operates the account through the multi-signer / external-signer pipeline.
public struct KitWalletSession: WalletSession {

    private let kit: OZSmartAccountKit
    private let contractId: String

    /// Constructs a session for [kit] connecting headlessly to [contractId].
    public init(kit: OZSmartAccountKit, contractId: String) {
        self.kit = kit
        self.contractId = contractId
    }

    public func connect() async throws -> String {
        let result = try await kit.walletOperations.connectToContract(contractId: contractId)
        return result.contractId
    }
}

/// Production `MultiSignerContractCall` backed by `OZMultiSignerManager`.
public struct MultiSignerContractCallAdapter: MultiSignerContractCall {

    private let manager: OZMultiSignerManager

    /// Constructs the adapter from a live `OZMultiSignerManager`.
    public init(manager: OZMultiSignerManager) {
        self.manager = manager
    }

    public func multiSignerContractCall(
        target: String,
        targetFn: String,
        targetArgs: [SCValXDR],
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        try await manager.multiSignerContractCall(
            target: target,
            targetFn: targetFn,
            targetArgs: targetArgs,
            selectedSigners: selectedSigners
        )
    }
}

/// Production assembly of the reference agent.
///
/// Wires an `OZSmartAccountKit` (in-memory storage, no WebAuthn provider, the
/// agent's `AgentEd25519SignerAdapter` supplied as the Ed25519 adapter), an
/// `HttpCoordinationClient`, and an `AgentRunner`. Owns the kit and the
/// coordination URL session; call `dispose` when finished.
public final class Agent: @unchecked Sendable {

    /// The configured runner.
    public let runner: AgentRunner

    private let kit: OZSmartAccountKit
    private let session: URLSession

    private init(runner: AgentRunner, kit: OZSmartAccountKit, session: URLSession) {
        self.runner = runner
        self.kit = kit
        self.session = session
    }

    /// Builds a fully wired agent from [config].
    ///
    /// Throws `AgentConfigError` when [config] is missing a value required for a
    /// live run, or a `SmartAccount…Exception` when the kit configuration is
    /// rejected. Supply [session] to inject a coordination URL session;
    /// otherwise one is created and invalidated by `dispose`.
    public static func fromConfig(
        _ config: AgentConfig,
        logger: AgentLogger = StdoutAgentLogger(),
        session: URLSession? = nil
    ) throws -> Agent {
        try config.validateForLiveRun()

        // validateForLiveRun guarantees these are present and well-formed.
        let seedHex = config.agentSecretSeed!
        guard let seedBytes = Hex.decode(seedHex.lowercased()) else {
            throw AgentConfigError("agentSecretSeed is not valid hex.")
        }
        let agentKeypair = KeyPair(seed: try Seed(bytes: seedBytes))
        let signerAdapter = AgentEd25519SignerAdapter()

        let ozConfig = try OZSmartAccountConfig(
            rpcUrl: config.rpcUrl,
            networkPassphrase: config.networkPassphrase,
            accountWasmHash: config.accountWasmHash,
            webauthnVerifierAddress: config.webauthnVerifierAddress,
            relayerUrl: config.relayerUrl.isEmpty ? nil : config.relayerUrl,
            storage: OZInMemoryStorageAdapter(),
            externalEd25519Adapter: signerAdapter,
            // The relayer chain the demo submits through (OpenZeppelin Relayer
            // Channels) parses the submitted auth XDR with a pre-protocol-27
            // schema and rejects ADDRESS_V2 entries. Legacy ADDRESS entries stay
            // valid on-chain, so the kit requests and builds those instead.
            // Remove this override once the relayer parses protocol-27 XDR.
            useUpgradedAuth: false,
            // The external wallet builds the demo connects to are not confirmed
            // to sign the address-bound preimage
            // (ENVELOPE_TYPE_SOROBAN_AUTHORIZATION_WITH_ADDRESS), so delegated
            // wallet entries stay on the legacy ADDRESS credential arm. Flip
            // this to the SDK default (true) once a wallet is confirmed to sign
            // the address-bound form.
            useUpgradedAuthForWalletSigners: false
        )
        let kit = OZSmartAccountKit.create(config: ozConfig)

        let urlSession = session ?? URLSession(configuration: .ephemeral)
        let coordination = HttpCoordinationClient(
            baseUrl: config.coordinationBaseUrl,
            token: config.coordinationToken,
            session: urlSession
        )

        let runner = AgentRunner(
            config: config,
            session: KitWalletSession(kit: kit, contractId: config.smartAccountContractId!),
            contractCall: MultiSignerContractCallAdapter(manager: kit.multiSignerManager),
            coordination: coordination,
            signerAdapter: signerAdapter,
            agentKeypair: agentKeypair,
            logger: logger
        )

        return Agent(runner: runner, kit: kit, session: urlSession)
    }

    /// Runs one agent cycle.
    public func run() async throws -> AgentResult {
        try await runner.run()
    }

    /// Releases the coordination URL session and the kit's held resources.
    public func dispose() async {
        session.invalidateAndCancel()
        await kit.close()
    }
}
