// Copyright 2026 Soneso. Reference agent for the OZ smart-account demo.

import Foundation
import Testing
import stellarsdk

@testable import ReferenceAgentCore

// MARK: - Mocks

/// Records the connect call and returns a fixed smart-account contract id.
private final class FakeWalletSession: WalletSession, @unchecked Sendable {
    private let lock = NSLock()
    let contractId: String
    private var _connectCount = 0

    init(_ contractId: String) { self.contractId = contractId }

    var connectCount: Int { lock.withLock { _connectCount } }

    func connect() async throws -> String {
        lock.withLock { _connectCount += 1 }
        return contractId
    }
}

/// Returns a canned `OZTransactionResult` or throws a canned error, recording
/// the last call's arguments.
private final class FakeContractCall: MultiSignerContractCall, @unchecked Sendable {
    private let lock = NSLock()
    private let result: OZTransactionResult?
    private let error: Error?

    private var _callCount = 0
    private var _lastSelectedSigners: [OZSelectedSigner]?
    private var _lastArgs: [SCValXDR]?
    private var _lastTarget: String?
    private var _lastTargetFn: String?

    init(result: OZTransactionResult) {
        self.result = result
        self.error = nil
    }

    init(error: Error) {
        self.result = nil
        self.error = error
    }

    var callCount: Int { lock.withLock { _callCount } }
    var lastSelectedSigners: [OZSelectedSigner]? { lock.withLock { _lastSelectedSigners } }
    var lastArgs: [SCValXDR]? { lock.withLock { _lastArgs } }
    var lastTarget: String? { lock.withLock { _lastTarget } }
    var lastTargetFn: String? { lock.withLock { _lastTargetFn } }

    func multiSignerContractCall(
        target: String,
        targetFn: String,
        targetArgs: [SCValXDR],
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        lock.withLock {
            _callCount += 1
            _lastTarget = target
            _lastTargetFn = targetFn
            _lastArgs = targetArgs
            _lastSelectedSigners = selectedSigners
        }
        if let error { throw error }
        return result!
    }
}

/// Captures the created request and replays a queued status sequence.
private final class FakeCoordinationClient: CoordinationClient, @unchecked Sendable {
    private let lock = NSLock()
    private let pollResponses: [CoordinationRequest]
    private var _getCount = 0
    private var _createBody: [String: Any]?

    init(pollResponses: [CoordinationRequest]) {
        self.pollResponses = pollResponses
    }

    var getCount: Int { lock.withLock { _getCount } }
    var createBody: [String: Any]? { lock.withLock { _createBody } }

    func createRequest(
        smartAccount: String,
        target: String,
        targetFn: String,
        args: [String],
        amount: String?,
        reason: Int
    ) async throws -> CoordinationRequest {
        lock.withLock {
            _createBody = [
                "smartAccount": smartAccount,
                "target": target,
                "targetFn": targetFn,
                "args": args,
                "amount": amount as Any,
                "reason": reason,
            ]
        }
        return CoordinationRequest(
            id: "req-1",
            smartAccount: smartAccount,
            target: target,
            targetFn: targetFn,
            args: args,
            amount: amount ?? "",
            reason: reason,
            status: CoordinationRequest.statusPending,
            createdAt: 1
        )
    }

    func getRequest(_ id: String) async throws -> CoordinationRequest {
        lock.withLock {
            let index = _getCount < pollResponses.count ? _getCount : pollResponses.count - 1
            _getCount += 1
            return pollResponses[index]
        }
    }
}

/// Records the created request, then throws on the configured poll attempts
/// (1-based) and returns a canned approved/resolved response on the others.
///
/// Models a coordination server that is briefly unreachable for a poll or two
/// before the escalation resolves.
private final class FlakyCoordinationClient: CoordinationClient, @unchecked Sendable {
    private let lock = NSLock()
    private let throwOnAttempts: Set<Int>
    private let resolved: CoordinationRequest
    private var _getCount = 0

    init(throwOnAttempts: Set<Int>, resolved: CoordinationRequest) {
        self.throwOnAttempts = throwOnAttempts
        self.resolved = resolved
    }

    var getCount: Int { lock.withLock { _getCount } }

    func createRequest(
        smartAccount: String,
        target: String,
        targetFn: String,
        args: [String],
        amount: String?,
        reason: Int
    ) async throws -> CoordinationRequest {
        CoordinationRequest(
            id: "req-1",
            smartAccount: smartAccount,
            target: target,
            targetFn: targetFn,
            args: args,
            amount: amount ?? "",
            reason: reason,
            status: CoordinationRequest.statusPending,
            createdAt: 1
        )
    }

    func getRequest(_ id: String) async throws -> CoordinationRequest {
        let attempt: Int = lock.withLock {
            _getCount += 1
            return _getCount
        }
        if throwOnAttempts.contains(attempt) {
            throw CoordinationError("transient network failure while polling")
        }
        return resolved
    }
}

private final class RecordingLogger: AgentLogger, @unchecked Sendable {
    private let lock = NSLock()
    private var _messages: [String] = []

    var messages: [String] { lock.withLock { _messages } }

    func info(_ message: String) { lock.withLock { _messages.append("INFO:\(message)") } }
    func success(_ message: String) { lock.withLock { _messages.append("OK:\(message)") } }
    func error(_ message: String) { lock.withLock { _messages.append("ERROR:\(message)") } }
}

// MARK: - Tests

@Suite("AgentRunner")
struct AgentRunnerTests {

    private let smartAccount = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
    private let ed25519Verifier = "CAW2Z46INPO5VIJEILMYSSEOLBVJIIII5GOE3TN5EUURSRM2FJCF7AJ6"

    private func makeContext() throws -> (agentKeypair: KeyPair, destination: String, adapter: AgentEd25519SignerAdapter) {
        let agentKeypair = try KeyPair.generateRandomKeyPair()
        let destination = try KeyPair.generateRandomKeyPair().accountId
        return (agentKeypair, destination, AgentEd25519SignerAdapter())
    }

    private func buildConfig(destination: String) -> AgentConfig {
        // The runner is constructed with the agent keypair directly; the config's
        // hex seed is not re-derived here, so any valid 64-hex seed is sufficient.
        AgentConfig(
            tokenContractId: AgentDefaults.nativeTokenContract,
            amount: "5",
            smartAccountContractId: smartAccount,
            agentSecretSeed: String(repeating: "01", count: 32),
            destinationAddress: destination,
            pollInterval: .zero,
            pollMaxAttempts: 5
        )
    }

    private func buildRunner(
        config: AgentConfig,
        contractCall: MultiSignerContractCall,
        coordination: CoordinationClient,
        session: WalletSession,
        signerAdapter: AgentEd25519SignerAdapter,
        agentKeypair: KeyPair,
        logger: AgentLogger
    ) -> AgentRunner {
        AgentRunner(
            config: config,
            session: session,
            contractCall: contractCall,
            coordination: coordination,
            signerAdapter: signerAdapter,
            agentKeypair: agentKeypair,
            logger: logger,
            sleep: { _ in }
        )
    }

    @Test("successful scoped call returns callSucceeded with the hash")
    func successPath() async throws {
        let (agentKeypair, destination, adapter) = try makeContext()
        let contractCall = FakeContractCall(result: OZTransactionResult(success: true, hash: "TXHASH123"))
        let coordination = FakeCoordinationClient(pollResponses: [])
        let session = FakeWalletSession(smartAccount)
        let logger = RecordingLogger()

        let runner = buildRunner(
            config: buildConfig(destination: destination),
            contractCall: contractCall,
            coordination: coordination,
            session: session,
            signerAdapter: adapter,
            agentKeypair: agentKeypair,
            logger: logger
        )

        let result = try await runner.run()

        #expect(result == .callSucceeded(hash: "TXHASH123"))
        #expect(session.connectCount == 1)
        #expect(contractCall.callCount == 1)

        // The selected signer is the agent's Ed25519 external signer.
        let signers = try #require(contractCall.lastSelectedSigners)
        #expect(signers.count == 1)
        guard case let .ed25519(verifierAddress, publicKey) = try #require(signers.first) else {
            Issue.record("expected an ed25519 selected signer")
            return
        }
        #expect(verifierAddress == ed25519Verifier)
        #expect(publicKey == Data(agentKeypair.publicKey.bytes))
        #expect(contractCall.lastTargetFn == "transfer")
        #expect(contractCall.lastTarget == AgentDefaults.nativeTokenContract)

        // No escalation occurred.
        #expect(coordination.createBody == nil)
        #expect(coordination.getCount == 0)

        // The adapter reference is cleared after the attempt.
        #expect(adapter.canSignFor(verifierAddress: ed25519Verifier, publicKey: Data(agentKeypair.publicKey.bytes)) == false)
    }

    @Test("logs the agent public key as raw 64-char hex on startup")
    func logsPublicKey() async throws {
        let (agentKeypair, destination, adapter) = try makeContext()
        let contractCall = FakeContractCall(result: OZTransactionResult(success: true, hash: "TXHASH123"))
        let logger = RecordingLogger()

        let runner = buildRunner(
            config: buildConfig(destination: destination),
            contractCall: contractCall,
            coordination: FakeCoordinationClient(pollResponses: []),
            session: FakeWalletSession(smartAccount),
            signerAdapter: adapter,
            agentKeypair: agentKeypair,
            logger: logger
        )

        _ = try await runner.run()

        let expectedHex = Hex.encode(agentKeypair.publicKey.bytes)
        let startupLine = try #require(logger.messages.first { $0.contains("Delegate-to-agent") })
        #expect(startupLine.contains(expectedHex))
        #expect(expectedHex.count == 64)
        #expect(expectedHex.allSatisfy { $0.isHexDigit })
    }

    @Test("non-policy failure returns callFailed without escalating")
    func nonPolicyFailure() async throws {
        let (agentKeypair, destination, adapter) = try makeContext()
        let contractCall = FakeContractCall(
            result: OZTransactionResult(success: false, error: "RPC endpoint unreachable")
        )
        let coordination = FakeCoordinationClient(pollResponses: [])

        let runner = buildRunner(
            config: buildConfig(destination: destination),
            contractCall: contractCall,
            coordination: coordination,
            session: FakeWalletSession(smartAccount),
            signerAdapter: adapter,
            agentKeypair: agentKeypair,
            logger: RecordingLogger()
        )

        let result = try await runner.run()

        guard case let .callFailed(message) = result else {
            Issue.record("expected .callFailed, got \(result)")
            return
        }
        #expect(message.contains("unreachable"))
        #expect(coordination.createBody == nil)
    }

    @Test("policy rejection escalates and returns approved with the result hash")
    func escalationApproved() async throws {
        let (agentKeypair, destination, adapter) = try makeContext()
        let contractCall = FakeContractCall(
            result: OZTransactionResult(success: false, error: "HostError: Error(Contract, #3016)")
        )
        let approved = CoordinationRequest(
            id: "req-1", smartAccount: smartAccount, target: smartAccount, targetFn: "transfer",
            args: [], amount: "5", reason: 3016, status: CoordinationRequest.statusApproved,
            createdAt: 1, resolvedAt: 2, resultHash: "RESOLVEDHASH"
        )
        // First poll still pending, second poll approved — exercises the loop.
        let pending = CoordinationRequest(
            id: "req-1", smartAccount: smartAccount, target: smartAccount, targetFn: "transfer",
            args: [], amount: "5", reason: 3016, status: CoordinationRequest.statusPending, createdAt: 1
        )
        let coordination = FakeCoordinationClient(pollResponses: [pending, approved])

        let config = buildConfig(destination: destination)
        let runner = buildRunner(
            config: config,
            contractCall: contractCall,
            coordination: coordination,
            session: FakeWalletSession(smartAccount),
            signerAdapter: adapter,
            agentKeypair: agentKeypair,
            logger: RecordingLogger()
        )

        let result = try await runner.run()

        #expect(result == .escalationApproved(requestId: "req-1", resultHash: "RESOLVEDHASH", errorCode: 3016))
        #expect(coordination.getCount == 2)

        // The escalation body matches the wire contract.
        let body = try #require(coordination.createBody)
        #expect(body["smartAccount"] as? String == smartAccount)
        #expect(body["target"] as? String == config.tokenContractId)
        #expect(body["targetFn"] as? String == "transfer")
        #expect(body["reason"] as? Int == 3016)
        #expect(body["amount"] as? String == "5")

        // args are the three base64-encoded SCValXDR call args (from, to, amount).
        // Decode them and assert the concrete transfer semantics: source is the
        // smart account, destination is the configured recipient (not the smart
        // account again), and the amount is the configured value scaled to base
        // units by the token decimals.
        let args = try #require(body["args"] as? [String])
        #expect(args.count == 3)

        // The from-address is a contract address; its 32-byte payload (hex form
        // of the C-strkey) must match the smart account, independently derived.
        let expectedSmartAccountHex = try SCAddressXDR(contractId: smartAccount).contractId
        let from = try SCValXDR.fromXdr(base64: args[0])
        guard case let .address(fromAddress) = from else {
            Issue.record("arg[0] (from) is not an address SCVal")
            return
        }
        #expect(fromAddress.contractId == expectedSmartAccountHex)

        let to = try SCValXDR.fromXdr(base64: args[1])
        guard case let .address(toAddress) = to else {
            Issue.record("arg[1] (to) is not an address SCVal")
            return
        }
        // The destination is the configured G-address recipient, returned as a
        // strkey by the accountId getter, and must not be the smart account.
        #expect(toAddress.accountId == destination)
        #expect(toAddress.contractId == nil)
        #expect(toAddress.contractId != expectedSmartAccountHex)

        let amount = try SCValXDR.fromXdr(base64: args[2])
        guard case let .i128(parts) = amount else {
            Issue.record("arg[2] (amount) is not an i128 SCVal")
            return
        }
        // "5" scaled by 7 decimals -> 50_000_000 base units, which fits in `lo`.
        #expect(parts.hi == 0)
        #expect(parts.lo == 50_000_000)
    }

    @Test("escalation with pollMaxAttempts == 0 returns pending without polling or trapping")
    func escalationPendingZeroAttempts() async throws {
        let (agentKeypair, destination, adapter) = try makeContext()
        let contractCall = FakeContractCall(
            result: OZTransactionResult(success: false, error: "Error(Contract, #3016)")
        )
        // No poll responses are needed: the loop must not execute at all.
        let coordination = FakeCoordinationClient(pollResponses: [])

        let config = buildConfig(destination: destination).with(pollMaxAttempts: 0)

        let runner = buildRunner(
            config: config,
            contractCall: contractCall,
            coordination: coordination,
            session: FakeWalletSession(smartAccount),
            signerAdapter: adapter,
            agentKeypair: agentKeypair,
            logger: RecordingLogger()
        )

        let result = try await runner.run()

        #expect(result == .escalationPending(requestId: "req-1", errorCode: 3016, attempts: 0))
        // The request was created but never polled.
        #expect(coordination.createBody != nil)
        #expect(coordination.getCount == 0)
    }

    @Test("policy rejection escalates and returns rejected with the note")
    func escalationRejected() async throws {
        let (agentKeypair, destination, adapter) = try makeContext()
        // Exercise the thrown-error classification path.
        let contractCall = FakeContractCall(
            error: SmartAccountTransactionException.simulationFailed(reason: "Error(Contract, #3016)")
        )
        let rejected = CoordinationRequest(
            id: "req-1", smartAccount: smartAccount, target: smartAccount, targetFn: "transfer",
            args: [], amount: "5", reason: 3016, status: CoordinationRequest.statusRejected,
            createdAt: 1, resolvedAt: 2, note: "looks malicious"
        )
        let coordination = FakeCoordinationClient(pollResponses: [rejected])

        let runner = buildRunner(
            config: buildConfig(destination: destination),
            contractCall: contractCall,
            coordination: coordination,
            session: FakeWalletSession(smartAccount),
            signerAdapter: adapter,
            agentKeypair: agentKeypair,
            logger: RecordingLogger()
        )

        let result = try await runner.run()

        #expect(result == .escalationRejected(requestId: "req-1", errorCode: 3016, note: "looks malicious"))
    }

    @Test("a transient poll error is tolerated and polling continues until resolution")
    func escalationTransientPollErrorThenApproved() async throws {
        let (agentKeypair, destination, adapter) = try makeContext()
        let contractCall = FakeContractCall(
            result: OZTransactionResult(success: false, error: "Error(Contract, #3016)")
        )
        let approved = CoordinationRequest(
            id: "req-1", smartAccount: smartAccount, target: smartAccount, targetFn: "transfer",
            args: [], amount: "5", reason: 3016, status: CoordinationRequest.statusApproved,
            createdAt: 1, resolvedAt: 2, resultHash: "RESOLVEDHASH"
        )
        // The first poll attempt throws a transient network error; the second
        // succeeds and reports the resolution. A single failed poll must not
        // abort the whole run.
        let coordination = FlakyCoordinationClient(throwOnAttempts: [1], resolved: approved)

        let runner = buildRunner(
            config: buildConfig(destination: destination),
            contractCall: contractCall,
            coordination: coordination,
            session: FakeWalletSession(smartAccount),
            signerAdapter: adapter,
            agentKeypair: agentKeypair,
            logger: RecordingLogger()
        )

        let result = try await runner.run()

        #expect(result == .escalationApproved(requestId: "req-1", resultHash: "RESOLVEDHASH", errorCode: 3016))
        // Two polls happened: attempt 1 threw and was tolerated, attempt 2 resolved.
        #expect(coordination.getCount == 2)
    }

    @Test("escalation that never resolves returns escalationPending")
    func escalationPending() async throws {
        let (agentKeypair, destination, adapter) = try makeContext()
        let contractCall = FakeContractCall(
            result: OZTransactionResult(success: false, error: "Error(Contract, #3016)")
        )
        let pending = CoordinationRequest(
            id: "req-1", smartAccount: smartAccount, target: smartAccount, targetFn: "transfer",
            args: [], amount: "5", reason: 3016, status: CoordinationRequest.statusPending, createdAt: 1
        )
        let coordination = FakeCoordinationClient(pollResponses: [pending])

        let runner = buildRunner(
            config: buildConfig(destination: destination),
            contractCall: contractCall,
            coordination: coordination,
            session: FakeWalletSession(smartAccount),
            signerAdapter: adapter,
            agentKeypair: agentKeypair,
            logger: RecordingLogger()
        )

        let result = try await runner.run()

        #expect(result == .escalationPending(requestId: "req-1", errorCode: 3016, attempts: 5))
        #expect(coordination.getCount == 5)
    }
}
