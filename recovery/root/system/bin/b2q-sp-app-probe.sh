#!/system/bin/sh
set +e
log() { echo "[b2q-sp-app] $*"; }

FW=""
for p in /sys/devices/platform/soc/soc:qcom,spss_utils/firmware_name /sys/devices/platform/soc@0/soc:qcom,spss_utils/firmware_name /sys/devices/soc/soc:qcom,spss_utils/firmware_name; do
    if [ -r "$p" ]; then
        FW="$(cat "$p" 2>/dev/null | tr -d '\r\n')"
        [ -n "$FW" ] && break
    fi
done
[ -n "$FW" ] || { log "missing firmware_name"; exit 41; }

VER="$(echo "$FW" | sed -n 's/^spss\([12]\)[dtp]$/\1/p')"
TYPE="$(echo "$FW" | sed -n 's/^spss[12]\([dtp]\)$/\1/p')"
[ -n "$VER" ] && [ -n "$TYPE" ] || { log "unsupported firmware_name=$FW"; exit 42; }

KEYM="keym$VER$TYPE.sig"
CRYPT="crypt$VER$TYPE.sig"
ASYM="asym$VER$TYPE.sig"
log "firmware_name=$FW"
log "expected_keymaster=$KEYM"
log "expected_crypto=$CRYPT"
log "expected_asym=$ASYM"

SCAN=/tmp/b2q-spu-fw-scan
mkdir -p "$SCAN"

mount_vfat_ro() {
    src="$1"; dst="$2"
    mkdir -p "$dst"
    grep -q " $dst " /proc/mounts 2>/dev/null && return 0
    mount -t vfat -o ro,shortname=lower,uid=0,gid=1000,dmask=227,fmask=337 "$src" "$dst"
}
mount_ext4_ro() {
    src="$1"; dst="$2"
    mkdir -p "$dst"
    grep -q " $dst " /proc/mounts 2>/dev/null && return 0
    mount -t ext4 -o ro,noatime,nosuid,nodev "$src" "$dst"
}

for n in apnhlos firmware modem; do
    p="/dev/block/bootdevice/by-name/$n"
    [ -e "$p" ] || continue
    mount_vfat_ro "$p" "$SCAN/$n" >/dev/null 2>&1 || true
done
if [ -e /dev/block/bootdevice/by-name/spu ]; then
    mount_ext4_ro /dev/block/bootdevice/by-name/spu "$SCAN/spu" >/dev/null 2>&1 || true
fi

find_one() {
    name="$1"
    for d in /vendor/firmware_mnt/image /vendor/firmware_mnt /vendor/firmware-modem/image /vendor/firmware-modem /spu "$SCAN/apnhlos" "$SCAN/firmware" "$SCAN/modem" "$SCAN/spu"; do
        [ -d "$d" ] || continue
        f="$(find "$d" -type f -name "$name" 2>/dev/null | head -n 1)"
        if [ -n "$f" ]; then echo "$f"; return 0; fi
    done
    return 1
}

KEYM_SRC="$(find_one "$KEYM")"
CRYPT_SRC="$(find_one "$CRYPT")"
ASYM_SRC="$(find_one "$ASYM")"

[ -n "$KEYM_SRC" ] && log "found_keymaster=$KEYM_SRC" || log "found_keymaster=missing"
[ -n "$CRYPT_SRC" ] && log "found_crypto=$CRYPT_SRC" || log "found_crypto=missing"
[ -n "$ASYM_SRC" ] && log "found_asym=$ASYM_SRC" || log "found_asym=missing"

[ -n "$KEYM_SRC" ] || exit 43
[ -n "$CRYPT_SRC" ] || exit 44

TARGET=/vendor/firmware_mnt/image
# test6ag consumes this exact, firmware-derived path after stock spdaemon
# finishes its SPU-ready sequence. Never guess between keym*.sig variants.
printf '%s\n' "$TARGET/$KEYM" > /tmp/b2q-sp-keymaster-sig

if [ "$KEYM_SRC" = "$TARGET/$KEYM" ] && [ "$CRYPT_SRC" = "$TARGET/$CRYPT" ]; then
    log "SP app signatures already in expected path"
    exit 0
fi

ORIG=/tmp/b2q-fw-original-image
STAGE=/tmp/b2q-fw-merged-image
mkdir -p "$ORIG" "$STAGE"

if [ -d "$TARGET" ] && ! grep -q " $ORIG " /proc/mounts 2>/dev/null; then
    mount -o bind "$TARGET" "$ORIG" >/dev/null 2>&1 || true
fi

rm -rf "$STAGE"/*
for f in "$ORIG"/*; do
    [ -e "$f" ] || continue
    ln -s "$f" "$STAGE/$(basename "$f")" 2>/dev/null || true
done

ln -sf "$KEYM_SRC" "$STAGE/$KEYM"
ln -sf "$CRYPT_SRC" "$STAGE/$CRYPT"
[ -n "$ASYM_SRC" ] && ln -sf "$ASYM_SRC" "$STAGE/$ASYM"

mkdir -p "$TARGET"
umount "$TARGET" >/dev/null 2>&1 || true
mount -o bind "$STAGE" "$TARGET" || { log "merged bind failed"; exit 45; }

log "--- merged SP app view ---"
ls -l "$TARGET/$KEYM" "$TARGET/$CRYPT" "$TARGET/$ASYM" 2>&1 || true
[ -r "$TARGET/$KEYM" ] || exit 46
[ -r "$TARGET/$CRYPT" ] || exit 47
log "SP app signatures ready"
exit 0
