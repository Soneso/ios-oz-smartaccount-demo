// Copyright 2026 Soneso. Reference agent for the OZ smart-account demo.

import Foundation
import stellarsdk

/// Static testnet defaults shared by every reference-agent run.
///
/// Every value mirrors a constant already published in the demo app's
/// configuration (or the coordination server README). They are testnet-only,
/// public by design, and safe to ship as defaults. Per-run identity values
/// (smart account, agent seed, destination) have no static default and must be
/// supplied explicitly.
public enum AgentDefaults {

    /// Soroban RPC endpoint for testnet.
    public static let rpcUrl = "https://soroban-testnet.stellar.org"

    /// Stellar testnet network passphrase.
    public static let networkPassphrase = "Test SDF Network ; September 2015"

    /// WASM hash of the multisig smart-account contract deployed on testnet.
    public static let accountWasmHash =
        "86b49fe03f7df0ad1c2a28bd8361b923ab57096e09f397f92f0c00ae3bd06d28"

    /// WebAuthn (secp256r1) signature verifier contract address. Required by
    /// `OZSmartAccountConfig` even though the headless agent never signs with a
    /// passkey.
    public static let webauthnVerifierAddress =
        "CB26VN37RCVNTHJZDEPK6IRO2MMTS3Z2IEO5JD5BINY2OOJ5KKJG7NKY"

    /// Ed25519 signature verifier contract address. The agent registers as an
    /// `External(ed25519VerifierAddress, publicKey)` signer under this verifier.
    public static let ed25519VerifierAddress =
        "CAW2Z46INPO5VIJEILMYSSEOLBVJIIII5GOE3TN5EUURSRM2FJCF7AJ6"

    /// Relayer proxy for fee-sponsored (gasless) submission. The empty string
    /// disables the relayer and submits directly via the RPC endpoint.
    public static let relayerUrl =
        "https://smart-account-relayer-proxy.soneso.workers.dev"

    /// XLM native token Stellar Asset Contract (SAC) on testnet. Used as the
    /// default scoped-call target token.
    public static let nativeTokenContract =
        "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"

    /// Decimal scale used when converting the human-readable `AgentConfig.amount`
    /// to base units (7 = same scale as XLM and the DEMO token).
    public static let tokenDecimals = 7

    /// Default human-readable transfer amount.
    public static let amount = "1"

    /// Coordination server base URL. Matches the server's default bind port.
    public static let coordinationBaseUrl = "http://localhost:8787"

    /// Coordination server bearer token. Matches the server README's documented
    /// development token. Override in any shared or deployed environment.
    public static let coordinationToken = "dev-token-change-me"

    /// Seconds between successive escalation polls.
    public static let pollIntervalSeconds = 3

    /// Maximum number of escalation polls before the agent gives up waiting.
    public static let pollMaxAttempts = 40

    /// Known testnet policy contracts, by policy type. Informational reference
    /// for operators wiring up the step-2 delegation flow; the agent does not
    /// install policies itself.
    public static let knownPolicies: [String: String] = [
        "threshold": "CAZJ3UVRY3R3S5C5BH32GMYBRSN23N75ZEEXEOLXOUUAHDFIMVP4AXUC",
        "spendingLimit": "CBQE7L3UNP5IR4I7IBKLS7NV256WHR5TTH26HTMUIK7WXJC6J64RSE2L",
        "weightedThreshold": "CAF4OCRIB73T5777UWAQS7KGOG6WVIZ3EFXNNUYSPFSBKW2Q5XEIOSPW",
    ]
}

/// Thrown when an `AgentConfig` cannot satisfy the requirements of a live run.
public struct AgentConfigError: Error, CustomStringConvertible, Sendable {

    /// Human-readable description of the configuration problem.
    public let message: String

    /// Constructs a config error with a user-facing [message].
    public init(_ message: String) {
        self.message = message
    }

    public var description: String { "AgentConfigError: \(message)" }
}

/// Immutable configuration for a single reference-agent run.
///
/// Construct directly for tests, or via `AgentConfig.resolve` to layer
/// command-line arguments over environment variables over an optional JSON file
/// over the `AgentDefaults`. Precedence, highest first:
/// CLI args > environment > JSON file > defaults.
public struct AgentConfig: Sendable, Equatable {

    /// Soroban RPC endpoint URL.
    public let rpcUrl: String

    /// Stellar network passphrase.
    public let networkPassphrase: String

    /// 64-character hex WASM hash of the smart-account contract.
    public let accountWasmHash: String

    /// WebAuthn signature verifier contract address (C-address).
    public let webauthnVerifierAddress: String

    /// Ed25519 signature verifier contract address (C-address).
    public let ed25519VerifierAddress: String

    /// Relayer URL for gasless submission; the empty string disables it.
    public let relayerUrl: String

    /// Contract address of the token the agent calls (`transfer`).
    public let tokenContractId: String

    /// Decimal scale of `tokenContractId` used for amount conversion.
    public let tokenDecimals: Int

    /// Human-readable transfer amount (decimal string, e.g. `"1"` or `"10.5"`).
    public let amount: String

    /// Deployed smart-account contract address (C-address). Required for a live
    /// run.
    public let smartAccountContractId: String?

    /// Agent Ed25519 secret seed as raw 64-character hex (32 bytes). Required
    /// for a live run.
    public let agentSecretSeed: String?

    /// Transfer recipient address (G- or C-address). Required for a live
    /// `transfer` call.
    public let destinationAddress: String?

    /// Coordination server base URL.
    public let coordinationBaseUrl: String

    /// Coordination server bearer token.
    public let coordinationToken: String

    /// Delay between escalation polls.
    public let pollInterval: Duration

    /// Maximum escalation polls before the agent stops waiting.
    public let pollMaxAttempts: Int

    /// Constructs a configuration. Static network values fall back to
    /// `AgentDefaults`; per-run identity values default to `nil` and must be
    /// supplied for a live run (see `validateForLiveRun`).
    public init(
        rpcUrl: String = AgentDefaults.rpcUrl,
        networkPassphrase: String = AgentDefaults.networkPassphrase,
        accountWasmHash: String = AgentDefaults.accountWasmHash,
        webauthnVerifierAddress: String = AgentDefaults.webauthnVerifierAddress,
        ed25519VerifierAddress: String = AgentDefaults.ed25519VerifierAddress,
        relayerUrl: String = AgentDefaults.relayerUrl,
        tokenContractId: String = AgentDefaults.nativeTokenContract,
        tokenDecimals: Int = AgentDefaults.tokenDecimals,
        amount: String = AgentDefaults.amount,
        smartAccountContractId: String? = nil,
        agentSecretSeed: String? = nil,
        destinationAddress: String? = nil,
        coordinationBaseUrl: String = AgentDefaults.coordinationBaseUrl,
        coordinationToken: String = AgentDefaults.coordinationToken,
        pollInterval: Duration = .seconds(AgentDefaults.pollIntervalSeconds),
        pollMaxAttempts: Int = AgentDefaults.pollMaxAttempts
    ) {
        self.rpcUrl = rpcUrl
        self.networkPassphrase = networkPassphrase
        self.accountWasmHash = accountWasmHash
        self.webauthnVerifierAddress = webauthnVerifierAddress
        self.ed25519VerifierAddress = ed25519VerifierAddress
        self.relayerUrl = relayerUrl
        self.tokenContractId = tokenContractId
        self.tokenDecimals = tokenDecimals
        self.amount = amount
        self.smartAccountContractId = smartAccountContractId
        self.agentSecretSeed = agentSecretSeed
        self.destinationAddress = destinationAddress
        self.coordinationBaseUrl = coordinationBaseUrl
        self.coordinationToken = coordinationToken
        self.pollInterval = pollInterval
        self.pollMaxAttempts = pollMaxAttempts
    }

    /// Whether every value required for a live, end-to-end run is present.
    public var isCompleteForLiveRun: Bool {
        do {
            try validateForLiveRun()
            return true
        } catch {
            return false
        }
    }

    /// Validates that the per-run identity values are present and well-formed.
    ///
    /// Throws `AgentConfigError` describing the first problem found.
    public func validateForLiveRun() throws {
        guard let smartAccount = smartAccountContractId, !smartAccount.isEmpty else {
            throw AgentConfigError("smartAccountContractId is required.")
        }
        if !smartAccount.isValidContractId() {
            throw AgentConfigError(
                "smartAccountContractId is not a valid contract address: \(smartAccount)"
            )
        }

        guard let seed = agentSecretSeed, !seed.isEmpty else {
            throw AgentConfigError("agentSecretSeed is required.")
        }
        if seed.count != agentHexKeyLength || !Hex.isHexString(seed) {
            throw AgentConfigError(
                "agentSecretSeed is not a valid 64-character hex Ed25519 seed."
            )
        }

        guard let destination = destinationAddress, !destination.isEmpty else {
            throw AgentConfigError("destinationAddress is required.")
        }
        if !destination.isValidEd25519PublicKey() && !destination.isValidContractId() {
            throw AgentConfigError(
                "destinationAddress is not a valid G- or C-address: \(destination)"
            )
        }

        if !ed25519VerifierAddress.isValidContractId() {
            throw AgentConfigError(
                "ed25519VerifierAddress is not a valid contract address: \(ed25519VerifierAddress)"
            )
        }
        if !tokenContractId.isValidContractId() {
            throw AgentConfigError(
                "tokenContractId is not a valid contract address: \(tokenContractId)"
            )
        }
        if coordinationBaseUrl.isEmpty {
            throw AgentConfigError("coordinationBaseUrl is required.")
        }
        if coordinationToken.isEmpty {
            throw AgentConfigError("coordinationToken is required.")
        }
        if pollMaxAttempts < 0 {
            throw AgentConfigError(
                "pollMaxAttempts must be zero or greater, got: \(pollMaxAttempts)."
            )
        }
        if pollInterval < .zero {
            throw AgentConfigError("pollInterval must be zero or greater.")
        }
    }

    /// Returns a copy of this configuration with the given fields replaced.
    public func with(
        rpcUrl: String? = nil,
        networkPassphrase: String? = nil,
        accountWasmHash: String? = nil,
        webauthnVerifierAddress: String? = nil,
        ed25519VerifierAddress: String? = nil,
        relayerUrl: String? = nil,
        tokenContractId: String? = nil,
        tokenDecimals: Int? = nil,
        amount: String? = nil,
        smartAccountContractId: String?? = nil,
        agentSecretSeed: String?? = nil,
        destinationAddress: String?? = nil,
        coordinationBaseUrl: String? = nil,
        coordinationToken: String? = nil,
        pollInterval: Duration? = nil,
        pollMaxAttempts: Int? = nil
    ) -> AgentConfig {
        AgentConfig(
            rpcUrl: rpcUrl ?? self.rpcUrl,
            networkPassphrase: networkPassphrase ?? self.networkPassphrase,
            accountWasmHash: accountWasmHash ?? self.accountWasmHash,
            webauthnVerifierAddress: webauthnVerifierAddress ?? self.webauthnVerifierAddress,
            ed25519VerifierAddress: ed25519VerifierAddress ?? self.ed25519VerifierAddress,
            relayerUrl: relayerUrl ?? self.relayerUrl,
            tokenContractId: tokenContractId ?? self.tokenContractId,
            tokenDecimals: tokenDecimals ?? self.tokenDecimals,
            amount: amount ?? self.amount,
            smartAccountContractId: smartAccountContractId ?? self.smartAccountContractId,
            agentSecretSeed: agentSecretSeed ?? self.agentSecretSeed,
            destinationAddress: destinationAddress ?? self.destinationAddress,
            coordinationBaseUrl: coordinationBaseUrl ?? self.coordinationBaseUrl,
            coordinationToken: coordinationToken ?? self.coordinationToken,
            pollInterval: pollInterval ?? self.pollInterval,
            pollMaxAttempts: pollMaxAttempts ?? self.pollMaxAttempts
        )
    }

    /// Resolves a configuration by layering, highest precedence first:
    /// [args] (`--kebab-key=value`) > [env] (`AGENT_UPPER_SNAKE`) > the JSON
    /// file at `--config`/`AGENT_CONFIG_FILE`/[jsonPath] > `AgentDefaults`.
    ///
    /// The JSON file, when present, must decode to a JSON object whose keys are
    /// the camelCase field names.
    public static func resolve(
        args: [String] = [],
        env: [String: String] = ProcessInfo.processInfo.environment,
        jsonPath: String? = nil
    ) throws -> AgentConfig {
        let argMap = parseArgs(args)

        let resolvedJsonPath = argMap["config"] ?? env["AGENT_CONFIG_FILE"] ?? jsonPath
        let json: [String: Any]
        if let path = resolvedJsonPath {
            json = try readJsonFile(path)
        } else {
            json = [:]
        }

        func pick(_ argKey: String, _ envKey: String, _ jsonKey: String) -> String? {
            if let fromArg = argMap[argKey] { return fromArg }
            if let fromEnv = env[envKey] { return fromEnv }
            if let fromJson = json[jsonKey] { return stringify(fromJson) }
            return nil
        }

        func pickInt(_ argKey: String, _ envKey: String, _ jsonKey: String, _ fallback: Int) throws -> Int {
            guard let raw = pick(argKey, envKey, jsonKey) else { return fallback }
            guard let parsed = Int(raw) else {
                throw AgentConfigError("\(jsonKey) must be an integer, got: \(raw)")
            }
            return parsed
        }

        let pollSeconds = try pickInt(
            "poll-interval-seconds", "AGENT_POLL_INTERVAL_SECONDS", "pollIntervalSeconds",
            AgentDefaults.pollIntervalSeconds)

        return AgentConfig(
            rpcUrl: pick("rpc-url", "AGENT_RPC_URL", "rpcUrl") ?? AgentDefaults.rpcUrl,
            networkPassphrase: pick("network-passphrase", "AGENT_NETWORK_PASSPHRASE", "networkPassphrase")
                ?? AgentDefaults.networkPassphrase,
            accountWasmHash: pick("account-wasm-hash", "AGENT_ACCOUNT_WASM_HASH", "accountWasmHash")
                ?? AgentDefaults.accountWasmHash,
            webauthnVerifierAddress: pick("webauthn-verifier", "AGENT_WEBAUTHN_VERIFIER", "webauthnVerifierAddress")
                ?? AgentDefaults.webauthnVerifierAddress,
            ed25519VerifierAddress: pick("ed25519-verifier", "AGENT_ED25519_VERIFIER", "ed25519VerifierAddress")
                ?? AgentDefaults.ed25519VerifierAddress,
            relayerUrl: pick("relayer-url", "AGENT_RELAYER_URL", "relayerUrl") ?? AgentDefaults.relayerUrl,
            tokenContractId: pick("token-contract", "AGENT_TOKEN_CONTRACT", "tokenContractId")
                ?? AgentDefaults.nativeTokenContract,
            tokenDecimals: try pickInt("token-decimals", "AGENT_TOKEN_DECIMALS", "tokenDecimals", AgentDefaults.tokenDecimals),
            amount: pick("amount", "AGENT_AMOUNT", "amount") ?? AgentDefaults.amount,
            smartAccountContractId: pick("smart-account", "AGENT_SMART_ACCOUNT", "smartAccountContractId"),
            agentSecretSeed: pick("secret-seed", "AGENT_SECRET_SEED", "agentSecretSeed"),
            destinationAddress: pick("destination", "AGENT_DESTINATION", "destinationAddress"),
            coordinationBaseUrl: pick("coordination-url", "AGENT_COORDINATION_URL", "coordinationBaseUrl")
                ?? AgentDefaults.coordinationBaseUrl,
            coordinationToken: pick("coordination-token", "AGENT_COORDINATION_TOKEN", "coordinationToken")
                ?? AgentDefaults.coordinationToken,
            pollInterval: .seconds(pollSeconds),
            pollMaxAttempts: try pickInt("poll-max-attempts", "AGENT_POLL_MAX_ATTEMPTS", "pollMaxAttempts", AgentDefaults.pollMaxAttempts)
        )
    }

    /// Parses `--key=value` and `--key value` argument pairs into a map keyed by
    /// the kebab-case option name (without the leading `--`).
    static func parseArgs(_ args: [String]) -> [String: String] {
        var map = [String: String]()
        var i = 0
        while i < args.count {
            let arg = args[i]
            guard arg.hasPrefix("--") else {
                i += 1
                continue
            }
            let body = String(arg.dropFirst(2))
            if let eq = body.firstIndex(of: "=") {
                map[String(body[..<eq])] = String(body[body.index(after: eq)...])
            } else if i + 1 < args.count && !args[i + 1].hasPrefix("--") {
                map[body] = args[i + 1]
                i += 1
            } else {
                // A bare boolean-style flag; record its presence as "true".
                map[body] = "true"
            }
            i += 1
        }
        return map
    }

    /// Reads and decodes a JSON object from [path].
    static func readJsonFile(_ path: String) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: path) else {
            throw AgentConfigError("Config file not found: \(path)")
        }
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw AgentConfigError("Failed to read JSON config \(path): \(error)")
        }
        let decoded: Any
        do {
            decoded = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw AgentConfigError("Failed to parse JSON config \(path): \(error)")
        }
        guard let object = decoded as? [String: Any] else {
            throw AgentConfigError(
                "JSON config \(path) must decode to an object, got: \(type(of: decoded))"
            )
        }
        return object
    }

    /// Renders a JSON scalar as the string the layered resolver consumes (string,
    /// integer, double, or boolean), so a value from the JSON config carries the
    /// same parsing and precedence as the equivalent CLI argument or environment
    /// variable.
    private static func stringify(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let bool as Bool:
            return bool ? "true" : "false"
        case let number as NSNumber:
            // NSNumber bridges JSON numbers and booleans; the Bool case above
            // already intercepts true/false, so this is a numeric value.
            if number === kCFBooleanTrue || number === kCFBooleanFalse {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        default:
            return String(describing: value)
        }
    }
}

extension AgentConfig: CustomStringConvertible {
    /// Redacts the agent seed and bearer token so the config is safe to log.
    public var description: String {
        "AgentConfig(rpcUrl: \(rpcUrl), network: \(networkPassphrase), "
            + "smartAccount: \(smartAccountContractId ?? "nil"), "
            + "ed25519Verifier: \(ed25519VerifierAddress), "
            + "token: \(tokenContractId), amount: \(amount), "
            + "destination: \(destinationAddress ?? "nil"), "
            + "relayer: \(relayerUrl.isEmpty ? "(disabled)" : relayerUrl), "
            + "coordination: \(coordinationBaseUrl), "
            + "agentSecretSeed: \(agentSecretSeed == nil ? "nil" : "***"), "
            + "coordinationToken: ***, "
            + "pollInterval: \(pollInterval), pollMaxAttempts: \(pollMaxAttempts))"
    }
}
