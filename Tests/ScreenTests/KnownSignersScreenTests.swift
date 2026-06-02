// KnownSignersScreenTests.swift
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
// MARK: - KnownSignersScreenCore construction
// ============================================================================

@Suite("KnownSignersScreenCore: Construction")
@MainActor
struct KnownSignersScreenCoreConstructionTests {

    @Test("Core view constructs with an onDismiss closure")
    func core_constructs() {
        _ = KnownSignersScreenCore { }
    }
}
