# Spike results — clone identity and timing (2026-10-20)

Emulator 36.5.10.0, image android-36 google_apis_playstore arm64-v8a, Apple Silicon Mac, 16 GB RAM, AVDs on external SSD.

## Verdict: PASS

## Offline base
- `-dns-server 127.0.0.1` alone keeps the base offline: `ping google.com` → unknown host during the whole first boot.
- `cmd connectivity airplane-mode enable` right after `adb wait-for-device` fails ("Can't find service: connectivity"); not needed. Airplane mode must NOT be left on in the base (clones would inherit it).
- Base first cold boot: `sys.boot_completed` after ~26 s; base folder 1.0 GB after first boot.

## Identity
- Both clones log `Finsky: Unable to fetch checkin consistency token: empty token` at first boot → the base never registered with Google; each clone registers fresh.
- Both clones: `Checkin Succeeded: https://android.googleapis.com/checkin` on their own first online boot (99 needed one retry after a transient SSL error).
- GSF ID cannot be read directly on this user build (`content query … gservices` → SecurityException; no root). Distinct Google registrations are inferred from the fresh check-ins above.
- **Finding:** `settings get secure android_id` is identical on both clones (`bd0849194a65c0f8`); the SSAID seed is created on the base's first boot. Apps reading `Settings.Secure.ANDROID_ID` will see the same value on every phone. `ro.serialno` is also identical (`EMULATOR36X5X10X0`, same on any emulator). Spec non-goal ("unique hardware identities not needed") covers this; reported to the user.

## Save and stop
- `adb -s <serial> emu kill` saves the Quick Boot snapshot (`snapshots/default_boot`, 2.0 GB for 2048 MB RAM) and exits.
- Stop time: 9 s for the first save, ~2 s for later saves.

## Resume
- Quick Boot resume to `sys.boot_completed=1`: 5.3 s, 5.1 s, 5.0 s.
- Clone first boot (cold, from booted base): 12 s.

## Storage
- `cp -cR` clone: ~0 bytes at creation.
- After first boot + snapshot: `du` 3.5 GB per clone (upper bound); real SSD free-space drop for two phones = 5.4 GB → ~2.7 GB per phone. 15 phones ≈ 40 GB + 1 GB base.
