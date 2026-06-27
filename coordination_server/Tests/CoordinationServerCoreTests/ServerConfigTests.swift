import Testing

@testable import CoordinationServerCore

@Suite("ServerConfig.resolve")
struct ServerConfigTests {
    @Test("uses defaults with only a token in the environment")
    func defaultsWithToken() throws {
        let config = try ServerConfig.resolve(
            args: [],
            environment: ["COORDINATION_TOKEN": "secret"]
        )
        #expect(config.port == ServerConfig.defaultPort)
        #expect(config.token == "secret")
        #expect(config.storePath == nil)
    }

    @Test("reads port and store from the environment")
    func portAndStoreFromEnvironment() throws {
        let config = try ServerConfig.resolve(
            args: [],
            environment: [
                "COORDINATION_TOKEN": "secret",
                "PORT": "9000",
                "COORDINATION_STORE": "/var/data/store.json",
            ]
        )
        #expect(config.port == 9000)
        #expect(config.storePath == "/var/data/store.json")
    }

    @Test("CLI flags override environment variables")
    func flagsOverrideEnvironment() throws {
        let config = try ServerConfig.resolve(
            args: ["--token", "flag-token", "--port", "1234"],
            environment: ["COORDINATION_TOKEN": "env-token", "PORT": "8787"]
        )
        #expect(config.token == "flag-token")
        #expect(config.port == 1234)
    }

    @Test("accepts the --flag=value form")
    func flagEqualsForm() throws {
        let config = try ServerConfig.resolve(
            args: ["--token=abc", "--port=2020", "--store=/tmp/s.json"],
            environment: [:]
        )
        #expect(config.token == "abc")
        #expect(config.port == 2020)
        #expect(config.storePath == "/tmp/s.json")
    }

    @Test("throws when no token is configured")
    func throwsWithoutToken() {
        #expect(throws: ConfigError.self) {
            try ServerConfig.resolve(args: [], environment: [:])
        }
    }

    @Test("throws on an empty token")
    func throwsOnEmptyToken() {
        #expect(throws: ConfigError.self) {
            try ServerConfig.resolve(args: ["--token", ""], environment: [:])
        }
    }

    @Test("throws on a non-numeric port")
    func throwsOnNonNumericPort() {
        #expect(throws: ConfigError.self) {
            try ServerConfig.resolve(args: ["--token", "t", "--port", "abc"], environment: [:])
        }
    }

    @Test("throws on an out-of-range port")
    func throwsOnOutOfRangePort() {
        #expect(throws: ConfigError.self) {
            try ServerConfig.resolve(args: ["--token", "t", "--port", "70000"], environment: [:])
        }
    }

    @Test("throws on an unknown flag")
    func throwsOnUnknownFlag() {
        #expect(throws: ConfigError.self) {
            try ServerConfig.resolve(args: ["--token", "t", "--bogus", "x"], environment: [:])
        }
    }

    @Test("throws on a missing flag value")
    func throwsOnMissingFlagValue() {
        #expect(throws: ConfigError.self) {
            try ServerConfig.resolve(args: ["--token"], environment: [:])
        }
    }
}
