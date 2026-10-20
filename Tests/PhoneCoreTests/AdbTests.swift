import Testing
@testable import PhoneCore

struct AdbTests {
    @Test func parsesRunningEmulators() throws {
        let shell = FakeShell()
        shell.on("adb devices", stdout: "List of devices attached\nemulator-5554\tdevice\nemulator-5556\toffline\nR58M\tdevice\n\n")
        shell.on("adb -s emulator-5554 emu avd name", stdout: "ps_phone_03\r\nOK\r\n")
        let running = try Adb(config: makeTestConfig(), shell: shell).runningEmulators()
        #expect(running == [RunningEmulator(serial: "emulator-5554", avdName: "ps_phone_03")])
        #expect(!shell.calls.contains { $0.contains("emulator-5556") || $0.contains("R58M") })
    }

    @Test func isBootedReadsProp() {
        let shell = FakeShell()
        let adb = Adb(config: makeTestConfig(), shell: shell)
        shell.on("adb -s emulator-5554 shell getprop sys.boot_completed", stdout: "1\n")
        #expect(adb.isBooted(serial: "emulator-5554"))
        shell.on("adb -s emulator-5554 shell getprop sys.boot_completed", stdout: "")
        #expect(!adb.isBooted(serial: "emulator-5554"))
    }

    @Test func killSavingSendsEmuKillAndWaitsForExit() throws {
        let shell = FakeShell()
        shell.on("adb devices", stdout: "List of devices attached\n")
        shell.on("pgrep", status: 1)
        try Adb(config: makeTestConfig(), shell: shell).killSaving(serial: "emulator-5554", avdName: "ps_phone_03")
        #expect(shell.calls.contains("adb -s emulator-5554 emu kill"))
        #expect(shell.calls.contains("pgrep -f -- -avd ps_phone_03( |$)"))
    }
}
