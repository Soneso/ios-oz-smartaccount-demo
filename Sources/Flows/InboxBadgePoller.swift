// InboxBadgePoller.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation

// ============================================================================
// MARK: - InboxBadgePoller
// ============================================================================

/// Refreshes the inbox bell badge by polling the coordination server for the
/// pending agent-escalation count while a wallet is connected.
///
/// Owns the poll loop, the inter-poll sleep, the de-duplicated error logging,
/// and the badge-state write so the iOS and macOS `MainScreen` shells share one
/// implementation. Each shell starts it from a `.task(id:)` keyed on the
/// connected account: keying on the account restarts the poll whenever the
/// account changes, and the surrounding task's cancellation (screen disappears
/// or the account changes) stops it.
@MainActor
public struct InboxBadgePoller {

    // -------------------------------------------------------------------------
    // MARK: - Dependencies
    // -------------------------------------------------------------------------

    private let demoState: DemoState
    private let activityLog: ActivityLogState

    /// Seconds between inbox pending-count polls.
    public static let pollInterval: Double = 8

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates a poller bound to the shared demo state and activity log.
    public init(demoState: DemoState, activityLog: ActivityLogState) {
        self.demoState = demoState
        self.activityLog = activityLog
    }

    // -------------------------------------------------------------------------
    // MARK: - Run
    // -------------------------------------------------------------------------

    /// Polls the pending-count endpoint until the surrounding task is cancelled.
    ///
    /// Sets the badge count to zero and returns immediately when no wallet is
    /// connected. While connected, refreshes the count every
    /// ``pollInterval`` seconds. A failed fetch leaves the previous count in
    /// place rather than clearing the badge, and is logged once at info level
    /// when the failure first appears (de-duplicated so a sustained outage does
    /// not flood the activity log every interval).
    public func run() async {
        guard demoState.isConnected else {
            demoState.setPendingRequestCount(0)
            return
        }
        let inbox = DemoFlowFactory.makeApprovalInboxFlow(
            demoState: demoState,
            activityLog: activityLog
        )
        var lastLoggedError: String?
        while !Task.isCancelled {
            do {
                let count = try await inbox.pendingCount()
                demoState.setPendingRequestCount(count)
                lastLoggedError = nil
            } catch {
                // The badge is best-effort: keep the previous count and keep
                // polling. Surface the failure at info level, de-duplicated, so a
                // transient blip is visible without spamming the log every poll.
                let message = ActivityLogState.redact(actionableMessage(for: error))
                if message != lastLoggedError {
                    activityLog.info("Inbox badge refresh paused: \(message)")
                    lastLoggedError = message
                }
            }
            do {
                try await Task.sleep(for: .seconds(Self.pollInterval))
            } catch {
                return
            }
        }
    }
}
