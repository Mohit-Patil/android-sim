import Foundation

public struct StorageReport: Equatable, Sendable {
    /// Upper bound: APFS clone blocks shared with the base are counted once per phone.
    public var phonesBytes: Int64
    public var freeBytes: Int64
    public var warningBytes: Int64
    public var overWarning: Bool { phonesBytes > warningBytes }

    public init(phonesBytes: Int64, freeBytes: Int64, warningBytes: Int64) {
        self.phonesBytes = phonesBytes
        self.freeBytes = freeBytes
        self.warningBytes = warningBytes
    }
}

public struct Storage: Sendable {
    let config: Config

    public init(config: Config) {
        self.config = config
    }

    /// Allocated size of each named AVD folder, plus free space on the AVD volume.
    public func report(avdNames: [String]) throws -> StorageReport {
        let total = avdNames.reduce(Int64(0)) { sum, name in
            sum + Self.allocatedSize(of: config.avdDir.appendingPathComponent("\(name).avd"))
        }
        let values = try config.avdDir.resolvingSymlinksInPath()
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return StorageReport(
            phonesBytes: total,
            freeBytes: values.volumeAvailableCapacityForImportantUsage ?? 0,
            warningBytes: config.storageWarningBytes
        )
    }

    static func allocatedSize(of folder: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
