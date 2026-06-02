// ReownWalletHandler.swift
// SmartAccountDemo (iOS)
//
// Copyright (c) 2026 Soneso. All rights reserved.

// Reown WalletConnect is only functional on physical iOS devices.
// Simulator builds use the stub below.
// swiftlint:disable file_length
#if !targetEnvironment(simulator)

import Combine
import Foundation
import os.log
import UIKit
// `@preconcurrency import` silences Swift 6 strict-concurrency errors that
// would otherwise fire at every `Sign.instance` / `Pair.instance` /
// `Networking.configure` call. Reown 2.2.9 has not yet annotated its static
// `instance` accessors as `nonisolated(unsafe)` (or otherwise concurrency-safe).
// The handler itself guards all mutable state via `stateLock` (NSLock) and is
// `@unchecked Sendable`, so the safety story is preserved at this layer.
@preconcurrency import WalletConnectNetworking
@preconcurrency import WalletConnectPairing
@preconcurrency import WalletConnectSign

// MARK: - SocketFactory

/// URLSessionWebSocket-based `WebSocketFactory` for the Reown networking relay.
/// Uses `URLSessionWebSocketTask` (iOS 13+) to avoid a Starscream dependency.
private final class URLSessionWebSocketFactory: WebSocketFactory {

    func create(with url: URL) -> WebSocketConnecting {
        return URLSessionWebSocket(url: url)
    }
}

/// `URLSessionWebSocketTask`-backed `WebSocketConnecting` implementation.
///
/// Uses plain stored properties without an internal serialization queue.
/// Reown's `RelayClient` synchronously reads `isConnected` from inside the
/// callback chain that runs `onText` (the receive loop), so wrapping that
/// getter in a `DispatchQueue.sync` triggers a recursive-sync trap
/// (EXC_BREAKPOINT) the first time a payload arrives. Reown's own dispatching
/// infrastructure sequences reads and writes across its internal queues.
// @unchecked-justified: stored properties are touched only from
// (a) Reown's dispatching layer, which sequences calls onto its internal
// queues, and (b) URLSession's serial delegate queue. No cross-actor access
// from consumer code: the type is private to this file and never escapes the
// Networking.configure(socketFactory:) handoff.
private final class URLSessionWebSocket: NSObject, WebSocketConnecting, URLSessionWebSocketDelegate,
    @unchecked Sendable {

    var isConnected: Bool = false
    var onConnect: (() -> Void)?
    var onDisconnect: ((Error?) -> Void)?
    var onText: ((String) -> Void)?
    var request: URLRequest

    private var task: URLSessionWebSocketTask?
    private lazy var session: URLSession = {
        URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }()

    init(url: URL) {
        self.request = URLRequest(url: url)
        super.init()
    }

    func connect() {
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        receive(task: task)
    }

    func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
    }

    func write(string: String, completion: (() -> Void)?) {
        task?.send(.string(string)) { _ in completion?() }
    }

    // Recursive receive loop — keep draining frames until the task closes.
    // Only continues if `task` is still the current task to avoid retaining a
    // stale task reference after a reconnect.
    private func receive(task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            if case .success(let message) = result,
               case .string(let text) = message {
                self.onText?(text)
            }
            if self.task === task {
                self.receive(task: task)
            }
        }
    }

    // MARK: URLSessionWebSocketDelegate

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        isConnected = true
        onConnect?()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        isConnected = false
        onDisconnect?(nil)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if isConnected {
            isConnected = false
            onDisconnect?(error)
        }
    }
}

// MARK: - DefaultCryptoProvider

/// Minimal `CryptoProvider` stub required by WalletConnectSign.
/// `recoverPubKey` and `keccak256` are Ethereum-only paths never exercised during Stellar sessions.
private final class DefaultCryptoProvider: CryptoProvider {

    func recoverPubKey(signature: EthereumSignature, message: Data) throws -> Data {
        return Data()
    }

    func keccak256(_ data: Data) -> Data {
        return Data()
    }
}

// MARK: - ReownWalletHandler

/// Reown WalletConnect-based `WalletConnector` implementation.
///
/// Manages one active `stellar:testnet` session scoped to `stellar_signAuthEntry`.
/// Sessions survive app restarts via the App Group container. State mutations are
/// protected by `stateLock`. All reads and writes of `pendingConnectContinuation`
/// and `pendingSignContinuations` are performed inside `stateLock.withLock { }` to
/// prevent double-resume races between concurrent callbacks.
///
/// On `init()` all stored sessions are enumerated; those failing
/// `isValidStellarTestnetSession` are disconnected so orphan sessions do not
/// accumulate in the shared App Group relay storage. The same purge runs on
/// `disconnect()`.
// @unchecked-justified: all mutable state is protected by `stateLock` (NSLock);
// `_pendingConnectContinuation` and `_pendingSignContinuations` use
// `SafeCheckedContinuation` wrappers that enforce the single-resume invariant;
// Combine `cancellables` is written only from `init()` before any async access.
public final class ReownWalletHandler: WalletConnector, @unchecked Sendable {

    // MARK: - Constants

    private static let stellarNamespaceKey = "stellar"
    private static let signMethod = "stellar_signAuthEntry"
    private static let testnetChain = "stellar:testnet"
    private static let appGroupId = "group.com.soneso.stellar.smartaccount.demo.ios"

    private static let connectionTimeoutSeconds: TimeInterval = 120
    private static let signingTimeoutSeconds: TimeInterval = 120
    // WalletConnect request TTL bounds: min 300s, max 604800s.
    private static let requestTtlSeconds: TimeInterval = 300

    // MARK: - State (protected by stateLock)

    private let stateLock = NSLock()

    private var _activeSession: Session?
    private var activeSession: Session? {
        get { stateLock.withLock { _activeSession } }
        set { stateLock.withLock { _activeSession = newValue } }
    }

    private var _connectedAddress: String?
    public var connectedAddress: String? { stateLock.withLock { _connectedAddress } }

    private var _walletMetadata: WalletMetadata?
    public var walletMetadata: WalletMetadata? { stateLock.withLock { _walletMetadata } }

    // MARK: - Pending sign entry

    /// Bundles the continuation, the WalletConnect request ID, and the session topic for
    /// a pending `stellar_signAuthEntry` request. The topic and RPCID are needed to
    /// issue an error response to the wallet when a timeout fires, signalling it to
    /// dismiss its signing prompt.
    private struct PendingSignEntry {
        let continuation: SafeCheckedContinuation<String>
        let requestId: RPCID
        let sessionTopic: String
    }

    // MARK: - Pending completions (protected by stateLock)

    /// Awaited in `connect()`. Resolved when session settles.
    /// All reads and writes must be performed inside `stateLock.withLock`.
    /// `SafeCheckedVoidContinuation` enforces single-resume; double-resume → Debug fatalError.
    private var _pendingConnectContinuation: SafeCheckedVoidContinuation?

    /// Awaited in `signAuthEntry()`. Keyed by WalletConnect request ID string.
    /// All reads and writes must be performed inside `stateLock.withLock`.
    /// `SafeCheckedContinuation<String>` inside `PendingSignEntry` enforces single-resume
    /// per entry; late wallet responses that look up an already-resumed entry trigger the
    /// wrapper's Debug fatalError. The `requestId` and `sessionTopic` fields allow
    /// the timeout block to send an error response to the wallet.
    private var _pendingSignContinuations: [String: PendingSignEntry] = [:]

    // MARK: - Internal logger

    private let logger = Logger(
        subsystem: "com.soneso.stellar.smartaccount.demo",
        category: "ReownWalletHandler"
    )

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init / Configuration

    /// Configures the Reown networking stack. Call once at app startup.
    public static func configureOnce() {
        Networking.configure(
            groupIdentifier: appGroupId,
            projectId: DemoConfig.reownProjectId,
            socketFactory: URLSessionWebSocketFactory()
        )
        // `AppMetadata.Redirect.init(native:universal:)` is throwing and the
        // `redirect:` parameter on `AppMetadata` is non-optional in Reown 2.2.9,
        // so `try!` is the correct form here. The native scheme is a compile-time
        // constant string in the form `scheme://`, which is always valid input,
        // so the force-try cannot fire at runtime.
        // swiftlint:disable:next force_try
        let redirect = try! AppMetadata.Redirect(native: "stellar-smartaccount-ios://", universal: nil)
        Pair.configure(metadata: AppMetadata(
            name: "Smart Account Demo",
            description: "Stellar Smart Account Demo",
            url: "https://soneso.com",
            icons: ["https://soneso.com/icon.png"],
            redirect: redirect
        ))
        Sign.configure(crypto: DefaultCryptoProvider())
    }

    /// Initializes the handler, restoring the persisted `stellar:testnet` WalletConnect session if one exists.
    public init() {
        subscribeToPublishers()
        restoreExistingSession()
    }

    /// Forwards a deep-link URL into the WalletConnect Sign client so it can
    /// process responses that arrive via the custom-scheme link mode (instead
    /// of the relay websocket).
    ///
    /// Wallets such as Freighter Mobile return the session-settle envelope by
    /// opening the dApp with a URL like
    /// `stellar-smartaccount-ios://?wc_ev=<base64-envelope>`. iOS routes that
    /// URL to the SwiftUI `.onOpenURL` modifier, which calls this static so
    /// `Sign.instance` can decode the envelope and resolve any pending
    /// `connect()` / `request()` continuations. URLs without a `wc_ev` query
    /// item are ignored.
    public static func handleOpenURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              queryItems.contains(where: { $0.name == "wc_ev" }) else {
            return
        }
        do {
            try Sign.instance.dispatchEnvelope(url.absoluteString)
        } catch {
            // Failure here means the envelope was malformed or stale; either
            // way the pending continuation will fall back to the connection /
            // signing timeout watchdog. Log to os.log for postmortem.
            os_log(
                "Reown: dispatchEnvelope failed: %{public}@",
                log: OSLog(subsystem: "com.soneso.stellar.smartaccount.demo", category: "ReownWalletHandler"),
                type: .error,
                String(describing: error)
            )
        }
    }

    // MARK: - WalletConnector

    /// Initiates a WalletConnect pairing session scoped to `stellar:testnet` / `stellar_signAuthEntry`.
    ///
    /// Re-entrant calls while a connection is already pending are rejected immediately with
    /// `WalletConnectorError.reownError` rather than silently overwriting the prior continuation.
    /// Throws `connectionTimeout` if the wallet does not settle within 120 seconds.
    public func connect() async throws {
        if let session = activeSession, stellarAddress(from: session) != nil {
            return
        }
        try await withSafeCheckedThrowingVoidContinuation { safe in
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    safe.resume(throwing: WalletConnectorError.reownError(
                        underlying: NSError(domain: "ReownWalletHandler", code: -1)
                    ))
                    return
                }
                // C1: Reject re-entrant connect() calls while one is already pending.
                // Rather than overwriting _pendingConnectContinuation (which would leak the
                // prior continuation and cause a "continuation leaked" runtime warning), the
                // new continuation is immediately rejected with an error. The caller in-flight
                // on the prior continuation continues to wait normally.
                let isAlreadyPending = self.stateLock.withLock { self._pendingConnectContinuation != nil }
                if isAlreadyPending {
                    safe.resume(throwing: WalletConnectorError.reownError(
                        underlying: NSError(
                            domain: "ReownWalletHandler",
                            code: -4,
                            userInfo: [NSLocalizedDescriptionKey: "connect() called while a connection attempt is already in progress"]
                        )
                    ))
                    return
                }
                self.stateLock.withLock { self._pendingConnectContinuation = safe }
                Task { await self.startPairing(safe: safe) }
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.connectionTimeoutSeconds) { [weak self] in
                    guard let self else { return }
                    let pending = self.stateLock.withLock { () -> SafeCheckedVoidContinuation? in
                        let cont = self._pendingConnectContinuation
                        self._pendingConnectContinuation = nil
                        return cont
                    }
                    guard let pending else { return }
                    pending.resume(throwing: WalletConnectorError.connectionTimeout)
                    // Tear down any session that arrives after the timeout so app
                    // state and relay state stay in sync. The disconnect is
                    // fire-and-forget; failures are non-fatal.
                    Task { await self.disconnect() }
                }
            }
        }
    }

    /// Disconnects the active session, rejects pending sign continuations, and purges all
    /// stored sessions and pairings from the App Group relay storage.
    ///
    /// Iterates every session returned by `Sign.instance.getSessions()` and every pairing
    /// returned by `Pair.instance.getPairings()`, disconnecting each entry — not just the
    /// in-memory `activeSession`. This prevents orphan sessions from accumulating in the
    /// shared App Group container across app runs.
    public func disconnect() async {
        stateLock.withLock { _activeSession = nil; _connectedAddress = nil; _walletMetadata = nil }
        let snapshot = stateLock.withLock { () -> [String: PendingSignEntry] in
            let captured = _pendingSignContinuations
            _pendingSignContinuations = [:]
            return captured
        }
        // Attempt to send an error response for each pending sign request so the
        // wallet can dismiss its signing prompt. Reown 2.2.9 exposes
        // `Sign.instance.respond(topic:requestId:response:)` as the only
        // client-side mechanism for retiring a pending request.
        // The call is best-effort; failure is non-fatal.
        for (_, entry) in snapshot {
            try? await Sign.instance.respond(
                topic: entry.sessionTopic,
                requestId: entry.requestId,
                response: .error(JSONRPCError(code: -32000, message: "Request cancelled: session disconnected"))
            )
            entry.continuation.resume(throwing: WalletConnectorError.noActiveSession)
        }
        // Purge every session and pairing — not just the in-memory activeSession.
        // This removes orphan entries left in shared App Group relay storage.
        for session in Sign.instance.getSessions() {
            try? await Sign.instance.disconnect(topic: session.topic)
        }
        for pairing in Pair.instance.getPairings() {
            try? await Pair.instance.disconnect(topic: pairing.topic)
        }
    }

    /// Requests the active wallet to sign an OZ smart-account authorization entry.
    ///
    /// Sends a `stellar_signAuthEntry` WalletConnect request carrying the full auth entry
    /// XDR and context rule IDs. The wallet computes the OZ auth digest and returns the
    /// signature.
    ///
    /// Failure modes:
    /// - `noActiveSession`: no wallet connected.
    /// - `signingTimeout`: wallet did not respond within 120 seconds.
    /// - `signingRejected`: wallet explicitly declined.
    /// - `malformedWalletResponse`: the response payload was not parseable.
    public func signAuthEntry(
        authEntryXdr: String,
        contextRuleIds: [UInt32]
    ) async throws -> SignedAuthEntry {
        guard let session = activeSession else {
            throw WalletConnectorError.noActiveSession
        }
        guard let chain = Blockchain(Self.testnetChain) else {
            throw WalletConnectorError.reownError(
                underlying: NSError(
                    domain: "ReownWalletHandler",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Could not construct Blockchain for stellar:testnet"]
                )
            )
        }
        let signedEntryXdr = try await sendSignRequest(
            session: session,
            chain: chain,
            authEntryXdr: authEntryXdr,
            contextRuleIds: contextRuleIds
        )
        guard let address = connectedAddress else {
            throw WalletConnectorError.noActiveSession
        }
        return SignedAuthEntry(signedAuthEntry: signedEntryXdr, signerAddress: address)
    }

}

// MARK: - ReownWalletHandler private helpers

private extension ReownWalletHandler {

    func subscribeToPublishers() {
        Sign.instance.sessionSettlePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] session, _ in
                guard let self else { return }
                self.handleSessionSettled(session)
            }
            .store(in: &cancellables)

        Sign.instance.sessionResponsePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] response in
                guard let self else { return }
                self.handleSessionResponse(response)
            }
            .store(in: &cancellables)

        Sign.instance.sessionDeletePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.disconnect() }
            }
            .store(in: &cancellables)
    }

    func restoreExistingSession() {
        let allSessions = Sign.instance.getSessions()
        var validSession: Session?

        for session in allSessions {
            if isValidStellarTestnetSession(session) {
                validSession = session
            } else {
                // Purge invalid sessions from the App Group relay storage.
                // Fire-and-forget: failures are non-fatal on startup.
                Task { try? await Sign.instance.disconnect(topic: session.topic) }
            }
        }

        // Also purge any dangling pairings that do not back a valid session.
        let validTopics = Set(allSessions.map(\.topic))
        for pairing in Pair.instance.getPairings() where !validTopics.contains(pairing.topic) {
            Task { try? await Pair.instance.disconnect(topic: pairing.topic) }
        }

        guard let session = validSession,
              let address = stellarAddress(from: session) else { return }
        stateLock.withLock {
            _activeSession = session
            _connectedAddress = address
            _walletMetadata = WalletMetadata(
                name: session.peer.name,
                url: session.peer.url,
                iconUrl: session.peer.icons.first
            )
        }
    }

    func startPairing(safe: SafeCheckedVoidContinuation) async {
        do {
            // `Sign.instance.connect` returns a WalletConnect URI that the wallet
            // must receive in order to settle the session. Without delivering the
            // URI, the wallet never sees the pairing request and the continuation
            // waits forever (until the connectionTimeout watchdog fires).
            let uri = try await Sign.instance.connect(
                namespaces: [
                    Self.stellarNamespaceKey: ProposalNamespace(
                        chains: [Blockchain(Self.testnetChain)].compactMap { $0 },
                        methods: [Self.signMethod],
                        events: []
                    )
                ]
            )
            // Hand the URI to Freighter Mobile via its `wc-redirect` deep link.
            // Reown's wallet registry documents the scheme as
            // `freighterwallet://wc-redirect?uri={percent-encoded WC URI}`. The
            // raw WC URI contains `?`, `&`, `=`, and other reserved characters
            // that must all be encoded; `.alphanumerics` is the safest charset
            // because it encodes every reserved/sub-delim character. After this
            // call, the continuation remains pending until either
            // `handleSessionSettled` (via `sessionSettlePublisher`) fires or the
            // connectionTimeout watchdog rejects it.
            await openWalletPairingUri(uri.absoluteString)
        } catch {
            let pending = stateLock.withLock { () -> SafeCheckedVoidContinuation? in
                let cont = _pendingConnectContinuation
                _pendingConnectContinuation = nil
                return cont
            }
            pending?.resume(throwing: WalletConnectorError.reownError(underlying: error))
        }
    }

    @MainActor
    func openWalletPairingUri(_ uriString: String) {
        guard
            let encoded = uriString.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
            let url = URL(string: "freighterwallet://wc-redirect?uri=\(encoded)")
        else {
            logger.error("Reown: failed to build Freighter wc-redirect URL.")
            return
        }
        UIApplication.shared.open(url) { [weak self] success in
            if !success {
                self?.logger.info("Reown: opening Freighter via wc-redirect failed — is Freighter installed?")
            }
        }
    }

    func sendSignRequest(
        session: Session,
        chain: Blockchain,
        authEntryXdr: String,
        contextRuleIds: [UInt32]
    ) async throws -> String {
        try await withSafeCheckedThrowingContinuation { safe in
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    safe.resume(throwing: WalletConnectorError.noActiveSession)
                    return
                }
                Task {
                    await self.executeSignRequest(
                        session: session,
                        chain: chain,
                        authEntryXdr: authEntryXdr,
                        contextRuleIds: contextRuleIds,
                        safe: safe
                    )
                }
            }
        }
    }

    func executeSignRequest(
        session: Session,
        chain: Blockchain,
        authEntryXdr: String,
        contextRuleIds: [UInt32],
        safe: SafeCheckedContinuation<String>
    ) async {
        do {
            // `AnyCodable` has two inits: `init<C>(_ codable: C) where C: Codable`
            // and `init(any value: Any)`. `[String: Any]` is not Codable, so the
            // `any:`-labelled init is required. The explicit `[String: Any]` cast
            // keeps Swift 6 strict-mode type inference unambiguous because the
            // dictionary mixes `String` and `[Int]`.
            let params = AnyCodable(any: [
                "entryXdr": authEntryXdr,
                "contextRuleIds": contextRuleIds.map { Int($0) }
            ] as [String: Any])
            let wcRequest = try Request(
                topic: session.topic,
                method: Self.signMethod,
                params: params,
                chainId: chain,
                ttl: Self.requestTtlSeconds
            )
            let requestIdKey = wcRequest.id.string
            let entry = PendingSignEntry(
                continuation: safe,
                requestId: wcRequest.id,
                sessionTopic: session.topic
            )
            stateLock.withLock { _pendingSignContinuations[requestIdKey] = entry }
            do {
                try await Sign.instance.request(params: wcRequest)
            } catch {
                // C2: Remove the dictionary entry BEFORE resuming the continuation so that
                // any late wallet response that arrives before the removal cannot look up
                // this entry and attempt a second resume on an already-resumed continuation.
                let registered = stateLock.withLock {
                    _pendingSignContinuations.removeValue(forKey: requestIdKey)
                }
                // Resume via the dictionary-extracted value if present (confirms we own
                // it); fall back to `safe` directly if for some reason the key was already
                // removed (e.g., a concurrent timeout fired between request() throwing and
                // this catch block — in that case the timeout already resumed `safe` and
                // the SafeCheckedContinuation wrapper will absorb the duplicate attempt).
                (registered?.continuation ?? safe).resume(
                    throwing: WalletConnectorError.reownError(underlying: error)
                )
                return
            }
            await openWalletForSigning(session: session)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.signingTimeoutSeconds) { [weak self] in
                guard let self else { return }
                let timed = self.stateLock.withLock {
                    self._pendingSignContinuations.removeValue(forKey: requestIdKey)
                }
                guard let timed else { return }
                timed.continuation.resume(throwing: WalletConnectorError.signingTimeout)
                // Signal the wallet to dismiss the pending signing prompt.
                // `Sign.instance.respond(topic:requestId:response:)` is the only
                // dApp-side mechanism in this version of the SDK for retiring a
                // pending request at the relay layer. Best-effort; non-fatal.
                Task {
                    try? await Sign.instance.respond(
                        topic: timed.sessionTopic,
                        requestId: timed.requestId,
                        response: .error(JSONRPCError(code: -32000, message: "Request timed out"))
                    )
                }
                self.logger.info("Reown: sign request timed out for request id [request-id:REDACTED]; wallet notified.")
            }
        } catch {
            safe.resume(throwing: WalletConnectorError.reownError(underlying: error))
        }
    }

    func handleSessionSettled(_ session: Session) {
        guard isValidStellarTestnetSession(session),
              let address = stellarAddress(from: session) else {
            rejectPendingConnect(code: -3, reason: "Session not scoped to stellar:testnet")
            return
        }
        // Check whether the connect timeout already fired. `_pendingConnectContinuation`
        // is nil after the timeout block clears it. Installing an active session
        // for a caller that has already received `connectionTimeout` would diverge
        // app state from relay state, so we disconnect the late session instead.
        let pending = stateLock.withLock { () -> SafeCheckedVoidContinuation? in
            let cont = _pendingConnectContinuation
            if cont != nil {
                // Timeout has NOT fired: install the session and resolve the caller.
                _activeSession = session
                _connectedAddress = address
                _walletMetadata = WalletMetadata(
                    name: session.peer.name,
                    url: session.peer.url,
                    iconUrl: session.peer.icons.first
                )
                _pendingConnectContinuation = nil
            }
            return cont
        }
        if let pending {
            pending.resume()
        } else {
            // Timeout fired before this session arrived. Disconnect the orphan
            // session so relay state stays consistent with the error the caller saw.
            logger.info("Reown: late session settle received after connect timeout; disconnecting orphan session.")
            Task { try? await Sign.instance.disconnect(topic: session.topic) }
        }
    }

    func rejectPendingConnect(code: Int, reason: String) {
        let pending = stateLock.withLock { () -> SafeCheckedVoidContinuation? in
            let cont = _pendingConnectContinuation
            _pendingConnectContinuation = nil
            return cont
        }
        pending?.resume(
            throwing: WalletConnectorError.reownError(
                underlying: NSError(
                    domain: "ReownWalletHandler",
                    code: code,
                    userInfo: [NSLocalizedDescriptionKey: reason]
                )
            )
        )
    }

    func handleSessionResponse(_ response: Response) {
        let idKey = response.id.string
        let entry = stateLock.withLock {
            _pendingSignContinuations.removeValue(forKey: idKey)
        }
        guard let entry else {
            // No continuation found: the request already timed out, was cancelled,
            // or the session was disconnected. Log and discard.
            logger.info("Reown: late sign response received for request id [request-id:REDACTED]; discarded.")
            return
        }
        switch response.result {
        case .response(let anyCodable):
            if let dict = anyCodable.value as? [String: Any],
               let signed = dict["signedAuthEntry"] as? String {
                entry.continuation.resume(returning: signed)
            } else if let signed = anyCodable.value as? String {
                entry.continuation.resume(returning: signed)
            } else {
                entry.continuation.resume(
                    throwing: WalletConnectorError.malformedWalletResponse(
                        detail: "Response is not a string or {signedAuthEntry} object"
                    )
                )
            }
        case .error(let rpcError):
            entry.continuation.resume(
                throwing: WalletConnectorError.signingRejected(reason: rpcError.message)
            )
        }
    }

    func isValidStellarTestnetSession(_ session: Session) -> Bool {
        session.namespaces[Self.stellarNamespaceKey]?.accounts
            .contains { $0.blockchainIdentifier == Self.testnetChain } ?? false
    }

    func stellarAddress(from session: Session) -> String? {
        session.namespaces[Self.stellarNamespaceKey]?.accounts
            .first { $0.blockchainIdentifier == Self.testnetChain }?.address
    }

    @MainActor
    func openWalletForSigning(session: Session) {
        guard let urlString = session.peer.redirect?.native ?? session.peer.redirect?.universal,
              let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}

#else

import Foundation

// MARK: - Simulator stub

/// Simulator-only stub. All methods throw `WalletConnectorError.notSupportedInSimulator`.
///
/// Conforms to `NoOpWalletConnectorMarker` so any UI surface gating "wallet
/// available" off `!(connector is NoOpWalletConnectorMarker)` hides cleanly
/// in the simulator — same treatment the macOS `NoOpWalletConnector` gets.
/// Showing wallet-connect UI that immediately throws would be worse UX than
/// hiding it.
// @unchecked-justified: no mutable state; all properties are read-only computed vars
// returning constants; no concurrency concern.
public final class ReownWalletHandler: WalletConnector, NoOpWalletConnectorMarker, @unchecked Sendable {

    public var connectedAddress: String? { nil }
    public var walletMetadata: WalletMetadata? { nil }

    public static func configureOnce() {
        // No-op in simulator — Reown is not configured.
    }

    public init() {}

    public func connect() async throws {
        throw WalletConnectorError.notSupportedInSimulator
    }

    public func disconnect() async {}

    public func signAuthEntry(authEntryXdr: String, contextRuleIds: [UInt32]) async throws -> SignedAuthEntry {
        throw WalletConnectorError.notSupportedInSimulator
    }

    /// Simulator no-op. The custom URL scheme is not exercised in the simulator
    /// because the wallet path is gated off there; this exists only so the
    /// SwiftUI `.onOpenURL` handler in the app entry compiles against the same
    /// public surface on both targets.
    public static func handleOpenURL(_ url: URL) {}
}

#endif

import Foundation

// MARK: - Unconfigured wallet connector

/// No-op connector injected when no Reown project ID is configured.
///
/// Conforms to `NoOpWalletConnectorMarker` so the shared UI gating "wallet
/// available" off `!(connector is NoOpWalletConnectorMarker)` hides the
/// "Connect Wallet" affordance — the same treatment the simulator stub and the
/// macOS connector receive. The Reown networking stack is never configured and
/// the Reown SDK is never initialised when this connector is in use.
///
/// Set `DemoConfig.reownProjectId` to a project ID from https://reown.com to
/// install the live `ReownWalletHandler` instead.
// @unchecked-justified: no mutable state; all properties are read-only computed
// vars returning constants; no concurrency concern.
public final class UnconfiguredWalletConnector: WalletConnector, NoOpWalletConnectorMarker, @unchecked Sendable {

    public var connectedAddress: String? { nil }
    public var walletMetadata: WalletMetadata? { nil }

    public init() {}

    public func connect() async throws {
        throw WalletConnectorError.notSupportedOnPlatform(
            reason: "No Reown project ID configured. Set DemoConfig.reownProjectId to enable external-wallet connect."
        )
    }

    public func disconnect() async {}

    public func signAuthEntry(authEntryXdr: String, contextRuleIds: [UInt32]) async throws -> SignedAuthEntry {
        throw WalletConnectorError.notSupportedOnPlatform(
            reason: "No Reown project ID configured. Set DemoConfig.reownProjectId to enable external-wallet connect."
        )
    }
}
