import Foundation
@testable import PhoneCore

/// Scripted Shell for tests. Responses are matched by the longest key that
/// prefixes "executable-basename arg1 arg2 …".
final class FakeShell: Shell, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: ShellResult] = [:]
    private(set) var calls: [String] = []
    private(set) var launches: [String] = []
    /// Calls and launches in the order they happened.
    private(set) var events: [String] = []
    /// Lets a test change scripted responses when a command runs (e.g. a kill or a launch).
    var hook: ((String, FakeShell) -> Void)?

    func on(_ commandPrefix: String, stdout: String = "", status: Int32 = 0) {
        lock.withLock { responses[commandPrefix] = ShellResult(status: status, stdout: stdout, stderr: "") }
    }

    func run(_ executable: String, _ args: [String], timeout: TimeInterval) throws -> ShellResult {
        let line = Self.line(executable, args)
        lock.withLock { calls.append(line); events.append(line) }
        hook?(line, self)
        return lock.withLock {
            let key = responses.keys.filter { line.hasPrefix($0) }.max { $0.count < $1.count }
            return key.map { responses[$0]! } ?? ShellResult(status: 0, stdout: "", stderr: "")
        }
    }

    func launchDetached(_ executable: String, _ args: [String]) throws -> Int32 {
        let line = Self.line(executable, args)
        lock.withLock { launches.append(line); events.append("launch " + line) }
        hook?("launch " + line, self)
        return 4242
    }

    static func line(_ executable: String, _ args: [String]) -> String {
        ([URL(fileURLWithPath: executable).lastPathComponent] + args).joined(separator: " ")
    }
}

func makeTempDir() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("phonetests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A Config rooted in a fresh temp directory with mount, avd and data dirs created.
func makeTestConfig() -> Config {
    let root = makeTempDir()
    var config = Config.default
    config.requiredVolume = root
    config.avdDir = root.appendingPathComponent("avd")
    config.dataDir = root.appendingPathComponent("data")
    config.sdkRoot = root.appendingPathComponent("sdk")
    for dir in [config.avdDir, config.dataDir, config.sdkRoot] {
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    return config
}
