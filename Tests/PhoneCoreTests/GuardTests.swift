import Foundation
import Testing
@testable import PhoneCore

struct GuardTests {
    @Test func requireStorageThrowsWhenMountMissing() {
        var config = makeTestConfig()
        config.requiredVolume = URL(fileURLWithPath: "/Volumes/definitely-not-here-\(UUID().uuidString)")
        let guards = Guards(config: config, fileManager: .default)
        #expect(throws: PhoneError.volumeMissing(config.requiredVolume!.path)) { try guards.requireStorage() }
    }

    @Test func requireStorageThrowsWhenAvdDirMissing() {
        var config = makeTestConfig()
        config.avdDir = config.requiredVolume!.appendingPathComponent("missing-avd")
        let guards = Guards(config: config, fileManager: .default)
        #expect(throws: PhoneError.volumeMissing(config.requiredVolume!.path)) { try guards.requireStorage() }
    }

    @Test func requireStorageThrowsWhenAvdDirIsNotOnTheSSD() throws {
        var config = makeTestConfig()
        let elsewhere = makeTempDir()
        config.avdDir = elsewhere
        let guards = Guards(config: config, fileManager: .default)
        #expect(throws: PhoneError.volumeMissing(config.requiredVolume!.path)) { try guards.requireStorage() }
    }

    @Test func requireStorageFollowsSymlinkOntoTheSSD() throws {
        var config = makeTestConfig()
        let link = makeTempDir().appendingPathComponent("avd-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: config.avdDir)
        config.avdDir = link
        try Guards(config: config, fileManager: .default).requireStorage()
    }

    @Test func requireStoragePassesWithoutRequiredVolume() throws {
        var config = makeTestConfig()
        config.requiredVolume = nil
        try Guards(config: config, fileManager: .default).requireStorage()
    }

    @Test func requireStorageThrowsWhenAvdDirMissingWithoutRequiredVolume() {
        var config = makeTestConfig()
        config.requiredVolume = nil
        config.avdDir = makeTempDir().appendingPathComponent("missing")
        #expect(throws: PhoneError.avdDirMissing(config.avdDir.path)) {
            try Guards(config: config, fileManager: .default).requireStorage()
        }
    }

    @Test func invalidConfigBlocksEverything() {
        var config = makeTestConfig()
        config.loadError = "config.json: bad JSON"
        #expect(throws: PhoneError.configInvalid("config.json: bad JSON")) {
            try Guards(config: config, fileManager: .default).requireStorage()
        }
    }

    @Test func requireStoragePassesWhenBothExist() throws {
        let guards = Guards(config: makeTestConfig(), fileManager: .default)
        try guards.requireStorage()
    }

    @Test(arguments: ["ps_phone_03", "ps_phone_15", "ps_phone_123", "zz_phoneswitcher_base"])
    func requireOwnedAcceptsPhonesAndBase(name: String) throws {
        try Guards(config: makeTestConfig(), fileManager: .default).requireOwned(avdName: name)
    }

    @Test(arguments: ["medium_phone", "ps_phone_../medium_phone", "ps_phone_", "ps_phone_3", "other_project_qa"])
    func requireOwnedRejectsOthers(name: String) {
        let guards = Guards(config: makeTestConfig(), fileManager: .default)
        #expect(throws: PhoneError.notOwned(name)) { try guards.requireOwned(avdName: name) }
    }

    @Test func volumeMissingMessageIsPlain() {
        let message = PhoneError.volumeMissing("/Volumes/SSD").errorDescription
        #expect(message == "The storage volume /Volumes/SSD is not connected. Connect it and try again — nothing was changed.")
    }
}
