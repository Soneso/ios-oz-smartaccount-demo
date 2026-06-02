// WasmResource.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation

// ============================================================================
// MARK: - WasmResource
// ============================================================================

/// Loads bundled WASM binaries from the main bundle.
///
/// The demo bundles `soroban_token_contract.wasm` in `Resources/`. This helper
/// centralises the bundle lookup so callers do not repeat the
/// `Bundle.main.url(forResource:withExtension:)` boilerplate and get a uniform
/// error when the resource is missing (which indicates a misconfigured project).
public enum WasmResource {

    // -------------------------------------------------------------------------
    // MARK: - Errors
    // -------------------------------------------------------------------------

    /// Errors thrown when a WASM resource cannot be loaded.
    public enum WasmError: LocalizedError {

        /// The named resource was not found in the main bundle.
        ///
        /// This is a programming error — the resource must be listed in
        /// the target's `Resources` phase in `project.yml`.
        case resourceNotFound(name: String)

        /// The resource URL was located but its data could not be read.
        case readFailed(name: String, underlying: Error)

        public var errorDescription: String? {
            switch self {
            case .resourceNotFound(let name):
                return "WASM resource '\(name).wasm' not found in main bundle. "
                    + "Verify it is included in the target's Resources build phase."
            case .readFailed(let name, let underlying):
                return "Failed to read WASM resource '\(name).wasm': \(underlying.localizedDescription)"
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Loading
    // -------------------------------------------------------------------------

    /// Loads the Soroban token contract WASM binary from the bundle.
    ///
    /// The returned `Data` is suitable for passing to SDK operations that
    /// accept a raw WASM payload (e.g. install + deploy flows).
    ///
    /// - Throws: `WasmError.resourceNotFound` if `soroban_token_contract.wasm`
    ///   is absent from `Bundle.main`. `WasmError.readFailed` if the file
    ///   exists but cannot be read.
    public static func loadTokenContract() throws -> Data {
        try load(named: "soroban_token_contract")
    }

    /// Loads a named WASM resource from the main bundle.
    ///
    /// - Parameter name: Resource name without the `.wasm` extension.
    /// - Throws: `WasmError.resourceNotFound` or `WasmError.readFailed`.
    public static func load(named name: String) throws -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wasm") else {
            throw WasmError.resourceNotFound(name: name)
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw WasmError.readFailed(name: name, underlying: error)
        }
    }
}
