import Foundation
import Testing
@testable import PhoneCore

struct EmulatorTests {
    @Test func startPassesOfflineFlag() throws {
        let shell = FakeShell()
        let emulator = Emulator(config: makeTestConfig(), shell: shell)
        _ = try emulator.start(avdName: "zz_phoneswitcher_base", offline: true)
        _ = try emulator.start(avdName: "ps_phone_02", offline: false)
        #expect(shell.launches == [
            "emulator -avd zz_phoneswitcher_base -no-boot-anim -no-snapshot -dns-server 127.0.0.1",
            "emulator -avd ps_phone_02 -no-boot-anim",
        ])
    }

    @Test func parsesBuildStamp() throws {
        let config = makeTestConfig()
        try FileManager.default.createDirectory(at: config.systemImageDir, withIntermediateDirectories: true)
        try "Pkg.Desc=Google Play\nPkg.Revision=7\n".write(
            to: config.systemImageDir.appendingPathComponent("source.properties"), atomically: true, encoding: .utf8)
        let shell = FakeShell()
        shell.on("emulator -version", stdout: "Android emulator version 36.5.10.0 (build_id 15081367) (CL:N/A)\nCopyright\n")
        let stamp = try Emulator(config: config, shell: shell).currentBuildStamp()
        #expect(stamp == BuildStamp(emulatorVersion: "36.5.10.0", systemImageRevision: "7"))
    }

    @Test func createBaseAvdSetsHardware() throws {
        let config = makeTestConfig()
        let folder = config.avdDir.appendingPathComponent("\(config.baseName).avd")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "PlayStore.enabled=no\nhw.gpu.enabled=no\nhw.gpu.mode=auto\nhw.keyboard=no\nhw.ramSize=2G\n"
            .write(to: folder.appendingPathComponent("config.ini"), atomically: true, encoding: .utf8)
        let shell = FakeShell()
        try Emulator(config: config, shell: shell).createBaseAvd()
        #expect(shell.calls.first?.hasPrefix(
            "sh -c echo no | ") == true)
        #expect(shell.calls.first?.contains("create avd -n zz_phoneswitcher_base -k 'system-images;android-36;google_apis_playstore;arm64-v8a' -d medium_phone") == true)
        let text = try String(contentsOf: folder.appendingPathComponent("config.ini"), encoding: .utf8)
        for line in ["PlayStore.enabled=yes", "hw.gpu.enabled=yes", "hw.gpu.mode=host", "hw.keyboard=yes", "hw.ramSize=2048"] {
            #expect(text.contains(line + "\n"))
        }
    }
}
