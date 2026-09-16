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

echo "[b2q] tree preparation complete"
