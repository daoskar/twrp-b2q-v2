#!/system/bin/sh

MNT=/vendor/firmware_mnt
MODEM_MNT=/vendor/firmware-modem
ALT=/tmp/b2q-firmware-alt
RAW=/tmp/b2q-firmware-raw

log() {
    echo "[b2q-fw] $*"
}

is_mounted() {
    grep -q " $1 " /proc/mounts 2>/dev/null
}

mount_vfat() {
    src="$1"
    dst="$2"
    mkdir -p "$dst"
    mount -t vfat -o ro,shortname=lower,uid=0,gid=1000,dmask=227,fmask=337 "$src" "$dst"
}

has_mdt() {
    dir="$1"
    [ -d "$dir" ] || return 1
    for f in "$dir"/*.mdt; do
        [ -e "$f" ] && return 0
    done
    return 1
}

has_keymaster_ta() {
    dir="$1"
    [ -d "$dir" ] || return 1
    for f in "$dir"/keymaste*.mdt "$dir"/*keymaster*.mdt "$dir"/*keymaste*.mdt; do
        [ -e "$f" ] && return 0
    done
    return 1
}

dump_dir() {
    label="$1"
    dir="$2"
    log "--- $label: $dir ---"
    ls -la "$dir" 2>&1 | head -n 120
    if [ -d "$dir/image" ]; then
        log "--- $label/image ---"
        ls -la "$dir/image" 2>&1 | head -n 160
        log "--- $label keymaster-like files ---"
        ls "$dir/image" 2>/dev/null | grep -Ei 'keymaste|keymaster|gatekeep|cmnlib|widevine|secapp' | head -n 80 || true
    fi
}

wrap_root_as_image() {
    src="$1"
    log "wrapping root-layout firmware from $src as $MNT/image"
    umount "$MNT" >/dev/null 2>&1 || true
    mount -t tmpfs -o mode=0755,size=4m tmpfs "$MNT" || return 1
    mkdir -p "$MNT/image" || return 1
    mount -o bind "$src" "$MNT/image" || return 1
    return 0
}

use_tree_as_firmware_mnt() {
    src="$1"
    log "binding $src over $MNT"
    umount "$MNT" >/dev/null 2>&1 || true
    mount -o bind "$src" "$MNT" || return 1
    return 0
}

log "probe start"
mkdir -p "$MNT" "$MODEM_MNT" "$ALT" "$RAW"

log "--- partition aliases ---"
for n in apnhlos firmware modem; do
    p="/dev/block/bootdevice/by-name/$n"
    if [ -e "$p" ]; then
        log "$n -> $(readlink -f "$p" 2>/dev/null)"
        blkid "$p" 2>/dev/null || true
    else
        log "$n -> missing"
    fi
done

log "--- mounts before probe ---"
grep -E 'firmware_mnt|firmware-modem|apnhlos|/modem ' /proc/mounts 2>/dev/null || true

if ! is_mounted "$MNT"; then
    for n in apnhlos firmware; do
        p="/dev/block/bootdevice/by-name/$n"
        [ -e "$p" ] || continue
        log "trying $n on $MNT"
        if mount_vfat "$p" "$MNT"; then
            break
        fi
    done
fi

if [ -e /dev/block/bootdevice/by-name/modem ] && ! is_mounted "$MODEM_MNT"; then
    log "mounting modem read-only for comparison"
    mount_vfat /dev/block/bootdevice/by-name/modem "$MODEM_MNT" || true
fi

dump_dir "current firmware" "$MNT"
dump_dir "modem firmware" "$MODEM_MNT"

if [ -d "$MNT/image" ] && has_mdt "$MNT/image"; then
    log "current firmware layout is valid"
    exit 0
fi

# Some builds expose the Qualcomm firmware payload directly at filesystem root.
# Preserve the read-only source with a bind mount, then present a tmpfs wrapper
# so hard-coded users of /vendor/firmware_mnt/image see the same payload.
if has_mdt "$MNT"; then
    log "current firmware uses root layout"
    umount "$RAW" >/dev/null 2>&1 || true
    mount -o bind "$MNT" "$RAW" || exit 21
    if wrap_root_as_image "$RAW"; then
        dump_dir "remapped firmware" "$MNT"
        exit 0
    fi
    exit 22
fi

# Samsung SM8350 trees contain both 'apnhlos' and, on some builds, a
# 'firmware' alias. Probe the latter only if it resolves to a different node.
APN_REAL="$(readlink -f /dev/block/bootdevice/by-name/apnhlos 2>/dev/null)"
FW_REAL="$(readlink -f /dev/block/bootdevice/by-name/firmware 2>/dev/null)"
if [ -n "$FW_REAL" ] && [ "$FW_REAL" != "$APN_REAL" ]; then
    log "probing alternate firmware partition: $FW_REAL"
    umount "$ALT" >/dev/null 2>&1 || true
    if mount_vfat /dev/block/bootdevice/by-name/firmware "$ALT"; then
        dump_dir "alternate firmware" "$ALT"
        if [ -d "$ALT/image" ] && has_mdt "$ALT/image"; then
            use_tree_as_firmware_mnt "$ALT" || exit 31
            log "alternate firmware selected"
            exit 0
        fi
        if has_mdt "$ALT"; then
            wrap_root_as_image "$ALT" || exit 32
            log "alternate root-layout firmware selected"
            exit 0
        fi
    fi
fi

# Samsung SM8350 stock has two fstab layouts. On q2q/Fold3, fstab.default
# maps apnhlos -> /vendor/firmware_mnt, while fstab.emmc maps
# modem -> /vendor/firmware_mnt. Therefore, if apnhlos does not expose image/
# but the modem partition does expose a normal Qualcomm image/*.mdt tree,
# prefer that complete modem tree. This is a read-only bind mount.
if [ -d "$MODEM_MNT/image" ] && has_mdt "$MODEM_MNT/image"; then
    log "modem image tree is valid; selecting stock SM8350 fstab.emmc layout"
    use_tree_as_firmware_mnt "$MODEM_MNT" || exit 41
    dump_dir "selected modem firmware" "$MNT"
    exit 0
fi

# A Keymaster-named trustlet remains useful as an explicit diagnostic signal,
# but no longer gates the modem fallback because stock Samsung can package
# trusted apps under other names.
if [ -d "$MODEM_MNT/image" ] && has_keymaster_ta "$MODEM_MNT/image"; then
    log "Keymaster-named trustlet found in modem firmware"
fi

log "no usable /vendor/firmware_mnt/image layout found"
log "--- final mounts ---"
grep -E 'firmware_mnt|firmware-modem|apnhlos|/modem ' /proc/mounts 2>/dev/null || true
exit 50
