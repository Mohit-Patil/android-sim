import Foundation
import Testing
@testable import PhoneCore

struct StorageTests {
    static func writeFile(_ url: URL, bytes: Int) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: url)
    }

    @Test func sumsFolderSizes() throws {
        let config = makeTestConfig()
        try Self.writeFile(config.avdDir.appendingPathComponent("ps_phone_01.avd/a.img"), bytes: 1_000_000)
        try Self.writeFile(config.avdDir.appendingPathComponent("ps_phone_01.avd/snapshots/default_boot/ram.bin"), bytes: 2_000_000)
        try Self.writeFile(config.avdDir.appendingPathComponent("medium_phone.avd/big.img"), bytes: 5_000_000)
        let report = try Storage(config: config).report(avdNames: ["ps_phone_01"])
        // Allocated sizes round up to blocks; must count both files and not the foreign AVD.
        #expect(report.phonesBytes >= 3_000_000 && report.phonesBytes < 3_200_000)
        #expect(report.freeBytes > 0)
        #expect(!report.overWarning)
    }

    @Test func flagsOverWarning() throws {
        var config = makeTestConfig()
        config.storageWarningBytes = 10
        try Self.writeFile(config.avdDir.appendingPathComponent("ps_phone_01.avd/a.img"), bytes: 100)
        #expect(try Storage(config: config).report(avdNames: ["ps_phone_01"]).overWarning)
    }
}
