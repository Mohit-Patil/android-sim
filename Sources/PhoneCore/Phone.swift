import Foundation

/// The emulator and system image a phone was made with. A change invalidates Quick Boot snapshots.
public struct BuildStamp: Codable, Equatable, Sendable {
    public var emulatorVersion: String
    public var systemImageRevision: String

    public init(emulatorVersion: String, systemImageRevision: String) {
        self.emulatorVersion = emulatorVersion
        self.systemImageRevision = systemImageRevision
    }
}

public struct Phone: Codable, Identifiable, Equatable, Sendable {
    public var id: Int
    public var avdName: String
    public var label: String
    public var notes: String
    public var createdAt: Date
    public var buildStamp: BuildStamp

    public init(id: Int, avdName: String, label: String, notes: String, createdAt: Date, buildStamp: BuildStamp) {
        self.id = id
        self.avdName = avdName
        self.label = label
        self.notes = notes
        self.createdAt = createdAt
        self.buildStamp = buildStamp
    }

    /// "03" for id 3.
    public var number: String { String(format: "%02d", id) }
}
