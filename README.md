# OpenZeppelin Smart Account Demo - iOS/macOS Stellar SDK

A native Swift demo application for testing the OpenZeppelin smart-account support in the iOS/macOS Stellar SDK with WebAuthn passkey authentication on Stellar testnet. The app covers wallet creation, token transfers, multi-signer authorization, on-chain context rule management, and an agent-signer flow that delegates scoped, spend-capped authority to an autonomous agent.

The primary purpose of this app is to test and validate the SDK's smart-account support. It is not intended as a production application template.

Supported platforms: iOS 18.0+ (iPhone and iPad) and macOS 15.0+ (native).

## Features

The demo includes 10 user-facing screens.

### 1. Main Dashboard
Wallet status display with XLM and DEMO token balances, navigation to all other screens, an approval-inbox bell that badges pending agent escalations, activity log showing SDK operations in real time, balance refresh, and wallet disconnect.

### 2. Wallet Creation
Collects a username, registers a passkey via the platform's WebAuthn provider, deploys a smart account contract to testnet, funds the wallet with XLM via Friendbot, and mints 10,000 DEMO tokens. Displays the credential ID, contract address, transaction hash, and initial balances on completion.

### 3. Wallet Connection
Four connection strategies:
- **Auto Connect** -- restores a saved session if one exists, otherwise authenticates with a passkey and tries to resolve the contract address automatically.
- **Connect via Indexer** -- authenticates with a passkey first, then looks up the associated contract address through the indexer service.
- **Connect with Address** -- recovery flow where the user provides a known contract address and authenticates with any registered passkey.
- **Retry Pending Deployment** -- retries contract deployment for credentials where the passkey was registered but the on-chain deployment did not complete.

### 4. Transfer
Send XLM or DEMO tokens from the connected smart account to any Stellar address. When the account has multiple signers (from context rules), a signer picker allows selecting which signers co-authorize the transaction. Supports both single-passkey and multi-signer transfer paths. Signing with a passkey signer triggers a WebAuthn authentication ceremony to sign the Soroban authorization entry.

### 5. Context Rules
Lists all on-chain authorization rules for the connected account. Each rule card shows its ID, name, context type (Default, CallContract, CreateContract), signers, policies, and expiry. Supports expanding rules for detail view, removing rules (with a safety check preventing removal of the last rule), and navigating to the rule builder for creating or editing rules.

### 6. Context Rule Builder
Form for creating or editing a context rule. Configure the context type, rule name, optional expiry (as a ledger offset converted to an absolute ledger number), signers (passkey, delegated G-address, raw Ed25519), and policy contracts (threshold, spending limit, weighted threshold) with their parameters. In edit mode, you can rename the rule, change its expiry, add or remove signers, and add, remove, or modify policies; each change is applied as a separate on-chain transaction.

### 7. Account Signers
Displays all unique signers registered across all context rules. Each signer entry shows its type (passkey, delegated G-address, raw Ed25519), identifier, and the list of context rules it belongs to. Signers are deduplicated across rules using stable signer keys.

### 8. Approve
Grants a SEP-41 token spending allowance that delegates spending authority over the smart account's tokens to another address. This screen demonstrates an arbitrary contract call: unlike Transfer (which uses the dedicated transfer helper), Approve invokes the token's `approve` function through the generic contract-call path, with both single-signer and multi-signer support.

### 9. Delegate to an Agent
Creates an on-chain context rule that scopes a raw Ed25519 agent key to a single token contract with a spending cap and an expiry, so an autonomous agent can sign transfers within that scope without a passkey. The result card exposes the agent key, the scoped token contract, and the transaction hash as copyable values for wiring the reference agent.

### 10. Approval Inbox
Reached from the bell on the Main Dashboard, which badges the count of pending escalations. When the agent attempts an over-cap call, the call is rejected on-chain and escalated to the coordination server; the inbox lists each pending request with its decoded call, and the user approves it (re-submitting it under the Default rule) or rejects it. An approved request shows its on-chain transaction hash as a copyable value.

## Architecture

```
ios-oz-smartaccount-demo/
├── Sources/                              # Cross-platform shared code
│   ├── Components/                       # SwiftUI components + *ScreenCore.swift shared screen bodies
│   ├── Config/                           # DemoConfig + PolicyInfo / knownPolicies
│   ├── Flows/                            # Business logic (primary SDK consumer)
│   ├── FlowTypes/                        # DTOs and typealiases so screens never import the SDK directly
│   ├── Navigation/                       # Route enum used by both platform shells
│   ├── State/                            # DemoState, ActivityLogState
│   ├── Theme/                            # Theme, BrandColors, Tokens, Typography
│   ├── Token/                            # DemoTokenService (deterministic deploy + balance)
│   ├── Util/                             # Helpers (formatting, clipboard, URL, policy decoders)
│   └── Wallet/                           # External wallet abstraction (Reown on iOS, no-op on macOS)
├── Sources-iOS/                          # iOS shell (App, Components, Screens, Wallet, Info.plist)
├── Sources-macOS/                        # macOS shell (App, Components, Screens, Wallet, Info.plist)
├── Resources/                            # Assets.xcassets, LaunchScreen.storyboard, soroban_token_contract.wasm
├── Entitlements/                         # SmartAccountDemo.entitlements (iOS), SmartAccountDemoMac.entitlements (macOS)
├── Tests/                                # Component, flow, screen, state, util tests
├── coordination_server/                  # Swift/Hummingbird coordination service (agent-signer flow)
├── reference_agent/                      # Swift reference agent executable (agent-signer flow)
├── documentation/                        # agent-flow.md end-to-end runbook
└── project.yml                           # XcodeGen spec
```

Each screen body lives in `Sources/Components/*ScreenCore.swift`, with thin platform shells in `Sources-iOS/Screens/` and `Sources-macOS/Screens/` adding only the navigation container and platform chrome. SDK calls stay concentrated in `Flows/`, with `FlowTypes/` surfacing DTOs and typealiases for the screen layer. `DemoState` holds wallet connection, balances, and the smart account kit instance; `ActivityLogState` is the sink for the live operation log.

The iOS shell links the Reown SDK for external wallet pairing; the macOS shell does not, and supplies its own WebAuthn presentation anchor. Each shell uses its platform's native navigation container.

## Agent-signer flow

The demo includes an end-to-end agent-signer flow: a user delegates a scoped, spend-capped Ed25519 authority to an autonomous agent (Delegate to an Agent), the agent signs calls within that scope, and an over-cap call is rejected on-chain and escalated to the user for approval (Approval Inbox). Two Swift subprojects support it:

- `coordination_server/` — a Swift/Hummingbird service that relays escalated calls between the agent and the app.
- `reference_agent/` — a macOS executable that connects to the smart account headlessly (`connectToContract`), attempts a token transfer, and escalates over-cap calls.

See [documentation/agent-flow.md](documentation/agent-flow.md) for the end-to-end runbook, plus the per-component [coordination_server/README.md](coordination_server/README.md) and [reference_agent/README.md](reference_agent/README.md).

## Prerequisites

- iOS 18.0+ / macOS 15.0+
- Xcode 16.0+
- Swift 6.0 with `SWIFT_STRICT_CONCURRENCY: complete`
- xcodegen 2.44+ (`brew install xcodegen`)
- SwiftLint 0.63.2+ (`brew install swiftlint`)
- stellar-ios-mac-sdk `3.6.1+` (resolved by Xcode on first package fetch from `https://github.com/Soneso/stellar-ios-mac-sdk.git`)
- Reown-swift `2.2.9` (pinned, resolved by Xcode on first package fetch)
- Passkey (WebAuthn) features require the Associated Domains configuration in [PASSKEY_SETUP.md](PASSKEY_SETUP.md). The demo is preconfigured for `soneso.com` (works on the iOS Simulator as-is); macOS additionally needs a one-time `swcutil developer-mode -e true`.

## Building and Running

The Xcode project file is generated by xcodegen and is gitignored. Regenerate it after every clone and after every edit to `project.yml`.

```bash
xcodegen generate
open SmartAccountDemo.xcodeproj
```

The `name=iPhone 16` destination in the commands below must match a simulator available on your machine; device names and runtimes vary by Xcode version. List yours with `xcrun simctl list devices available` and substitute as needed (for example pin the runtime with `,OS=18.6`, or choose another model).

### iOS

CLI build:

```bash
xcodebuild -project SmartAccountDemo.xcodeproj \
           -scheme SmartAccountDemo \
           -destination 'platform=iOS Simulator,name=iPhone 16' \
           build
```

CLI tests:

```bash
xcodebuild -project SmartAccountDemo.xcodeproj \
           -scheme SmartAccountDemo \
           -destination 'platform=iOS Simulator,name=iPhone 16' \
           test
```

### macOS

CLI build:

```bash
xcodebuild -project SmartAccountDemo.xcodeproj \
           -scheme SmartAccountDemoMac \
           -destination 'platform=macOS' \
           build
```

CLI tests:

```bash
xcodebuild -project SmartAccountDemo.xcodeproj \
           -scheme SmartAccountDemoMac \
           -destination 'platform=macOS' \
           test
```

For passkey work, enable developer mode once per machine: `sudo swcutil developer-mode -e true`. See [PASSKEY_SETUP.md](PASSKEY_SETUP.md).

### Physical-device builds

Physical-device builds require a signing team. The committed `Configs/Shared.xcconfig` conditionally includes a gitignored `Configs/Local.xcconfig` that injects `DEVELOPMENT_TEAM`, so your team selection survives every `xcodegen generate`:

```bash
cp Configs/Local.xcconfig.example Configs/Local.xcconfig
```

Then set your Apple Developer Team ID in `Configs/Local.xcconfig`:

```
DEVELOPMENT_TEAM = ABCD12EFGH
CODE_SIGN_STYLE = Automatic
```

`Local.xcconfig` is gitignored, so each developer keeps their own. Signing then persists across project regenerations without manual reconfiguration.

As a fallback, you can set the team in Xcode after each `xcodegen generate` (target → Signing & Capabilities → Team), but this must be redone every time the project is regenerated.

For passkey work on a physical iOS device, the `apple-app-site-association` file on the relying-party domain must be updated, or the `?mode=developer` suffix in the entitlements must remain in place. See [PASSKEY_SETUP.md](PASSKEY_SETUP.md) for full instructions.

## Passkey / WebAuthn Configuration

Passkeys are bound to a Relying Party (RP) ID. Each Apple platform links to the RP domain via an Associated Domains entitlement plus a hosted `apple-app-site-association` file:

| Platform | Dev configuration |
|----------|-------------------|
| iOS | `?mode=developer` suffix (simulator / local device) |
| macOS | `?mode=developer` + `swcutil developer-mode -e true` |

Demo defaults:

- **RP ID:** `soneso.com` (configured in `DemoConfig.swift`)
- **Associated Domains entitlement:** `webcredentials:soneso.com?mode=developer`
- **apple-app-site-association:** hosted at `https://soneso.com/.well-known/apple-app-site-association`

See [PASSKEY_SETUP.md](PASSKEY_SETUP.md) for the full setup procedure, the AASA template, the release-build gate, and the steps required to switch to a custom domain.

## Configuration

All testnet configuration is centralized as `public static` members of `public enum DemoConfig` in `Sources/Config/DemoConfig.swift`:

| Setting | Description |
|---|---|
| `rpcURL` | Soroban RPC endpoint |
| `networkPassphrase` | Stellar testnet passphrase |
| `accountWasmHash` | Smart account contract WASM hash (OZ stellar-contracts v0.7.0) |
| `webauthnVerifierAddress` | On-chain WebAuthn (secp256r1) signature verifier contract |
| `ed25519VerifierAddress` | On-chain Ed25519 signature verifier contract |
| `nativeTokenContract` | XLM Stellar Asset Contract (SAC) address on testnet |
| `defaultRelayerURL` | Relayer proxy for fee-sponsored transaction submission |
| `defaultIndexerURL` | Credential-to-contract address lookup service |
| `defaultRpId` | WebAuthn Relying Party ID (`soneso.com`) |
| `rpName` | Display name for passkey prompts |
| `reownProjectId` | Reown (WalletConnect) project ID for external-wallet connect. Empty by default; register a free project ID at [cloud.reown.com](https://cloud.reown.com) and set it. External-wallet connect is disabled (and its UI hidden) when unset. |
| `maxContextRuleScanId` | Upper bound on rule-ID iteration when scanning the chain (default `25`) |

DEMO token settings (`demoToken*`) control the deterministic deployment and minting of a custom Soroban token used for testing transfers. The token admin seed is intentionally public; the demo is testnet-only and the admin key has no monetary value.

Known policy contracts (threshold, spending limit, weighted threshold) are defined in `knownPolicies`.

## External Wallet Connection

The demo supports connecting an external Stellar wallet (Freighter) as a delegated signer, as an alternative to entering a secret key manually.

| Platform | Method | Requirement |
|---|---|---|
| iOS (device) | WalletConnect v2 (Reown) | A Reown project ID set in `DemoConfig.swift` + Freighter Mobile on the same device |
| iOS (Simulator) | Not available | Connect button is hidden |
| macOS | Not available | Reown is not linked |

Wallet connection buttons are hidden in the iOS Simulator because Reown requires a real device with a paired wallet app.

### Reown Project ID

External-wallet connect requires a Reown project ID, which is user-supplied and not shipped with the demo. Register a free project ID at [cloud.reown.com](https://cloud.reown.com) and set `reownProjectId` in `DemoConfig.swift`. When it is unset (the default), the external-wallet connector is not installed and the "Connect Wallet" UI is hidden — the passkey and keypair signer flows are unaffected.

### iOS App Group

Running on a physical iOS device requires registering the App Group and adding the bundle ID to the Reown dashboard allowlist; see the "Reown App Group" section in [PASSKEY_SETUP.md](PASSKEY_SETUP.md) for the full procedure.

## Quick Reference

| Task | Command |
|---|---|
| Generate Xcode project | `xcodegen generate` |
| Build iOS (CLI) | `xcodebuild -scheme SmartAccountDemo -destination 'platform=iOS Simulator,name=iPhone 16' build` |
| Build macOS (CLI) | `xcodebuild -scheme SmartAccountDemoMac -destination 'platform=macOS' build` |
| Enable macOS passkey developer mode (one-time) | `sudo swcutil developer-mode -e true` |

## License

Copyright 2026 Soneso

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
