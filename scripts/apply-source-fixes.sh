#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TWRP_ROOT="${1:-$(cd "$ROOT/../../.." && pwd)}"

# Newer twrp-12.1 minuitwrp uses Qualcomm atomic DRM setup that can leave some
# devices permanently on the TeamWin splash (atomic commit ret=-22).  Pin the
# known-working pre-atomic graphics_drm.cpp used by the public workaround for
# minimal-manifest-twrp issue #67 instead of following a moving branch.
DRM_COMMIT="0c2e119204d0eebe5e0c7fdc0395a3ce919dace8"
DRM_BLOB="e90e2a40323023e023f435215cc8eaa3d0a62116"
DRM_URL="https://raw.githubusercontent.com/cooked71/device_REALME_RMX3760_twrp/${DRM_COMMIT}/issue_atomic/graphics_drm.cpp"
DRM_TARGET="$TWRP_ROOT/bootable/recovery/minuitwrp/graphics_drm.cpp"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

curl -fL --retry 3 "$DRM_URL" -o "$tmp"
got="$(git hash-object "$tmp")"
if [[ "$got" != "$DRM_BLOB" ]]; then
    echo "ERROR: pinned graphics_drm.cpp blob mismatch: $got != $DRM_BLOB" >&2
    exit 1
fi

[[ -f "$DRM_TARGET" ]] || {
    echo "ERROR: TWRP graphics target not found: $DRM_TARGET" >&2
    exit 1
}

install -m 0644 "$tmp" "$DRM_TARGET"
final="$(git hash-object "$DRM_TARGET")"
[[ "$final" == "$DRM_BLOB" ]] || {
    echo "ERROR: installed graphics_drm.cpp blob mismatch: $final != $DRM_BLOB" >&2
    exit 1
}

echo "[b2q] applied pinned non-atomic DRM fix: $DRM_BLOB"
