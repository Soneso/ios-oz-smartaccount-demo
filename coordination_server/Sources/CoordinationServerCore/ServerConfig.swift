import Foundation

/// Runtime configuration resolved from CLI flags and environment variables.
///
/// CLI flags take precedence over environment variables. A bearer token is
/// mandatory: the server refuses to start without one rather than running
/// open.
public struct ServerConfig: Sendable, Equatable {
    /// TCP port to bind. Defaults to ``defaultPort``.
    public let port: Int

    /// Bearer token required on all `/requests*` routes.
    public let token: String

    /// Path to the JSON persistence file, or `nil` for in-memory only.
    public let storePath: String?

    public static let defaultPort = 8787

    /// Environment variable holding the bearer token.
    public static let tokenEnv = "COORDINATION_TOKEN"

    /// Environment variable holding the persistence file path.
    public static let storeEnv = "COORDINATION_STORE"

    /// Environment variable holding the port.
    public static let portEnv = "PORT"

    public init(port: Int, token: String, storePath: String? = nil) {
        self.port = port
        self.token = token
        self.storePath = storePath
    }

    /// Resolves configuration from process `args` and `environment`.
    ///
    /// Recognised flags: `--port <n>`, `--token <s>`, `--store <path>` (each
    /// also accepts the `--flag=value` form). Throws ``ConfigError`` on an
    /// unknown flag, a malformed port, or a missing/empty token.
    public static func resolve(
        args: [String],
        environment: [String: String]
    ) throws -> ServerConfig {
        let flags = try parseFlags(args)

        let portValue = flags["port"] ?? environment[portEnv]
        let port: Int
        if let portValue, !portValue.isEmpty {
            guard let parsed = Int(portValue), parsed >= 0, parsed <= 65535 else {
                throw ConfigError("invalid port \"\(portValue)\": expected an integer in 0..65535")
            }
            port = parsed
        } else {
            port = defaultPort
        }

        let tokenValue = flags["token"] ?? environment[tokenEnv]
        guard let token = tokenValue, !token.isEmpty else {
            throw ConfigError(
                "no bearer token configured. Set \(tokenEnv) or pass --token <value>. "
                    + "The server refuses to start without a token to avoid running open."
            )
        }

        let storeRaw = flags["store"] ?? environment[storeEnv]
        let storePath = (storeRaw?.isEmpty ?? true) ? nil : storeRaw

        return ServerConfig(port: port, token: token, storePath: storePath)
    }

    private static func parseFlags(_ args: [String]) throws -> [String: String] {
        let known: Set<String> = ["port", "token", "store"]
        var flags: [String: String] = [:]
        var index = 0
        while index < args.count {
            let arg = args[index]
            guard arg.hasPrefix("--") else {
                throw ConfigError("unexpected argument \"\(arg)\"")
            }
            let body = String(arg.dropFirst(2))
            let name: String
            let value: String
            if let eq = body.firstIndex(of: "=") {
                name = String(body[body.startIndex..<eq])
                value = String(body[body.index(after: eq)...])
            } else {
                name = body
                guard index + 1 < args.count else {
                    throw ConfigError("missing value for flag \"--\(name)\"")
                }
                index += 1
                value = args[index]
            }
            guard known.contains(name) else {
                throw ConfigError("unknown flag \"--\(name)\"")
            }
            flags[name] = value
            index += 1
        }
        return flags
    }
}
