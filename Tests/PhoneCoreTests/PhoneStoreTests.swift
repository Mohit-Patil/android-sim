import Foundation
import Testing
@testable import PhoneCore

struct PhoneStoreTests {
    static func phone(_ id: Int) -> Phone {
        Phone(id: id, avdName: String(format: "ps_phone_%02d", id), label: "Phone \(id)", notes: "",
              createdAt: Date(timeIntervalSince1970: 1_000), buildStamp: BuildStamp(emulatorVersion: "36.5.10.0", systemImageRevision: "7"))
    }

    @Test func storeRoundTrips() throws {
        let store = PhoneStore(fileURL: makeTempDir().appendingPathComponent("phones.json"))
        try store.save([Self.phone(2), Self.phone(1)])
        #expect(try store.load() == [Self.phone(1), Self.phone(2)])
    }

    @Test func loadOfMissingFileIsEmpty() throws {
        #expect(try PhoneStore(fileURL: makeTempDir().appendingPathComponent("phones.json")).load() == [])
    }

    @Test func nextIDIsMaxPlusOne() {
        let store = PhoneStore(fileURL: makeTempDir().appendingPathComponent("phones.json"))
        #expect(store.nextID([1, 2, 5].map(Self.phone)) == 6)
        #expect(store.nextID([]) == 1)
    }
}
