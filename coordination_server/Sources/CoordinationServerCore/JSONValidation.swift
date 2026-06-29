import Foundation

/// Field-level validators over a decoded JSON object (`[String: Any]` as
/// produced by `JSONSerialization`).
///
/// Each helper throws ``ValidationError`` with a field-specific message that
/// matches the wire contract, so a malformed body or a corrupt store record
/// fails loudly with the same diagnostics as every other client.
enum JSONField {
    /// JSON booleans decode to `NSNumber` like integers do; this distinguishes
    /// them so `true`/`false` are never accepted where an integer is required.
    private static func isBool(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    static func requireString(_ json: [String: Any], _ field: String) throws -> String {
        guard let value = json[field], !(value is NSNull) else {
            throw ValidationError("field '\(field)' must be a string")
        }
        guard let string = value as? String else {
            throw ValidationError("field '\(field)' must be a string")
        }
        return string
    }

    static func requireNonEmptyString(_ json: [String: Any], _ field: String) throws -> String {
        let value = try requireString(json, field)
        if value.isEmpty {
            throw ValidationError("field '\(field)' must not be empty")
        }
        return value
    }

    static func optionalString(_ json: [String: Any], _ field: String) throws -> String? {
        guard let value = json[field], !(value is NSNull) else {
            return nil
        }
        guard let string = value as? String else {
            throw ValidationError("field '\(field)' must be a string when present")
        }
        return string
    }

    /// Coerces a present, non-null JSON value to `Int`, rejecting booleans,
    /// non-numbers, fractional values, and values outside `Int`'s range.
    ///
    /// `presentSuffix` is appended to the error message so a required field
    /// reads "must be an integer" while an optional one reads "must be an
    /// integer when present".
    private static func coerceInt(_ value: Any, field: String, presentSuffix: String) throws -> Int {
        let message = "field '\(field)' must be an integer\(presentSuffix)"
        guard let number = value as? NSNumber, !isBool(value) else {
            throw ValidationError(message)
        }
        let doubleValue = number.doubleValue
        guard
            doubleValue.rounded(.towardZero) == doubleValue,
            doubleValue >= Double(Int.min),
            doubleValue <= Double(Int.max)
        else {
            throw ValidationError(message)
        }
        return number.intValue
    }

    static func requireInt(_ json: [String: Any], _ field: String) throws -> Int {
        guard let value = json[field], !(value is NSNull) else {
            throw ValidationError("field '\(field)' must be an integer")
        }
        return try coerceInt(value, field: field, presentSuffix: "")
    }

    static func optionalInt(_ json: [String: Any], _ field: String) throws -> Int? {
        guard let value = json[field], !(value is NSNull) else {
            return nil
        }
        return try coerceInt(value, field: field, presentSuffix: " when present")
    }

    static func requireStringList(_ json: [String: Any], _ field: String) throws -> [String] {
        guard let value = json[field], !(value is NSNull) else {
            throw ValidationError("field '\(field)' must be a list of strings")
        }
        guard let array = value as? [Any] else {
            throw ValidationError("field '\(field)' must be a list of strings")
        }
        var result: [String] = []
        result.reserveCapacity(array.count)
        for element in array {
            guard let string = element as? String else {
                throw ValidationError("field '\(field)' must contain only string elements")
            }
            result.append(string)
        }
        return result
    }
}
