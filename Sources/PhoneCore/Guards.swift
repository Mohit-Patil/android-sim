import Foundation

/// Safety checks every mutating or starting operation runs first.
public struct Guards: @unchecked Sendable {
    let config: Config
    let fileManager: FileManager

    public init(config: Config, fileManager: FileManager) {
        self.config = config
        self.fileManager = fileManager
    }

    /// The config must be readable, the AVD folder must exist, and — when a required volume
    /// is configured — the AVD folder (after symlinks) must live on that mounted volume.
    public func requireStorage() throws {
        if let error = config.loadError { throw PhoneError.configInvalid(error) }
        var isDir: ObjCBool = false
        let avd = config.avdDir.resolvingSymlinksInPath().path
        if let volume = config.requiredVolume {
            let mount = volume.resolvingSymlinksInPath().path
            guard fileManager.fileExists(atPath: mount, isDirectory: &isDir), isDir.boolValue,
                  fileManager.fileExists(atPath: avd, isDirectory: &isDir), isDir.boolValue,
                  avd.hasPrefix(mount + "/")
            else { throw PhoneError.volumeMissing(volume.path) }
        } else {
            guard fileManager.fileExists(atPath: avd, isDirectory: &isDir), isDir.boolValue
            else { throw PhoneError.avdDirMissing(config.avdDir.path) }
        }
    }

    public func isOwned(avdName: String) -> Bool {
        if avdName == config.baseName { return true }
        guard avdName.hasPrefix(config.phonePrefix) else { return false }
        let number = avdName.dropFirst(config.phonePrefix.count)
        return number.count >= 2 && number.allSatisfy(\.isASCII) && number.allSatisfy(\.isNumber)
    }

    /// A phone record may only name its own `ps_phone_NN` AVD — never the base or another phone.
    public func requirePhone(_ phone: Phone) throws {
        let expected = config.phonePrefix + phone.number
        guard phone.avdName == expected else { throw PhoneError.notOwned(phone.avdName) }
    }

    public func requireOwned(avdName: String) throws {
        guard isOwned(avdName: avdName) else { throw PhoneError.notOwned(avdName) }
    }
}
