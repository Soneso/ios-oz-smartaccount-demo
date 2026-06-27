// Copyright 2026 Soneso. Reference agent for the OZ smart-account demo.

import Foundation
import Testing
import stellarsdk

@testable import ReferenceAgentCore

/// A fresh, valid raw 32-byte agent seed as 64-character hex.
private func validSeedHex() throws -> String {
    try #require(try resolveAgentKey().secretSeedHex)
}

@Suite("AgentConfig defaults")
struct AgentConfigDefaultsTests {

    @Test("a bare config carries the demo testnet defaults")
    func bareConfigDefaults() {
        let config = AgentConfig()
        #expect(config.rpcUrl == AgentDefaults.rpcUrl)
        #expect(config.networkPassphrase == AgentDefaults.networkPassphrase)
        #expect(config.accountWasmHash == AgentDefaults.accountWasmHash)
        #expect(config.webauthnVerifierAddress == AgentDefaults.webauthnVerifierAddress)
        #expect(config.ed25519VerifierAddress == AgentDefaults.ed25519VerifierAddress)
        #expect(config.relayerUrl == AgentDefaults.relayerUrl)
        #expect(config.tokenContractId == AgentDefaults.nativeTokenContract)
        #expect(config.tokenDecimals == 7)
        #expect(config.coordinationBaseUrl == AgentDefaults.coordinationBaseUrl)
        #expect(config.coordinationToken == AgentDefaults.coordinationToken)
        // Per-run identity values have no default.
        #expect(config.smartAccountContractId == nil)
        #expect(config.isCompleteForLiveRun == false)
    }

    @Test("description redacts the seed and coordination token")
    func descriptionRedacts() throws {
        let config = AgentConfig(
            agentSecretSeed: try validSeedHex(),
            coordinationToken: "super-secret"
        )
        let text = config.description
        #expect(text.contains("agentSecretSeed: ***"))
        #expect(text.contains("coordinationToken: ***"))
        #expect(!text.contains("super-secret"))
    }
}

@Suite("AgentConfig resolve precedence")
struct AgentConfigResolveTests {

    @Test("empty inputs fall back to defaults")
    func emptyFallsBack() throws {
        let config = try AgentConfig.resolve(env: [:])
        #expect(config.rpcUrl == AgentDefaults.rpcUrl)
        #expect(config.smartAccountContractId == nil)
    }

    @Test("environment overrides defaults")
    func envOverrides() throws {
        let config = try AgentConfig.resolve(env: [
            "AGENT_RPC_URL": "https://env.example/rpc",
            "AGENT_SMART_ACCOUNT": "CENV",
            "AGENT_AMOUNT": "42",
            "AGENT_POLL_INTERVAL_SECONDS": "7",
        ])
        #expect(config.rpcUrl == "https://env.example/rpc")
        #expect(config.smartAccountContractId == "CENV")
        #expect(config.amount == "42")
        #expect(config.pollInterval == .seconds(7))
    }

    @Test("args override environment")
    func argsOverrideEnv() throws {
        let config = try AgentConfig.resolve(
            args: ["--rpc-url=https://arg.example/rpc", "--amount", "9"],
            env: [
                "AGENT_RPC_URL": "https://env.example/rpc",
                "AGENT_AMOUNT": "42",
            ]
        )
        #expect(config.rpcUrl == "https://arg.example/rpc")
        #expect(config.amount == "9")
    }

    @Test("json file sits below env and args but above defaults")
    func jsonPrecedence() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("agent.json")
        let json = """
            {"rpcUrl":"https://json.example/rpc","tokenContractId":"CJSONTOKEN","amount":"100"}
            """
        try json.write(to: file, atomically: true, encoding: .utf8)

        let config = try AgentConfig.resolve(
            args: ["--amount=5"],
            env: [:],
            jsonPath: file.path
        )
        // json wins over default for rpcUrl and token...
        #expect(config.rpcUrl == "https://json.example/rpc")
        #expect(config.tokenContractId == "CJSONTOKEN")
        // ...but the CLI arg wins over json for amount.
        #expect(config.amount == "5")
    }

    @Test("config path from args overrides the env config path")
    func argsConfigPathWins() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let argFile = dir.appendingPathComponent("from-arg.json")
        try "{\"rpcUrl\":\"https://from-arg/rpc\"}".write(to: argFile, atomically: true, encoding: .utf8)

        let config = try AgentConfig.resolve(
            args: ["--config=\(argFile.path)"],
            env: ["AGENT_CONFIG_FILE": "/no/such/file.json"]
        )
        #expect(config.rpcUrl == "https://from-arg/rpc")
    }

    @Test("non-integer poll interval is rejected")
    func nonIntegerPollRejected() {
        #expect(throws: AgentConfigError.self) {
            try AgentConfig.resolve(env: ["AGENT_POLL_INTERVAL_SECONDS": "soon"])
        }
    }

    @Test("missing config file path is rejected")
    func missingConfigRejected() {
        #expect(throws: AgentConfigError.self) {
            try AgentConfig.resolve(env: [:], jsonPath: "/no/such/file.json")
        }
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent_cfg_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

@Suite("AgentConfig validateForLiveRun")
struct AgentConfigValidateTests {

    private func completeConfig() throws -> AgentConfig {
        AgentConfig(
            smartAccountContractId: AgentDefaults.nativeTokenContract,
            agentSecretSeed: try validSeedHex(),
            destinationAddress: try KeyPair.generateRandomKeyPair().accountId
        )
    }

    @Test("passes for a complete configuration")
    func completePasses() throws {
        let config = try completeConfig()
        #expect(config.isCompleteForLiveRun)
        try config.validateForLiveRun()
    }

    @Test("requires the smart account")
    func requiresSmartAccount() throws {
        let bad = try completeConfig().with(smartAccountContractId: .some(""))
        #expect(throws: AgentConfigError.self) {
            try bad.validateForLiveRun()
        }
    }

    @Test("rejects a non-hex agent seed")
    func rejectsNonHexSeed() throws {
        let bad = AgentConfig(
            smartAccountContractId: AgentDefaults.nativeTokenContract,
            agentSecretSeed: "not-a-seed",
            destinationAddress: try KeyPair.generateRandomKeyPair().accountId
        )
        #expect(throws: AgentConfigError.self) {
            try bad.validateForLiveRun()
        }
    }

    @Test("rejects a wrong-length hex agent seed")
    func rejectsWrongLengthSeed() throws {
        // Valid hex but 62 characters — one byte short of a 32-byte seed.
        let bad = try completeConfig().with(agentSecretSeed: .some(String(repeating: "a", count: 62)))
        #expect(throws: AgentConfigError.self) {
            try bad.validateForLiveRun()
        }
    }

    @Test("rejects an invalid destination address")
    func rejectsInvalidDestination() throws {
        let bad = try completeConfig().with(destinationAddress: .some("nonsense"))
        #expect(throws: AgentConfigError.self) {
            try bad.validateForLiveRun()
        }
    }

    @Test("accepts a contract destination address")
    func acceptsContractDestination() throws {
        let ok = try completeConfig().with(destinationAddress: .some(AgentDefaults.nativeTokenContract))
        try ok.validateForLiveRun()
    }
}
