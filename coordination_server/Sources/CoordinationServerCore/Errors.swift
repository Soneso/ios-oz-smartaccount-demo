import Foundation

/// Raised when a client-supplied value fails validation. Maps to HTTP 400.
public struct ValidationError: Error, Sendable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { "ValidationError: \(message)" }
}

/// Raised when a referenced request id does not exist. Maps to HTTP 404.
public struct NotFoundError: Error, Sendable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { "NotFoundError: \(message)" }
}

/// Raised when a state transition is not permitted, e.g. resolving an
/// already-resolved request. Maps to HTTP 409.
public struct ConflictError: Error, Sendable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { "ConflictError: \(message)" }
}

/// Raised when configuration cannot be resolved into a runnable state.
public struct ConfigError: Error, Sendable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { "ConfigError: \(message)" }
}

/// Raised when a persisted store file cannot be parsed back into requests.
public struct StoreFormatError: Error, Sendable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { "StoreFormatError: \(message)" }
}
