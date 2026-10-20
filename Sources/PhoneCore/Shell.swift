import Foundation

public struct ShellResult: Equatable, Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// All external commands go through this so the core can be tested with a fake.
public protocol Shell: Sendable {
    func run(_ executable: String, _ args: [String], timeout: TimeInterval) throws -> ShellResult
    /// Starts a process that outlives the caller; returns its pid.
    func launchDetached(_ executable: String, _ args: [String]) throws -> Int32
}

public struct ProcessShell: Shell {
    public init() {}

    public func run(_ executable: String, _ args: [String], timeout: TimeInterval) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()

        // Drain pipes while waiting so large output can't block the child.
        let outData = DataBox(), errData = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { outData.data = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errData.data = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            process.terminate()
            throw PhoneError.timeout("\(URL(fileURLWithPath: executable).lastPathComponent) \(args.joined(separator: " "))")
        }
        group.wait()
        return ShellResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData.data, as: UTF8.self),
            stderr: String(decoding: errData.data, as: UTF8.self)
        )
    }

    public func launchDetached(_ executable: String, _ args: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process.processIdentifier
    }
}

/// Written by one reader thread, read after `group.wait()`.
private final class DataBox: @unchecked Sendable {
    var data = Data()
}
