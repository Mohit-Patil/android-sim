import Foundation
import Testing
@testable import PhoneCore

struct ConfigTests {
    static let home = URL(fileURLWithPath: "/Users/someone")

    static func file(_ json: String) throws -> URL {
        let url = makeTempDir().appendingPathComponent("config.json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func defaultsWithoutFileOrEnv() {
        let config = Config.load(file: makeTempDir().appendingPathComponent("none.json"), env: [:], home: Self.home)
        #expect(config.sdkRoot.path == "/Users/someone/Library/Android/sdk")
        #expect(config.avdDir.path == "/Users/someone/.android/avd")
        #expect(config.dataDir.path == "/Users/someone/Library/Application Support/PhoneSwitcher")
        #expect(config.requiredVolume == nil)
        #expect(config.ramMB == 2048)
        #expect(config.storageWarningBytes == 45_000_000_000)
        #expect(config.loadError == nil)
    }

    @Test func fileOverridesDefaults() throws {
        let url = try Self.file("""
        {"requiredVolume": "/Volumes/SSD", "sdkRoot": "~/sdk", "ramMB": 3072, "storageWarningGB": 60}
        """)
        let config = Config.load(file: url, env: [:], home: Self.home)
        #expect(config.requiredVolume?.path == "/Volumes/SSD")
        #expect(config.sdkRoot.path == "/Users/someone/sdk")
        #expect(config.dataDir.path == "/Volumes/SSD/PhoneSwitcher")
        #expect(config.ramMB == 3072)
        #expect(config.storageWarningBytes == 60_000_000_000)
    }

    @Test func fileCanSetDataDir() throws {
        let url = try Self.file(#"{"requiredVolume": "/Volumes/SSD", "dataDir": "/Volumes/SSD/Developer/Android/phone-switcher"}"#)
        #expect(Config.load(file: url, env: [:], home: Self.home).dataDir.path == "/Volumes/SSD/Developer/Android/phone-switcher")
    }

    @Test func envOverridesFile() throws {
        let url = try Self.file(#"{"sdkRoot": "/from/file", "avdDir": "/from/file/avd"}"#)
        let config = Config.load(file: url, env: ["ANDROID_HOME": "/from/env", "ANDROID_AVD_HOME": "/env/avd"], home: Self.home)
        #expect(config.sdkRoot.path == "/from/env")
        #expect(config.avdDir.path == "/env/avd")
    }

    @Test func androidSdkRootIsAccepted() {
        let config = Config.load(file: makeTempDir().appendingPathComponent("none.json"), env: ["ANDROID_SDK_ROOT": "/legacy"], home: Self.home)
        #expect(config.sdkRoot.path == "/legacy")
    }

    @Test func invalidFileIsReportedNotIgnored() throws {
        let url = try Self.file("{ not json")
        let config = Config.load(file: url, env: [:], home: Self.home)
        #expect(config.loadError?.contains(url.path) == true)
    }
}
