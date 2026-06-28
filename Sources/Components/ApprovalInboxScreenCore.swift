// ApprovalInboxScreenCore.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - ApprovalInboxScreenCore
// ============================================================================

/// Shared body for the approval inbox screen (steps 4 + 5 of the agent-signer
/// flow), hosted by the iOS and macOS shells.
///
/// Lists the policy-rejected smart-account calls the autonomous agent escalated
/// to the coordination server, scoped to the connected smart account. Each card
/// shows the smart account, target contract, function, the decoded rejection
/// reason, and — as the authoritative consent data — the recipient and on-chain
/// amount DECODED from the call arguments that actually execute (never the
/// server-supplied display amount). Approving rebuilds the agent's exact call
/// and re-submits it under the user's Default rule (single-signer passkey), then
/// reports the resulting transaction hash back.
///
/// All SDK and HTTP interactions are delegated to ``ApprovalInboxFlow``. This
/// view never references SDK kit classes or the HTTP client directly.
public struct ApprovalInboxScreenCore: View {

    // -------------------------------------------------------------------------
    // MARK: - Environment
    // -------------------------------------------------------------------------

    @EnvironmentObject private var demoState: DemoState
    @EnvironmentObject private var activityLog: ActivityLogState

    // -------------------------------------------------------------------------
    // MARK: - Flow
    // -------------------------------------------------------------------------

    @State private var flow: ApprovalInboxFlow?

    // -------------------------------------------------------------------------
    // MARK: - Load state
    // -------------------------------------------------------------------------

    @State private var isLoading: Bool = false
    @State private var loaded: Bool = false
    @State private var loadError: String?
    @State private var pending: [CoordinationRequest] = []

    /// IDs of requests with an approve/reject/report action in flight, so the
    /// active card shows its spinner.
    @State private var busyIds: Set<String> = []

    /// True while any approve/reject/report action is in flight. All cards'
    /// actions are disabled during that window so a second card cannot start a
    /// concurrent approval.
    @State private var actionInFlight: Bool = false

    /// IDs whose transaction confirmed on-chain but whose report-back is still
    /// outstanding: their card shows "Retry report" instead of "Approve".
    @State private var reportPending: Set<String> = []

    /// Session-scoped list of approvals that resolved on-chain, newest first.
    ///
    /// Each entry retains the FULL transaction hash so the user can copy it or
    /// open it on the explorer after the brief confirmation toast has gone. An
    /// approval that confirmed on-chain without a returned hash is kept here too,
    /// with an empty hash, so it degrades to an informational row rather than a
    /// broken copy control. Cleared only when the screen is torn down.
    @State private var approvedResults: [ApprovedResult] = []

    // -------------------------------------------------------------------------
    // MARK: - Reject dialog state
    // -------------------------------------------------------------------------

    @State private var rejectTarget: CoordinationRequest?
    @State private var rejectNote: String = ""

    // -------------------------------------------------------------------------
    // MARK: - Toast state
    // -------------------------------------------------------------------------

    @State private var snackbarMessage: SnackbarMessage?

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    public init() {}

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    public var body: some View {
        List {
            descriptionSection
            connectionNoteSection
            refreshSection
            approvedSection
            contentSections
        }
        .snackbar($snackbarMessage)
        .task { if !loaded { await load() } }
        .alert("Reject escalation", isPresented: rejectPresented, presenting: rejectTarget) { request in
            TextField("Note (optional)", text: $rejectNote)
            Button("Cancel", role: .cancel) { rejectTarget = nil }
            Button("Reject", role: .destructive) {
                let note = rejectNote
                rejectTarget = nil
                Task { await reject(request, note: note) }
            }
        } message: { _ in
            Text("Why are you rejecting this call?")
        }
    }

    private var rejectPresented: Binding<Bool> {
        Binding(get: { rejectTarget != nil }, set: { if !$0 { rejectTarget = nil } })
    }

    // -------------------------------------------------------------------------
    // MARK: - Description section
    // -------------------------------------------------------------------------

    private var descriptionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Agent Escalations")
                Text(
                    "Calls the agent attempted that its on-chain policy rejected. Approving " +
                    "re-submits the exact call under your Default rule (single-signer passkey); " +
                    "rejecting declines it. The recipient and amount shown are decoded from the " +
                    "call that executes."
                )
                .font(Typography.secondary)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var connectionNoteSection: some View {
        Section {
            if demoState.isConnected {
                signingAsNote
            } else {
                notConnectedNote
            }
        }
    }

    private var signingAsNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.seal")
                .foregroundStyle(Color.brandPrimary)
                .accessibilityHidden(true)
            (
                Text("Approvals sign as ")
                + Text(truncateAddress(demoState.contractId ?? "")).font(Typography.mono.weight(.bold))
                + Text(". Only escalations for this account are shown.")
            )
            .font(Typography.secondary)
            .foregroundStyle(.secondary)
        }
    }

    private var notConnectedNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.brandPrimary)
                .accessibilityHidden(true)
            Text(
                "Connect a wallet to review escalations for your smart account. The inbox shows " +
                "only the calls raised against the account you are connected to."
            )
            .font(Typography.secondary)
            .foregroundStyle(.secondary)
        }
    }

    private var refreshSection: some View {
        Section {
            LoadingButton(isLoading ? "Loading..." : "Refresh", loadingLabel: "Loading...", style: .outlined) {
                await load()
            }
            .disabled(isLoading)
        }
        .listRowBackground(Color.clear)
    }

    // -------------------------------------------------------------------------
    // MARK: - Approved section
    // -------------------------------------------------------------------------

    @ViewBuilder
    private var approvedSection: some View {
        if !approvedResults.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: "Approved")
                    Text(
                        "Approvals that resolved on-chain this session. Copy a transaction hash or " +
                        "open it on the explorer to look it up."
                    )
                    .font(Typography.secondary)
                    .foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(approvedResults) { result in
                    ApprovedResultCard(result: result, snackbarMessage: $snackbarMessage)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Content sections
    // -------------------------------------------------------------------------

    @ViewBuilder
    private var contentSections: some View {
        if isLoading && !loaded {
            Section {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.regular)
                    Spacer()
                }
                .padding(.vertical, 24)
            }
            .listRowBackground(Color.clear)
        } else if let loadError {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    InlineErrorBanner(message: loadError)
                    LoadingButton("Retry", style: .outlined) { await load() }
                }
            }
            .listRowBackground(Color.clear)
        } else if pending.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("No pending approvals", systemImage: "tray")
                } description: {
                    Text(
                        "When the agent escalates a policy-rejected call it appears here for you " +
                        "to approve or reject."
                    )
                }
                .symbolRenderingMode(.hierarchical)
            }
            .listRowBackground(Color.clear)
        } else {
            requestCardsSection
        }
    }

    private var requestCardsSection: some View {
        Section {
            ForEach(pending) { request in
                RequestCard(
                    request: request,
                    decoded: resolvedFlow().decodeCall(request),
                    busy: busyIds.contains(request.id),
                    enabled: !actionInFlight,
                    needsReport: reportPending.contains(request.id),
                    onApprove: { Task { await approve(request) } },
                    onReject: { presentReject(request) },
                    onRetryReport: { Task { await retryReport(request) } }
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Load
    // -------------------------------------------------------------------------

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false; loaded = true }
        do {
            let result = try await resolvedFlow().loadPending()
            pending = result
            let flow = resolvedFlow()
            reportPending = Set(result.map(\.id).filter(flow.isAwaitingReport))
            demoState.setPendingRequestCount(result.count)
        } catch let error as CoordinationError {
            loadError = "Could not reach the coordination server: \(error.message)"
        } catch {
            loadError = "Could not load pending approvals: \(actionableMessage(for: error))"
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Actions
    // -------------------------------------------------------------------------

    private func approve(_ request: CoordinationRequest) async {
        guard !actionInFlight else { showSnack("Another approval is in progress."); return }
        beginAction(request.id)
        let result = await resolvedFlow().approveRequest(request)
        endAction(request.id)
        if result.success {
            recordApproved(request, hash: result.hash ?? "")
            removeResolved(request.id)
            showSnack("Approved.")
            postAccessibilityAnnouncement("Approval submitted")
        } else if result.confirmedOnChain {
            let hash = result.hash ?? ""
            if hash.isEmpty {
                // Confirmed on-chain but no hash returned: nothing to report back,
                // so resolve the card and keep an informational approved entry.
                recordApproved(request, hash: hash)
                removeResolved(request.id)
                showSnack(result.error ??
                    "Transaction confirmed on-chain, but no transaction hash was returned.")
                postAccessibilityAnnouncement("Approval confirmed on-chain")
            } else {
                // Hash known but report-back failed: surface the confirmed hash in the
                // persistent approved list so it stays copyable, and keep the card so the
                // user can retry the report without re-submitting the call.
                recordApproved(request, hash: hash)
                reportPending.insert(request.id)
                showSnack(result.error ??
                    "Transaction confirmed on-chain, but reporting it back failed. Retry the report.")
            }
        } else {
            showSnack(result.error ?? "Approval failed.")
        }
    }

    private func retryReport(_ request: CoordinationRequest) async {
        guard !actionInFlight else { showSnack("Another approval is in progress."); return }
        beginAction(request.id)
        let result = await resolvedFlow().retryReport(request)
        endAction(request.id)
        if result.success {
            recordApproved(request, hash: result.hash ?? "")
            removeResolved(request.id)
            showSnack("Reported.")
        } else {
            showSnack(result.error ?? "Reporting failed.")
        }
    }

    private func reject(_ request: CoordinationRequest, note: String) async {
        guard !actionInFlight else { showSnack("Another approval is in progress."); return }
        beginAction(request.id)
        let result = await resolvedFlow().rejectRequest(request, note: note)
        endAction(request.id)
        if result.success {
            removeResolved(request.id)
            showSnack("Rejected.")
        } else {
            showSnack(result.error ?? "Rejection failed.")
        }
    }

    private func presentReject(_ request: CoordinationRequest) {
        guard !actionInFlight else { showSnack("Another approval is in progress."); return }
        rejectNote = ""
        rejectTarget = request
    }

    // -------------------------------------------------------------------------
    // MARK: - State helpers
    // -------------------------------------------------------------------------

    private func beginAction(_ id: String) {
        actionInFlight = true
        busyIds.insert(id)
    }

    private func endAction(_ id: String) {
        actionInFlight = false
        busyIds.remove(id)
    }

    /// Removes a resolved request from the list and keeps the badge in sync.
    private func removeResolved(_ id: String) {
        pending.removeAll { $0.id == id }
        reportPending.remove(id)
        demoState.setPendingRequestCount(pending.count)
    }

    private func showSnack(_ message: String) {
        snackbarMessage = SnackbarMessage(message)
    }

    /// Records a resolved approval in the persistent session list, newest first.
    ///
    /// A blank `hash` marks the confirmed-on-chain-but-no-hash case so the card
    /// renders an informational row with no copy/explorer control. Re-recording
    /// the same request (for example a retried report) replaces the prior entry.
    private func recordApproved(_ request: CoordinationRequest, hash: String) {
        let decoded = resolvedFlow().decodeCall(request)
        let entry = ApprovedResult(
            requestId: request.id,
            txHash: hash,
            contextLabel: ApprovedResult.contextLabel(for: request, decoded: decoded)
        )
        approvedResults.removeAll { $0.requestId == request.id }
        approvedResults.insert(entry, at: 0)
    }

    // -------------------------------------------------------------------------
    // MARK: - Flow resolution
    // -------------------------------------------------------------------------

    @MainActor
    private func resolvedFlow() -> ApprovalInboxFlow {
        if let flow { return flow }
        let newFlow = DemoFlowFactory.makeApprovalInboxFlow(
            demoState: demoState,
            activityLog: activityLog
        )
        flow = newFlow
        return newFlow
    }
}

// ============================================================================
// MARK: - RequestCard
// ============================================================================

/// A single pending-escalation card with Approve and Reject actions (or a
/// "Retry report" action once the transaction has confirmed on-chain).
private struct RequestCard: View {

    let request: CoordinationRequest
    let decoded: DecodedCall
    let busy: Bool
    let enabled: Bool
    let needsReport: Bool
    let onApprove: () -> Void
    let onReject: () -> Void
    let onRetryReport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            KeyValueRow(label: "Smart Account", value: truncateAddress(request.smartAccount), monospace: true)
            KeyValueRow(label: "Target", value: truncateAddress(request.target), monospace: true)
            KeyValueRow(label: "Function", value: request.targetFn)
            decodedRows
            if needsReport {
                retryReportRow
            } else {
                approveRejectRow
            }
        }
        .sectionCard()
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt")
                .foregroundStyle(Color.brandPrimary)
                .accessibilityHidden(true)
            Text(request.targetFn)
                .font(Typography.sectionHeader.weight(.bold))
            Spacer(minLength: 8)
            ReasonChip(reason: request.reason)
        }
    }

    @ViewBuilder
    private var decodedRows: some View {
        switch decoded.kind {
        case .transfer, .approve:
            KeyValueRow(
                label: decoded.recipientLabel ?? "Recipient",
                value: truncateAddress(decoded.recipient ?? "—"),
                monospace: true
            )
            KeyValueRow(label: "Amount", value: decoded.amount ?? "—", emphasised: true)
        case .unknown:
            Text("Arguments")
                .font(Typography.metadata.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(decoded.arguments) { arg in
                KeyValueRow(label: arg.label, value: arg.value, monospace: true)
            }
        case .undecodable:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Color.semanticError)
                    .accessibilityHidden(true)
                Text(decoded.error ?? "Cannot decode the stored call arguments. Do not approve.")
                    .font(Typography.secondary.weight(.semibold))
                    .foregroundStyle(Color.semanticError)
            }
        }
    }

    private var approveRejectRow: some View {
        // Approving is blocked while any action is in flight and when the call
        // arguments could not be decoded (the user cannot consent to an unknown
        // call). Rejecting stays available so an undecodable escalation can be
        // declined.
        let canApprove = enabled && decoded.kind != .undecodable
        return HStack(spacing: 12) {
            LoadingButton("Approve", loadingLabel: "Approving...", style: .primary) {
                await MainActor.run { onApprove() }
            }
            .disabled(!canApprove || busy)
            LoadingButton("Reject", style: .outlinedDestructive) {
                await MainActor.run { onReject() }
            }
            .disabled(!enabled || busy)
        }
        .padding(.top, 4)
    }

    private var retryReportRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(Color.brandPrimary)
                    .accessibilityHidden(true)
                Text(
                    "Confirmed on-chain. Reporting the result back to the agent failed; retry the " +
                    "report (the call is not re-submitted)."
                )
                .font(Typography.secondary)
                .foregroundStyle(.secondary)
            }
            LoadingButton("Retry report", loadingLabel: "Reporting...", style: .primary) {
                await MainActor.run { onRetryReport() }
            }
            .disabled(!enabled || busy)
        }
        .padding(.top, 4)
    }
}

// ============================================================================
// MARK: - ApprovedResult
// ============================================================================

/// A single resolved approval retained on the inbox screen for the session.
///
/// Holds the FULL transaction hash so the user can copy it or open it on the
/// explorer after the transient confirmation toast is gone. An approval that
/// confirmed on-chain without a returned hash is represented with an empty
/// ``txHash``; such an entry exposes no copy or explorer affordance.
public struct ApprovedResult: Identifiable, Equatable, Sendable {

    /// The coordination request this approval resolved.
    public let requestId: String

    /// The full on-chain transaction hash, or the empty string when the call
    /// confirmed on-chain but no hash was returned.
    public let txHash: String

    /// Short human-readable summary of the approved call (function, amount,
    /// recipient) shown above the hash, when cheaply derivable.
    public let contextLabel: String?

    public var id: String { requestId }

    public init(requestId: String, txHash: String, contextLabel: String? = nil) {
        self.requestId = requestId
        self.txHash = txHash
        self.contextLabel = contextLabel
    }

    /// True when a real on-chain hash is available to copy or open.
    public var hasHash: Bool { !txHash.isEmpty }

    /// stellar.expert testnet explorer URL for the transaction, or `nil` when no
    /// hash is available.
    public var explorerURL: URL? {
        guard hasHash else { return nil }
        return URL(string: "https://stellar.expert/explorer/testnet/tx/\(txHash)")
    }

    /// Derives a concise context label from the decoded call shape, or falls
    /// back to the called function name.
    public static func contextLabel(for request: CoordinationRequest, decoded: DecodedCall) -> String? {
        switch decoded.kind {
        case .transfer, .approve:
            let verb = decoded.kind == .approve ? "approve" : "transfer"
            let amount = decoded.amount ?? "—"
            let recipient = truncateAddress(decoded.recipient ?? "—")
            return "\(verb) \(amount) to \(recipient)"
        case .unknown, .undecodable:
            return request.targetFn
        }
    }
}

// ============================================================================
// MARK: - ApprovedResultCard
// ============================================================================

/// A persistent card showing one resolved approval with a copyable, selectable
/// full transaction hash and a "View on Explorer" link.
///
/// When the approval confirmed on-chain but returned no hash, the card degrades
/// to an informational row with no copy or explorer affordance.
private struct ApprovedResultCard: View {

    let result: ApprovedResult
    @Binding var snackbarMessage: SnackbarMessage?

    @Environment(\.clipboard) private var clipboard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let label = result.contextLabel {
                Text(label)
                    .font(Typography.secondary)
                    .foregroundStyle(.secondary)
            }
            if result.hasHash {
                hashBlock
                actionRow
            } else {
                noHashNote
            }
        }
        .sectionCard()
    }

    private var header: some View {
        HStack(spacing: Tokens.iconLabelSpacing) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.semanticSuccess)
                .accessibilityHidden(true)
            Text("Approved")
                .font(Typography.sectionHeader.weight(.bold))
            Spacer(minLength: 8)
        }
    }

    private var hashBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Transaction Hash")
                .font(Typography.caption)
                .foregroundStyle(Color.brandOnSurfaceVariant)
                .accessibilityHidden(true)
            Text(result.txHash)
                .font(.system(.footnote, design: .monospaced))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityLabel("Transaction hash: \(result.txHash)")
        }
    }

    private var actionRow: some View {
        HStack(spacing: 16) {
            Button(action: copyHash) {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(Typography.buttonLabel)
                    .foregroundStyle(Color.brandPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Copies the full transaction hash to the clipboard.")

            if let url = result.explorerURL {
                Link(destination: url) {
                    Label("View on Explorer", systemImage: "arrow.up.right.square")
                        .font(Typography.buttonLabel)
                        .foregroundStyle(Color.brandPrimary)
                }
                .accessibilityHint("Opens the transaction on stellar.expert.")
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private var noHashNote: some View {
        HStack(alignment: .top, spacing: Tokens.iconLabelSpacing) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Confirmed on-chain (no transaction hash returned).")
                .font(Typography.secondary)
                .foregroundStyle(.secondary)
        }
    }

    private func copyHash() {
        clipboard.copy(result.txHash, sensitive: false)
        snackbarMessage = SnackbarMessage("Transaction hash copied")
    }
}

// ============================================================================
// MARK: - ReasonChip
// ============================================================================

/// A small chip rendering the decoded rejection reason name.
private struct ReasonChip: View {

    let reason: Int

    var body: some View {
        Text(describeRejectionReason(reason))
            .font(Typography.metadata.weight(.semibold))
            .foregroundStyle(Color.semanticError)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.errorContainer)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
