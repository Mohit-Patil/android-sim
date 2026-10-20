import Foundation

/// Every path and tunable the tool uses, in one place.
///
/// Read from `~/Library/Application Support/PhoneSwitcher/config.json` (all keys optional),
/// then overridden by `ANDROID_HOME`/`ANDROID_SDK_ROOT` and `ANDROID_AVD_HOME`.
public struct Config: Sendable {
    public var sdkRoot: URL
    public var avdDir: URL
    public var dataDir: URL
    /// When set, nothing is created or started unless the AVD folder lives on this volume
    /// (e.g. an external SSD), so a missing drive never sends data to the internal disk.
    public var requiredVolume: URL?
    public var systemImage: String
    public var deviceProfile: String
    public var ramMB: Int
    public var baseName: String
    public var phonePrefix: String
    public var storageWarningBytes: Int64
    /// Set when the config file exists but can't be read; every operation then refuses to run.
    public var loadError: String?

    public static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/PhoneSwitcher/config.json")

    public static let `default` = load(file: fileURL, env: ProcessInfo.processInfo.environment,
                                       home: FileManager.default.homeDirectoryForCurrentUser)

    struct File: Decodable {
        var sdkRoot: String?
        var avdDir: String?
        var dataDir: String?
        var requiredVolume: String?
        var ramMB: Int?
        var storageWarningGB: Int?
    }

    public static func load(file: URL, env: [String: String], home: URL) -> Config {
        func path(_ string: String) -> URL {
            string.hasPrefix("~/") ? home.appendingPathComponent(String(string.dropFirst(2))) : URL(fileURLWithPath: string)
        }
        var settings = File()
        var loadError: String?
        if FileManager.default.fileExists(atPath: file.path) {
            do { settings = try JSONDecoder().decode(File.self, from: Data(contentsOf: file)) } catch {
                loadError = "Couldn't read \(file.path): \(error.localizedDescription) Fix or remove it; nothing will run until then."
            }
        }
        let requiredVolume = settings.requiredVolume.map(path)
        let sdk = env["ANDROID_HOME"] ?? env["ANDROID_SDK_ROOT"]
        return Config(
            sdkRoot: sdk.map(path) ?? settings.sdkRoot.map(path) ?? home.appendingPathComponent("Library/Android/sdk"),
            avdDir: env["ANDROID_AVD_HOME"].map(path) ?? settings.avdDir.map(path) ?? home.appendingPathComponent(".android/avd"),
            dataDir: settings.dataDir.map(path)
                ?? requiredVolume?.appendingPathComponent("PhoneSwitcher")
                ?? home.appendingPathComponent("Library/Application Support/PhoneSwitcher"),
            requiredVolume: requiredVolume,
            systemImage: "system-images;android-36;google_apis_playstore;arm64-v8a",
            deviceProfile: "medium_phone",
            ramMB: settings.ramMB ?? 2048,
            baseName: "zz_phoneswitcher_base",
            phonePrefix: "ps_phone_",
            storageWarningBytes: Int64(settings.storageWarningGB ?? 45) * 1_000_000_000,
            loadError: loadError
        )
    }

    public var adbPath: String { sdkRoot.appendingPathComponent("platform-tools/adb").path }
    public var emulatorPath: String { sdkRoot.appendingPathComponent("emulator/emulator").path }
    public var avdmanagerPath: String { sdkRoot.appendingPathComponent("cmdline-tools/latest/bin/avdmanager").path }

    /// `system-images;android-36;…` → `<sdk>/system-images/android-36/…`
    public var systemImageDir: URL {
        systemImage.split(separator: ";").reduce(sdkRoot) { $0.appendingPathComponent(String($1)) }
    }
}
