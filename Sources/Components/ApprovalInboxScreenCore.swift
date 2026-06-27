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
            removeResolved(request.id)
            showSnack("Approved. Transaction \(truncateAddress(result.hash ?? ""))")
            postAccessibilityAnnouncement("Approval submitted")
        } else if result.confirmedOnChain {
            reportPending.insert(request.id)
            showSnack(result.error ??
                "Transaction confirmed on-chain, but reporting it back failed. Retry the report.")
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
            removeResolved(request.id)
            showSnack("Reported. Transaction \(truncateAddress(result.hash ?? ""))")
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
