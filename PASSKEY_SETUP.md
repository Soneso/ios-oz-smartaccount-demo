# Passkey (WebAuthn) Domain Setup

This document describes the Relying Party (RP) domain configuration required for WebAuthn passkeys in the Smart Account Demo on iOS and macOS. Passkeys are bound to a specific RP ID (typically a domain name), and the authenticator will only allow credential use when the requesting origin matches that RP ID.

## Overview

WebAuthn passkeys require a trust relationship between the app and a domain. The RP ID identifies which domain "owns" the passkey credentials. On Apple platforms this trust is established by combining two pieces:

1. An **Associated Domains** entitlement on the app target, declaring `webcredentials:<rp-id>`.
2. A hosted **apple-app-site-association** (AASA) file at `https://<rp-id>/.well-known/apple-app-site-association` that lists the app's Team ID and bundle identifier.

The OS resolves the entitlement against the AASA file at install time (or at runtime when the developer-mode suffix is in use) and only permits passkey ceremonies when the two agree.

| Platform | RP ID Default | Association Mechanism | Dev Configuration |
|---|---|---|---|
| iOS | Must be set explicitly | Associated Domains entitlement + `apple-app-site-association` | `?mode=developer` suffix on simulator and developer-signed devices |
| macOS | Must be set explicitly | Associated Domains entitlement + `apple-app-site-association` | `?mode=developer` suffix **plus** `sudo swcutil developer-mode -e true` once per machine |

---

## iOS

iOS uses the AuthenticationServices framework (`ASAuthorizationPlatformPublicKeyCredentialProvider`) for passkey operations. The app must be associated with the RP domain via Associated Domains.

### Step 1: Set the RP ID

The RP ID is supplied to the WebAuthn provider (`AppleWebAuthnProvider`). The demo reads it from `DemoConfig.defaultRpId` (currently `soneso.com`):

```swift
public enum DemoConfig {
    public static let defaultRpId = "soneso.com"
    public static let rpName = "Smart Account Kit Demo"
    // ...
}
```

To target a different domain, update `defaultRpId` (and the matching entitlement string described below).

### Step 2: Associated Domains entitlement

The entitlement is already configured in `Entitlements/SmartAccountDemo.entitlements`:

```xml
<key>com.apple.developer.associated-domains</key>
<array>
    <string>webcredentials:soneso.com?mode=developer</string>
</array>
```

To switch domains, replace `soneso.com` with the target RP ID. The `?mode=developer` suffix is described in the "Developer mode" subsection below.

### Step 3: Host the AASA file

Serve a JSON file (no `.json` extension) at:

```
https://<rp-id>/.well-known/apple-app-site-association
```

For the demo bundles, the contents must include:

```json
{
  "webcredentials": {
    "apps": [
      "<TEAM_ID>.com.soneso.stellar.smartaccount.demo.ios",
      "<TEAM_ID>.com.soneso.stellar.smartaccount.demo.macos"
    ]
  }
}
```

Replace `<TEAM_ID>` with your Apple Developer Team ID. Hosting requirements:

- Served over HTTPS with a valid TLS certificate.
- Content-Type must be `application/json`.
- No authentication required.
- At most one redirect.

### Step 4: Team ID

Your Apple Developer Team ID is required for the AASA file. Find it at:

- [Apple Developer Portal](https://developer.apple.com/account) under Membership Details.
- Or in Xcode: select the project, open Signing & Capabilities, and read the Team field.

### Developer mode (simulator and developer-signed devices)

The `?mode=developer` suffix on the entitlement value (`webcredentials:soneso.com?mode=developer`) tells iOS to use an alternate validation path that does not require the AASA file to be publicly hosted at the RP domain. This is intended for local development and allows passkey registration and authentication on:

- The iOS Simulator.
- Developer-signed device builds running in Debug.

Notes:

- Simulator passkeys are stored locally and do not sync via iCloud Keychain.
- Even with developer mode, the device or Simulator must have network access.
- See Apple's documentation for [supporting associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains) for the full validation matrix.

---

## macOS

macOS uses the same `AuthenticationServices` framework as iOS, but the demo wires a custom presentation anchor for `ASAuthorizationController` in `Sources-macOS/Wallet/MacWebAuthnPresentationAnchor.swift` because macOS does not provide one out of the box.

The Associated Domains entitlement and AASA file requirements are identical to iOS, with the macOS bundle ID added to the AASA `webcredentials.apps` array (see Step 3 above).

### Critical: enable developer mode once per machine

macOS does **not** automatically bypass Associated Domains validation for debug builds. Without the following one-time step, passkey operations fail with "Application is not associated with domain":

```bash
sudo swcutil developer-mode -e true
```

The app must then be launched from Xcode with the debugger attached for the `?mode=developer` entitlement to take effect. Running the built `.app` directly will not work.

This step is not needed on iOS — iOS Simulator and developer-signed iOS devices honor `?mode=developer` directly.

### Biometric authenticators

Touch ID or an enrolled Apple Watch can serve as the biometric authenticator. If the Mac lacks both, macOS falls back to the system password or a security key.

---

## Release-build gate

Both app targets have a `postBuildScripts` entry that fails Release builds while `?mode=developer` is still present in the entitlements. The gate prevents accidental distribution before the AASA is properly configured on the RP domain. The script uses `basedOnDependencyAnalysis: false` so Xcode does not skip it on cached incremental builds.

To ship a Release build:

1. Update `https://<rp-id>/.well-known/apple-app-site-association` to include both bundle identifiers with the correct Team ID.
2. Wait for Apple's CDN to pick up the change. First-publication propagation can take up to 24 hours.
3. Remove `?mode=developer` from both entitlements files:
   - `Entitlements/SmartAccountDemo.entitlements`
   - `Entitlements/SmartAccountDemoMac.entitlements`
4. Rebuild in Release configuration. The build-time gate must pass.
5. Install the Release build on a physical device and confirm passkey ceremonies succeed without developer mode.

Do not remove or disable the build-time gate.

---

## Reown App Group (iOS only)

The iOS target links the Reown SDK so the user can pair an external Stellar wallet as a delegated signer. Reown requires an App Group for relay-session storage. The entitlement `group.com.soneso.stellar.smartaccount.demo.ios` is already declared in `Entitlements/SmartAccountDemo.entitlements`.

A Reown project ID is required for external-wallet connect and is not shipped with the demo. When `reownProjectId` in `DemoConfig.swift` is unset (the default), the external-wallet connector is not installed, the "Connect Wallet" UI is hidden, and the steps below can be skipped. The passkey and keypair signer flows do not need Reown.

To enable external-wallet connect on a physical iOS device:

1. Register a free project at [cloud.reown.com](https://cloud.reown.com) and set its project ID as `reownProjectId` in `DemoConfig.swift`.
2. Visit [Apple Developer → Identifiers → App Groups](https://developer.apple.com/account/resources/identifiers/list/applicationGroup).
3. Register `group.com.soneso.stellar.smartaccount.demo.ios`.
4. In Xcode, refresh the App Group capability on the iOS target (Signing & Capabilities → App Groups → refresh).
5. Add the iOS bundle ID `com.soneso.stellar.smartaccount.demo.ios` to the Reown dashboard allowlist.

The macOS target does not link Reown, so this step is iOS-only. Reown is additionally gated by `#if !targetEnvironment(simulator)`, so simulator builds do not require an active App Group.

---

## Permissions matrix

| Capability | iOS | macOS | Justification |
|---|---|---|---|
| Associated Domains | Required | Required | Passkey RP binding |
| App Groups | Required | Not present | Reown relay-session storage (iOS only) |
| App Sandbox | Not applicable | `app-sandbox = true` | macOS hardened-runtime requirement |

---

## Custom domain / production setup

To move off `soneso.com` onto a domain you control:

1. **Register a domain** and configure DNS to point to your server.
2. **Obtain a TLS certificate** (for example via Let's Encrypt).
3. **Update `DemoConfig.defaultRpId`** to your domain.
4. **Update both entitlements** files. Replace `webcredentials:soneso.com?mode=developer` with `webcredentials:<your-rp-id>` (or keep `?mode=developer` during initial development).
5. **Host the AASA file** at `https://<your-rp-id>/.well-known/apple-app-site-association` with your Team ID and the demo bundle identifiers (or whatever bundle identifiers you change to). All hosting requirements listed above apply.
6. **Test on real devices**. Simulator behavior can differ from physical hardware for biometric prompts and iCloud Keychain sync.

To ship a Release build on the new domain, follow the [Release-build gate](#release-build-gate) steps above (wait for CDN propagation, remove `?mode=developer`, rebuild Release).

---

## RP ID scope

The RP ID must be a registrable domain. Page-origin-style scope rules apply: an app declaring `webcredentials:app.example.com` can use either `app.example.com` or `example.com` as the RP ID when registering credentials, but not `other.com`.

Choose the RP ID carefully. Passkey credentials are permanently bound to the RP ID used at creation time. Changing the RP ID later invalidates all existing passkeys; users will need to register new credentials against the new RP ID.

---

## Cross-platform passkey sharing

Passkeys created on iOS can be used on macOS (and vice versa) when all of the following hold:

- The same RP ID is configured on both platforms.
- The credentials are synced via iCloud Keychain.
- The AASA file lists both bundle identifiers under `webcredentials.apps`.

This lets a user register a passkey on their iPhone and later authorize a transaction from the macOS app without re-registering.
