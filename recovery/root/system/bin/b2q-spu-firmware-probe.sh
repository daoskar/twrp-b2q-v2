#!/system/bin/sh
# b2q test6y: locate the exact SPSS firmware on the physical Samsung partitions.
# Do not start SPU daemons here. Normalise the discovered firmware directory
# onto /spu, which is a stock SM8350 ueventd firmware search directory.

set +e

log() {
    echo "[b2q-spu-fw] $*"
}

SYSFS_FW=""
FW=""
for p in     /sys/devices/platform/soc/soc:qcom,spss_utils/firmware_name     /sys/devices/platform/soc@0/soc:qcom,spss_utils/firmware_name     /sys/devices/soc/soc:qcom,spss_utils/firmware_name
do
    if [ -r "$p" ]; then
        v="$(cat "$p" 2>/dev/null | tr -d '\r\n')"
        log "firmware_name_path=$p"
        log "firmware_name=$v"
        if [ -n "$v" ]; then
            SYSFS_FW="$p"
            FW="$v"
            break
        fi
    fi
done

if [ -z "$FW" ]; then
    log "no firmware_name reported by spss_utils"
    exit 31
fi

case "$FW" in
    spss1d|spss1t|spss1p|spss2d|spss2t|spss2p) ;;
    *)
        log "unexpected firmware name: $FW"
        exit 32
        ;;
esac

SCAN=/tmp/b2q-spu-fw-scan
mkdir -p "$SCAN"

log "machine=$(cat /sys/devices/soc0/machine 2>/dev/null)"
log "sku=$(getprop ro.boot.product.vendor.sku)"
log "bootmode=$(getprop ro.bootmode)"

log "--- partition aliases ---"
for n in apnhlos firmware modem spu; do
    p="/dev/block/bootdevice/by-name/$n"
    if [ -e "$p" ]; then
        log "$n -> $(readlink -f "$p" 2>/dev/null)"
        blkid "$p" 2>/dev/null || true
    else
        log "$n -> missing"
    fi
done

mount_vfat_ro() {
    src="$1"
    dst="$2"
    mkdir -p "$dst"
    umount "$dst" >/dev/null 2>&1 || true
    mount -t vfat -o ro,shortname=lower,uid=0,gid=1000,dmask=227,fmask=337 "$src" "$dst"
}

mount_ext4_ro() {
    src="$1"
    dst="$2"
    mkdir -p "$dst"
    umount "$dst" >/dev/null 2>&1 || true
    mount -t ext4 -o ro,noatime,nosuid,nodev "$src" "$dst"
}

for n in apnhlos firmware modem; do
    p="/dev/block/bootdevice/by-name/$n"
    [ -e "$p" ] || continue
    d="$SCAN/$n"
    if mount_vfat_ro "$p" "$d"; then
        log "mounted raw $n at $d"
    else
        log "raw mount failed for $n"
    fi
done

if [ -e /dev/block/bootdevice/by-name/spu ]; then
    if mount_ext4_ro /dev/block/bootdevice/by-name/spu "$SCAN/spu"; then
        log "mounted raw spu at $SCAN/spu"
    else
        log "raw mount failed for spu"
    fi
fi

log "--- current mounts ---"
grep -E 'firmware_mnt|firmware-modem| /spu |b2q-spu-fw-scan' /proc/mounts 2>/dev/null || true

log "--- exact SPSS search ---"
FOUND=""
for d in     /vendor/firmware_mnt     /vendor/firmware-modem     /spu     "$SCAN/apnhlos"     "$SCAN/firmware"     "$SCAN/modem"     "$SCAN/spu"
do
    [ -d "$d" ] || continue
    log "scan $d"
    find "$d" -type f \( -name "$FW.mdt" -o -name "$FW.b00" -o -name "$FW.b01" \) 2>/dev/null | head -n 80
    if [ -z "$FOUND" ]; then
        FOUND="$(find "$d" -type f -name "$FW.mdt" 2>/dev/null | head -n 1)"
    fi
done

log "--- all SPSS-like files ---"
for d in /vendor/firmware_mnt /vendor/firmware-modem /spu "$SCAN/apnhlos" "$SCAN/firmware" "$SCAN/modem" "$SCAN/spu"; do
    [ -d "$d" ] || continue
    find "$d" -type f \( -iname 'spss*' -o -iname 'keym*.sig' -o -iname 'crypt*.sig' -o -iname 'asym*.sig' \) 2>/dev/null | head -n 160
done

if [ -z "$FOUND" ]; then
    log "missing exact firmware: $FW.mdt"
    exit 33
fi

SRC_DIR="$(dirname "$FOUND")"
log "found_spu_firmware=$FOUND"
log "found_spu_directory=$SRC_DIR"

case "$FOUND" in
    /spu/"$FW".mdt|/vendor/firmware_mnt/image/"$FW".mdt|/vendor/firmware-modem/image/"$FW".mdt)
        log "firmware already lives in a stock ueventd search directory"
        ;;
    *)
        # /spu is a stock ueventd firmware search directory. In recovery it is
        # safe to replace only the mount view with a read-only source directory.
        umount /spu >/dev/null 2>&1 || true
        mkdir -p /spu
        if ! mount -o bind "$SRC_DIR" /spu; then
            log "failed to bind discovered firmware directory onto /spu"
            exit 34
        fi
        log "bound $SRC_DIR -> /spu"
        ;;
esac

if [ ! -e "/spu/$FW.mdt" ] &&    [ ! -e "/vendor/firmware_mnt/image/$FW.mdt" ] &&    [ ! -e "/vendor/firmware-modem/image/$FW.mdt" ]; then
    log "firmware disappeared after normalisation"
    exit 35
fi

log "--- normalised SPU firmware ---"
ls -la /spu 2>/dev/null | head -n 160
ls -l /spu/"$FW".mdt /spu/"$FW".b* 2>/dev/null | head -n 120 || true
log "SPU firmware ready: $FW"
exit 0
