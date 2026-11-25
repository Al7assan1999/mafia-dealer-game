# QA on the emulator: source this, then tapl "label" [nth], labels, shot name, step (one offline-game step, English). See docs/handoff-2026-11-25.md.
A=/c/Users/WGN/sdk/android/platform-tools/adb
D=${D:-/c/Users/WGN/source/repos/mafia-dealer-game/docs/qa/journey}  # screenshots; set D before sourcing to change
mkdir -p $D
dump() { MSYS_NO_PATHCONV=1 $A shell uiautomator dump /sdcard/u.xml >/dev/null 2>&1; MSYS_NO_PATHCONV=1 $A shell cat /sdcard/u.xml; }
labels() { dump | grep -oE '(content-desc|text)="[^"]+"[^>]*bounds="[^"]+"' | sed -E 's/" .*bounds=/ @ /'; }
tapl() { # tapl "label prefix" [nth]
  local b; b=$(dump | grep -oE "(content-desc|text)=\"$1[^\"]*\"[^>]*bounds=\"\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]\"" | sed -n "${2:-1}p" | grep -oE '\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]')
  [ -z "$b" ] && { echo "NOT FOUND: $1"; return 1; }
  local n; n=($(echo $b | grep -oE '[0-9]+')); $A shell input tap $(( (n[0]+n[2])/2 )) $(( (n[1]+n[3])/2 ))
}
shot() { sleep ${2:-1.2}; $A exec-out screencap -p > $D/$1.png; }
tapb() { local n=($(echo "$1" | grep -oE '[0-9]+')); $A shell input tap $(( (n[0]+n[2])/2 )) $(( (n[1]+n[3])/2 )); }
# one generic step through an offline game: returns 1 when it doesn't know the screen
step() { local L b; L=$(labels); echo "$L" | head -1 | cut -c1-70
 if echo "$L" | grep -q '"I am'; then tapl "I am"
 elif echo "$L" | grep -q '"Done — hide'; then tapl "Done — hide"
 elif echo "$L" | grep -q 'Confirm @'; then b=$(echo "$L" | grep -E '^content-desc="[0-9]+&#10;' | grep -v 'you' | grep -v -i 'dead\|out' | head -1 | grep -oE '\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]'); tapb "$b"; sleep 0.6; tapl "Confirm"
 else echo "$L" | head -14; return 1; fi; sleep 1.3; }
