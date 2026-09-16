#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() { echo "ERROR: $*" >&2; exit 1; }
check_contains() {
  local file="$1" pattern="$2"
  grep -Fq -- "$pattern" "$file" || fail "$file is missing: $pattern"
}
check_not_contains() {
  local file="$1" pattern="$2"
  if grep -Fq -- "$pattern" "$file"; then
    fail "$file still contains forbidden/stale value: $pattern"
  fi
}
check_blob() {
  local file="$1" expected="$2"
  [[ -f "$file" ]] || fail "missing prepared file: $file (run scripts/prepare-tree.sh)"
  local got
  got="$(git hash-object "$file")"
  [[ "$got" == "$expected" ]] || fail "$file blob mismatch: $got != $expected"
}

for f in \
  BoardConfig.mk device.mk twrp_b2q.mk \
  recovery/root/init.recovery.qcom.rc \
  recovery/root/init.recovery.usb.rc \
  recovery/root/system/etc/recovery.fstab \
  recovery/root/system/etc/twrp.flags \
  recovery/root/system/bin/twrp-otg-watch.sh \
  recovery/root/system/bin/b2q-decrypt-service.sh; do
  [[ -f "$f" ]] || fail "missing required source file: $f"
done

# FBE / metadata decryption wiring.
check_contains BoardConfig.mk 'TW_INCLUDE_CRYPTO := true'
check_contains BoardConfig.mk 'TW_INCLUDE_CRYPTO_FBE := true'
check_contains BoardConfig.mk 'TW_INCLUDE_FBE_METADATA_DECRYPT := true'
check_contains BoardConfig.mk 'BOARD_USES_QCOM_FBE_DECRYPTION := true'
check_contains BoardConfig.mk 'BOARD_USES_METADATA_PARTITION := true'
check_contains BoardConfig.mk 'TW_USE_NEW_MINADBD := true'
check_contains device.mk 'qcom_decrypt'
check_contains device.mk 'qcom_decrypt_fbe'
check_contains recovery/root/init.recovery.qcom.rc 'import /init.recovery.qcom_decrypt.rc'
check_contains recovery/root/system/etc/recovery.fstab 'fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized'
check_contains recovery/root/system/etc/recovery.fstab 'metadata_encryption=aes-256-xts'
check_contains recovery/root/system/etc/recovery.fstab 'keydirectory=/metadata/vold/metadata_encryption'

# b2q stock-vendor crypto services.  The old recovery had no qsee/keymaster/
# gatekeeper binaries in its ramdisk, so the device tree must explicitly launch
# the services that already exist on the mounted F711B vendor partition.
check_contains recovery/root/init.recovery.qcom.rc 'service b2q-qseecomd /system/bin/sh /system/bin/b2q-decrypt-service.sh qseecomd'
check_contains recovery/root/init.recovery.qcom.rc 'service b2q-keymaster /system/bin/sh /system/bin/b2q-decrypt-service.sh keymaster'
check_contains recovery/root/init.recovery.qcom.rc 'service b2q-gatekeeper /system/bin/sh /system/bin/b2q-decrypt-service.sh gatekeeper'
check_contains recovery/root/init.recovery.qcom.rc 'property:keymaster_ver=4.x'
check_contains recovery/root/system/bin/b2q-decrypt-service.sh '/vendor/bin/qseecomd'
check_contains recovery/root/system/bin/b2q-decrypt-service.sh '/vendor/bin/hw/android.hardware.keymaster@4.0-service'
check_contains recovery/root/system/bin/b2q-decrypt-service.sh '/vendor/bin/hw/android.hardware.gatekeeper@1.0-service'
check_contains recovery/root/system/bin/b2q-decrypt-service.sh 'LD_LIBRARY_PATH=/vendor/lib64:/vendor/lib:/system/lib64:/system/lib:/sbin'

# USB OTG must not depend on the old fixed sdf node.
check_not_contains recovery/root/system/etc/twrp.flags '/dev/block/sdf1'
check_contains recovery/root/system/etc/twrp.flags '/dev/block/twrp-usb1'
check_contains recovery/root/system/etc/twrp.flags '/dev/block/twrp-usb'
check_contains recovery/root/init.recovery.qcom.rc 'service twrp-otg-watch /system/bin/sh /system/bin/twrp-otg-watch.sh'
check_contains recovery/root/system/bin/twrp-otg-watch.sh '/sys/block/sd*'
check_contains recovery/root/system/bin/twrp-otg-watch.sh '/removable'

# Ensure we did not regress the sideload path back to the legacy minadbd.
check_contains recovery/root/init.recovery.usb.rc 'sys.usb.config=sideload'

# Locked upstream artifacts/support files prepared by prepare-tree.sh.
check_blob prebuilt/dtb 18d1fbd8ed9443abd883b7b5d132a3c248918f0c
check_blob prebuilt/recoverydtbo 57049e2905cb4e2a5dd94f412ed51121c4b39bdc
check_blob prebuilt/zImage bc970471fc662e5745a301005d65aeb79c78f0cf
check_blob recovery/root/system/etc/task_profiles.json ac6a84a81028573d17dc8de007919e5646e308e7
check_blob recovery/root/system/etc/vintf/manifest.xml 340549343f3cb09204734789083e81c44c3c8a45
check_blob recovery/root/vendor/etc/task_profiles.json 5989bf53a3d766bdcbd8aea62a45f101d6aca6a4
check_blob recovery/root/vendor/etc/vintf/manifest.xml 617c89fc8a7cd8aa292c77a0d0ea09ca1e29324a

# Syntax/data sanity.
bash -n scripts/prepare-tree.sh scripts/fetch-prebuilts.sh scripts/validate-tree.sh
sh -n recovery/root/system/bin/twrp-otg-watch.sh
sh -n recovery/root/system/bin/b2q-decrypt-service.sh
python3 - <<'PY'
import json
import xml.etree.ElementTree as ET
from pathlib import Path

for p in [
    Path('recovery/root/system/etc/task_profiles.json'),
    Path('recovery/root/vendor/etc/task_profiles.json'),
]:
    with p.open('r', encoding='utf-8') as f:
        json.load(f)

for p in [
    Path('recovery/root/system/etc/vintf/manifest.xml'),
    Path('recovery/root/vendor/etc/vintf/manifest.xml'),
]:
    ET.parse(p)
PY

echo '[b2q] validation passed'
