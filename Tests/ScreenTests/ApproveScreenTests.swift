// ApproveScreenTests.swift
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
import SwiftUI
import Testing

// ============================================================================
// MARK: - ApproveScreenCore construction
// ============================================================================

@Suite("ApproveScreenCore: Construction")
@MainActor
struct ApproveScreenCoreConstructionTests {

    @Test("Core view constructs with an onDismiss closure")
    func core_constructs() {
        _ = ApproveScreenCore { }
    }
}

// ============================================================================
// MARK: - ApproveExpirationOption
// ============================================================================

@Suite("ApproveExpirationOption: Cases")
struct ApproveExpirationOptionCaseTests {

    @Test("All three cases are exposed")
    func allCases_includesAllThree() {
        let allCases = ApproveExpirationOption.allCases
        #expect(allCases.count == 3)
        #expect(allCases.contains(.oneDay))
        #expect(allCases.contains(.tenDays))
        #expect(allCases.contains(.thirtyDays))
    }
}
