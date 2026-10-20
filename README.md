# Phone Switcher

A Mac app for keeping many Android emulator "phones", each signed in with a
different Google account, and switching between them in seconds. One phone
runs at a time.

It is made for seeing your own app through the eyes of different users: phone
1 is signed in as one account, phone 2 as another, and so on. Click a phone and
the running one is saved and the one you picked resumes where you left it.

Every phone is an APFS copy-on-write clone of one base phone, so the shared
parts are stored once.

## Requirements

- An Apple Silicon Mac with macOS 15 or later.
- Xcode 16 or later (Swift 6).
- The Android SDK with the emulator, platform-tools and command-line tools
  (Android Studio installs these at `~/Library/Android/sdk`).
- The system image `system-images;android-36;google_apis_playstore;arm64-v8a`:

  ```bash
  sdkmanager "system-images;android-36;google_apis_playstore;arm64-v8a"
  ```

- An APFS volume for the emulators (the internal disk or an external drive).
  Plan for about 3 GB per phone.

## Build

```bash
./scripts/make-app.sh
open "build/Phone Switcher.app"
```

The command-line tool:

```bash
swift build -c release --product phones
.build/release/phones list
```

Run the tests with `swift test`.

## First run

1. **Set up base phone.** It boots once with the internet blocked (about 3
   minutes), so Google never registers it. Every copy then registers with
   Google as its own device.
2. **Add phones**, as many as you need.
3. Click a phone to switch to it. The first start of each phone is a cold boot
   (15–25 seconds). Sign in with that phone's Google account, install your
   app, and rename the phone (right-click → Rename…) to the account.
4. From then on, clicking a phone saves the running one and resumes the one you
   picked (about 12 seconds on an M-series Mac).

## Commands

| Command | What it does |
|---|---|
| `phones list` | Phones, status, storage |
| `phones setup-base` | Create the base phone (once) |
| `phones add [count]` | Add phones copied from the base |
| `phones switch <n>` | Save the running phone, start phone n |
| `phones stop` | Save and stop the running phone |
| `phones label <n> <text>` | Label phone n (e.g. its Google account) |
| `phones reset <n>` | Erase phone n back to a fresh phone |
| `phones delete <n> [--yes]` | Delete phone n |
| `phones front <n>` | Bring phone n's window to the front |

## Configuration

Everything works without a config file. To change the defaults, create
`~/Library/Application Support/PhoneSwitcher/config.json`. Every key is
optional:

```json
{
  "sdkRoot": "~/Library/Android/sdk",
  "avdDir": "~/.android/avd",
  "dataDir": "/Volumes/MyDrive/PhoneSwitcher",
  "requiredVolume": "/Volumes/MyDrive",
  "ramMB": 2048,
  "storageWarningGB": 45
}
```

- `sdkRoot`: the Android SDK. `ANDROID_HOME` or `ANDROID_SDK_ROOT` wins over it.
- `avdDir`: where emulators live. `ANDROID_AVD_HOME` wins over it.
- `dataDir`: where the phone list is kept. Defaults to
  `<requiredVolume>/PhoneSwitcher`, or `~/Library/Application Support/PhoneSwitcher`.
- `requiredVolume`: if your emulators live on an external drive (for example
  with `~/.android/avd` symlinked to it), set this to the drive's mount point.
  When the drive is not connected, or `avdDir` does not resolve onto it, the
  app and CLI refuse to change anything instead of creating phones on the
  internal disk.
- `ramMB`: guest RAM for new phones. The saved state of each phone is about
  this size.
- `storageWarningGB`: show a warning when phones use more than this.

If the file is not valid JSON, nothing runs until it is fixed.

## How it works

- The base phone (`zz_phoneswitcher_base`) is a normal AVD made with
  `avdmanager`. Its first boot runs with DNS blocked and no snapshot, so Google
  Play services never checks it in.
- A phone (`ps_phone_NN`) is a `clonefile` copy of the base folder, with the
  name rewritten in its `.ini` files. Phones are independent; resetting or
  deleting one doesn't touch the others.
- Switching runs `adb emu kill`, which saves a Quick Boot snapshot, then starts
  the chosen phone, which resumes from its own snapshot.
- The phone list (labels, notes) is `phones.json` in the data folder.

## Safety

- The tool only touches AVDs named `ps_phone_NN` and `zz_phoneswitcher_base`.
  Your other emulators are never started, stopped or changed.
- If another emulator is running, switching is refused, and the app says
  which one. Close it yourself first.
- Phones also appear in Android Studio's Device Manager. Starting a phone from
  there is fine. Don't start the base phone: it is the template new phones are
  copied from.

## Limitations

- **Same device ID on every phone.** `Settings.Secure.ANDROID_ID` and the
  serial number are identical across phones. Google accounts, Google device
  registrations and your app's own install IDs (for example Firebase) are
  separate on each phone.
- **Emulator and system-image updates.** An update throws away every phone's
  saved state. Logins and data are kept, but each phone then does one cold
  start. The app warns you when the versions no longer match.
- **Switch time.** About 12 seconds, mostly saving the running phone's memory.
- **Storage figures are an upper bound.** Clones share blocks, which the
  figure does not subtract.
- These are emulators, and apps and Google services can tell. This is a tool
  for looking at your own app, not for passing as real devices.

## License

MIT. See [LICENSE](LICENSE).
