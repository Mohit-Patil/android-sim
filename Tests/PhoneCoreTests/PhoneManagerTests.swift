import Foundation
import Testing
@testable import PhoneCore

/// Simulates adb/emulator: launches add a booted emulator, `emu kill` removes it.
final class FakeEmulators: @unchecked Sendable {
    let shell = FakeShell()
    private var running: [(serial: String, avd: String)] = []
    /// Emulator processes adb can't see yet (booting, offline, or still saving).
    var processOnly: [String] = [] { didSet { publish() } }
    private var nextPort = 5554

    init(running avds: [String] = [], emulatorVersion: String = "36.5.10.0") {
        shell.on("emulator -version", stdout: "Android emulator version \(emulatorVersion) (build_id 1)\n")
        shell.on("pgrep", status: 1)
        for avd in avds { add(avd) }
        shell.hook = { [unowned self] line, shell in
            if line.hasPrefix("launch emulator -avd "), let avd = line.split(separator: " ").dropFirst(3).first {
                self.add(String(avd))
            } else if line.hasSuffix(" emu kill"), let serial = line.split(separator: " ").dropFirst(2).first {
                self.running.removeAll { $0.serial == serial }
                self.publish()
            }
        }
    }

    private func add(_ avd: String) {
        let serial = "emulator-\(nextPort)"
        nextPort += 2
        running.append((serial, avd))
        shell.on("adb -s \(serial) emu avd name", stdout: "\(avd)\nOK\n")
        shell.on("adb -s \(serial) shell getprop sys.boot_completed", stdout: "1\n")
        publish()
    }

    private func publish() {
        let lines = running.map { "\($0.serial)\tdevice" }.joined(separator: "\n")
        shell.on("adb devices", stdout: "List of devices attached\n\(lines)\n")
        let processes = (running.map(\.avd) + processOnly).map {
            "/sdk/emulator/qemu/darwin-aarch64/qemu-system-aarch64 -netdelay none -avd \($0) -no-boot-anim"
        }
        shell.on("ps -axo command=", stdout: (["/usr/sbin/syslogd", "/bin/zsh -l"] + processes).joined(separator: "\n") + "\n")
    }
}

struct PhoneManagerTests {
    static let stamp = BuildStamp(emulatorVersion: "36.5.10.0", systemImageRevision: "7")

    /// Config with a fake base AVD, system image props and `ids` phones already made.
    static func setUp(ids: [Int] = [1, 2], fake: FakeEmulators) throws -> (PhoneManager, Config) {
        let config = makeTestConfig()
        try FileManager.default.createDirectory(at: config.systemImageDir, withIntermediateDirectories: true)
        try "Pkg.Revision=7\n".write(to: config.systemImageDir.appendingPathComponent("source.properties"), atomically: true, encoding: .utf8)
        try AvdFilesTests.makeFakeAvd(config.baseName, in: config)
        let phones = ids.map { Phone(id: $0, avdName: String(format: "ps_phone_%02d", $0), label: "Phone \($0)", notes: "",
                                     createdAt: Date(), buildStamp: stamp) }
        for phone in phones { try AvdFilesTests.makeFakeAvd(phone.avdName, in: config) }
        try PhoneStore(fileURL: config.dataDir.appendingPathComponent("phones.json")).save(phones)
        try Data().write(to: config.dataDir.appendingPathComponent("base-ready"))
        return (PhoneManager(config: config, shell: fake.shell, timing: .instant), config)
    }

    @Test func switchRefusesWhenForeignEmulatorRuns() throws {
        let fake = FakeEmulators(running: ["medium_phone"])
        let (manager, _) = try Self.setUp(fake: fake)
        #expect(throws: PhoneError.foreignEmulatorRunning("medium_phone")) { try manager.switchTo(id: 2) { _ in } }
        #expect(!fake.shell.calls.contains { $0.hasSuffix("emu kill") })
        #expect(fake.shell.launches.isEmpty)
    }

    @Test func switchToRunningPhoneIsNoop() throws {
        let fake = FakeEmulators(running: ["ps_phone_02"])
        let (manager, _) = try Self.setUp(fake: fake)
        try manager.switchTo(id: 2) { _ in }
        #expect(!fake.shell.calls.contains { $0.hasSuffix("emu kill") })
        #expect(fake.shell.launches.isEmpty)
    }

    @Test func switchStopsCurrentThenStartsTarget() throws {
        let fake = FakeEmulators(running: ["ps_phone_01"])
        let (manager, _) = try Self.setUp(fake: fake)
        var messages: [String] = []
        try manager.switchTo(id: 2) { messages.append($0) }
        let kill = try #require(fake.shell.events.firstIndex(of: "adb -s emulator-5554 emu kill"))
        let launch = try #require(fake.shell.events.firstIndex { $0.hasPrefix("launch emulator -avd ps_phone_02 ") })
        #expect(kill < launch)
        #expect(messages == ["Saving Phone 1…", "Starting Phone 2…", "Ready"])
    }

    @Test func switchRefusesWhenSSDMissing() throws {
        let fake = FakeEmulators()
        let (_, good) = try Self.setUp(fake: fake)
        var config = good
        config.requiredVolume = URL(fileURLWithPath: "/Volumes/nope-\(UUID().uuidString)")
        let manager = PhoneManager(config: config, shell: fake.shell, timing: .instant)
        #expect(throws: PhoneError.volumeMissing(config.requiredVolume!.path)) { try manager.switchTo(id: 2) { _ in } }
        #expect(fake.shell.calls.isEmpty && fake.shell.launches.isEmpty)
    }

    @Test func switchToUnknownPhoneThrows() throws {
        let (manager, _) = try Self.setUp(fake: FakeEmulators())
        #expect(throws: PhoneError.phoneNotFound(9)) { try manager.switchTo(id: 9) { _ in } }
    }

    @Test func statusFlagsBuildStampMismatch() throws {
        let (manager, _) = try Self.setUp(fake: FakeEmulators(emulatorVersion: "36.6.0.0"))
        #expect(manager.overview().buildStampMismatch)
    }

    @Test func statusMatchesWhenStampSame() throws {
        let (manager, _) = try Self.setUp(fake: FakeEmulators())
        #expect(!manager.overview().buildStampMismatch)
    }

    @Test func addPhonesNumbersSequentially() throws {
        let (manager, config) = try Self.setUp(fake: FakeEmulators())
        let added = try manager.addPhones(count: 2)
        #expect(added.map(\.id) == [3, 4])
        #expect(added.map(\.avdName) == ["ps_phone_03", "ps_phone_04"])
        #expect(added.map(\.label) == ["Phone 03", "Phone 04"])
        #expect(added.allSatisfy { $0.buildStamp == Self.stamp })
        #expect(FileManager.default.fileExists(atPath: config.avdDir.appendingPathComponent("ps_phone_04.avd").path))
        #expect(manager.overview().rows.map(\.id) == [1, 2, 3, 4])
    }

    @Test func addPhonesNeedsBase() throws {
        let (manager, config) = try Self.setUp(fake: FakeEmulators())
        try FileManager.default.removeItem(at: config.avdDir.appendingPathComponent("\(config.baseName).avd"))
        #expect(throws: PhoneError.baseMissing) { try manager.addPhones(count: 1) }
    }

    @Test func overviewStatuses() throws {
        let fake = FakeEmulators(running: ["ps_phone_01", "medium_phone"])
        let (manager, config) = try Self.setUp(ids: [1, 2, 3], fake: fake)
        try FileManager.default.removeItem(at: config.avdDir.appendingPathComponent("ps_phone_02.avd/snapshots"))
        try FileManager.default.removeItem(at: config.avdDir.appendingPathComponent("ps_phone_03.avd"))
        let overview = manager.overview()
        #expect(overview.rows.map(\.status) == [.running, .neverStarted, .broken])
        #expect(overview.foreignRunning == ["medium_phone"])
        #expect(overview.storageConnected && overview.baseExists)
        #expect(overview.storage != nil)
    }

    @Test func rowsCarryLastScreenshot() throws {
        let (manager, config) = try Self.setUp(ids: [1, 2], fake: FakeEmulators())
        let shot = config.avdDir.appendingPathComponent("ps_phone_01.avd/snapshots/default_boot/screenshot.png")
        try Data([1, 2, 3]).write(to: shot)
        let rows = manager.overview().rows
        #expect(rows[0].screenshot == shot)
        #expect(rows[1].screenshot == nil)
    }

    @Test func brokenWhenAvdFolderMissing() throws {
        let (manager, config) = try Self.setUp(ids: [1], fake: FakeEmulators())
        try FileManager.default.removeItem(at: config.avdDir.appendingPathComponent("ps_phone_01.avd"))
        #expect(manager.overview().rows.first?.status == .broken)
    }

    @Test func overviewWithoutSSDIsEmpty() throws {
        let fake = FakeEmulators()
        var config = try Self.setUp(fake: fake).1
        config.requiredVolume = URL(fileURLWithPath: "/Volumes/nope-\(UUID().uuidString)")
        let overview = PhoneManager(config: config, shell: fake.shell, timing: .instant).overview()
        #expect(!overview.storageConnected && overview.rows.isEmpty)
        #expect(overview.storageError == PhoneError.volumeMissing(config.requiredVolume!.path).localizedDescription)
    }

    @Test func relabelPersists() throws {
        let (manager, _) = try Self.setUp(fake: FakeEmulators())
        try manager.relabel(id: 2, label: "xyz@gmail.com", notes: "admin user")
        let row = try #require(manager.overview().rows.first { $0.id == 2 })
        #expect(row.phone.label == "xyz@gmail.com" && row.phone.notes == "admin user")
    }

    @Test func deleteStopsRunningPhoneAndRemovesIt() throws {
        let fake = FakeEmulators(running: ["ps_phone_02"])
        let (manager, config) = try Self.setUp(fake: fake)
        try manager.delete(id: 2)
        #expect(fake.shell.calls.contains("adb -s emulator-5554 emu kill"))
        #expect(!FileManager.default.fileExists(atPath: config.avdDir.appendingPathComponent("ps_phone_02.avd").path))
        #expect(manager.overview().rows.map(\.id) == [1])
    }

    @Test func resetKeepsLabelAndRecreatesFromBase() throws {
        let (manager, config) = try Self.setUp(fake: FakeEmulators())
        try manager.relabel(id: 1, label: "abc@gmail.com", notes: "")
        try "signed-in".write(to: config.avdDir.appendingPathComponent("ps_phone_01.avd/userdata-qemu.img.qcow2"), atomically: true, encoding: .utf8)
        try manager.reset(id: 1)
        let data = try String(contentsOf: config.avdDir.appendingPathComponent("ps_phone_01.avd/userdata-qemu.img.qcow2"), encoding: .utf8)
        #expect(data == "data")
        #expect(manager.overview().rows.first?.phone.label == "abc@gmail.com")
        #expect(manager.overview().rows.first?.status == .neverStarted)
    }

    @Test func setupBaseBootsOfflineThenStops() throws {
        let fake = FakeEmulators()
        let (manager, config) = try Self.setUp(ids: [], fake: fake)
        try FileManager.default.removeItem(at: config.avdDir.appendingPathComponent("\(config.baseName).avd"))
        try FileManager.default.removeItem(at: config.avdDir.appendingPathComponent("\(config.baseName).ini"))
        try FileManager.default.removeItem(at: config.dataDir.appendingPathComponent("base-ready"))
        fake.shell.hook = { [hook = fake.shell.hook] line, shell in
            hook?(line, shell)
            if line.hasPrefix("sh -c echo no") {   // avdmanager creating the base
                try? AvdFilesTests.makeFakeAvd(config.baseName, in: config)
            }
        }
        try manager.setupBase { _ in }
        #expect(fake.shell.launches == ["emulator -avd zz_phoneswitcher_base -no-boot-anim -no-snapshot -dns-server 127.0.0.1"])
        #expect(fake.shell.calls.contains("adb -s emulator-5554 emu kill"))
        #expect(!FileManager.default.fileExists(atPath: config.avdDir.appendingPathComponent("\(config.baseName).avd/snapshots").path))
        #expect(manager.overview().baseExists)
    }

    // MARK: Review fixes

    /// Rewrites phones.json so phone `id` points at `avdName` (a corrupted record).
    static func corrupt(_ config: Config, id: Int, avdName: String) throws {
        let store = PhoneStore(fileURL: config.dataDir.appendingPathComponent("phones.json"))
        var phones = try store.load()
        let index = try #require(phones.firstIndex { $0.id == id })
        phones[index].avdName = avdName
        try store.save(phones)
    }

    @Test(arguments: ["delete", "reset", "switch"])
    func refusesRecordPointingAtForeignAvd(operation: String) throws {
        let fake = FakeEmulators(running: ["medium_phone"])
        let (manager, config) = try Self.setUp(fake: fake)
        try AvdFilesTests.makeFakeAvd("medium_phone", in: config)
        try Self.corrupt(config, id: 2, avdName: "medium_phone")
        #expect(throws: PhoneError.notOwned("medium_phone")) {
            switch operation {
            case "delete": try manager.delete(id: 2)
            case "reset": try manager.reset(id: 2)
            default: try manager.switchTo(id: 2) { _ in }
            }
        }
        #expect(!fake.shell.calls.contains { $0.hasSuffix("emu kill") })
        #expect(fake.shell.launches.isEmpty)
        #expect(FileManager.default.fileExists(atPath: config.avdDir.appendingPathComponent("medium_phone.avd").path))
    }

    @Test(arguments: ["zz_phoneswitcher_base", "ps_phone_01"])
    func deleteRefusesRecordNotMatchingItsNumber(avdName: String) throws {
        let (manager, config) = try Self.setUp(fake: FakeEmulators())
        try Self.corrupt(config, id: 2, avdName: avdName)
        #expect(throws: PhoneError.notOwned(avdName)) { try manager.delete(id: 2) }
        #expect(FileManager.default.fileExists(atPath: config.avdDir.appendingPathComponent("\(avdName).avd").path))
    }

    @Test func switchRefusesWhenForeignEmulatorIsStillBooting() throws {
        let fake = FakeEmulators()
        fake.processOnly = ["medium_phone"]
        let (manager, _) = try Self.setUp(fake: fake)
        #expect(throws: PhoneError.foreignEmulatorRunning("medium_phone")) { try manager.switchTo(id: 2) { _ in } }
        #expect(fake.shell.launches.isEmpty)
        #expect(manager.overview().foreignRunning == ["medium_phone"])
    }

    @Test func switchRefusesWhileAnotherPhoneIsStillStartingOrSaving() throws {
        let fake = FakeEmulators()
        fake.processOnly = ["ps_phone_01"]
        let (manager, _) = try Self.setUp(fake: fake)
        #expect(throws: PhoneError.phoneBusy("Phone 1")) { try manager.switchTo(id: 2) { _ in } }
        #expect(fake.shell.launches.isEmpty)
    }

    @Test func switchRecordsCurrentBuildStamp() throws {
        let fake = FakeEmulators(emulatorVersion: "36.6.0.0")
        let (manager, _) = try Self.setUp(ids: [1], fake: fake)
        #expect(manager.overview().buildStampMismatch)
        try manager.switchTo(id: 1) { _ in }
        #expect(!manager.overview().buildStampMismatch)
    }

    @Test func setupBaseRedoesUnfinishedBase() throws {
        let fake = FakeEmulators()
        let (manager, config) = try Self.setUp(ids: [], fake: fake)
        try FileManager.default.removeItem(at: config.dataDir.appendingPathComponent("base-ready"))
        #expect(!manager.overview().baseExists)
        fake.shell.hook = { [hook = fake.shell.hook] line, shell in
            hook?(line, shell)
            if line.hasPrefix("sh -c echo no") { try? AvdFilesTests.makeFakeAvd(config.baseName, in: config) }
        }
        try manager.setupBase { _ in }
        #expect(fake.shell.launches.count == 1)
        #expect(manager.overview().baseExists)
    }

    @Test func addPhonesRefusesWhileBaseIsRunning() throws {
        let fake = FakeEmulators()
        fake.processOnly = ["zz_phoneswitcher_base"]
        let (manager, config) = try Self.setUp(ids: [], fake: fake)
        #expect(throws: PhoneError.phoneBusy("the base phone")) { try manager.addPhones(count: 1) }
        #expect(!FileManager.default.fileExists(atPath: config.avdDir.appendingPathComponent("ps_phone_01.avd").path))
    }
}
