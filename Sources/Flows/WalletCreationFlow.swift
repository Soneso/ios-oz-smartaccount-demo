// WalletCreationFlow.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - WalletCreationResult
// ============================================================================

/// Successful outcome of a wallet creation attempt.
///
/// All fields are populated when `WalletCreationFlow.createWallet(...)` returns
/// without throwing. When `autoSubmit` was `false`, `isDeployed` is `false` and
/// the user must trigger deployment later via the Deploy Now button.
public struct WalletCreationResult: Sendable {

    /// Smart account contract address (`C…` strkey) of the newly created wallet.
    public let contractAddress: String

    /// Base64URL-encoded WebAuthn credential identifier.
    public let credentialId: String

    /// `true` when the deploy transaction was submitted and confirmed on-chain
    /// (`autoSubmit == true`); `false` when deployment is pending.
    public let isDeployed: Bool

    /// XLM balance display string fetched immediately after creation, or `nil`
    /// when the balance fetch did not succeed (e.g. unfunded, no kit).
    public let xlmBalance: String?

    /// DEMO token balance display string fetched after the mint step, or `nil`
    /// when no DEMO contract was reached (no mint, or mint failed non-fatally).
    public let demoTokenBalance: String?

    /// On-chain transaction hash of the deploy transaction, or `nil` when the
    /// contract was not deployed (pending deployment path) or the SDK did not
    /// return a hash for the submission.
    public let transactionHash: String?
}

// ============================================================================
// MARK: - WalletCreationError
// ============================================================================

/// Errors that can be thrown by `WalletCreationFlow.createWallet(...)`.
///
/// Each case has an `errorDescription` suitable for display in an error banner
/// or the activity log. Cases are ordered from most-recoverable (user action
/// needed) to least-recoverable (SDK/network failure).
public enum WalletCreationError: Error, Sendable {

    /// The username field failed local validation before any SDK call was made.
    ///
    /// Trigger: username is empty or whitespace-only.
    /// Recovery: user corrects the input and retries.
    case invalidUsername(reason: String)

    /// The user dismissed the passkey ceremony sheet before completing it.
    ///
    /// Trigger: `WebAuthnException` whose message contains "cancel" or "abort".
    /// Recovery: show a neutral "cancelled" message; re-enable the Create button.
    case userCanceled

    /// The demo-layer credential public key format check failed.
    ///
    /// Trigger: the public key returned by the SDK is not a valid 65-byte
    /// uncompressed secp256r1 key with the required 0x04 prefix. This indicates
    /// malformed attestation data or an unexpected key format from the passkey
    /// ceremony.
    /// Recovery: surfaced as an error banner; user may retry.
    case webAuthnKeyFormatInvalid(reason: String)

    /// The SDK `createWallet` call threw an error that is not a user cancellation
    /// or a credential format failure.
    ///
    /// Trigger: network error, RPC failure, storage failure, deploy failure, etc.
    /// Recovery: `underlying.errorDescription` is shown; user may retry.
    case creationFailed(underlying: Error)
}

extension WalletCreationError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .invalidUsername(let reason):
            return "Invalid username: \(reason)"
        case .userCanceled:
            return "Passkey registration cancelled by user"
        case .webAuthnKeyFormatInvalid(let reason):
            return "Passkey key format invalid: \(reason)"
        case .creationFailed(let underlying):
            return actionableMessage(for: underlying)
        }
    }
}

// ============================================================================
// MARK: - WalletOperationsType
// ============================================================================

/// Abstraction over `OZWalletOperations` used by `WalletCreationFlow`.
///
/// Exists so unit tests can inject a mock without instantiating a real
/// `OZSmartAccountKit`. The protocol exposes only the subset of
/// `OZWalletOperations` that the flow requires.
///
/// Production code passes `kit.walletOperations` through a conforming adapter.
/// Tests inject a `MockWalletOperations` that controls return values and errors.
public protocol WalletOperationsType: Sendable {

    /// Creates a new smart account wallet.
    ///
    /// This is a subset of `OZWalletOperations.createWallet`; the `forceMethod`
    /// parameter is intentionally omitted because the flow always relies on the
    /// kit's default submission method.
    func createWallet(
        userName: String,
        autoSubmit: Bool,
        autoFund: Bool,
        nativeTokenContract: String?
    ) async throws -> CreateWalletResult
}

// ============================================================================
// MARK: - WalletOperationsAdapter
// ============================================================================

/// Production adapter that forwards `WalletOperationsType` calls to the
/// underlying `OZWalletOperations`.
///
/// The `OZSmartAccountKit`'s `walletOperations` property is `@unchecked
/// Sendable`, and `OZWalletOperations` is `@unchecked Sendable`. The adapter
/// conforms by forwarding unconditionally.
public struct WalletOperationsAdapter: WalletOperationsType, Sendable {

    /// The concrete SDK operations module.
    private let inner: OZWalletOperations

    public init(_ inner: OZWalletOperations) {
        self.inner = inner
    }

    public func createWallet(
        userName: String,
        autoSubmit: Bool,
        autoFund: Bool,
        nativeTokenContract: String?
    ) async throws -> CreateWalletResult {
        return try await inner.createWallet(
            userName: userName,
            autoSubmit: autoSubmit,
            autoFund: autoFund,
            nativeTokenContract: nativeTokenContract
        )
    }
}

// ============================================================================
// MARK: - WalletCreationFlow
// ============================================================================

/// Business logic for the wallet creation screen.
///
/// This is the single entry point that the iOS and macOS `WalletCreationScreen`
/// views use for all wallet-creation operations. Views must not call the SDK
/// directly; all SDK interaction is encapsulated here.
///
/// Thread Safety:
/// `WalletCreationFlow` is `@MainActor` because it mutates `DemoState` and
/// `ActivityLogState`, both of which have `@Published` properties. All public
/// methods must be awaited from a `Task` or `.task` modifier.
///
/// Re-entrancy:
/// `createWallet(...)` uses an `isCreating` flag to reject concurrent invocations.
/// Any call that arrives while a creation is already in flight throws
/// `WalletCreationError.creationFailed` immediately. The screen's `LoadingButton`
/// also prevents concurrent taps; the flag is an additional safeguard for
/// callers outside the screen.
///
/// Failure modes (see `WalletCreationError`):
/// - Invalid username: caught before any SDK call; never logged as an error.
/// - User cancelled: distinguished from real errors; shown as neutral state.
/// - Credential key format invalid: the public key returned by the SDK failed
///   the secp256r1 uncompressed-format check.
/// - Creation failed: SDK or network error; shown as error banner.
@MainActor
public final class WalletCreationFlow {

    // -------------------------------------------------------------------------
    // MARK: - Dependencies
    // -------------------------------------------------------------------------

    /// Shared observable demo state mutated when wallet creation succeeds.
    private let demoState: DemoState

    /// Shared append-only activity log.
    private let activityLog: ActivityLogState

    /// Abstraction over the SDK's wallet operations module.
    ///
    /// Injected rather than resolved from `demoState.kit` at call time so that
    /// unit tests can supply a mock without a real kit. In production the flow
    /// is constructed by `WalletCreationScreen` which reads `demoState.kit`
    /// and wraps `walletOperations` in a `WalletOperationsAdapter`.
    private let walletOperations: any WalletOperationsType

    /// DEMO token service used for the post-creation mint step.
    ///
    /// Injected as a protocol type so tests can supply a mock.
    private let demoTokenService: (any DemoTokenServiceType)?

    /// The shared main screen flow used to refresh balances after a successful
    /// wallet creation. Injected so that post-creation balance refresh (XLM and
    /// DEMO) is performed through the canonical refresh path rather than a
    /// separate implementation.
    private let mainScreenFlow: MainScreenFlow?

    // -------------------------------------------------------------------------
    // MARK: - Re-entrancy guard
    // -------------------------------------------------------------------------

    /// `true` while `createWallet(...)` is executing.
    ///
    /// Prevents a concurrent second invocation from starting a second creation
    /// attempt. The screen's `LoadingButton` already guards against double-tap;
    /// this flag is an additional safeguard for any non-screen caller.
    private var isCreating: Bool = false

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates a flow bound to the provided state, log, operations, and optional flows.
    ///
    /// - Parameters:
    ///   - demoState: The shared observable demo state.
    ///   - activityLog: The shared activity log.
    ///   - walletOperations: SDK wallet operations adapter.
    ///   - demoTokenService: Optional DEMO token service for the mint step.
    ///   - mainScreenFlow: Optional shared main screen flow used to refresh
    ///     balances after creation succeeds. When non-nil, `refreshBalances()` is
    ///     called on this instance immediately after the wallet is connected, so
    ///     both the XLM and DEMO token balances are populated in `DemoState`.
    public init(
        demoState: DemoState,
        activityLog: ActivityLogState,
        walletOperations: any WalletOperationsType,
        demoTokenService: (any DemoTokenServiceType)? = nil,
        mainScreenFlow: MainScreenFlow? = nil
    ) {
        self.demoState = demoState
        self.activityLog = activityLog
        self.walletOperations = walletOperations
        self.demoTokenService = demoTokenService
        self.mainScreenFlow = mainScreenFlow
    }

    // -------------------------------------------------------------------------
    // MARK: - Public: createWallet
    // -------------------------------------------------------------------------

    /// Creates a new smart account wallet.
    ///
    /// Happy path:
    /// 1. Validates `username` (non-empty, non-whitespace-only).
    /// 2. Derives `autoFund = autoSubmit` — funding is only meaningful when the
    ///    contract is deployed immediately; keeping them in sync avoids a state
    ///    where the user expects Friendbot funding without a deployed contract.
    /// 3. Calls `walletOperations.createWallet(...)` which triggers the passkey
    ///    ceremony and, when `autoSubmit == true`, deploys the contract.
    /// 4. Runs the demo-layer credential public key format check on the returned
    ///    public key (verifies 65-byte uncompressed secp256r1 format with 0x04
    ///    prefix). The Apple platform authenticator and the SDK independently
    ///    enforce origin/type/crossOrigin and COSE key validity before this
    ///    check runs.
    /// 5. Updates `DemoState` to the connected state.
    /// 6. Calls `mainScreenFlow.refreshBalances()` to populate both the XLM and
    ///    DEMO token balances via the canonical balance-refresh path.
    /// 7. Attempts a DEMO token mint when `autoSubmit == true`. Mint failure is
    ///    non-fatal — it is logged at error level and the flow continues so the
    ///    result card can still display the outcome. The wallet is fully usable
    ///    after this step regardless of whether the mint succeeded.
    ///
    /// Failure modes:
    /// - `WalletCreationError.creationFailed` — when already in progress or on
    ///   SDK/network error.
    /// - `WalletCreationError.invalidUsername` — before any SDK call.
    /// - `WalletCreationError.userCanceled` — passkey sheet dismissed.
    /// - `WalletCreationError.webAuthnKeyFormatInvalid` — credential key format check.
    ///
    /// - Parameters:
    ///   - username: Display name for the passkey credential. Must be non-empty.
    ///   - autoSubmit: When `true`, the SDK deploys the contract immediately.
    ///     Funding is also applied when `autoSubmit` is `true`.
    ///   - onProgress: Optional closure invoked on the main actor with a short
    ///     status string at long-running transitions. Called at most twice: once
    ///     at the start of the SDK call, and once immediately before the demo
    ///     token mint step (only when `autoSubmit` is `true`). The default is a
    ///     no-op, so existing callers are unaffected.
    /// - Returns: `WalletCreationResult` describing the created wallet.
    /// - Throws: `WalletCreationError`
    public func createWallet(
        username: String,
        autoSubmit: Bool,
        onProgress: @MainActor (String) -> Void = { _ in }
    ) async throws -> WalletCreationResult {
        guard !isCreating else {
            throw WalletCreationError.creationFailed(
                underlying: PlainError("Wallet creation already in progress.")
            )
        }
        isCreating = true
        defer { isCreating = false }

        onProgress("Creating wallet...")
        let trimmed = try validateUsername(username)
        // Funding is only meaningful when the contract is deployed immediately.
        let autoFund = autoSubmit
        let sdkResult = try await invokeSDK(userName: trimmed, autoSubmit: autoSubmit, autoFund: autoFund)
        try verifyCredentialPublicKey(sdkResult)
        commitConnectionState(sdkResult: sdkResult, autoSubmit: autoSubmit)
        await refreshBalancesIfPossible(contractId: sdkResult.contractId)
        if autoSubmit {
            onProgress("Deploying demo token...")
            await attemptMint(sdkResult: sdkResult)
        }

        return WalletCreationResult(
            contractAddress: sdkResult.contractId,
            credentialId: sdkResult.credentialId,
            isDeployed: autoSubmit,
            xlmBalance: demoState.xlmBalance,
            demoTokenBalance: demoState.demoTokenBalance,
            transactionHash: sdkResult.transactionHash
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - Private: createWallet substeps
    // -------------------------------------------------------------------------

    /// Validates the username and returns the trimmed value.
    ///
    /// Throws `WalletCreationError.invalidUsername` if empty after trimming.
    private func validateUsername(_ username: String) throws -> String {
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw WalletCreationError.invalidUsername(reason: "Username must not be empty.")
        }
        return trimmed
    }

    /// Calls the SDK wallet-operations `createWallet` and maps any error.
    ///
    /// Distinguishes user-cancellation (logged at info) from other failures
    /// (logged at error) so the UI can show an appropriate state.
    private func invokeSDK(
        userName: String,
        autoSubmit: Bool,
        autoFund: Bool
    ) async throws -> CreateWalletResult {
        let safeName = Self.safeUserNameForLog(userName)
        activityLog.info("Creating wallet for \"\(safeName)\"…")
        do {
            return try await walletOperations.createWallet(
                userName: userName,
                autoSubmit: autoSubmit,
                autoFund: autoFund,
                nativeTokenContract: autoFund ? DemoConfig.nativeTokenContract : nil
            )
        } catch {
            let mapped = mapCreationError(error)
            logCreationError(mapped, originalError: error)
            throw mapped
        }
    }

    /// Logs the mapped creation error at the appropriate severity level.
    ///
    /// User-cancellations are logged at `info` (neutral); all other errors at `error`.
    private func logCreationError(_ mapped: WalletCreationError, originalError: Error) {
        switch mapped {
        case .userCanceled:
            activityLog.info("Wallet creation cancelled by user.")
        default:
            activityLog.error(
                "Wallet creation failed: \(ActivityLogState.redact(actionableMessage(for: originalError)))"
            )
        }
    }

    /// Verifies that the credential public key is a valid 65-byte uncompressed
    /// secp256r1 key with the required 0x04 prefix.
    ///
    /// This is a structural format check, not a freshness or ceremony check.
    /// The Apple platform authenticator enforces origin binding, type, and
    /// crossOrigin at the ceremony layer before returning attestation; the SDK
    /// independently validates COSE key extraction. This check provides an
    /// additional guard that the returned key bytes match the expected secp256r1
    /// uncompressed format before the key is registered on-chain.
    ///
    /// Note: `clientDataJSON` fields (origin, type, crossOrigin) cannot be
    /// re-verified here because `CreateWalletResult` does not surface
    /// `clientDataJSON` or `attestationObject`. The structural ceiling for
    /// registration-time demo-layer rechecks is this key-format guard.
    ///
    /// - Throws: `WalletCreationError.webAuthnKeyFormatInvalid` if the key
    ///   does not pass the format check.
    private func verifyCredentialPublicKey(_ sdkResult: CreateWalletResult) throws {
        do {
            try performCredentialPublicKeyCheck(publicKey: sdkResult.publicKey)
        } catch let verifyError as WalletCreationError {
            activityLog.error("Credential key format check failed: \(verifyError.errorDescription ?? "")")
            throw verifyError
        }
    }

    /// Updates `DemoState` to the connected state and logs success.
    ///
    /// Also clears stale balances so the UI shows a pending state while the
    /// post-creation balance refresh runs asynchronously.
    private func commitConnectionState(sdkResult: CreateWalletResult, autoSubmit: Bool) {
        let isDeployed = autoSubmit
        demoState.setConnected(
            contractId: sdkResult.contractId,
            credentialId: sdkResult.credentialId,
            isDeployed: isDeployed
        )
        let shortAddr = truncateAddress(sdkResult.contractId)
        let safeCredId = ActivityLogState.redactCredentialId(sdkResult.credentialId)
        if isDeployed {
            activityLog.success("Wallet created and deployed: \(shortAddr) (cred: \(safeCredId))")
        } else {
            activityLog.success(
                "Passkey registered: \(shortAddr) (cred: \(safeCredId)) — deployment pending."
            )
        }
    }

    /// Refreshes both XLM and DEMO token balances after a successful wallet
    /// creation by delegating to the shared `mainScreenFlow`.
    ///
    /// When `mainScreenFlow` is nil (unit tests with no main screen) the refresh
    /// is skipped — tests assert on `DemoState` values via direct kit injection.
    /// In production the flow is always constructed with a non-nil `mainScreenFlow`.
    ///
    /// Errors from the balance refresh are non-fatal (they are logged by
    /// `MainScreenFlow.refreshBalances()` internally). The wallet creation is
    /// already committed at this point.
    private func refreshBalancesIfPossible(contractId: String) async {
        await mainScreenFlow?.refreshBalances()
    }

    /// Attempts the DEMO token mint after a successful deployment.
    ///
    /// Delegates to `provisionDemoTokens(...)` so the orchestration (info entry,
    /// contract-id write, balance refresh, error redaction) is identical to the
    /// main-screen Deploy Now path and the retry-pending-deploy path. Mint
    /// failure is non-fatal: the shared helper logs the curated error message
    /// and returns `nil`.
    private func attemptMint(sdkResult: CreateWalletResult) async {
        let mainFlow = mainScreenFlow
        await provisionDemoTokens(
            service: demoTokenService,
            demoState: demoState,
            activityLog: activityLog,
            onRefreshBalances: { await mainFlow?.refreshBalances() },
            recipientContractId: sdkResult.contractId
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - Private: credential public key check
    // -------------------------------------------------------------------------

    /// Checks that `publicKey` is a valid 65-byte uncompressed secp256r1 key.
    ///
    /// A valid secp256r1 uncompressed public key is exactly 65 bytes and starts
    /// with the 0x04 prefix byte. A key that fails this check indicates the
    /// attestation data is malformed or the SDK extracted an unexpected key format
    /// from the COSE structure.
    ///
    /// - Throws: `WalletCreationError.webAuthnKeyFormatInvalid` if the key does
    ///   not conform to the expected 65-byte / 0x04-prefix shape.
    private func performCredentialPublicKeyCheck(publicKey: Data) throws {
        guard publicKey.count == 65, publicKey.first == 0x04 else {
            throw WalletCreationError.webAuthnKeyFormatInvalid(
                reason: "Credential public key is not a valid uncompressed secp256r1 key " +
                "(expected 65 bytes starting with 0x04, got \(publicKey.count) bytes)."
            )
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Private: error mapping
    // -------------------------------------------------------------------------

    /// Maps a raw SDK error to a `WalletCreationError`.
    ///
    /// User cancellations are detected via `isUserCancellation(_:)` so the UI
    /// can show a neutral state rather than an error banner. All other errors
    /// are wrapped in `.creationFailed`.
    private func mapCreationError(_ error: Error) -> WalletCreationError {
        if isUserCancellation(error) {
            return .userCanceled
        }
        return .creationFailed(underlying: error)
    }

    // -------------------------------------------------------------------------
    // MARK: - Private: log helpers
    // -------------------------------------------------------------------------

    /// Returns a log-safe representation of the username.
    ///
    /// Truncates to 32 characters, strips control characters and directional
    /// override code points, and passes through `ActivityLogState.redact(_:)`.
    /// This prevents RTL/zero-width injections from reordering subsequent log
    /// entries and avoids echoing multi-KB or credential-shaped display names.
    private static func safeUserNameForLog(_ name: String) -> String {
        let truncated = String(name.prefix(32))
        let stripped = truncated.filter { $0.isASCII && !$0.isNewline }
        return ActivityLogState.redact(stripped)
    }
}

// ============================================================================
// MARK: - PlainError
// ============================================================================

/// A simple `LocalizedError` wrapper for string error messages.
///
/// Used to wrap guard-failure messages before wrapping them in
/// `WalletCreationError.creationFailed(underlying:)`.
struct PlainError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) {
        self.errorDescription = message
    }
}
