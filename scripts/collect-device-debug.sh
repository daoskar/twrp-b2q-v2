#!/usr/bin/env bash
set -euo pipefail

ADB="${ADB:-adb}"
OUT="${1:-b2q-twrp-debug-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"

run() {
  local name="$1"; shift
  echo "[b2q] collecting $name"
  "$ADB" shell "$@" >"$OUT/$name.txt" 2>&1 || true
}

"$ADB" wait-for-device

run properties 'getprop'
run decrypt_props 'getprop | grep -E "^(\[b2q\.decrypt|\[crypto\.|\[keymaster_ver|\[ro\.crypto|\[vendor\.sys\.listeners|\[sys\.listeners)"'
run mounts 'cat /proc/mounts'
run block_devices 'ls -l /dev/block /dev/block/by-name 2>/dev/null; echo; cat /proc/partitions'
run data_probe 'ls -ld /data /data/media /metadata 2>/dev/null; echo; mount | grep -E " /data | /metadata | /vendor "'
run crypto_binaries 'for f in /vendor/bin/qseecomd /vendor/bin/hw/android.hardware.keymaster@4.0-service /vendor/bin/hw/android.hardware.keymaster@4.0-service-qti /vendor/bin/hw/android.hardware.gatekeeper@1.0-service /vendor/bin/hw/android.hardware.gatekeeper@1.0-service-qti; do if [ -e "$f" ]; then ls -lZ "$f" 2>/dev/null || ls -l "$f"; else echo "MISSING $f"; fi; done'
run crypto_processes 'ps -A 2>/dev/null | grep -Ei "qsee|keymaster|gatekeeper|keystore|prepdecrypt"'
run usb_otg 'ls -l /sys/block 2>/dev/null; echo; for x in /sys/block/sd*; do [ -e "$x" ] || continue; echo "$x removable=$(cat "$x/removable" 2>/dev/null)"; done; echo; ls -l /dev/block/twrp-usb* /dev/block/sd* 2>/dev/null'
run dmesg 'dmesg'

"$ADB" pull /tmp/recovery.log "$OUT/recovery.log" >/dev/null 2>&1 || \
"$ADB" pull /cache/recovery/log "$OUT/recovery.log" >/dev/null 2>&1 || true

if command -v tar >/dev/null 2>&1; then
  tar -czf "$OUT.tar.gz" "$OUT"
  echo "[b2q] saved $OUT.tar.gz"
else
  echo "[b2q] saved $OUT/"
fi
