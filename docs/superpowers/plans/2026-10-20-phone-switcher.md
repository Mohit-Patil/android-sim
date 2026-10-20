# Phone Switcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS app plus a `phones` CLI that manage 10–15 APFS-cloned Android emulators ("phones"), each with its own Google account, and switch between them in seconds, one running at a time, with all data on the external SSD.

**Architecture:** A Swift package with one core library (`PhoneCore`) that owns config, the phone list, AVD cloning, emulator/adb control and safety guards. A thin CLI (`phones`) and a SwiftUI window app (`PhoneSwitcherApp`) both call `PhoneManager` in the core. All external commands go through a `Shell` protocol so the core is unit-tested with a fake; real-emulator behaviour is checked in a gating spike (Task 1) and manual verification steps.

**Tech Stack:** Swift 6.4, SwiftPM, SwiftUI (macOS 15+), Swift Testing, Android SDK emulator 36.5.10 / adb / avdmanager. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-10-20-phone-switcher-design.md`

## Global Constraints

- All emulator data lives under `~/.android/avd` (symlink → an external SSD); tool data in a folder on the SSD. Never write emulator data to the internal disk; never replace the `~/.android/avd` symlink.
- If the SSD is not mounted: refuse to create, start or change anything, and say so plainly.
- Never modify, start or stop AVDs the tool did not create (for example the user's own `medium_phone`).
- System image: `system-images;android-36;google_apis_playstore;arm64-v8a`; device profile `medium_phone`; guest RAM 2048 MB (tunable in config); `hw.gpu.mode=host`.
- Base AVD name: `zz_phoneswitcher_base`. Phone AVD names: `ps_phone_NN` (two-digit, e.g. `ps_phone_03`).
- Base first boot is offline; base is created before any Google sign-in or app install.
- One phone runs at a time. Foreign emulator running → refuse to switch, name it.
- Storage warning when phones total > 45 GB (warning, not failure). Speed beats space.
- Personal tool: unsigned, non-sandboxed; paths in one `Config` with this Mac's values as defaults.
- SDK root: `~/Library/Android/sdk`.

## Review Focus

- SSD unplugged at launch or between actions → every mutating/starting call throws `PhoneError.ssdMissing` before touching disk or launching anything (test: Task 2 guard tests, Task 6 manager test).
- User's own emulator (e.g. `medium_phone`) running when they press Switch → refuse with its name, never kill it (test: Task 6 `switchRefusesWhenForeignEmulatorRuns`).
- Switching to the phone that is already running → no stop/start, just report it running (test: Task 6 `switchToRunningPhoneIsNoop`).
- Emulator or system image updated since phones were made → warning surfaced in status, start still allowed (test: Task 6 `statusFlagsBuildStampMismatch`).
- Delete/reset with a phone record whose AVD path is outside `avdDir` or not `ps_phone_` prefixed (corrupted `phones.json`) → refuse, touch nothing (test: Task 3 `refusesToDeleteNonOwnedAvd`).

---

### Task 0: Repository and package skeleton

**Files:**
- Create: `Package.swift`, `.gitignore`, `Sources/PhoneCore/PhoneCore.swift`, `Sources/phones/main.swift`, `Sources/PhoneSwitcherApp/PhoneSwitcherApp.swift`, `Tests/PhoneCoreTests/SmokeTests.swift`

- [ ] **Step 1:** `git init` in the project folder (only if the user agreed; local only, never push). `.gitignore`: `.build/`, `build/`, `.swiftpm/`, `*.xcodeproj`.
- [ ] **Step 2:** `Package.swift`: tools 6.0, platform `.macOS(.v15)`, targets: library `PhoneCore`, executable `phones` (deps PhoneCore), executable `PhoneSwitcherApp` (deps PhoneCore), test target `PhoneCoreTests`. Smoke test `@Test func coreLoads() { #expect(PhoneCore.version == "0.1.0") }`.
- [ ] **Step 3:** Run `swift build && swift test`. Expected: build succeeds, 1 test passes.
- [ ] **Step 4:** Commit `chore: package skeleton`.

### Task 1: GATING SPIKE — offline base + clones get distinct identities, and switch timing

Throwaway script, not product code. Nothing after Task 2 is built until this passes. If it fails, stop and report to the user (spec: "stop and report rather than work around it silently").

**Files:**
- Create: `spike/clone-identity.sh`, `spike/RESULTS.md`

- [ ] **Step 1:** Script creates `zz_phoneswitcher_base` with `avdmanager create avd -n zz_phoneswitcher_base -k "system-images;android-36;google_apis_playstore;arm64-v8a" -d medium_phone` (answer `no` to custom profile), sets `hw.ramSize=2048`, `hw.gpu.mode=host` in its `config.ini`.
- [ ] **Step 2:** Cold-boot the base **offline**: `emulator -avd zz_phoneswitcher_base -no-snapshot -no-boot-anim -dns-server 127.0.0.1` (unresolvable DNS so Play services cannot check in). Wait for `sys.boot_completed=1`, then wait 120 s more for first-boot work, then `adb emu kill`. Confirm offline by `adb shell ping -c1 google.com` failing during the boot. If DNS blocking is not enough (e.g. GMS reaches Google by IP), also try `adb shell cmd connectivity airplane-mode enable` immediately after `adb wait-for-device`, and record which method worked.
- [ ] **Step 3:** Delete `zz_phoneswitcher_base.avd/snapshots/`, then APFS-clone into `ps_phone_98` and `ps_phone_99` (`cp -cR`), rewriting paths/names in `<name>.ini`, `config.ini`, `hardware-qemu.ini` (`sed` replacement of `zz_phoneswitcher_base` → new name is acceptable for the spike).
- [ ] **Step 4:** Boot each clone online (normal `emulator -avd ps_phone_9N`), wait 3 min for Play services check-in. Record for each: Google device/GSF ID (`adb shell content query --uri content://com.google.android.gsf.gservices --where "name='android_id'"`; if blocked on this user build, use the Google Play Store app → settings "Device" / `adb shell dumpsys package com.google.android.gms | grep -i checkin` — record the method used) and `adb shell settings get secure android_id`.
- [ ] **Step 5:** Timing: on `ps_phone_98`, `adb emu kill`, then time `emulator -avd ps_phone_98` until `sys.boot_completed=1` (Quick Boot resume). Repeat 3×. Record: does `adb emu kill` save the Quick Boot snapshot (does `snapshots/default_boot` exist and the next start resume)? Record sizes: `du -sh` of each clone, and real SSD free-space delta (`df`) across the whole spike.
- [ ] **Step 6:** Write `spike/RESULTS.md`. **Pass criteria:** the two clones' Google device IDs differ; resume ≤ 10 s; `adb emu kill` saves the snapshot (or record the command that does). Delete `ps_phone_98/99` after. Keep the base if passed.
- [ ] **Step 7:** Commit `spike: clone identity and timing results`. Report results to the user before continuing.

### Task 2: Config, Shell and safety guards

**Files:**
- Create: `Sources/PhoneCore/Config.swift`, `Sources/PhoneCore/Shell.swift`, `Sources/PhoneCore/Guards.swift`, `Sources/PhoneCore/PhoneError.swift`
- Test: `Tests/PhoneCoreTests/GuardTests.swift`, `Tests/PhoneCoreTests/FakeShell.swift`

**Interfaces:**
- Produces:
  - `struct Config { var sdkRoot, avdDir, dataDir, ssdMount: URL; var systemImage: String; var deviceProfile: String; var ramMB: Int; var baseName: String; var phonePrefix: String; var storageWarningBytes: Int64; static let `default`: Config }` — defaults from Global Constraints; `storageWarningBytes = 45 * 1_000_000_000`; `ramMB = 2048`; `phonePrefix = "ps_phone_"`. `Config.default` reads env `PHONES_SSD_MOUNT` to override `ssdMount` (used only for manual SSD-missing testing).
  - `protocol Shell: Sendable { func run(_ executable: String, _ args: [String], timeout: TimeInterval) throws -> ShellResult; func launchDetached(_ executable: String, _ args: [String]) throws -> Int32 /* pid */ }`, `struct ShellResult { let status: Int32; let stdout: String; let stderr: String }`, `struct ProcessShell: Shell`.
  - `enum PhoneError: Error, Equatable, LocalizedError { case ssdMissing(String), foreignEmulatorRunning(String), notOwned(String), phoneNotFound(Int), baseMissing, commandFailed(String), timeout(String) }` — `ssdMissing` message: "The SSD (/Volumes/SSD) is not connected. Connect it and try again — nothing was changed."
  - `struct Guards { init(config: Config, fileManager: FileManager); func requireSSD() throws; func requireOwned(avdName: String) throws }`.
- Test `FakeShell`: records calls, returns scripted `ShellResult`s keyed by `"exe arg1 arg2"` prefix.

- [ ] **Step 1: Failing tests** in `GuardTests.swift`:
  - `requireSSDThrowsWhenMountMissing`: config with `ssdMount` = nonexistent temp path → `#expect(throws: PhoneError.ssdMissing(...))`.
  - `requireSSDThrowsWhenAvdDirMissing`: mount exists, `avdDir` doesn't → throws `ssdMissing`.
  - `requireSSDPassesWhenBothExist`.
  - `requireOwnedAcceptsPhonesAndBase`: `ps_phone_03`, `zz_phoneswitcher_base` pass.
  - `requireOwnedRejectsOthers`: `medium_phone`, `ps_phone_../medium_phone`, `ps_phone_` (no number) throw `notOwned`.
- [ ] **Step 2:** `swift test --filter GuardTests` → FAIL (types missing).
- [ ] **Step 3:** Implement. Owned name regex: `^ps_phone_[0-9]{2,}$` or exactly `baseName`.
- [ ] **Step 4:** `swift test --filter GuardTests` → PASS.
- [ ] **Step 5:** Commit `feat(core): config, shell, guards`.

### Task 3: Phone store and AVD cloning

**Files:**
- Create: `Sources/PhoneCore/Phone.swift`, `Sources/PhoneCore/PhoneStore.swift`, `Sources/PhoneCore/AvdFiles.swift`
- Test: `Tests/PhoneCoreTests/PhoneStoreTests.swift`, `Tests/PhoneCoreTests/AvdFilesTests.swift`

**Interfaces:**
- Consumes: `Config`, `Guards`, `PhoneError`.
- Produces:
  - `struct BuildStamp: Codable, Equatable { var emulatorVersion: String; var systemImageRevision: String }`
  - `struct Phone: Codable, Identifiable, Equatable { var id: Int; var avdName: String; var label: String; var notes: String; var createdAt: Date; var buildStamp: BuildStamp }`
  - `final class PhoneStore { init(fileURL: URL); func load() throws -> [Phone]; func save(_ phones: [Phone]) throws; func nextID(_ phones: [Phone]) -> Int }` — file `dataDir/phones.json`, atomic write, sorted by id; `nextID` = max+1 (start 1); ids never reused while a higher one exists.
  - `struct AvdFiles { init(config: Config, guards: Guards); func clone(from source: String, to target: String) throws; func remove(_ avdName: String) throws; func exists(_ avdName: String) -> Bool; func hasQuickBootSnapshot(_ avdName: String) -> Bool; func avdFolder(_ avdName: String) -> URL }`.
- `clone`: `clonefile(2)` the `<source>.avd` folder (Darwin `clonefile` with `CLONE_NOFOLLOW`; falls back to error, never to a full copy), copy `<source>.ini` → `<target>.ini`, then rewrite every occurrence of `<source>` with `<target>` in `<target>.ini`, `config.ini`, `hardware-qemu.ini` (if present); set `AvdId=<target>` and `avd.ini.displayname=Phone NN`. Delete `<target>.avd/snapshots` and any `*.lock` files in the clone. Calls `guards.requireSSD()` and `requireOwned(target)` first.
- `remove`: `requireSSD`, `requireOwned`, and the resolved folder must be inside `avdDir` → delete `<name>.avd` and `<name>.ini`.

- [ ] **Step 1: Failing tests** (temp dirs with fake AVD folders containing small text ini files):
  - `storeRoundTrips`, `nextIDIsMaxPlusOne` (`[1,2,5]` → 6; empty → 1).
  - `cloneRewritesPathsAndNames`: fake base with `config.ini` containing `AvdId=zz_phoneswitcher_base`, `hardware-qemu.ini` containing `/x/zz_phoneswitcher_base.avd/userdata-qemu.img`, `<base>.ini` with `path=…/zz_phoneswitcher_base.avd` → after clone to `ps_phone_03`, none of the three files contain `zz_phoneswitcher_base`; `AvdId=ps_phone_03`; `avd.ini.displayname=Phone 03`.
  - `cloneDropsSnapshotsAndLocks`.
  - `cloneRefusesWhenSSDMissing` → `ssdMissing`, no target folder created.
  - `refusesToDeleteNonOwnedAvd`: `remove("medium_phone")` throws `notOwned`; folder still exists.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `swift test` → PASS.
- [ ] **Step 5:** Commit `feat(core): phone store and APFS cloning`.

### Task 4: Emulator and adb control

**Files:**
- Create: `Sources/PhoneCore/Emulator.swift`, `Sources/PhoneCore/Adb.swift`
- Test: `Tests/PhoneCoreTests/AdbTests.swift`, `Tests/PhoneCoreTests/EmulatorTests.swift`

**Interfaces:**
- Consumes: `Config`, `Shell`, `PhoneError`, `BuildStamp`.
- Produces:
  - `struct RunningEmulator: Equatable { let serial: String; let avdName: String }`
  - `struct Adb { init(config: Config, shell: Shell); func runningEmulators() throws -> [RunningEmulator]; func isBooted(serial: String) -> Bool; func killSaving(serial: String) throws }` — `runningEmulators`: parse `adb devices` lines `emulator-NNNN\tdevice`, then `adb -s <serial> emu avd name` (first line). `killSaving` uses the save-and-stop command recorded in `spike/RESULTS.md`, then waits up to 60 s for the serial to disappear, else `timeout`.
  - `struct Emulator { init(config: Config, shell: Shell); func start(avdName: String, offline: Bool) throws -> Int32; func currentBuildStamp() throws -> BuildStamp; func createBaseAvd() throws }` — `start` launches detached: `emulator -avd <name> -no-boot-anim` plus `-dns-server 127.0.0.1` (or the offline method from RESULTS.md) when `offline`. `currentBuildStamp`: first line of `emulator -version` after "version ", and `Pkg.Revision` from `<sdk>/system-images/android-36/google_apis_playstore/arm64-v8a/source.properties`. `createBaseAvd`: `avdmanager create avd` as in Task 1 Step 1, then sets `hw.ramSize=<ramMB>`, `hw.gpu.mode=host`.
- [ ] **Step 1: Failing tests** with `FakeShell`:
  - `parsesRunningEmulators`: `adb devices` output with `emulator-5554\tdevice`, `emulator-5556\toffline`, `R58M\tdevice` → only `emulator-5554` queried; `emu avd name` returns `"ps_phone_03\nOK"` → `[RunningEmulator(serial:"emulator-5554", avdName:"ps_phone_03")]`.
  - `isBootedReadsProp`: `getprop sys.boot_completed` `"1\n"` → true; `""` → false.
  - `startPassesOfflineFlag`: `start(avdName:"zz_phoneswitcher_base", offline:true)` launches with args containing `-dns-server` and `127.0.0.1`; `offline:false` does not.
  - `parsesBuildStamp`: `"Android emulator version 36.5.10.0 (build_id 15081367) (CL:N/A)"` → `emulatorVersion == "36.5.10.0"`.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(core): emulator and adb control`.

### Task 5: Storage measurement

**Files:**
- Create: `Sources/PhoneCore/Storage.swift`
- Test: `Tests/PhoneCoreTests/StorageTests.swift`

**Interfaces:**
- Produces: `struct StorageReport: Equatable { var phonesBytes: Int64; var ssdFreeBytes: Int64; var overWarning: Bool }`, `struct Storage { init(config: Config); func report(avdNames: [String]) throws -> StorageReport }`.
- `phonesBytes` = allocated size (`totalFileAllocatedSize`) summed over each phone's `.avd` folder plus the base. This over-counts shared clone blocks (upper bound) — label it "up to" in UIs. `ssdFreeBytes` from `volumeAvailableCapacityForImportantUsage` of `avdDir`. `overWarning = phonesBytes > storageWarningBytes`.
- [ ] **Step 1: Failing tests:** `sumsFolderSizes` (temp folders with known-size files), `flagsOverWarning` (config with `storageWarningBytes = 10`).
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5:** Commit `feat(core): storage report`.

### Task 6: PhoneManager (orchestration)

**Files:**
- Create: `Sources/PhoneCore/PhoneManager.swift`
- Test: `Tests/PhoneCoreTests/PhoneManagerTests.swift`

**Interfaces:**
- Consumes: everything above.
- Produces:
  - `enum PhoneStatus: Equatable { case running, saved, neverStarted, broken }` — broken = record exists but AVD folder missing; saved = `hasQuickBootSnapshot`.
  - `struct PhoneRow: Identifiable, Equatable { var phone: Phone; var status: PhoneStatus; var id: Int { phone.id } }`
  - `struct Overview: Equatable { var ssdConnected: Bool; var baseExists: Bool; var rows: [PhoneRow]; var foreignRunning: [String]; var buildStampMismatch: Bool; var storage: StorageReport? }`
  - `final class PhoneManager: @unchecked Sendable { init(config: Config, shell: Shell, fileManager: FileManager = .default); func overview() -> Overview; func setupBase(progress: (String) -> Void) throws; func addPhones(count: Int) throws -> [Phone]; func switchTo(id: Int, progress: (String) -> Void) throws; func stopRunning() throws; func relabel(id: Int, label: String, notes: String) throws; func reset(id: Int) throws; func delete(id: Int) throws; func bringToFront(id: Int) }`
- Behaviour:
  - `overview` never throws; `ssdConnected=false` → empty rows, everything else default.
  - `setupBase`: `requireSSD`; create base AVD; offline cold boot; wait boot_completed (timeout 300 s) + 120 s settle; `killSaving`; delete base snapshots. Idempotent: if base exists, return.
  - `addPhones`: `requireSSD`, `baseMissing` if no base; for each: `nextID`, clone `ps_phone_NN`, `label = "Phone NN"`, stamp = `currentBuildStamp()`; save store after each.
  - `switchTo(id)`: `requireSSD`; running = `runningEmulators()`; if any running AVD is not owned → `foreignEmulatorRunning(name)`; if target already running → return (no-op); stop owned running phone via `killSaving`; `start(target, offline:false)`; poll `isBooted` every 0.5 s up to 120 s → else `timeout`. Progress strings: "Saving Phone NN…", "Starting Phone MM…", "Ready".
  - `reset(id)`: stop it if running; `remove` + `clone` from base; keep id/label/notes; new stamp.
  - `delete(id)`: stop if running; `remove`; drop from store.
  - `bringToFront`: find pid by `pgrep -f "qemu.*-avd <avdName>"`, `NSRunningApplication(processIdentifier:)?.activate()`.
  - `buildStampMismatch` = any phone's stamp ≠ `currentBuildStamp()`.
- [ ] **Step 1: Failing tests** (FakeShell + temp dirs):
  - `switchRefusesWhenForeignEmulatorRuns`: running `[medium_phone]` → throws `foreignEmulatorRunning("medium_phone")`; FakeShell recorded no `emu kill` and no emulator launch.
  - `switchToRunningPhoneIsNoop`: running `[ps_phone_02]`, `switchTo(2)` → no kill, no launch.
  - `switchStopsCurrentThenStartsTarget`: running `[ps_phone_01]`, `switchTo(2)` → kill on `emulator-5554` recorded before launch of `ps_phone_02`.
  - `switchRefusesWhenSSDMissing`: no shell calls recorded.
  - `statusFlagsBuildStampMismatch`: stored stamp `36.5.10.0`, current `36.6.0.0` → `overview().buildStampMismatch == true`.
  - `addPhonesNumbersSequentially`: existing ids `[1,2]`, `addPhones(count:2)` → ids `[3,4]`, avd names `ps_phone_03`, `ps_phone_04`.
  - `brokenWhenAvdFolderMissing`.
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5:** Commit `feat(core): phone manager`.

### Task 7: `phones` CLI

**Files:**
- Modify: `Sources/phones/main.swift`

**Interfaces:**
- Consumes: `PhoneManager`, `Overview`.
- Commands (manual arg parsing, no dependency): `phones list` (table: `#  label  status`, then storage line "Phones use up to X GB · SSD free Y GB" and warnings), `phones setup-base`, `phones add [count=1]`, `phones switch <n>`, `phones stop`, `phones label <n> <text…>`, `phones reset <n>`, `phones delete <n>` (asks `y/N` unless `--yes`), `phones front <n>`. Errors print `localizedDescription` to stderr, exit 1. Unknown command → usage, exit 2.
- [ ] **Step 1:** Implement.
- [ ] **Step 2: Verify:** `swift run phones list` with SSD mounted → prints header and storage line, exit 0. `swift run phones bogus` → usage, exit 2.
- [ ] **Step 3: Manual end-to-end** (real emulator): `phones setup-base`, `phones add 2`, `phones switch 1` (cold first boot), sign in nothing, `phones switch 2`, `phones switch 1` — time the last one; expected ≤ 10 s to Ready. `phones list` shows 1 running, 2 saved. Record times in `spike/RESULTS.md`.
- [ ] **Step 4:** Commit `feat(cli): phones command`.

### Task 8: Mac app

**Files:**
- Create: `Sources/PhoneSwitcherApp/PhoneSwitcherApp.swift`, `Sources/PhoneSwitcherApp/AppModel.swift`, `Sources/PhoneSwitcherApp/PhoneListView.swift`, `Sources/PhoneSwitcherApp/PhoneEditSheet.swift`, `scripts/make-app.sh`, `Resources/Info.plist`

**Interfaces:**
- Consumes: `PhoneManager`, `Overview`, `PhoneRow`, `PhoneError`.
- Produces: `@MainActor @Observable final class AppModel { var overview: Overview; var busyMessage: String?; var errorMessage: String?; func refresh(); func switchTo(_ id: Int); func add(count: Int); func relabel(_ id: Int, label: String, notes: String); func reset(_ id: Int); func delete(_ id: Int); func setupBase(); func bringToFront(_ id: Int) }` — manager calls run off the main actor (`Task.detached`), progress updates `busyMessage`; refresh every 3 s while the window is visible.
- UI (one regular window, min 560×480, title "Phone Switcher"):
  - Banner at top when: SSD missing (red, the `ssdMissing` text, all actions disabled); no base (button "Set up base phone"); foreign emulator running ("Close <name> to switch phones"); build stamp mismatch ("The emulator was updated since these phones were made. Each phone will do one slow start (about a minute); logins are kept."); storage over warning.
  - Table: `#`, Label (+ notes secondary), Status (Running ● / Saved / Not started yet / Broken), actions: **Switch** (primary; "Show" when running → `bringToFront`), menu: Rename…, Reset…, Delete… (Reset/Delete use confirmation dialogs naming the phone; Reset copy: "This erases Phone NN back to a fresh phone. Its Google sign-in and app data will be lost.").
  - Footer: "Add phone" (stepper count 1–15), storage "Phones use up to X GB · SSD free Y GB", busy spinner + `busyMessage`.
  - Switch is disabled while busy (no overlapping operations).
- `scripts/make-app.sh`: `swift build -c release --product PhoneSwitcherApp`, assemble `build/Phone Switcher.app/Contents/{MacOS/PhoneSwitcherApp,Info.plist}` (bundle id `local.phoneswitcher`, `LSMinimumSystemVersion` 15.0), no signing (ad-hoc `codesign -s -` only).
- [ ] **Step 1:** Implement `AppModel` + views.
- [ ] **Step 2: Verify build:** `./scripts/make-app.sh` → exits 0, `build/Phone Switcher.app` exists; `open "build/Phone Switcher.app"` shows the window listing phones from Task 7.
- [ ] **Step 3: Manual checks:** Switch between two phones from the app (≤ 10 s, spinner shows "Saving…/Starting…"); start `medium_phone` from Android Studio → banner appears and Switch refuses with its name; rename a phone → label persists after app restart; with SSD unmounted (simulate by pointing `Config.ssdMount` at a missing path via env `PHONES_SSD_MOUNT`) → red banner, actions disabled.
- [ ] **Step 4:** Commit `feat(app): Phone Switcher window app`.

### Task 9: README and final verification

**Files:**
- Create: `README.md`

- [ ] **Step 1:** README: what it is, `./scripts/make-app.sh`, first-run flow (Set up base → Add phones → Switch to each and sign in with its Google account, then install your app), CLI commands, warnings (don't update emulator casually; phones live on the SSD; don't boot `zz_phoneswitcher_base` from Android Studio).
- [ ] **Step 2:** `swift test` → all pass. `du`/`df` check: internal disk free space unchanged (±200 MB) across a create/switch cycle.
- [ ] **Step 3:** Commit `docs: README`.
