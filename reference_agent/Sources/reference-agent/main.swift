// Copyright 2026 Soneso. Reference agent for the OZ smart-account demo.
//
// Command-line entry point. Three modes, selected by environment gates:
//
//   - AGENT_PRINT_KEY=true (or --print-key): bootstrap keygen. Derives or
//     generates the agent's Ed25519 identity and prints the `[agent] [KEY]`
//     lines. Needs no other configuration.
//
//       AGENT_PRINT_KEY=true swift run reference-agent
//       AGENT_PRINT_KEY=true AGENT_SECRET_SEED=<64-hex> swift run reference-agent
//
//   - AGENT_RUN_LIVE=true with a complete live config: runs one full agent
//     cycle against testnet and a running coordination server.
//
//       AGENT_RUN_LIVE=true \
//       AGENT_SMART_ACCOUNT=C... \
//       AGENT_SECRET_SEED=<64-hex> \
//       AGENT_DESTINATION=G... \
//       AGENT_COORDINATION_URL=http://localhost:8787 \
//       AGENT_COORDINATION_TOKEN=dev-token-change-me \
//       swift run reference-agent
//
//   - Otherwise: prints usage and exits without touching the network.

import Foundation
import ReferenceAgentCore

let arguments = Array(CommandLine.arguments.dropFirst())
let environment = ProcessInfo.processInfo.environment
let logger = StdoutAgentLogger()

func printKeyLines(_ result: AgentKeyResult) {
    for line in formatAgentKeyOutput(result) {
        print("[agent] [KEY] \(line)")
    }
}

func runLiveRequested() -> Bool {
    (environment["AGENT_RUN_LIVE"] ?? "").lowercased() == "true"
}

func printUsage() {
    print(
        """
        reference-agent — autonomous OZ smart-account agent.

        Modes (selected by environment gates):
          AGENT_PRINT_KEY=true   Print the agent Ed25519 identity (keygen bootstrap).
                                 Optionally set AGENT_SECRET_SEED=<64-hex> to derive
                                 the public key for a seed you already hold.
          AGENT_RUN_LIVE=true    Run one full agent cycle. Requires a complete live
                                 config: AGENT_SMART_ACCOUNT, AGENT_SECRET_SEED,
                                 AGENT_DESTINATION, AGENT_COORDINATION_URL,
                                 AGENT_COORDINATION_TOKEN.

        Without a gate this usage is printed and nothing else happens.
        """
    )
}

if shouldPrintAgentKey(env: environment, args: arguments) {
    do {
        let result = try resolveAgentKey(seed: environment["AGENT_SECRET_SEED"])
        printKeyLines(result)
    } catch {
        logger.error("Failed to resolve agent key: \(error)")
        exit(1)
    }
} else if runLiveRequested() {
    do {
        let config = try AgentConfig.resolve(args: arguments, env: environment)
        // Agent.fromConfig validates the config before any allocation, so no
        // separate validateForLiveRun call is needed here.
        let agent = try Agent.fromConfig(config, logger: logger)
        let result = try await agent.run()
        await agent.dispose()
        logger.info("Agent result: \(result)")
    } catch {
        logger.error("Live run failed: \(error)")
        exit(1)
    }
} else {
    printUsage()
}
