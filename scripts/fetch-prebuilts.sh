#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/prebuilt"
BASE="https://raw.githubusercontent.com/AlexFurina/twrp_device_samsung_b2q/android-12.1/prebuilt"
mkdir -p "$OUT"

fetch_one() {
  local name="$1"
  local expected_blob="$2"
  local dest="$OUT/$name"
  echo "[b2q] downloading $name"
  curl -fL --retry 3 --retry-delay 2 "$BASE/$name" -o "$dest.tmp"
  local got
  got="$(git hash-object "$dest.tmp")"
  if [[ "$got" != "$expected_blob" ]]; then
    echo "ERROR: $name blob mismatch: got $got expected $expected_blob" >&2
    rm -f "$dest.tmp"
    exit 1
  fi
  mv "$dest.tmp" "$dest"
  echo "[b2q] verified $name ($got)"
}

fetch_one dtb 18d1fbd8ed9443abd883b7b5d132a3c248918f0c
fetch_one recoverydtbo 57049e2905cb4e2a5dd94f412ed51121c4b39bdc
fetch_one zImage bc970471fc662e5745a301005d65aeb79c78f0cf

echo "[b2q] prebuilts ready in $OUT"
