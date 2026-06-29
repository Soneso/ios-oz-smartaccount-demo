# Agent-signer flow: end-to-end runbook

This is the authoritative guide for running the full agent-signer flow against
this iOS/macOS demo: an autonomous agent acts under a scoped, user-delegated
Ed25519 authority; its over-limit call is rejected on-chain; it escalates to a
coordination server; the user reviews and approves in the app; the call is
re-submitted under the user's Default rule; and the agent learns the outcome by
polling.

The subsystem is all-Swift. Three processes cooperate, and all of them are
Swift: a Hummingbird coordination server, a Swift reference agent run with
`swift run`, and the SwiftUI demo app (iOS and macOS). Read the component docs
for the detail behind each:

- Coordination server — [`coordination_server/README.md`](../coordination_server/README.md)
- Reference agent — [`reference_agent/README.md`](../reference_agent/README.md)

Everything below targets Stellar **testnet**. The agent's `AgentDefaults` and the
app's `DemoConfig` share the same testnet network, RPC, verifier, relayer, and
token defaults; they are testnet-only and public by design. Steps 2 and 4 are
device-only: they create the smart account, delegate to the agent, and approve
the escalation with a real passkey (WebAuthn), so they run on a simulator or
device by hand.

## Prerequisites

- A current Xcode and Swift 6 toolchain (macOS 15+ for the two SwiftPM
  packages).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen). The Xcode project is
  generated from `project.yml`; run `xcodegen generate` after any edit to it.
- **Temporary local-SDK override.** `connectToContract` (headless
  smart-account connect) and the auto-fund RPC-visibility poll fix that this
  flow depends on are only on the local SDK clone
  `../stellar-ios-mac-sdk`, branch `sa-improvements`; they are not in a
  published tag yet. `project.yml` therefore points the `stellarsdk` package at
  `path: ../stellar-ios-mac-sdk` (no `url`/`from`), and both SwiftPM packages
  path-depend on the same clone (`reference_agent` →
  `.package(path: "../../stellar-ios-mac-sdk")`). This override is temporary and
  must be switched back to a published `stellarsdk` version before release.
  After changing `project.yml`, run `xcodegen generate` and confirm the app
  still builds.

Build commands for reference:

```sh
# App (iOS simulator)
xcodebuild -project SmartAccountDemo.xcodeproj -scheme SmartAccountDemo \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

# App (macOS)
xcodebuild -project SmartAccountDemo.xcodeproj -scheme SmartAccountDemoMac \
  -destination 'platform=macOS' build

# Packages: from coordination_server/ and reference_agent/
swift build   # swift test / swift run <exe>
```

## Shared configuration

Every value below must agree across the three processes or the flow breaks. The
static network/verifier/token values already share a default between the agent's
`AgentDefaults` and the app's `DemoConfig`; the per-run identity values are
produced during the flow and copied between processes.

| Value | Coordination server | Reference agent | Demo app | Must agree because |
|-------|---------------------|-----------------|----------|--------------------|
| Coordination URL | binds `0.0.0.0:<port>` (`--port`/`PORT`, default 8787) | `AGENT_COORDINATION_URL` | `COORDINATION_URL` env (default `http://localhost:8787`) | agent posts and app polls the same server |
| Coordination token | `--token`/`COORDINATION_TOKEN` (required) | `AGENT_COORDINATION_TOKEN` | `COORDINATION_TOKEN` env (default `dev-token-change-me`) | every `/requests*` call is bearer-authenticated |
| Network passphrase | — | `AGENT_NETWORK_PASSPHRASE` | `DemoConfig` default | same network (defaults match) |
| RPC URL | — | `AGENT_RPC_URL` | `DemoConfig` default | same testnet RPC (defaults match) |
| Ed25519 verifier | — | `AGENT_ED25519_VERIFIER` | `DemoConfig` default | the external Ed25519 signer verifies against the same verifier contract |
| Smart account | — | `AGENT_SMART_ACCOUNT` (`C...`) | the connected account's "Contract address" | the agent connects to the account it was delegated on |
| Agent seed | — | `AGENT_SECRET_SEED` (raw 64-char hex, secret) | — | the agent signs with this key |
| Agent public key | — | derived from the seed (raw 64-char hex) | pasted into Delegate to Agent | the app registers it as the Ed25519 external signer |
| Scoped token | — | `AGENT_TOKEN_CONTRACT` (default XLM SAC) | the token chosen in Delegate to Agent | the call must hit the one token the rule scopes |
| Spending cap vs. amount | — | `AGENT_AMOUNT` (default `1`) | the cap entered in Delegate to Agent | **`AGENT_AMOUNT` must EXCEED the cap** so the call is policy-rejected |
| Destination | — | `AGENT_DESTINATION` (`G...`/`C...`) | — | the transfer recipient |
| Relayer URL | — | `AGENT_RELAYER_URL` | `DemoConfig` default | gasless submission via the same relayer (defaults match) |

Because the agent's static defaults already mirror the app, a normal run only
sets the per-run identity values (`AGENT_SMART_ACCOUNT`, `AGENT_SECRET_SEED`,
`AGENT_DESTINATION`) plus an over-cap `AGENT_AMOUNT`.

## Step 0 — Start the coordination server (preflight)

Pick a token (for local development the app and agent default to
`dev-token-change-me`). The server binds `0.0.0.0` and is reachable from
simulators, devices, and other hosts on the LAN. Run it from
`coordination_server/`:

```sh
cd coordination_server
swift run coordination-server --token dev-token-change-me --port 8787
```

A bearer token is mandatory; the server exits with code 64 if none is given.
`--port` defaults to 8787. For a request set that survives a restart, add
`--store` (loaded on start if present, written atomically after every
mutation):

```sh
swift run coordination-server --token dev-token-change-me --port 8787 \
  --store ./requests.json
```

The equivalent environment variables are `COORDINATION_TOKEN`, `PORT`, and
`COORDINATION_STORE` (CLI flags take precedence). Confirm the server is up:

```sh
curl http://localhost:8787/health   # -> {"status":"ok"}
```

## Step 1 — Get the agent's public key (bootstrap)

Before a full live config exists, obtain the agent's identity. With no seed set,
print-key mode generates a fresh keypair and prints BOTH the seed (to copy into
the agent config, keep secret) and the 64-hex public key (to paste into the
app). Run it from `reference_agent/`:

```sh
cd reference_agent
AGENT_PRINT_KEY=true swift run reference-agent
```

Look for the `[agent] [KEY]` lines:

```
[agent] [KEY] Generated a new agent Ed25519 keypair.
[agent] [KEY] AGENT_SECRET_SEED (copy into the agent config, keep secret): <64-hex>
[agent] [KEY] Agent public key (paste into Delegate-to-agent): <64-hex>
```

To re-derive the public key for a seed you already hold (the secret is never
printed back):

```sh
AGENT_PRINT_KEY=true AGENT_SECRET_SEED=<64-hex> swift run reference-agent
```

Keep the seed secret; share only the 64-hex public key with the wallet.

## Step 2 — Create/connect the account, then delegate to the agent (device-only)

Build and run the app, then delegate to the agent from inside it:

```sh
# iOS simulator (SmartAccountDemo scheme)
xcodebuild -project SmartAccountDemo.xcodeproj -scheme SmartAccountDemo \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
# then launch from Xcode (Run), or boot the built app on the simulator

# macOS app (SmartAccountDemoMac scheme)
xcodebuild -project SmartAccountDemo.xcodeproj -scheme SmartAccountDemoMac \
  -destination 'platform=macOS' build
```

The app reads `COORDINATION_URL` / `COORDINATION_TOKEN` from the process
environment, falling back to `http://localhost:8787` / `dev-token-change-me`. To
override them, set them in the scheme's Run environment (Product > Scheme > Edit
Scheme > Run > Arguments > Environment Variables) for an iOS or macOS run, or
export them in the process environment for macOS runs and tests. On an iOS
simulator or device the OS process environment is empty, so without a scheme
override the defaults apply.

In the app:

1. **Create or connect a smart account** with a passkey.
2. From the **Context Rules** screen, tap **Delegate to Agent** and:
   - paste the agent's 64-hex public key from step 1 into the
     **Agent Ed25519 Public Key (hex)** field;
   - set the **Token Contract** to the scoped token (defaults to the demo
     token);
   - set a **small** spending cap (this is what the agent must exceed);
   - choose an expiry (for example 1 day);
   - submit with the passkey.

This installs one on-chain context rule that scopes the agent to one token via a
`CallContract(token)` scope plus an Ed25519 external signer (the pasted key),
caps its spend with a spending-limit policy, and expires on its own via
`validUntil`. The coordination server is not involved in this step.

Copy the value the agent needs from the app's wallet status card: the account
**Contract address** (`C...`). The agent connects headlessly by contract address
alone — it holds no passkey credential.

## Step 3 — Configure and run the agent so its call is rejected

Set `AGENT_AMOUNT` ABOVE the cap from step 2 so the spending-limit policy
rejects the call. The agent connects headlessly, registers its Ed25519 key as an
external signer, attempts the scoped `transfer`, classifies the rejection,
escalates it, and polls. Run it from `reference_agent/`:

```sh
cd reference_agent
AGENT_RUN_LIVE=true \
AGENT_SMART_ACCOUNT=C...           # account "Contract address" from step 2 \
AGENT_SECRET_SEED=<64-hex>         # the agent seed from step 1 \
AGENT_DESTINATION=G...             # transfer recipient \
AGENT_AMOUNT=1000                  # MUST exceed the delegated cap \
AGENT_COORDINATION_URL=http://localhost:8787 \
AGENT_COORDINATION_TOKEN=dev-token-change-me \
swift run reference-agent
```

`AGENT_RUN_LIVE=true` gates the live run; without it the executable prints usage
and touches nothing. If the scoped token is not the default XLM SAC, also set
`AGENT_TOKEN_CONTRACT` to the same token chosen in step 2 — a call to a different
token is not governed by that rule. The agent logs the rejection code, posts the
escalation (`POST /requests`), prints the request id, and begins polling.

## Step 4 — Review and approve in the app (device-only)

Open the approval inbox from the badged **bell** — the AppBar trailing button on
iOS, the toolbar button on macOS — which shows the pending count:

1. The pending escalation appears with the decoded call (target, function,
   recipient, amount) and the rejection reason. The decoded amount is
   authoritative; the server's `amount` field is display-only.
2. **Approve** it. The app re-submits the exact same call under the user's
   **Default rule** (single-signer passkey, gasless via the relayer) and reports
   the resulting transaction hash back to the coordination server
   (`POST /requests/{id}/approve`). Rejecting instead posts
   `POST /requests/{id}/reject`.

## Step 5 — The agent learns the outcome

The agent's poll sees the request resolve to `approved` with the `resultHash`
and returns `.escalationApproved(requestId, resultHash, errorCode)`. The agent
does NOT re-submit — the app did, under the Default rule. A rejection in the
inbox returns `.escalationRejected(...)`; no resolution within the poll budget
(`AGENT_POLL_INTERVAL_SECONDS` × `AGENT_POLL_MAX_ATTEMPTS`, default 3s × 40 ≈
2 min) returns `.escalationPending(...)`.

## Troubleshooting

- **Server unreachable / connection refused.** Confirm step 0 is running and
  `curl http://localhost:8787/health` returns `{"status":"ok"}`. On a physical
  device, `localhost` is the device itself — point the app at the host machine's
  LAN IP (`COORDINATION_URL=http://<lan-ip>:8787`) and check the host firewall
  allows the port. The server already binds `0.0.0.0`.
- **`401 Unauthorized` on `/requests*`.** The token differs across processes.
  The server's `--token`/`COORDINATION_TOKEN`, the agent's
  `AGENT_COORDINATION_TOKEN`, and the app's `COORDINATION_TOKEN` must be
  identical.
- **No rejection — the call succeeds instead of escalating.** `AGENT_AMOUNT` is
  at or below the delegated cap, so the spending-limit policy permits it. Raise
  `AGENT_AMOUNT` above the cap, or lower the cap in a new delegation. Also
  confirm `AGENT_TOKEN_CONTRACT` matches the token the rule scopes.
- **Account mismatch / agent cannot connect or sign.** `AGENT_SMART_ACCOUNT`
  must be the exact "Contract address" of the account you delegated on in
  step 2, and the agent's 64-hex public key (derived from `AGENT_SECRET_SEED`)
  must be the key you pasted into Delegate to Agent. Re-derive it with
  `AGENT_PRINT_KEY=true AGENT_SECRET_SEED=<64-hex> swift run reference-agent`
  (step 1).
