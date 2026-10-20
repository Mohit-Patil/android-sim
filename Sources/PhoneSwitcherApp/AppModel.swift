import Foundation
import Observation
import PhoneCore

@MainActor @Observable
final class AppModel {
    var overview = Overview()
    var busyMessage: String?
    var errorMessage: String?
    var lastSwitchSeconds: Double?

    private let manager: PhoneManager
    private var refreshTask: Task<Void, Never>?
    private var refreshing = false
    private var refreshAgain = false
    /// Identifies the running operation so late progress messages from it are ignored.
    private var operation = 0

    init(manager: PhoneManager = PhoneManager()) {
        self.manager = manager
    }

    var isBusy: Bool { busyMessage != nil }

    /// Refreshes every 3 s while the window is open.
    func startRefreshing() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stopRefreshing() {
        refreshTask?.cancel()
    }

    /// One refresh at a time; a request during a refresh runs once more afterwards,
    /// so a slow, stale overview can never overwrite a newer one.
    func refresh() async {
        if refreshing { refreshAgain = true; return }
        refreshing = true
        defer { refreshing = false }
        let manager = manager
        repeat {
            refreshAgain = false
            overview = await Task.detached { manager.overview() }.value
        } while refreshAgain
    }

    func switchTo(_ id: Int) {
        let started = Date()
        run("Switching…") { manager, progress in
            try manager.switchTo(id: id, progress: progress)
        } done: { model in
            model.lastSwitchSeconds = Date().timeIntervalSince(started)
        }
    }

    func add(count: Int) { run("Adding phones…") { manager, _ in _ = try manager.addPhones(count: count) } }
    func setupBase() { run("Setting up the base phone…") { manager, progress in try manager.setupBase(progress: progress) } }
    func stop() { run("Saving…") { manager, _ in try manager.stopRunning() } }
    func reset(_ id: Int) { run("Resetting…") { manager, _ in try manager.reset(id: id) } }
    func delete(_ id: Int) { run("Deleting…") { manager, _ in try manager.delete(id: id) } }

    /// Only edits the phone list, so it runs even while a switch or setup is in progress.
    func relabel(_ id: Int, label: String, notes: String) {
        let manager = manager
        Task {
            let error: String? = await Task.detached {
                do { try manager.relabel(id: id, label: label, notes: notes); return nil } catch { return error.localizedDescription }
            }.value
            if let error { errorMessage = error }
            await refresh()
        }
    }

    func bringToFront(_ id: Int) {
        let manager = manager
        Task.detached { manager.bringToFront(id: id) }
    }

    /// Runs one manager operation off the main actor; only one at a time.
    private func run(_ message: String, _ work: @escaping @Sendable (PhoneManager, @escaping @Sendable (String) -> Void) throws -> Void,
                     done: (@MainActor (AppModel) -> Void)? = nil) {
        guard !isBusy else { return }
        operation += 1
        let token = operation
        busyMessage = message
        errorMessage = nil
        let manager = manager
        Task {
            let progress: @Sendable (String) -> Void = { text in
                Task { @MainActor in if self.operation == token && self.busyMessage != nil { self.busyMessage = text } }
            }
            let error: String? = await Task.detached {
                do { try work(manager, progress); return nil } catch { return error.localizedDescription }
            }.value
            operation += 1
            busyMessage = nil
            errorMessage = error
            if error == nil { done?(self) }
            await refresh()
        }
    }
}
