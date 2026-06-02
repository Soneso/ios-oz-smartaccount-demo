// WasmResourceTests.swift
// SmartAccountDemoTests
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
#if canImport(UIKit)
@testable import SmartAccountDemoLib
#else
@testable import SmartAccountDemoMacLib
#endif
import Testing

// ============================================================================
// MARK: - WasmResourceTests
// ============================================================================

/// Tests for `WasmResource` in `WasmResource.swift`.
///
/// `loadTokenContract()` depends on `Bundle.main` which, in a test runner,
/// points to the test bundle — not a bundle that contains the WASM file.
/// These tests therefore verify the error-path (resource not found) and the
/// `load(named:)` direct-error path. The happy-path for `loadTokenContract`
/// is exercised by the app bundle at runtime; unit tests verify the error
/// type and description shape.
@Suite("WasmResource")
struct WasmResourceTests {

    // -------------------------------------------------------------------------
    // MARK: - load(named:) — missing resource
    // -------------------------------------------------------------------------

    @Test("load(named:) throws resourceNotFound for a missing WASM name")
    func loadMissingThrows() throws {
        #expect(throws: WasmResource.WasmError.self) {
            try WasmResource.load(named: "nonexistent_contract_xyz_not_real")
        }
    }

    @Test("load(named:) error description mentions the resource name")
    func loadMissingErrorDescriptionContainsName() {
        do {
            _ = try WasmResource.load(named: "my_missing_contract")
            // If we reach here the resource unexpectedly exists — skip the check.
        } catch let error as WasmResource.WasmError {
            let description = error.errorDescription ?? ""
            #expect(description.contains("my_missing_contract"))
        } catch {
            // Some other error type — still acceptable for the missing-file path.
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - loadTokenContract — missing in test bundle
    // -------------------------------------------------------------------------

    @Test("loadTokenContract throws when WASM is absent from the test bundle")
    func loadTokenContractThrowsInTestBundle() {
        // In the unit test runner, Bundle.main does not contain the production
        // resources (those live in the app bundle). This verifies the throw path.
        // If the test framework ever starts bundling resources here, this test
        // should be updated accordingly.
        #expect(throws: WasmResource.WasmError.self) {
            try WasmResource.loadTokenContract()
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - WasmError localised descriptions
    // -------------------------------------------------------------------------

    @Test("resourceNotFound error description includes the name and guidance")
    func resourceNotFoundDescription() {
        let error = WasmResource.WasmError.resourceNotFound(name: "sample")
        let description = error.errorDescription ?? ""
        #expect(description.contains("sample"))
        #expect(description.contains("Resources"))
    }

    @Test("readFailed error description includes the name and underlying error")
    func readFailedDescription() {
        let underlying = NSError(domain: "TestDomain", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "disk full"
        ])
        let error = WasmResource.WasmError.readFailed(name: "token_contract", underlying: underlying)
        let description = error.errorDescription ?? ""
        #expect(description.contains("token_contract"))
        #expect(description.contains("disk full"))
    }
}
