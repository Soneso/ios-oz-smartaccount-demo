// DemoStateBootstrapErrorTest.swift
// SmartAccountDemoTests
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
#if canImport(UIKit)
@testable import SmartAccountDemoLib
#else
@testable import SmartAccountDemoMacLib
#endif
import stellarsdk
import Testing

// ============================================================================
// MARK: - DemoStateBootstrapErrorTest
// ============================================================================

/// Verifies that `MainScreenFlow.initializeKit()` routes provider-init failures
/// to the activity log when a required platform provider is missing.
///
/// Errors are surfaced exclusively through the activity log so screens observe
/// a single state source rather than a dedicated error field.
@Suite("DemoState bootstrap error path (activity log only)")
struct DemoStateBootstrapErrorTest {

    @Test("initializeKit logs error when WebAuthn provider is nil")
    @MainActor
    func kitInitLogsErrorWhenProviderMissing() async {
        let state = DemoState()
        state.setStorage(InMemoryStorageAdapter())
        // WebAuthn provider deliberately absent.

        let log = ActivityLogState()
        let flow = MainScreenFlow(demoState: state, activityLog: log)

        await flow.initializeKit()

        // The error path must append at least one .error-level entry.
        #expect(log.entries.contains { $0.level == .error },
                "Expected an error log entry when provider is missing")
    }

    @Test("initializeKit logs error message containing 'Failed to initialize SDK' prefix")
    @MainActor
    func kitInitErrorMessageHasExpectedPrefix() async {
        let state = DemoState()
        // Neither provider injected — provider-nil guard fires first.

        let log = ActivityLogState()
        let flow = MainScreenFlow(demoState: state, activityLog: log)

        await flow.initializeKit()

        #expect(log.entries.contains { $0.message.hasPrefix("Failed to initialize SDK:") },
                "Expected activity log entry starting with 'Failed to initialize SDK:'")
    }

    @Test("initializeKit does not set kit when provider is missing")
    @MainActor
    func kitInitDoesNotSetKitOnFailure() async {
        let state = DemoState()
        state.setStorage(InMemoryStorageAdapter())

        let log = ActivityLogState()
        let flow = MainScreenFlow(demoState: state, activityLog: log)

        await flow.initializeKit()

        #expect(state.kit == nil, "kit must remain nil after a failed init")
    }
}
