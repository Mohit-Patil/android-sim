#!/bin/zsh
# Throwaway spike (Task 1). Commands as run on 2026-10-20; kept as a record.
set -e
export PATH=$HOME/Library/Android/sdk/platform-tools:$HOME/Library/Android/sdk/emulator:$HOME/Library/Android/sdk/cmdline-tools/latest/bin:$PATH
A=$HOME/.android/avd
B=zz_phoneswitcher_base

echo no | avdmanager create avd -n $B -k "system-images;android-36;google_apis_playstore;arm64-v8a" -d medium_phone
sed -i '' -e 's/^PlayStore.enabled=.*/PlayStore.enabled=yes/' -e 's/^hw.gpu.enabled=.*/hw.gpu.enabled=yes/' \
  -e 's/^hw.gpu.mode=.*/hw.gpu.mode=host/' -e 's/^hw.ramSize=.*/hw.ramSize=2048/' -e 's/^hw.keyboard=no/hw.keyboard=yes/' $A/$B.avd/config.ini

# Offline first boot: unresolvable DNS keeps Play services from checking in.
emulator -avd $B -no-snapshot -no-boot-anim -dns-server 127.0.0.1 &
adb wait-for-device
until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = 1 ]; do sleep 2; done
sleep 120
adb emu kill
rm -rf $A/$B.avd/snapshots

for n in 98 99; do
  t=ps_phone_$n
  cp -cR $A/$B.avd $A/$t.avd && rm -f $A/$t.avd/*.lock
  sed "s/$B/$t/g" $A/$B.ini > $A/$t.ini
  for f in config.ini hardware-qemu.ini; do sed -i '' "s/$B/$t/g" $A/$t.avd/$f; done
  printf "AvdId=$t\navd.ini.displayname=Phone $n\n" >> $A/$t.avd/config.ini
done
# Then: boot each online, grep logcat for "Checkin Succeeded" and "empty token";
# time `adb emu kill` and Quick Boot resume.
