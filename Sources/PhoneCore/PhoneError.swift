import Foundation

public enum PhoneError: Error, Equatable, LocalizedError {
    case volumeMissing(String)
    case foreignEmulatorRunning(String)
    case notOwned(String)
    case phoneNotFound(Int)
    case baseMissing
    case commandFailed(String)
    case timeout(String)
    case phoneBusy(String)
    case avdDirMissing(String)
    case configInvalid(String)

    public var errorDescription: String? {
        switch self {
        case .volumeMissing(let mount):
            "The storage volume \(mount) is not connected. Connect it and try again — nothing was changed."
        case .avdDirMissing(let path):
            "The emulator folder \(path) doesn't exist. Create an emulator in Android Studio once, or set avdDir in the config file."
        case .configInvalid(let detail):
            detail
        case .foreignEmulatorRunning(let name):
            "Another emulator (\(name)) is running. Close it to switch phones."
        case .notOwned(let name):
            "\(name) is not a Phone Switcher phone, so it was left alone."
        case .phoneNotFound(let id):
            "There is no phone number \(id)."
        case .baseMissing:
            "The base phone hasn't been set up yet. Set it up first."
        case .commandFailed(let detail):
            "A command failed: \(detail)"
        case .timeout(let what):
            "Timed out: \(what)"
        case .phoneBusy(let name):
            "\(name) is still starting or saving. Try again in a moment."
        }
    }
}
