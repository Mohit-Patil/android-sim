import Foundation

/// The phone list, kept as JSON in the SSD data folder.
public final class PhoneStore: @unchecked Sendable {
    let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> [Phone] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Phone].self, from: Data(contentsOf: fileURL)).sorted { $0.id < $1.id }
    }

    public func save(_ phones: [Phone]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(phones.sorted { $0.id < $1.id }).write(to: fileURL, options: .atomic)
    }

    public func nextID(_ phones: [Phone]) -> Int {
        (phones.map(\.id).max() ?? 0) + 1
    }
}
