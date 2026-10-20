import AppKit
import Foundation

public enum PhoneStatus: Equatable, Sendable {
    case running, saved, neverStarted, broken
}

public struct PhoneRow: Identifiable, Equatable, Sendable {
    public var phone: Phone
    public var status: PhoneStatus
    /// The screen as it was when the phone was last saved.
    public var screenshot: URL?
    public var id: Int { phone.id }
}

public struct Overview: Equatable, Sendable {
    public var storageConnected = false
    /// Why storage isn't usable (volume unplugged, bad config…), when it isn't.
    public var storageError: String?
    public var baseExists = false
    public var rows: [PhoneRow] = []
    public var foreignRunning: [String] = []
    public var buildStampMismatch = false
    public var storage: StorageReport?
    public var loadError: String?

    public init() {}
}

/// Waits and polling intervals; tests use `.instant`.
public struct Timing: Sendable {
    public var poll: TimeInterval
    public var bootTimeout: TimeInterval
    public var baseSettle: TimeInterval

    public static let real = Timing(poll: 0.5, bootTimeout: 300, baseSettle: 120)
    public static let instant = Timing(poll: 0, bootTimeout: 1, baseSettle: 0)
}

/// Everything the CLI and app do goes through here.
public final class PhoneManager: @unchecked Sendable {
    let config: Config
    let shell: Shell
    let timing: Timing
    let guards: Guards
    let files: AvdFiles
    let adb: Adb
    let emulator: Emulator
    let store: PhoneStore
    private let stampLock = NSLock()
    private var cachedStamp: (stamp: BuildStamp, at: Date)?

    public init(config: Config = .default, shell: Shell = ProcessShell(), fileManager: FileManager = .default, timing: Timing = .real) {
        self.config = config
        self.shell = shell
        self.timing = timing
        guards = Guards(config: config, fileManager: fileManager)
        files = AvdFiles(config: config, guards: guards)
        adb = Adb(config: config, shell: shell)
        emulator = Emulator(config: config, shell: shell)
        store = PhoneStore(fileURL: config.dataDir.appendingPathComponent("phones.json"))
    }

    // MARK: Reading

    public func overview() -> Overview {
        var overview = Overview()
        do { try guards.requireStorage() } catch {
            overview.storageError = error.localizedDescription
            return overview
        }
        overview.storageConnected = true
        overview.baseExists = baseReady
        let phones: [Phone]
        do { phones = try store.load() } catch {
            overview.loadError = "Couldn't read the phone list: \(error.localizedDescription)"
            return overview
        }
        let running = (try? adb.runningEmulators()) ?? []
        let runningNames = Set(running.map(\.avdName))
        let processes = (try? adb.emulatorProcesses()) ?? running.map(\.avdName)
        overview.foreignRunning = processes.filter { !guards.isOwned(avdName: $0) }
        overview.rows = phones.map { phone in
            let status: PhoneStatus =
                if !files.exists(phone.avdName) { .broken }
                else if runningNames.contains(phone.avdName) { .running }
                else if files.hasQuickBootSnapshot(phone.avdName) { .saved }
                else { .neverStarted }
            return PhoneRow(phone: phone, status: status, screenshot: files.screenshot(phone.avdName))
        }
        if let current = try? buildStamp() {
            overview.buildStampMismatch = phones.contains { $0.buildStamp != current }
        }
        overview.storage = try? Storage(config: config).report(avdNames: phones.map(\.avdName) + [config.baseName])
        return overview
    }

    /// Cached briefly so the app's 3 s refresh doesn't run `emulator -version` every time,
    /// but an emulator update is still noticed within a minute.
    func buildStamp() throws -> BuildStamp {
        if let cached = stampLock.withLock({ cachedStamp }), Date().timeIntervalSince(cached.at) < 60 {
            return cached.stamp
        }
        let stamp = try emulator.currentBuildStamp()
        stampLock.withLock { cachedStamp = (stamp, Date()) }
        return stamp
    }

    var baseReadyMarker: URL { config.dataDir.appendingPathComponent("base-ready") }

    /// The base exists and finished its offline first boot.
    var baseReady: Bool {
        files.exists(config.baseName) && FileManager.default.fileExists(atPath: baseReadyMarker.path)
    }

    /// Loads a phone record and checks it names its own AVD.
    func phone(_ id: Int) throws -> Phone {
        guard let phone = try store.load().first(where: { $0.id == id }) else { throw PhoneError.phoneNotFound(id) }
        try guards.requirePhone(phone)
        return phone
    }

    // MARK: Base and phones

    /// Creates the base AVD and gives it one offline first boot. Does nothing if it exists.
    public func setupBase(progress: (String) -> Void) throws {
        try guards.requireStorage()
        guard !baseReady else { return }
        try stopOwnedEmulators(refusingForeign: true, progress: progress)
        if files.exists(config.baseName) || FileManager.default.fileExists(atPath: config.avdDir.appendingPathComponent("\(config.baseName).ini").path) {
            progress("Removing an unfinished base phone…")
            try files.remove(config.baseName)
        }
        progress("Creating the base phone…")
        try emulator.createBaseAvd()
        progress("First start of the base phone (offline, about 3 minutes)…")
        _ = try emulator.start(avdName: config.baseName, offline: true)
        let serial = try waitForBoot(avdName: config.baseName)
        if timing.baseSettle > 0 { Thread.sleep(forTimeInterval: timing.baseSettle) }
        progress("Shutting down the base phone…")
        try adb.killSaving(serial: serial, avdName: config.baseName)
        try? FileManager.default.removeItem(at: files.avdFolder(config.baseName).appendingPathComponent("snapshots"))
        try FileManager.default.createDirectory(at: config.dataDir, withIntermediateDirectories: true)
        try Data().write(to: baseReadyMarker)
        progress("Base phone ready")
    }

    public func addPhones(count: Int) throws -> [Phone] {
        try guards.requireStorage()
        guard baseReady else { throw PhoneError.baseMissing }
        guard !(try adb.emulatorProcesses()).contains(config.baseName) else { throw PhoneError.phoneBusy("the base phone") }
        var phones = try store.load()
        var added: [Phone] = []
        for _ in 0..<max(count, 0) {
            let id = store.nextID(phones)
            let avdName = config.phonePrefix + String(format: "%02d", id)
            try files.clone(from: config.baseName, to: avdName)
            let phone = Phone(id: id, avdName: avdName, label: "Phone \(String(format: "%02d", id))", notes: "",
                              createdAt: Date(), buildStamp: try buildStamp())
            phones.append(phone)
            added.append(phone)
            try store.save(phones)
        }
        return added
    }

    public func relabel(id: Int, label: String, notes: String) throws {
        try guards.requireStorage()
        var phones = try store.load()
        guard let index = phones.firstIndex(where: { $0.id == id }) else { throw PhoneError.phoneNotFound(id) }
        phones[index].label = label
        phones[index].notes = notes
        try store.save(phones)
    }

    /// Erases a phone back to a fresh copy of the base; keeps its number, label and notes.
    public func reset(id: Int) throws {
        try guards.requireStorage()
        var phones = try store.load()
        guard let index = phones.firstIndex(where: { $0.id == id }) else { throw PhoneError.phoneNotFound(id) }
        try guards.requirePhone(phones[index])
        guard baseReady else { throw PhoneError.baseMissing }
        guard !(try adb.emulatorProcesses()).contains(config.baseName) else { throw PhoneError.phoneBusy("the base phone") }
        try stop(avdName: phones[index].avdName)
        try files.remove(phones[index].avdName)
        try files.clone(from: config.baseName, to: phones[index].avdName)
        phones[index].buildStamp = try buildStamp()
        try store.save(phones)
    }

    public func delete(id: Int) throws {
        try guards.requireStorage()
        var phones = try store.load()
        guard let index = phones.firstIndex(where: { $0.id == id }) else { throw PhoneError.phoneNotFound(id) }
        try guards.requirePhone(phones[index])
        try stop(avdName: phones[index].avdName)
        try files.remove(phones[index].avdName)
        phones.remove(at: index)
        try store.save(phones)
    }

    // MARK: Running

    /// Saves and stops whatever phone is running, then resumes `id`.
    public func switchTo(id: Int, progress: (String) -> Void) throws {
        try guards.requireStorage()
        let target = try phone(id)
        guard files.exists(target.avdName) else {
            throw PhoneError.commandFailed("\(target.label)'s files are missing. Reset it to rebuild it.")
        }
        let running = try adb.runningEmulators()
        let processes = try adb.emulatorProcesses()
        if let foreign = (processes + running.map(\.avdName)).first(where: { !guards.isOwned(avdName: $0) }) {
            throw PhoneError.foreignEmulatorRunning(foreign)
        }
        if running.contains(where: { $0.avdName == target.avdName }) { return }
        // An owned emulator adb can't talk to is mid-boot or mid-save; starting another would run two.
        let reachable = Set(running.map(\.avdName))
        if let busy = processes.first(where: { !reachable.contains($0) }) {
            throw PhoneError.phoneBusy(try label(forAvd: busy))
        }
        try stopOwnedEmulators(refusingForeign: false, progress: progress)
        progress("Starting \(target.label)…")
        _ = try emulator.start(avdName: target.avdName, offline: false)
        _ = try waitForBoot(avdName: target.avdName)
        try recordCurrentStamp(id: target.id)
        progress("Ready")
    }

    public func stopRunning() throws {
        try guards.requireStorage()
        try stopOwnedEmulators(refusingForeign: false) { _ in }
    }

    public func bringToFront(id: Int) {
        guard let phone = try? phone(id),
              let result = try? shell.run("/usr/bin/pgrep", ["-f", "--", Adb.processPattern(phone.avdName)], timeout: 5),
              let pid = result.stdout.split(whereSeparator: \.isNewline).compactMap({ Int32($0) }).first
        else { return }
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    // MARK: Helpers

    private func stopOwnedEmulators(refusingForeign: Bool, progress: (String) -> Void) throws {
        let running = try adb.runningEmulators()
        if refusingForeign, let foreign = running.first(where: { !guards.isOwned(avdName: $0.avdName) }) {
            throw PhoneError.foreignEmulatorRunning(foreign.avdName)
        }
        let labels = Dictionary((try? store.load())?.map { ($0.avdName, $0.label) } ?? [], uniquingKeysWith: { a, _ in a })
        for emulator in running where guards.isOwned(avdName: emulator.avdName) {
            progress("Saving \(labels[emulator.avdName] ?? emulator.avdName)…")
            try adb.killSaving(serial: emulator.serial, avdName: emulator.avdName)
        }
    }

    /// After a successful boot the phone's saved state matches the current emulator.
    private func recordCurrentStamp(id: Int) throws {
        let stamp = try buildStamp()
        var phones = try store.load()
        guard let index = phones.firstIndex(where: { $0.id == id }), phones[index].buildStamp != stamp else { return }
        phones[index].buildStamp = stamp
        try store.save(phones)
    }

    private func label(forAvd avdName: String) throws -> String {
        if avdName == config.baseName { return "the base phone" }
        return try store.load().first { $0.avdName == avdName }?.label ?? avdName
    }

    private func stop(avdName: String) throws {
        try guards.requireOwned(avdName: avdName)
        if let running = try adb.runningEmulators().first(where: { $0.avdName == avdName }) {
            try adb.killSaving(serial: running.serial, avdName: avdName)
        }
    }

    /// Polls until the AVD shows up in adb and reports boot completed; returns its serial.
    private func waitForBoot(avdName: String) throws -> String {
        let deadline = Date().addingTimeInterval(timing.bootTimeout)
        repeat {
            if let serial = try? adb.runningEmulators().first(where: { $0.avdName == avdName })?.serial,
               adb.isBooted(serial: serial) {
                return serial
            }
            if timing.poll > 0 { Thread.sleep(forTimeInterval: timing.poll) }
        } while Date() < deadline
        throw PhoneError.timeout("starting \(avdName)")
    }
}
