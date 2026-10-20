# Phone Switcher — Design

Date: 2026-10-20
Status: approved by user 2026-10-20

## Intent

The user is building an Android app and wants to see it through the eyes of
10–15 different users. Each "user" is a separate Android phone (emulator) signed
in with its own Google account, with the user's app installed. Only one phone
runs at a time; the user wants to jump between them in a few seconds from a
native Mac app, without filling the disk.

The pain that started this: separate emulators each cost 3–6 GB, so 15 of them
would need ~60–85 GB, and the Mac's internal disk is small.

This is not load testing. The server never needs 15 users active at once.

## Goals

- Manage 10–15 phones (no hard cap) that all share one device setup.
- Switch from the running phone to another in roughly 2–6 seconds (resume from
  saved state, not a cold boot).
- Keep total storage for 15 signed-in phones around 25–45 GB, on the external
  SSD only.
- A full native macOS app (a regular window, not a menu-bar app) to see,
  switch, add, label, reset and delete phones, and to see storage use.
- A command-line tool with the same core actions (e.g. `phones switch 3`),
  which the app is built on.

## Non-goals

- Running several phones at the same time.
- Load or stress testing the user's server.
- Different device models, screen sizes or Android versions per phone.
- Unique hardware identities (serial, IMEI). Phones only need different Google
  accounts.
- Remote VM / cloud hosting. Possible later upgrade, out of scope now.
- Automating Google sign-in or app install. The user does those by hand, once
  per phone.

## Anti-goals (would make this a failure even if it works)

- Writing emulator data to the Mac's internal disk.
- Creating emulators anywhere other than `~/.android/avd`, or replacing the
  `~/.android/avd` symlink with a real folder.
- Silently recreating phones when the SSD is unplugged.
- Phones that look like the same app install to the user's server (shared
  Firebase installation ID / FCM token) because the app was cloned in.
- One shared file whose loss or invalidation wipes every phone at once.

## Environment (verified)

- Apple Silicon Mac, 16 GB RAM.
- Android SDK at `~/Library/Android/sdk`; emulator 36.5.10.0.
- System image already installed: `system-images/android-36/google_apis_playstore/arm64-v8a/`
  (Android 16, Google Play, 2.3 GB, shared by all AVDs).
- `~/.android/avd` → an external SSD (APFS).
- Existing AVDs (for example `medium_phone`)
  are the user's own and must not be modified.
- Tool data folder (created): a folder on the SSD.
- Project code: a new folder (not a git repo yet).

## How it works (decided)

### Base phone
- The tool creates one base AVD from the existing Google Play Android 16 arm64
  image, `medium_phone` device profile, same as the user's current phones.
- It boots the base once (cold), lets first boot finish, then shuts it down.
- The base is made before any Google sign-in and before the user's app is
  installed, so clones do not share app install IDs.

### Phones are APFS clones
- Each phone is an AVD in `~/.android/avd`, made by cloning the base AVD
  folder with APFS copy-on-write (`cp -c` / `clonefile`), so unchanged data is
  shared on disk.
- After cloning, paths and names inside `<name>.ini`, `config.ini` and
  `hardware-qemu.ini` are rewritten to the new phone.
- Every phone is independent: one can be reset, rebuilt or deleted without
  touching the others.

### Switching
- One phone runs at a time.
- Switch = save the running phone's state and stop it, then start the chosen
  phone from its own Quick Boot snapshot.
- Each phone keeps its own saved state (RAM snapshot ≈ guest RAM size, so
  guest RAM is a lever on disk use).
- Target: ~2–6 s to a usable phone, measured on this Mac.

### Labels
- Each phone has a number, a user-editable label (typically the Google
  account, e.g. `xyz@gmail.com`) and optional notes. Stored by the tool in the
  SSD data folder.

### Safety
- If the SSD is not mounted, the app and CLI say so plainly and refuse
  to create, start or change anything.
- The tool warns that an emulator or system-image update invalidates every
  phone's saved state (logins and data survive; each phone then cold boots
  once). It records the emulator version the phones were made with and flags a
  mismatch. The user decides when to update.
- Storage view shows real on-disk usage (accounting for shared clone blocks
  where possible) and free SSD space.
- Never touches AVDs it did not create.

## The app (decided)

- Native macOS app, regular window (not menu bar).
- Shows the list of phones: number, label, status (running / saved / never
  started / broken), and a Switch action.
- Actions: add phone(s), rename/label, reset phone (back to fresh base),
  delete phone, open the running phone's window.
- Shows storage used by phones and SSD free space; SSD-missing warning.
- A CLI with the same core actions underneath; the app uses the same core.

## Calls made by Claude (not yet confirmed by the user)

- **Base first boot is offline.** The base phone completes first boot with
  networking disabled, so Google Play services never registers (checks in) the
  base with Google. Each clone registers itself on its first online boot and
  gets its own Google device registration and FCM token. The builder must
  verify this early (two clones, check that their GSF/checkin IDs and FCM
  tokens differ) before building the app on top of cloning. If it fails, stop
  and report rather than work around it silently.
- **Other emulators running.** Before starting a phone, the tool checks for
  any running emulator (via adb). If one of its own phones is running, even
  one Android Studio launched, that counts as "running" and switching saves and
  stops it. If an emulator it does not own is running, it refuses to switch and
  says which one, rather than stopping it or running two at once (16 GB RAM).
- **Base AVD is hidden in plain sight.** Named so it is clearly not for use
  (e.g. `zz_phoneswitcher_base`); the app never boots it after creation except
  to rebuild it.
- **Speed over space.** If the switch-time and storage targets conflict, fast
  switching wins; the app shows a warning when phones exceed ~45 GB total
  rather than failing.
- **Personal tool for this Mac.** Unsigned, non-sandboxed app built and run
  locally. Paths (SDK, AVD folder, SSD data folder) live in one config place
  with this Mac's values as defaults; no SDK discovery, signing or
  notarization.

## Left to the builder

- Language/stack details: Swift + SwiftUI for the app is the default call
  (native Mac app); the CLI may be Swift too and share a core package.
- Exact guest RAM size (1.5–2 GB) based on measured switch time and stability.
- How "save and stop" is done (`adb emu kill` with snapshot save,
  `adb emu avd snapshot save`, etc.), chosen by measurement.
- Where the phone list/labels are stored (a JSON file in the SSD data folder
  is the default call).
- How storage is measured.
- Whether to init a git repo for the project (ask the user).
