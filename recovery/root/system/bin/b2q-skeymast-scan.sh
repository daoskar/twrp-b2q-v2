#!/system/bin/sh
OUT=/tmp/b2q-skeymast-scan.log
FOUND_MNT=/tmp/b2q-skeymast-found
CAND=/tmp/b2q-skeymast-candidate-dir
: > "$OUT"
rm -f "$CAND"
umount "$FOUND_MNT" >/dev/null 2>&1 || true
rm -rf "$FOUND_MNT"
mkdir -p "$FOUND_MNT"

echo "=== SKEYMAST PARTITION SCAN ===" >> "$OUT"

if [ -r /vendor/firmware_mnt/image/skeymast.mdt ]; then
    echo "FOUND current=/vendor/firmware_mnt/image" >> "$OUT"
    echo "/vendor/firmware_mnt/image" > "$CAND"
    cat "$OUT"
    exit 0
fi

for link in /dev/block/bootdevice/by-name/*; do
    [ -e "$link" ] || continue
    name="$(basename "$link")"
    lname="$(echo "$name" | tr '[:upper:]' '[:lower:]')"
    case "$lname" in
        efs|efs_backup|persist|persdata|metadata|userdata|data|cache|keystore|keydata|keyrefuge|frp|modemst*|fsg)
            continue
            ;;
    esac

    dev="$(readlink -f "$link" 2>/dev/null)"
    [ -b "$dev" ] || continue

    size="$(blockdev --getsize64 "$dev" 2>/dev/null)"
    [ -n "$size" ] || continue
    [ "$size" -ge 1048576 ] || continue
    [ "$size" -le 536870912 ] || continue

    echo "TRY name=$name dev=$dev size=$size" >> "$OUT"

    umount "$FOUND_MNT" >/dev/null 2>&1 || true
    rm -rf "$FOUND_MNT"
    mkdir -p "$FOUND_MNT"

    if ! mount -t vfat -o ro "$dev" "$FOUND_MNT" >/dev/null 2>&1; then
        continue
    fi

    hit="$(find "$FOUND_MNT" -maxdepth 4 -type f -name 'skeymast.mdt' 2>/dev/null | head -n 1)"
    if [ -n "$hit" ]; then
        dir="$(dirname "$hit")"
        echo "FOUND name=$name dev=$dev dir=$dir" >> "$OUT"
        ls -l "$dir"/skeymast* >> "$OUT" 2>&1 || true
        echo "$dir" > "$CAND"
        cat "$OUT"
        exit 0
    fi

    umount "$FOUND_MNT" >/dev/null 2>&1 || true
done

echo "SKEYMAST_SCAN_RESULT=missing" >> "$OUT"
cat "$OUT"
exit 2
