import Foundation
import PhoneCore

let usage = """
usage: phones <command>
  list                  show phones and their status
  setup-base            create the base phone (once)
  add [count]           add phones copied from the base (default 1)
  switch <n>            save the running phone and start phone n
  stop                  save and stop the running phone
  label <n> <text…>     set phone n's label (e.g. its Google account)
  reset <n> [--yes]     erase phone n back to a fresh phone
  delete <n> [--yes]    delete phone n
  front <n>             bring phone n's window to the front
"""

func gb(_ bytes: Int64) -> String { String(format: "%.1f GB", Double(bytes) / 1_000_000_000) }

func statusText(_ status: PhoneStatus) -> String {
    switch status {
    case .running: "running"
    case .saved: "saved"
    case .neverStarted: "not started yet"
    case .broken: "broken (files missing)"
    }
}

func printOverview(_ overview: Overview) {
    guard overview.storageConnected else {
        print(overview.storageError ?? "Storage isn't available.")
        return
    }
    if let error = overview.loadError { print(error) }
    if !overview.baseExists { print("No base phone yet. Run: phones setup-base") }
    print(" #  \("label".padding(toLength: 32, withPad: " ", startingAt: 0))  status")
    for row in overview.rows {
        let label = row.phone.label.padding(toLength: 32, withPad: " ", startingAt: 0)
        print("\(row.phone.number)  \(label)  \(statusText(row.status))")
    }
    if let storage = overview.storage {
        print("Phones use up to \(gb(storage.phonesBytes)) · \(gb(storage.freeBytes)) free")
        if storage.overWarning { print("Warning: phones are using more than \(gb(storage.warningBytes)).") }
    }
    for name in overview.foreignRunning { print("Close \(name) to switch phones.") }
    if overview.buildStampMismatch {
        print("The emulator was updated since these phones were made. Each phone will do one slow start (about a minute); logins are kept.")
    }
}

func number(_ args: ArraySlice<String>) -> Int? { args.first.flatMap(Int.init) }

func confirm(_ question: String, _ args: ArraySlice<String>) -> Bool {
    if args.contains("--yes") { return true }
    print("\(question) [y/N] ", terminator: "")
    return readLine()?.lowercased().hasPrefix("y") == true
}

func say(_ message: String) { print(message) }

let args = CommandLine.arguments.dropFirst()
let rest = args.dropFirst()
let manager = PhoneManager()

do {
    switch args.first {
    case "list", nil:
        printOverview(manager.overview())
    case "setup-base":
        try manager.setupBase(progress: say)
    case "add":
        let added = try manager.addPhones(count: number(rest) ?? 1)
        print("Added \(added.map(\.label).joined(separator: ", "))")
    case "switch":
        guard let id = number(rest) else { throw PhoneError.commandFailed("switch needs a phone number") }
        let start = Date()
        try manager.switchTo(id: id, progress: say)
        print(String(format: "Switched in %.1f s", Date().timeIntervalSince(start)))
    case "stop":
        try manager.stopRunning()
    case "label":
        guard let id = number(rest), rest.count > 1 else { throw PhoneError.commandFailed("label needs a number and text") }
        let notes = (manager.overview().rows.first { $0.id == id }?.phone.notes) ?? ""
        try manager.relabel(id: id, label: rest.dropFirst().joined(separator: " "), notes: notes)
    case "reset":
        guard let id = number(rest) else { throw PhoneError.commandFailed("reset needs a phone number") }
        if confirm("Erase phone \(id) back to a fresh phone? Its Google sign-in and app data will be lost.", rest) {
            try manager.reset(id: id)
        }
    case "delete":
        guard let id = number(rest) else { throw PhoneError.commandFailed("delete needs a phone number") }
        if confirm("Delete phone \(id)?", rest) { try manager.delete(id: id) }
    case "front":
        guard let id = number(rest) else { throw PhoneError.commandFailed("front needs a phone number") }
        manager.bringToFront(id: id)
    default:
        FileHandle.standardError.write(Data((usage + "\n").utf8))
        exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
