// CoordinationE2ETests.swift
// SmartAccountDemoTests
//
// Copyright (c) 2026 Soneso. All rights reserved.
//
// Opt-in end-to-end test of the coordination seam: the demo's real
// URLSessionCoordinationClient against a real coordination_server subprocess.
//
// This is the only automatable slice of the agent-signer flow — it exercises
// the HTTP coordination contract end to end WITHOUT a chain, passkey, or
// relayer. The on-chain submission and the WebAuthn approval ceremony remain
// device-only (see documentation/agent-flow.md).
//
// GATED: the suite is enabled only when the test process sees
// RUN_COORDINATION_E2E=true, so the default `xcodebuild test` run never builds
// the server, spawns a subprocess, or binds a socket — it reports the tests as
// skipped. Run it explicitly:
//
//   TEST_RUNNER_RUN_COORDINATION_E2E=true xcodebuild \
//     -project SmartAccountDemo.xcodeproj \
//     -scheme SmartAccountDemoMac -destination 'platform=macOS' test
//
// xcodebuild does not forward the invoking shell's environment into the test
// host; the `TEST_RUNNER_` prefix is the mechanism that injects the variable
// (stripped of the prefix) into the test process. Running the bundle directly
// under `xctest` honours a plain RUN_COORDINATION_E2E=true.
//
// macOS only: launching the server with Foundation `Process` requires the
// macOS Foundation that ships `Process`/`NSTask`, which is absent on the iOS
// simulator. The whole file is `#if os(macOS)` so the iOS test target compiles
// it to nothing.

#if os(macOS)

import Foundation
import Darwin
@testable import SmartAccountDemoMacLib
import stellarsdk
import Testing

// ============================================================================
// MARK: - Gate
// ============================================================================

/// Environment gate. The default test run leaves this unset, disabling the
/// suite so no subprocess is started and no socket is bound.
private let runCoordinationE2E =
    (ProcessInfo.processInfo.environment["RUN_COORDINATION_E2E"] ?? "")
        .lowercased() == "true"

// ============================================================================
// MARK: - Suite
// ============================================================================

@Suite(
    "coordination end-to-end (real server subprocess)",
    .enabled(
        if: runCoordinationE2E,
        "Set RUN_COORDINATION_E2E=true to run the coordination end-to-end test against a real coordination_server subprocess."
    ),
    .serialized
)
struct CoordinationE2ETests {

    /// Bearer token the spawned server requires on every `/requests*` call.
    let token = "coordination-e2e-test-token"

    // -------------------------------------------------------------------------
    // MARK: - Approve path
    // -------------------------------------------------------------------------

    @Test("agent escalation round-trips through approve and resolve")
    func approveLifecycle() async throws {
        let server = try await CoordinationServerProcess.start(token: token)
        defer { server.stop() }

        let client = URLSessionCoordinationClient(
            baseURL: server.baseURL,
            token: token,
            session: Self.makeSession()
        )

        // The exact call the agent would escalate: transfer(from, to, amount).
        let smartAccount = "CAZJ3UVRY3R3S5C5BH32GMYBRSN23N75ZEEXEOLXOUUAHDFIMVP4AXUC"
        let target = DemoConfig.nativeTokenContract
        let destination = try KeyPair.generateRandomKeyPair().accountId
        let amount = "1"
        let reason = 3016 // a spending-limit policy rejection code

        let encodedArgs = try Self.buildAgentTransferArgs(
            smartAccount: smartAccount,
            destination: destination,
            amount: amount
        )

        // (a) POST the agent-shaped escalation via a raw URLSession request,
        // byte-for-byte the reference agent's HttpCoordinationClient.createRequest
        // body ({ smartAccount, target, targetFn, args:[base64], reason, amount }).
        let created = try await Self.postEscalation(
            to: server.baseURL,
            token: token,
            smartAccount: smartAccount,
            target: target,
            targetFn: "transfer",
            args: encodedArgs,
            amount: amount,
            reason: reason
        )
        let requestId = created.id
        #expect(!requestId.isEmpty)
        #expect(created.status == CoordinationRequest.statusPending)

        // (b) The demo's real client lists the pending request with its fields
        // and decoded call arguments intact.
        let pending = try await client.listPending()
        let matches = pending.filter { $0.id == requestId }
        #expect(matches.count == 1, "escalation not found in listPending")
        let request = try #require(matches.first)
        #expect(request.smartAccount == smartAccount)
        #expect(request.target == target)
        #expect(request.targetFn == "transfer")
        #expect(request.amount == amount)
        #expect(request.reason == reason)
        #expect(request.status == CoordinationRequest.statusPending)
        #expect(request.isResolved == false)

        // The args round-trip verbatim and decode to the original call: two
        // addresses and the i128 amount the inbox would re-submit.
        #expect(request.args == encodedArgs)
        let decoded = try request.args.map { try SCValXDR.fromXdr(base64: $0) }
        #expect(decoded.count == 3)
        #expect(Self.isAddress(decoded[0]))
        #expect(Self.isAddress(decoded[1]))
        let expectedBaseUnits = try OZTransactionOperations.amountToBaseUnits(
            amount,
            decimals: Int(DemoConfig.demoTokenDecimals)
        )
        #expect(Self.i128String(decoded[2]) == expectedBaseUnits)

        // (c) Approve through the real client with a sample result hash.
        let resultHash =
            "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
        let approved = try await client.approve(requestId, resultHash: resultHash)
        #expect(approved.status == CoordinationRequest.statusApproved)
        #expect(approved.resultHash == resultHash)
        #expect(approved.isResolved == true)

        // (d) A fresh fetch shows it approved and resolved (the agent's poll).
        let polled = try await client.getRequest(requestId)
        #expect(polled.status == CoordinationRequest.statusApproved)
        #expect(polled.resultHash == resultHash)
        #expect(polled.resolvedAt != nil)
        #expect(polled.isResolved == true)

        // It is no longer pending in the inbox.
        let afterApproval = try await client.listPending()
        #expect(afterApproval.contains { $0.id == requestId } == false)
    }

    // -------------------------------------------------------------------------
    // MARK: - Reject path
    // -------------------------------------------------------------------------

    @Test("agent escalation can be rejected with a note")
    func rejectPath() async throws {
        let server = try await CoordinationServerProcess.start(token: token)
        defer { server.stop() }

        let client = URLSessionCoordinationClient(
            baseURL: server.baseURL,
            token: token,
            session: Self.makeSession()
        )

        let smartAccount = "CAZJ3UVRY3R3S5C5BH32GMYBRSN23N75ZEEXEOLXOUUAHDFIMVP4AXUC"
        let target = DemoConfig.nativeTokenContract
        let destination = try KeyPair.generateRandomKeyPair().accountId
        let amount = "2.5"
        let reason = 3016

        let encodedArgs = try Self.buildAgentTransferArgs(
            smartAccount: smartAccount,
            destination: destination,
            amount: amount
        )

        let created = try await Self.postEscalation(
            to: server.baseURL,
            token: token,
            smartAccount: smartAccount,
            target: target,
            targetFn: "transfer",
            args: encodedArgs,
            amount: amount,
            reason: reason
        )
        let requestId = created.id
        #expect(created.status == CoordinationRequest.statusPending)

        // Reject through the real client with a note.
        let note = "Recipient not on the allowlist."
        let rejected = try await client.reject(requestId, note: note)
        #expect(rejected.status == CoordinationRequest.statusRejected)
        #expect(rejected.note == note)
        #expect(rejected.resultHash == nil)
        #expect(rejected.isResolved == true)

        // A fresh fetch confirms the terminal state and the note (the agent's poll).
        let polled = try await client.getRequest(requestId)
        #expect(polled.status == CoordinationRequest.statusRejected)
        #expect(polled.note == note)
        #expect(polled.resolvedAt != nil)
        #expect(polled.isResolved == true)

        // It is no longer pending in the inbox.
        let afterRejection = try await client.listPending()
        #expect(afterRejection.contains { $0.id == requestId } == false)
    }

    // -------------------------------------------------------------------------
    // MARK: - Agent payload construction
    // -------------------------------------------------------------------------

    /// Builds the base64-encoded `SCValXDR` `transfer(from, to, amount)` vector
    /// exactly as the reference agent's `AgentRunner.buildTransferArgs` does, so
    /// the POST body is byte-for-byte an agent escalation.
    static func buildAgentTransferArgs(
        smartAccount: String,
        destination: String,
        amount: String
    ) throws -> [String] {
        let baseUnits = try OZTransactionOperations.amountToBaseUnits(
            amount,
            decimals: Int(DemoConfig.demoTokenDecimals)
        )
        let args: [SCValXDR] = [
            try addressSCVal(smartAccount),
            try addressSCVal(destination),
            try SCValXDR.i128(stringValue: baseUnits),
        ]
        return try args.map { arg in
            guard let encoded = arg.xdrEncoded else {
                throw CoordinationError(message: "Failed to base64-encode a transfer argument.")
            }
            return encoded
        }
    }

    /// `address` `SCValXDR` from a `G…` or `C…` strkey, mirroring the agent.
    static func addressSCVal(_ strKey: String) throws -> SCValXDR {
        if strKey.hasPrefix("C") {
            return .address(try SCAddressXDR(contractId: strKey))
        }
        return .address(try SCAddressXDR(accountId: strKey))
    }

    static func isAddress(_ value: SCValXDR) -> Bool {
        if case .address = value { return true }
        return false
    }

    /// Decodes a signed `i128` `SCValXDR` back to its decimal string.
    static func i128String(_ value: SCValXDR) -> String? {
        guard case .i128(let parts) = value else { return nil }
        let combined = (Int128(parts.hi) << 64) + Int128(parts.lo)
        return String(combined)
    }

    // -------------------------------------------------------------------------
    // MARK: - Raw POST (agent side of the contract)
    // -------------------------------------------------------------------------

    /// POSTs an escalation to `POST /requests` with the agent's exact JSON body
    /// and returns the decoded created record. Asserts HTTP 201.
    static func postEscalation(
        to baseURL: String,
        token: String,
        smartAccount: String,
        target: String,
        targetFn: String,
        args: [String],
        amount: String,
        reason: Int
    ) async throws -> CoordinationRequest {
        let url = try #require(URL(string: "\(baseURL)/requests"))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = [
            "smartAccount": smartAccount,
            "target": target,
            "targetFn": targetFn,
            "args": args,
            "reason": reason,
            "amount": amount,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await makeSession().data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        #expect(
            http.statusCode == 201,
            "POST /requests returned \(http.statusCode): \(String(decoding: data, as: UTF8.self))"
        )
        return try JSONDecoder().decode(CoordinationRequest.self, from: data)
    }

    /// A short-timeout ephemeral session so a hung loopback request fails the
    /// test rather than wedging the run.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
    }
}

// ============================================================================
// MARK: - CoordinationServerProcess
// ============================================================================

/// A `coordination-server` child process bound to a loopback ephemeral port.
///
/// Builds the package with `swift build`, launches the produced binary on a
/// reserved free port with a temp store, and blocks until `/health` answers
/// `200`. The caller must [stop] it (a `defer` in each test) to terminate the
/// subprocess and remove its temp store.
final class CoordinationServerProcess: @unchecked Sendable {

    private let process: Process
    private let storeDir: URL
    private let logURL: URL

    /// The loopback port the server bound to.
    let port: UInt16

    /// Loopback base URL for HTTP calls.
    var baseURL: String { "http://127.0.0.1:\(port)" }

    private init(process: Process, port: UInt16, storeDir: URL, logURL: URL) {
        self.process = process
        self.port = port
        self.storeDir = storeDir
        self.logURL = logURL
    }

    /// Builds and starts the server, resolving once it answers `/health`.
    static func start(token: String) async throws -> CoordinationServerProcess {
        let swift = try resolveSwiftExecutable()
        let serverDir = coordinationServerDirectory()

        // Build the package once up front so the launch step runs the binary
        // directly rather than going through `swift run` (which would rebuild).
        try buildPackage(swift: swift, packageDir: serverDir)
        let binary = try binaryURL(swift: swift, packageDir: serverDir)

        let storeDir = try makeTempDirectory()
        let storePath = storeDir.appendingPathComponent("requests.store.json")
        let logURL = storeDir.appendingPathComponent("server.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)

        let port = try reserveEphemeralPort()

        let process = Process()
        process.executableURL = binary
        process.arguments = [
            "--port", String(port),
            "--token", token,
            "--store", storePath.path,
        ]
        process.standardOutput = logHandle
        process.standardError = logHandle

        do {
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: storeDir)
            throw CoordinationError(
                message: "Failed to launch coordination-server at \(binary.path): \(error)"
            )
        }

        let server = CoordinationServerProcess(
            process: process,
            port: port,
            storeDir: storeDir,
            logURL: logURL
        )
        do {
            try await server.awaitHealthy()
        } catch {
            server.stop()
            throw error
        }
        return server
    }

    /// Polls `/health` until it answers `200` or a deadline passes. Fails fast
    /// if the process exits before becoming healthy.
    private func awaitHealthy() async throws {
        let session = CoordinationE2ETests.makeSession()
        let healthURL = URL(string: "\(baseURL)/health")!
        let deadline = Date().addingTimeInterval(30)

        while Date() < deadline {
            if !process.isRunning {
                throw CoordinationError(
                    message: "coordination-server exited early (code "
                        + "\(process.terminationStatus)) before binding.\n\(readLog())"
                )
            }
            var request = URLRequest(url: healthURL)
            request.timeoutInterval = 2
            if let (_, response) = try? await session.data(for: request),
               let http = response as? HTTPURLResponse,
               http.statusCode == 200 {
                return
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw CoordinationError(
            message: "coordination-server did not become healthy on \(baseURL).\n\(readLog())"
        )
    }

    /// Terminates the subprocess (SIGTERM, escalating to SIGKILL) and removes
    /// the temp store. Idempotent.
    func stop() {
        if process.isRunning {
            process.terminate()
            if !waitForExit(within: 5) {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
        }
        try? FileManager.default.removeItem(at: storeDir)
    }

    /// Synchronously waits up to `seconds` for the process to exit.
    private func waitForExit(within seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if !process.isRunning { return true }
            usleep(50_000)
        }
        return !process.isRunning
    }

    private func readLog() -> String {
        (try? String(contentsOf: logURL, encoding: .utf8)) ?? "(no server output captured)"
    }

    // -------------------------------------------------------------------------
    // MARK: - Build and launch helpers
    // -------------------------------------------------------------------------

    /// Builds the package in debug, throwing with captured output on failure.
    private static func buildPackage(swift: URL, packageDir: URL) throws {
        let result = try runCapturing(
            executable: swift,
            arguments: ["build", "--package-path", packageDir.path]
        )
        guard result.status == 0 else {
            throw CoordinationError(
                message: "`swift build` for coordination_server failed "
                    + "(exit \(result.status)):\n\(result.output)"
            )
        }
    }

    /// Resolves the built `coordination-server` binary via `--show-bin-path`.
    private static func binaryURL(swift: URL, packageDir: URL) throws -> URL {
        let result = try runCapturing(
            executable: swift,
            arguments: ["build", "--package-path", packageDir.path, "--show-bin-path"]
        )
        guard result.status == 0 else {
            throw CoordinationError(
                message: "`swift build --show-bin-path` failed "
                    + "(exit \(result.status)):\n\(result.output)"
            )
        }
        let binDir = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let binary = URL(fileURLWithPath: binDir).appendingPathComponent("coordination-server")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            throw CoordinationError(
                message: "coordination-server binary not found at \(binary.path)."
            )
        }
        return binary
    }

    /// Runs `executable` to completion, capturing merged stdout+stderr.
    private static func runCapturing(
        executable: URL,
        arguments: [String]
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        // Drain before waiting to avoid a full-pipe deadlock on large output.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// Resolves the active toolchain's `swift` via `xcrun --find swift`.
    private static func resolveSwiftExecutable() throws -> URL {
        let result = try runCapturing(
            executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["--find", "swift"]
        )
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.status == 0, !path.isEmpty,
              FileManager.default.isExecutableFile(atPath: path) else {
            throw CoordinationError(
                message: "Could not resolve the swift executable via xcrun: \(result.output)"
            )
        }
        return URL(fileURLWithPath: path)
    }

    /// `<repo-root>/coordination_server`, derived from this source file's path.
    ///
    /// This file lives at `Tests/NetworkTests/CoordinationE2ETests.swift`, so the
    /// repo root is three directories up.
    private static func coordinationServerDirectory() -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent() // NetworkTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        return repoRoot.appendingPathComponent("coordination_server")
    }

    private static func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("coordination_e2e_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Reserves a free loopback TCP port by binding to port 0, reading the
    /// OS-assigned port, then releasing the socket for the server to rebind.
    static func reserveEphemeralPort() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw CoordinationError(message: "socket() failed reserving an ephemeral port.")
        }
        defer { close(fd) }

        var reuse: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        let bindStatus = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindStatus == 0 else {
            throw CoordinationError(message: "bind() to 127.0.0.1:0 failed.")
        }

        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameStatus = withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getsockname(fd, sa, &length)
            }
        }
        guard nameStatus == 0 else {
            throw CoordinationError(message: "getsockname() failed reserving an ephemeral port.")
        }
        return UInt16(bigEndian: bound.sin_port)
    }
}

#endif
