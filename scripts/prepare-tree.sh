#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="https://raw.githubusercontent.com/AlexFurina/twrp_device_samsung_b2q/android-12.1"

fetch_locked() {
  local rel="$1"
  local expected_blob="$2"
  local dest="$ROOT/$rel"
  local tmp="${dest}.tmp"

  mkdir -p "$(dirname "$dest")"

  if [[ -f "$dest" ]]; then
    local current
    current="$(git hash-object "$dest")"
    if [[ "$current" == "$expected_blob" ]]; then
      echo "[b2q] OK $rel ($current)"
      return 0
    fi
    echo "[b2q] replacing stale $rel ($current != $expected_blob)"
  else
    echo "[b2q] fetching $rel"
  fi

  curl -fL --retry 3 --retry-delay 2 "$BASE/$rel" -o "$tmp"

  local got
  got="$(git hash-object "$tmp")"
  if [[ "$got" != "$expected_blob" ]]; then
    echo "ERROR: $rel blob mismatch: got $got expected $expected_blob" >&2
    rm -f "$tmp"
    exit 1
  fi

  mv "$tmp" "$dest"
  echo "[b2q] verified $rel ($got)"
}

# Kernel / DT artifacts from the known-good upstream b2q recovery tree.
fetch_locked prebuilt/dtb 18d1fbd8ed9443abd883b7b5d132a3c248918f0c
fetch_locked prebuilt/recoverydtbo 57049e2905cb4e2a5dd94f412ed51121c4b39bdc
fetch_locked prebuilt/zImage bc970471fc662e5745a301005d65aeb79c78f0cf

# Recovery support files that were present in the upstream tree. These stay
# fetched/locked instead of being hand-copied so their contents remain exact.
fetch_locked recovery/root/system/etc/task_profiles.json ac6a84a81028573d17dc8de007919e5646e308e7
fetch_locked recovery/root/system/etc/vintf/manifest.xml 340549343f3cb09204734789083e81c44c3c8a45
fetch_locked recovery/root/vendor/etc/task_profiles.json 5989bf53a3d766bdcbd8aea62a45f101d6aca6a4
fetch_locked recovery/root/vendor/etc/vintf/manifest.xml 617c89fc8a7cd8aa292c77a0d0ea09ca1e29324a

# test6d diagnostic instrumentation. The test6c device run proved that the
# ActionThread reaches TWPartitionManager::Decrypt_Data(), but the call does
# not return. Print visible GUI checkpoints around every potentially blocking
# stage without changing the decrypt algorithm itself.
RECOVERY="$(cd "$ROOT/../../.." && pwd)/bootable/recovery"
PM="$RECOVERY/partitionmanager.cpp"
if [[ -f "$PM" ]]; then
  python3 - "$PM" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
text = p.read_text()

def once(old, new, label):
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly 1 anchor, got {count}")
    text = text.replace(old, new, 1)

once(
    '\t\tTWPartition* Key_Directory_Partition = Find_Partition_By_Path(Decrypt_Data->Key_Directory);',
    '\t\tgui_msg("b2q_decrypt_enter=[b2q] DECRYPT_DATA ENTER");\n'
    '\t\tgui_msg("b2q_keydir_start=[b2q] KEYDIR MOUNT START");\n'
    '\t\tTWPartition* Key_Directory_Partition = Find_Partition_By_Path(Decrypt_Data->Key_Directory);',
    'Decrypt_Data entry')

once(
    '\t\tif (!Decrypt_Data->Key_Directory.empty()) {',
    '\t\tgui_msg("b2q_keydir_return=[b2q] KEYDIR MOUNT RETURN");\n'
    '\t\tif (!Decrypt_Data->Key_Directory.empty()) {',
    'key directory return')

once(
    '\t\t\tSet_Crypto_Type("file");',
    '\t\t\tgui_msg("b2q_crypto_type_start=[b2q] CRYPTO TYPE START");\n'
    '\t\t\tSet_Crypto_Type("file");\n'
    '\t\t\tgui_msg("b2q_crypto_type_return=[b2q] CRYPTO TYPE RETURN");',
    'Set_Crypto_Type')

meta_call = ('\t\t\tif (android::vold::fscrypt_mount_metadata_encrypted('
             'Decrypt_Data->Actual_Block_Device, Decrypt_Data->Mount_Point, false, false, '
             'Decrypt_Data->Current_File_System, TWFunc::Path_Exists(additional_fstab) ? additional_fstab : "")) {')
once(
    meta_call,
    '\t\t\tgui_msg("b2q_metadata_start=[b2q] METADATA START");\n' +
    meta_call + '\n'
    '\t\t\t\tgui_msg("b2q_metadata_ok=[b2q] METADATA OK");',
    'metadata decrypt call')

once(
    '\t\t\t\tint retry_count = 10;',
    '\t\t\t\tgui_msg("b2q_data_mount_start=[b2q] DATA MOUNT START");\n'
    '\t\t\t\tint retry_count = 10;',
    'data mount start')

once(
    '\t\t\t\tif (Decrypt_Data->Mount(false)) {\n\t\t\t\t\tif (!Decrypt_Data->Decrypt_FBE_DE()) {',
    '\t\t\t\tif (Decrypt_Data->Mount(false)) {\n'
    '\t\t\t\t\tgui_msg("b2q_data_mount_ok=[b2q] DATA MOUNT OK");\n'
    '\t\t\t\t\tgui_msg("b2q_fbe_de_start=[b2q] FBE DE START");\n'
    '\t\t\t\t\tif (!Decrypt_Data->Decrypt_FBE_DE()) {',
    'FBE DE start')

p.write_text(text)
PY

  grep -Fq 'b2q_decrypt_enter=[b2q] DECRYPT_DATA ENTER' "$PM"
  grep -Fq 'b2q_keydir_start=[b2q] KEYDIR MOUNT START' "$PM"
  grep -Fq 'b2q_keydir_return=[b2q] KEYDIR MOUNT RETURN' "$PM"
  grep -Fq 'b2q_crypto_type_start=[b2q] CRYPTO TYPE START' "$PM"
  grep -Fq 'b2q_crypto_type_return=[b2q] CRYPTO TYPE RETURN' "$PM"
  grep -Fq 'b2q_metadata_start=[b2q] METADATA START' "$PM"
  grep -Fq 'b2q_metadata_ok=[b2q] METADATA OK' "$PM"
  grep -Fq 'b2q_data_mount_start=[b2q] DATA MOUNT START' "$PM"
  grep -Fq 'b2q_data_mount_ok=[b2q] DATA MOUNT OK' "$PM"
  grep -Fq 'b2q_fbe_de_start=[b2q] FBE DE START' "$PM"
  echo "[b2q] test6d decrypt-stage instrumentation applied"
fi

echo "[b2q] tree preparation complete"
