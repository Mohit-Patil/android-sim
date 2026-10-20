import Testing
@testable import PhoneCore

struct ProcessShellTests {
    @Test func capturesStdoutAndStatus() throws {
        let result = try ProcessShell().run("/bin/sh", ["-c", "echo hi; echo oops >&2; exit 3"], timeout: 5)
        #expect(result == ShellResult(status: 3, stdout: "hi\n", stderr: "oops\n"))
    }

    @Test func throwsOnTimeout() {
        #expect(throws: PhoneError.timeout("sleep 5")) {
            try ProcessShell().run("/bin/sleep", ["5"], timeout: 0.3)
        }
    }
}
