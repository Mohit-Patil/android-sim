import Foundation
import Testing
@testable import PhoneCore

struct AvdFilesTests {
    /// Writes a small fake AVD that looks like what avdmanager + a first boot leave behind.
    static func makeFakeAvd(_ name: String, in config: Config) throws {
        let fm = FileManager.default
        let folder = config.avdDir.appendingPathComponent("\(name).avd")
        try fm.createDirectory(at: folder.appendingPathComponent("snapshots/default_boot"), withIntermediateDirectories: true)
        try "path=/Users/x/.android/avd/\(name).avd\npath.rel=avd/\(name).avd\ntarget=android-36\n"
            .write(to: config.avdDir.appendingPathComponent("\(name).ini"), atomically: true, encoding: .utf8)
        try "AvdId=\(name)\navd.ini.displayname=Base\nhw.ramSize=2048\n"
            .write(to: folder.appendingPathComponent("config.ini"), atomically: true, encoding: .utf8)
        try "disk.dataPartition.path = /x/\(name).avd/userdata-qemu.img\n"
            .write(to: folder.appendingPathComponent("hardware-qemu.ini"), atomically: true, encoding: .utf8)
        try "data".write(to: folder.appendingPathComponent("userdata-qemu.img.qcow2"), atomically: true, encoding: .utf8)
        try "".write(to: folder.appendingPathComponent("multiinstance.lock"), atomically: true, encoding: .utf8)
    }

    static func files(_ config: Config) -> AvdFiles { AvdFiles(config: config, guards: Guards(config: config, fileManager: .default)) }

    @Test func cloneRewritesPathsAndNames() throws {
        let config = makeTestConfig()
        try Self.makeFakeAvd(config.baseName, in: config)
        try Self.files(config).clone(from: config.baseName, to: "ps_phone_03")

        let folder = config.avdDir.appendingPathComponent("ps_phone_03.avd")
        let ini = try String(contentsOf: config.avdDir.appendingPathComponent("ps_phone_03.ini"), encoding: .utf8)
        let cfg = try String(contentsOf: folder.appendingPathComponent("config.ini"), encoding: .utf8)
        let hw = try String(contentsOf: folder.appendingPathComponent("hardware-qemu.ini"), encoding: .utf8)
        for text in [ini, cfg, hw] { #expect(!text.contains(config.baseName)) }
        #expect(ini.contains("path=/Users/x/.android/avd/ps_phone_03.avd"))
        #expect(cfg.contains("AvdId=ps_phone_03\n"))
        #expect(cfg.contains("avd.ini.displayname=Phone 03\n"))
        #expect(!cfg.contains("avd.ini.displayname=Base"))
        #expect(hw.contains("/x/ps_phone_03.avd/userdata-qemu.img"))
        #expect(try String(contentsOf: folder.appendingPathComponent("userdata-qemu.img.qcow2"), encoding: .utf8) == "data")
    }

    @Test func cloneDropsSnapshotsAndLocks() throws {
        let config = makeTestConfig()
        try Self.makeFakeAvd(config.baseName, in: config)
        let files = Self.files(config)
        try files.clone(from: config.baseName, to: "ps_phone_04")
        let folder = files.avdFolder("ps_phone_04")
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("snapshots").path))
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("multiinstance.lock").path))
        #expect(!files.hasQuickBootSnapshot("ps_phone_04"))
        #expect(files.hasQuickBootSnapshot(config.baseName))
    }

    @Test func cloneRefusesWhenSSDMissing() throws {
        var config = makeTestConfig()
        try Self.makeFakeAvd(config.baseName, in: config)
        config.requiredVolume = URL(fileURLWithPath: "/Volumes/nope-\(UUID().uuidString)")
        #expect(throws: PhoneError.volumeMissing(config.requiredVolume!.path)) {
            try Self.files(config).clone(from: config.baseName, to: "ps_phone_05")
        }
        #expect(!FileManager.default.fileExists(atPath: config.avdDir.appendingPathComponent("ps_phone_05.avd").path))
    }

    @Test func cloneRefusesToOverwriteExisting() throws {
        let config = makeTestConfig()
        try Self.makeFakeAvd(config.baseName, in: config)
        try Self.makeFakeAvd("ps_phone_06", in: config)
        #expect(throws: (any Error).self) { try Self.files(config).clone(from: config.baseName, to: "ps_phone_06") }
    }

    @Test func refusesToDeleteNonOwnedAvd() throws {
        let config = makeTestConfig()
        try Self.makeFakeAvd("medium_phone", in: config)
        #expect(throws: PhoneError.notOwned("medium_phone")) { try Self.files(config).remove("medium_phone") }
        #expect(Self.files(config).exists("medium_phone"))
    }

    @Test func removeDeletesFolderAndIni() throws {
        let config = makeTestConfig()
        try Self.makeFakeAvd("ps_phone_07", in: config)
        let files = Self.files(config)
        try files.remove("ps_phone_07")
        #expect(!files.exists("ps_phone_07"))
        #expect(!FileManager.default.fileExists(atPath: config.avdDir.appendingPathComponent("ps_phone_07.ini").path))
    }
}
