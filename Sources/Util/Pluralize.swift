// Pluralize.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

// ============================================================================
// MARK: - English-only count-aware string helper
// ============================================================================

/// Returns a count-qualified string using the correct English singular or
/// plural form.  Example: `pluralize(1, "day", "days")` → `"1 day"`.
///
/// All user-facing strings are English-only. Whenever a count-dependent word
/// is needed, call this helper instead of hard-coding the `(s)` suffix.
///
/// - Parameters:
///   - count: The integer quantity to display.
///   - singular: The word form used when `count == 1`.
///   - plural: The word form used for all other values of `count`.
/// - Returns: `"\(count) \(singular)"` or `"\(count) \(plural)"`.
public func pluralize(_ count: Int, _ singular: String, _ plural: String) -> String {
    "\(count) \(count == 1 ? singular : plural)"
}
