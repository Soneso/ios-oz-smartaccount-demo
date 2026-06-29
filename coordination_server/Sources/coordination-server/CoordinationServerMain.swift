import CoordinationServerCore
import Foundation
import Hummingbird

/// Entry point for the coordination server.
///
/// Resolves configuration, loads any persisted store, binds `0.0.0.0:<port>`,
/// and serves until interrupted. Exits with code 64 (`EX_USAGE`) on a
/// configuration error so process supervisors can distinguish a misconfigured
/// launch from a runtime crash.
@main
struct CoordinationServerMain {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())

        let config: ServerConfig
        do {
            config = try ServerConfig.resolve(args: arguments, environment: ProcessInfo.processInfo.environment)
        } catch let error as ConfigError {
            FileHandle.standardError.write(Data("Configuration error: \(error.message)\n".utf8))
            exit(64)
        }

        let store = RequestStore(storePath: config.storePath)
        do {
            try await store.load()
        } catch {
            FileHandle.standardError.write(
                Data("Failed to load store \"\(config.storePath ?? "")\": \(error)\n".utf8)
            )
            exit(70)
        }

        let application = buildApplication(store: store, token: config.token, port: config.port)

        print("coordination-server listening on http://0.0.0.0:\(config.port)")
        if let storePath = config.storePath {
            print("Persisting requests to \(storePath)")
        } else {
            print("Running in-memory only (no --store configured)")
        }

        try await application.run()
    }
}
