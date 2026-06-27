// Copyright 2026 Soneso. Reference agent for the OZ smart-account demo.

import Foundation
import stellarsdk

/// Establishes the kit's connected state for the configured smart account.
///
/// Behind a protocol so the runner can be unit-tested without a live account or
/// a network round-trip.
public protocol WalletSession: Sendable {
    /// Connects to the smart account headlessly and returns its contract id.
    func connect() async throws -> String
}

/// Submits a multi-signer scoped contract call.
///
/// The production adapter wraps `OZMultiSignerManager`, while tests inject a
/// fake that returns canned `OZTransactionResult`s or throws.
public protocol MultiSignerContractCall: Sendable {
    /// Invokes [targetFn] on [target] with [targetArgs], authorised by the
    /// explicit [selectedSigners] list.
    func multiSignerContractCall(
        target: String,
        targetFn: String,
        targetArgs: [SCValXDR],
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult
}

/// Sink for the agent's progress messages.
public protocol AgentLogger: Sendable {
    /// Logs an informational message.
    func info(_ message: String)
    /// Logs a success message.
    func success(_ message: String)
    /// Logs an error message.
    func error(_ message: String)
}

/// `AgentLogger` that writes to stdout. Stdout is the headless agent's console
/// output channel, so a direct write is intentional here.
public struct StdoutAgentLogger: AgentLogger {
    public init() {}
    public func info(_ message: String) { write("INFO", message) }
    public func success(_ message: String) { write("OK", message) }
    public func error(_ message: String) { write("ERROR", message) }
    private func write(_ level: String, _ message: String) {
        print("[agent] [\(level)] \(message)")
    }
}

/// Terminal result of an `AgentRunner.run` invocation.
public enum AgentResult: Sendable, Equatable {

    /// The scoped call confirmed on-chain; no escalation was needed.
    case callSucceeded(hash: String)

    /// The scoped call failed for a non-policy reason; the agent did not
    /// escalate.
    case callFailed(message: String)

    /// The escalated policy rejection was approved by the user. The agent learns
    /// the outcome by polling and does not re-submit — the mobile app re-submits
    /// the call under the Default rule and reports `resultHash`.
    case escalationApproved(requestId: String, resultHash: String, errorCode: Int)

    /// The escalated policy rejection was declined by the user.
    case escalationRejected(requestId: String, errorCode: Int, note: String?)

    /// The escalation was created but no resolution arrived within the poll
    /// budget.
    case escalationPending(requestId: String, errorCode: Int, attempts: Int)
}

/// Orchestrates one autonomous agent cycle: connect, register, submit a scoped
/// call, classify the outcome, and (on a policy rejection) escalate and poll.
///
/// All collaborators are injected so unit tests can drive the success,
/// rejection, escalate-and-approved, escalate-and-rejected, and pending paths
/// without a network or a live account.
public final class AgentRunner: @unchecked Sendable {

    /// The function the agent calls on the target token.
    public static let targetFn = "transfer"

    /// The resolved run configuration.
    public let config: AgentConfig

    private let session: WalletSession
    private let contractCall: MultiSignerContractCall
    private let coordination: CoordinationClient
    private let signerAdapter: AgentEd25519SignerAdapter
    private let agentKeypair: KeyPair
    private let logger: AgentLogger
    private let sleep: @Sendable (Duration) async throws -> Void

    /// Constructs a runner from its injected collaborators.
    ///
    /// [signerAdapter] is the same adapter instance supplied to the kit's
    /// `OZSmartAccountConfig.externalEd25519Adapter`; the runner registers
    /// [agentKeypair] on it before submission and clears it afterwards.
    /// [sleep] is injectable so tests can run the poll loop without real delays.
    public init(
        config: AgentConfig,
        session: WalletSession,
        contractCall: MultiSignerContractCall,
        coordination: CoordinationClient,
        signerAdapter: AgentEd25519SignerAdapter,
        agentKeypair: KeyPair,
        logger: AgentLogger = StdoutAgentLogger(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.config = config
        self.session = session
        self.contractCall = contractCall
        self.coordination = coordination
        self.signerAdapter = signerAdapter
        self.agentKeypair = agentKeypair
        self.logger = logger
        self.sleep = sleep
    }

    private var agentPublicKey: Data { Data(agentKeypair.publicKey.bytes) }

    /// Runs one agent cycle and returns its terminal `AgentResult`.
    public func run() async throws -> AgentResult {
        logger.info(
            "Starting agent: account=\(config.smartAccountContractId ?? "nil"), "
                + "token=\(config.tokenContractId), amount=\(config.amount)"
        )
        // Print the agent's own public key as raw 64-character hex so an operator
        // can paste it into the demo's "Delegate to agent" screen, which
        // registers it as the Ed25519 external signer this agent then signs with.
        logger.info(
            "Agent public key (paste into Delegate-to-agent): \(Hex.encode(agentKeypair.publicKey.bytes))"
        )

        let smartAccount = try await session.connect()
        logger.info("Connected to smart account \(smartAccount)")

        let args = try buildTransferArgs(smartAccount: smartAccount)
        let selectedSigners: [OZSelectedSigner] = [
            .ed25519(verifierAddress: config.ed25519VerifierAddress, publicKey: agentPublicKey)
        ]

        // The signing keypair is only needed to authorise the scoped call below;
        // escalation and polling never sign. Register it immediately before the
        // call and drop the adapter's reference the moment the call returns or
        // throws, regardless of outcome, so the key is not retained for the whole
        // escalation/poll window. `attemptCall` classifies any throw into a
        // `CallOutcome` rather than rethrowing, so `clearAll` always runs.
        try signerAdapter.add(verifierAddress: config.ed25519VerifierAddress, keypair: agentKeypair)
        let outcome = await attemptCall(args: args, selectedSigners: selectedSigners)
        signerAdapter.clearAll()

        switch outcome {
        case .succeeded(let hash):
            logger.success("Scoped call confirmed. Hash: \(hash)")
            return .callSucceeded(hash: hash)
        case .failed(let message):
            logger.error("Scoped call failed (not a policy rejection): \(message)")
            return .callFailed(message: message)
        case .rejected(let errorCode, let errorName, _):
            return try await escalateAndPoll(
                errorCode: errorCode,
                errorName: errorName,
                args: args,
                smartAccount: smartAccount
            )
        }
    }

    private func attemptCall(
        args: [SCValXDR],
        selectedSigners: [OZSelectedSigner]
    ) async -> CallOutcome {
        do {
            let result = try await contractCall.multiSignerContractCall(
                target: config.tokenContractId,
                targetFn: AgentRunner.targetFn,
                targetArgs: args,
                selectedSigners: selectedSigners
            )
            return classifyResult(result)
        } catch {
            return classifyError(error)
        }
    }

    private func escalateAndPoll(
        errorCode: Int,
        errorName: String?,
        args: [SCValXDR],
        smartAccount: String
    ) async throws -> AgentResult {
        logger.info(
            "Policy rejection (code \(errorCode)\(errorName == nil ? "" : " / \(errorName!)")). "
                + "Escalating to \(config.coordinationBaseUrl)."
        )

        let encodedArgs = try args.map { arg -> String in
            guard let encoded = arg.xdrEncoded else {
                throw AgentConfigError("Failed to base64-encode a transfer argument for escalation.")
            }
            return encoded
        }

        let created = try await coordination.createRequest(
            smartAccount: smartAccount,
            target: config.tokenContractId,
            targetFn: AgentRunner.targetFn,
            args: encodedArgs,
            amount: config.amount,
            reason: errorCode
        )
        let requestId = created.id
        logger.info("Escalation request created: id=\(requestId) (pending).")

        // Half-open range so a non-positive pollMaxAttempts yields an empty loop
        // (matching the Flutter reference, which skips the body and returns
        // pending with attempts: 0) instead of trapping on an invalid range.
        for attempt in 0..<config.pollMaxAttempts {
            try await sleep(config.pollInterval)

            let current: CoordinationRequest
            do {
                current = try await coordination.getRequest(requestId)
            } catch {
                // A single failed poll (e.g. a transient network blip) must not
                // abort the escalation: the loop is already bounded by
                // pollMaxAttempts. Log it and try again on the next attempt;
                // the request resolves server-side independently of our polling.
                logger.info(
                    "Poll attempt \(attempt + 1)/\(config.pollMaxAttempts) for \(requestId) failed: "
                        + "\(error). Retrying."
                )
                continue
            }
            switch current.status {
            case CoordinationRequest.statusApproved:
                let resultHash = current.resultHash ?? ""
                logger.success(
                    "Escalation approved by user. resultHash=\(resultHash). "
                        + "The mobile app re-submitted under the Default rule; the agent "
                        + "does not re-submit."
                )
                return .escalationApproved(requestId: requestId, resultHash: resultHash, errorCode: errorCode)
            case CoordinationRequest.statusRejected:
                logger.info(
                    "Escalation rejected by user\(current.note == nil ? "" : ": \(current.note!)")."
                )
                return .escalationRejected(requestId: requestId, errorCode: errorCode, note: current.note)
            default:
                // Still pending — keep polling.
                break
            }
        }

        logger.info(
            "Escalation \(requestId) still pending after \(config.pollMaxAttempts) polls; stopping."
        )
        return .escalationPending(requestId: requestId, errorCode: errorCode, attempts: config.pollMaxAttempts)
    }

    /// Builds the `transfer(from, to, amount)` argument vector.
    ///
    /// The encoded form of this exact list is sent to the coordination server so
    /// the mobile inbox can rebuild the call verbatim.
    func buildTransferArgs(smartAccount: String) throws -> [SCValXDR] {
        guard let destination = config.destinationAddress, !destination.isEmpty else {
            throw AgentConfigError("destinationAddress is required to build the transfer call.")
        }
        let baseUnits = try OZTransactionOperations.amountToBaseUnits(
            config.amount,
            decimals: config.tokenDecimals
        )
        return [
            try AgentRunner.addressSCVal(smartAccount),
            try AgentRunner.addressSCVal(destination),
            try SCValXDR.i128(stringValue: baseUnits),
        ]
    }

    /// Builds an `address` `SCValXDR` from a `G…` or `C…` strkey, mirroring the
    /// SDK's own `transfer` argument construction.
    static func addressSCVal(_ strKey: String) throws -> SCValXDR {
        if strKey.hasPrefix("C") {
            return .address(try SCAddressXDR(contractId: strKey))
        }
        return .address(try SCAddressXDR(accountId: strKey))
    }
}
