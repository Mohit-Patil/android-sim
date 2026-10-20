import Foundation

public struct RunningEmulator: Equatable, Sendable {
    public let serial: String
    public let avdName: String

    public init(serial: String, avdName: String) {
        self.serial = serial
        self.avdName = avdName
    }
}

public struct Adb: Sendable {
    let config: Config
    let shell: Shell

    public init(config: Config, shell: Shell) {
        self.config = config
        self.shell = shell
    }

    func adb(_ args: String...) throws -> ShellResult {
        try shell.run(config.adbPath, args, timeout: 20)
    }

    /// Emulators adb sees as online, with the AVD each one runs.
    public func runningEmulators() throws -> [RunningEmulator] {
        let serials = try adb("devices").stdout.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let parts = line.split(separator: "\t")
            guard parts.count == 2, parts[0].hasPrefix("emulator-"), parts[1] == "device" else { return nil }
            return String(parts[0])
        }
        return serials.compactMap { serial in
            guard let out = try? adb("-s", serial, "emu", "avd", "name").stdout,
                  let name = out.split(whereSeparator: \.isNewline).first?.trimmingCharacters(in: .whitespaces),
                  !name.isEmpty
            else { return nil }
            return RunningEmulator(serial: serial, avdName: name)
        }
    }

    /// AVD names of every emulator process, including ones adb can't see yet
    /// (booting, offline) or any more (still saving).
    public func emulatorProcesses() throws -> [String] {
        let out = try shell.run("/bin/ps", ["-axo", "command="], timeout: 10).stdout
        var names: [String] = []
        for line in out.split(whereSeparator: \.isNewline) {
            let words = line.split(separator: " ")
            guard let first = words.first, first.contains("qemu-system") || first.hasSuffix("/emulator"),
                  let index = words.firstIndex(of: "-avd"), index + 1 < words.count
            else { continue }
            let name = String(words[index + 1])
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    public func isBooted(serial: String) -> Bool {
        (try? adb("-s", serial, "shell", "getprop", "sys.boot_completed").stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)) == "1"
    }

    /// `emu kill` saves the Quick Boot snapshot then exits; wait for the process to be gone
    /// so the snapshot is fully written before anything else starts.
    public func killSaving(serial: String, avdName: String, timeout: TimeInterval = 90) throws {
        _ = try adb("-s", serial, "emu", "kill")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let process = try shell.run("/usr/bin/pgrep", ["-f", "--", Self.processPattern(avdName)], timeout: 5)
            if process.status != 0 { return }
            Thread.sleep(forTimeInterval: 0.5)
        }
        throw PhoneError.timeout("saving \(avdName)")
    }

    /// Matches the emulator's command line for exactly this AVD.
    static func processPattern(_ avdName: String) -> String {
        "-avd \(avdName)( |$)"
    }
}
