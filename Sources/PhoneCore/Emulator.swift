import Foundation

public struct Emulator: Sendable {
    let config: Config
    let shell: Shell

    public init(config: Config, shell: Shell) {
        self.config = config
        self.shell = shell
    }

    /// Launches the emulator detached. `offline` = cold boot with unresolvable DNS and no
    /// snapshot, used once for the base so Play services never checks it in.
    public func start(avdName: String, offline: Bool) throws -> Int32 {
        var args = ["-avd", avdName, "-no-boot-anim"]
        if offline { args += ["-no-snapshot", "-dns-server", "127.0.0.1"] }
        return try shell.launchDetached(config.emulatorPath, args)
    }

    public func currentBuildStamp() throws -> BuildStamp {
        let out = try shell.run(config.emulatorPath, ["-version"], timeout: 20).stdout
        guard let range = out.range(of: "version ") else { throw PhoneError.commandFailed("emulator -version: \(out)") }
        let version = out[range.upperBound...].prefix { !$0.isWhitespace }
        let props = try String(contentsOf: config.systemImageDir.appendingPathComponent("source.properties"), encoding: .utf8)
        let revision = props.split(whereSeparator: \.isNewline)
            .first { $0.hasPrefix("Pkg.Revision=") }
            .map { String($0.dropFirst("Pkg.Revision=".count)) } ?? "unknown"
        return BuildStamp(emulatorVersion: String(version), systemImageRevision: revision)
    }

    /// Creates the base AVD with avdmanager, then sets the hardware the phones use.
    public func createBaseAvd() throws {
        let command = "echo no | '\(config.avdmanagerPath)' create avd -n \(config.baseName) -k '\(config.systemImage)' -d \(config.deviceProfile)"
        let result = try shell.run("/bin/sh", ["-c", command], timeout: 180)
        guard result.status == 0 else { throw PhoneError.commandFailed("avdmanager: \(result.stderr)\(result.stdout)") }
        let url = config.avdDir.appendingPathComponent("\(config.baseName).avd/config.ini")
        var text = try String(contentsOf: url, encoding: .utf8)
        for (key, value) in [("PlayStore.enabled", "yes"), ("hw.gpu.enabled", "yes"), ("hw.gpu.mode", "host"),
                             ("hw.keyboard", "yes"), ("hw.ramSize", "\(config.ramMB)")] {
            text = AvdFiles.setting(text, key: key, value: value)
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
