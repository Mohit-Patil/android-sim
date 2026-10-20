import Darwin
import Foundation

/// File-level AVD work: APFS clones, path rewriting, removal.
public struct AvdFiles: @unchecked Sendable {
    let config: Config
    let guards: Guards
    let fileManager = FileManager.default

    public init(config: Config, guards: Guards) {
        self.config = config
        self.guards = guards
    }

    public func avdFolder(_ avdName: String) -> URL {
        config.avdDir.appendingPathComponent("\(avdName).avd")
    }

    func iniFile(_ avdName: String) -> URL {
        config.avdDir.appendingPathComponent("\(avdName).ini")
    }

    public func exists(_ avdName: String) -> Bool {
        fileManager.fileExists(atPath: avdFolder(avdName).path)
    }

    public func hasQuickBootSnapshot(_ avdName: String) -> Bool {
        fileManager.fileExists(atPath: avdFolder(avdName).appendingPathComponent("snapshots/default_boot").path)
    }

    public func screenshot(_ avdName: String) -> URL? {
        let url = avdFolder(avdName).appendingPathComponent("snapshots/default_boot/screenshot.png")
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// Copy-on-write clone of `source` into a new AVD `target`. Never falls back to a full copy.
    public func clone(from source: String, to target: String) throws {
        try guards.requireStorage()
        try guards.requireOwned(avdName: target)
        let from = avdFolder(source), to = avdFolder(target)
        guard !fileManager.fileExists(atPath: to.path), !fileManager.fileExists(atPath: iniFile(target).path) else {
            throw PhoneError.commandFailed("\(target) already exists")
        }
        guard clonefile(from.path, to.path, UInt32(CLONE_NOFOLLOW)) == 0 else {
            throw PhoneError.commandFailed("APFS clone of \(source) failed: \(String(cString: strerror(errno)))")
        }
        do {
            try? fileManager.removeItem(at: to.appendingPathComponent("snapshots"))
            for item in try fileManager.contentsOfDirectory(atPath: to.path) where item.hasSuffix(".lock") {
                try fileManager.removeItem(at: to.appendingPathComponent(item))
            }
            let ini = try String(contentsOf: iniFile(source), encoding: .utf8)
            try ini.replacingOccurrences(of: source, with: target).write(to: iniFile(target), atomically: true, encoding: .utf8)
            for name in ["config.ini", "hardware-qemu.ini"] {
                let url = to.appendingPathComponent(name)
                guard fileManager.fileExists(atPath: url.path) else { continue }
                var text = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: source, with: target)
                if name == "config.ini" {
                    let number = target.dropFirst(config.phonePrefix.count)
                    text = Self.setting(text, key: "AvdId", value: target)
                    text = Self.setting(text, key: "avd.ini.displayname", value: "Phone \(number)")
                }
                try text.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            try? fileManager.removeItem(at: to)
            try? fileManager.removeItem(at: iniFile(target))
            throw error
        }
    }

    /// Deletes an owned AVD's folder and ini. Refuses anything outside `avdDir`.
    public func remove(_ avdName: String) throws {
        try guards.requireStorage()
        try guards.requireOwned(avdName: avdName)
        let folder = avdFolder(avdName).standardizedFileURL
        guard folder.deletingLastPathComponent().path == config.avdDir.standardizedFileURL.path else {
            throw PhoneError.notOwned(avdName)
        }
        if fileManager.fileExists(atPath: folder.path) { try fileManager.removeItem(at: folder) }
        if fileManager.fileExists(atPath: iniFile(avdName).path) { try fileManager.removeItem(at: iniFile(avdName)) }
    }

    /// Replaces `key=…` lines (either `key=v` or `key = v` style) or appends one.
    static func setting(_ text: String, key: String, value: String) -> String {
        var found = false
        var lines = text.components(separatedBy: "\n").map { line -> String in
            let name = line.split(separator: "=", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces)
            guard name == key else { return line }
            found = true
            return "\(key)=\(value)"
        }
        if !found {
            if lines.last == "" { lines.removeLast() }
            lines.append("\(key)=\(value)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
