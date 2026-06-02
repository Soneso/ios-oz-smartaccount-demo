// SafeCheckedContinuation.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import os.log

// ============================================================================
// MARK: - SafeCheckedContinuation
// ============================================================================

/// A thread-safe wrapper around `CheckedContinuation<T, Error>` that enforces the
/// single-resume invariant at runtime.
///
/// `CheckedContinuation` is a reference type that must be resumed exactly once.
/// Resuming it a second time — however it happens (double-callback, timeout racing
/// a late wallet response, re-entrant connect) — causes an uncatchable runtime trap
/// in production. `SafeCheckedContinuation` prevents the second resume from reaching
/// the underlying continuation:
///
/// - **Debug builds:** the second resume calls `fatalError` immediately with a precise
///   source location, making the defect impossible to miss during development.
/// - **Release builds:** the second resume is silently dropped and logged via `os_log`
///   at error level. This prevents the runtime trap from reaching production users while
///   preserving the operational signal in system logs.
///
/// The `resumed` flag is guarded by an `OSAllocatedUnfairLock<Bool>`, which is both
/// `Sendable` and extremely low-overhead (backed by `os_unfair_lock`). The wrapper
/// itself is `@unchecked Sendable`; the `CheckedContinuation` underneath is guaranteed
/// by the Swift runtime to be safe to resume from any thread exactly once.
///
/// Usage:
/// ```swift
/// let result = try await withSafeCheckedThrowingContinuation { safe in
///     // store `safe` somewhere; resume it when the async event arrives
///     safe.resume(returning: value)
/// }
/// ```
// @unchecked-justified: OSAllocatedUnfairLock guards the resumed flag; CheckedContinuation
// is internally thread-safe by the Swift runtime; no mutable state escapes the lock.
public final class SafeCheckedContinuation<T: Sendable>: @unchecked Sendable {

    // -------------------------------------------------------------------------
    // MARK: - Storage
    // -------------------------------------------------------------------------

    private let continuation: CheckedContinuation<T, Error>
    private let resumed: OSAllocatedUnfairLock<Bool>

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Wraps a raw `CheckedContinuation<T, Error>`.
    ///
    /// Do not call directly. Use `withSafeCheckedThrowingContinuation(_:)` instead.
    public init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
        self.resumed = OSAllocatedUnfairLock(initialState: false)
    }

    // -------------------------------------------------------------------------
    // MARK: - Resume
    // -------------------------------------------------------------------------

    /// Resumes the continuation by returning a value.
    ///
    /// Safe to call from any thread. If called more than once, the second call is
    /// detected atomically. In Debug the process terminates with a descriptive
    /// `fatalError`; in Release the duplicate resume is dropped and logged.
    ///
    /// - Parameters:
    ///   - value: The value to return to the awaiting task.
    ///   - file:  Caller source file (filled automatically).
    ///   - line:  Caller source line (filled automatically).
    public func resume(returning value: T, file: StaticString = #fileID, line: UInt = #line) {
        let alreadyResumed = resumed.withLock { flag -> Bool in
            if flag { return true }
            flag = true
            return false
        }
        if alreadyResumed {
            handleDoubleResume(file: file, line: line)
            return
        }
        continuation.resume(returning: value)
    }

    /// Resumes the continuation by throwing an error.
    ///
    /// Safe to call from any thread. Duplicate-resume detection applies identically
    /// to `resume(returning:)`.
    ///
    /// - Parameters:
    ///   - error: The error to throw in the awaiting task.
    ///   - file:  Caller source file (filled automatically).
    ///   - line:  Caller source line (filled automatically).
    public func resume(throwing error: Error, file: StaticString = #fileID, line: UInt = #line) {
        let alreadyResumed = resumed.withLock { flag -> Bool in
            if flag { return true }
            flag = true
            return false
        }
        if alreadyResumed {
            handleDoubleResume(file: file, line: line)
            return
        }
        continuation.resume(throwing: error)
    }

    /// Resumes the continuation from a `Result<T, Error>`.
    ///
    /// Convenience wrapper over `resume(returning:)` and `resume(throwing:)`.
    ///
    /// - Parameters:
    ///   - result: The result to deliver to the awaiting task.
    ///   - file:   Caller source file (filled automatically).
    ///   - line:   Caller source line (filled automatically).
    public func resume(with result: Result<T, Error>, file: StaticString = #fileID, line: UInt = #line) {
        switch result {
        case .success(let value):
            resume(returning: value, file: file, line: line)
        case .failure(let error):
            resume(throwing: error, file: file, line: line)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Double-resume handling
    // -------------------------------------------------------------------------

    private func handleDoubleResume(file: StaticString, line: UInt) {
        #if DEBUG
        fatalError("SafeCheckedContinuation resumed twice at \(file):\(line)")
        #else
        let logger = Logger(subsystem: "com.soneso.stellar.smartaccount.demo", category: "SafeCheckedContinuation")
        logger.error("SafeCheckedContinuation resumed twice at \(file, privacy: .public):\(line, privacy: .public)")
        #endif
    }
}

// ============================================================================
// MARK: - Void convenience alias
// ============================================================================

/// A `SafeCheckedContinuation` specialized to `Void` for throwing-continuation sites
/// where the result carries no value.
///
/// Callers use `safe.resume()` instead of `safe.resume(returning: ())` for readability.
// @unchecked-justified: OSAllocatedUnfairLock guards the resumed flag; CheckedContinuation
// is internally thread-safe by the Swift runtime; no mutable state escapes the lock.
public final class SafeCheckedVoidContinuation: @unchecked Sendable {


    private let continuation: CheckedContinuation<Void, Error>
    private let resumed: OSAllocatedUnfairLock<Bool>

    /// Wraps a raw `CheckedContinuation<Void, Error>`.
    ///
    /// Do not call directly. Use `withSafeCheckedThrowingVoidContinuation(_:)` instead.
    public init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
        self.resumed = OSAllocatedUnfairLock(initialState: false)
    }

    /// Resumes the continuation successfully (returns `Void`).
    ///
    /// - Parameters:
    ///   - file: Caller source file (filled automatically).
    ///   - line: Caller source line (filled automatically).
    public func resume(file: StaticString = #fileID, line: UInt = #line) {
        let alreadyResumed = resumed.withLock { flag -> Bool in
            if flag { return true }
            flag = true
            return false
        }
        if alreadyResumed {
            handleDoubleResume(file: file, line: line)
            return
        }
        continuation.resume()
    }

    /// Resumes the continuation by throwing an error.
    ///
    /// - Parameters:
    ///   - error: The error to throw in the awaiting task.
    ///   - file:  Caller source file (filled automatically).
    ///   - line:  Caller source line (filled automatically).
    public func resume(throwing error: Error, file: StaticString = #fileID, line: UInt = #line) {
        let alreadyResumed = resumed.withLock { flag -> Bool in
            if flag { return true }
            flag = true
            return false
        }
        if alreadyResumed {
            handleDoubleResume(file: file, line: line)
            return
        }
        continuation.resume(throwing: error)
    }

    /// Resumes the continuation from a `Result<Void, Error>`.
    ///
    /// - Parameters:
    ///   - result: The result to deliver to the awaiting task.
    ///   - file:   Caller source file (filled automatically).
    ///   - line:   Caller source line (filled automatically).
    public func resume(with result: Result<Void, Error>, file: StaticString = #fileID, line: UInt = #line) {
        switch result {
        case .success:
            resume(file: file, line: line)
        case .failure(let error):
            resume(throwing: error, file: file, line: line)
        }
    }

    private func handleDoubleResume(file: StaticString, line: UInt) {
        #if DEBUG
        fatalError("SafeCheckedVoidContinuation resumed twice at \(file):\(line)")
        #else
        let logger = Logger(subsystem: "com.soneso.stellar.smartaccount.demo", category: "SafeCheckedContinuation")
        logger.error("SafeCheckedVoidContinuation resumed twice at \(file, privacy: .public):\(line, privacy: .public)")
        #endif
    }
}

// ============================================================================
// MARK: - Companion functions
// ============================================================================

/// Suspends the current task and creates a `SafeCheckedContinuation<T, Error>`.
///
/// This is the safe replacement for `withCheckedThrowingContinuation`. The body
/// receives a `SafeCheckedContinuation<T>` which tracks the resumed state and
/// prevents double-resume from reaching the underlying `CheckedContinuation`.
///
/// - Parameter body: A closure receiving the safe continuation. The closure must
///   arrange for `safe.resume(returning:)`, `safe.resume(throwing:)`, or
///   `safe.resume(with:)` to be called exactly once across all code paths.
///   Calling it more than once is caught (Debug: fatalError; Release: os_log).
/// - Returns: The value delivered by `resume(returning:)`.
/// - Throws: The error delivered by `resume(throwing:)` or `resume(with:)`.
public func withSafeCheckedThrowingContinuation<T: Sendable>(
    _ body: (SafeCheckedContinuation<T>) -> Void
) async throws -> T {
    try await withCheckedThrowingContinuation { raw in
        body(SafeCheckedContinuation(raw))
    }
}

/// Suspends the current task and creates a `SafeCheckedVoidContinuation`.
///
/// This is the safe replacement for `withCheckedThrowingContinuation` at `Void`-valued
/// sites. The body receives a `SafeCheckedVoidContinuation` which tracks the resumed
/// state and prevents double-resume.
///
/// - Parameter body: A closure receiving the safe void continuation. Must call
///   `safe.resume()` or `safe.resume(throwing:)` exactly once.
/// - Throws: The error delivered by `resume(throwing:)`.
public func withSafeCheckedThrowingVoidContinuation(
    _ body: (SafeCheckedVoidContinuation) -> Void
) async throws {
    try await withCheckedThrowingContinuation { (raw: CheckedContinuation<Void, Error>) in
        body(SafeCheckedVoidContinuation(raw))
    }
}
