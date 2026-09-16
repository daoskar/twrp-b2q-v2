#!/system/bin/sh
# Launch the crypto HAL/service binaries from the phone's stock vendor.
# We intentionally do not redistribute Samsung/Qualcomm proprietary blobs.
# TWRP may unmount /vendor after probing the Keymaster manifest, so make sure
# the logical vendor partition is mounted again before starting any stock HAL.

name="$1"
export LD_LIBRARY_PATH=/vendor/lib64:/vendor/lib64/hw:/vendor/lib:/vendor/lib/hw:/system/lib64:/system/lib64/hw:/system/lib:/system/lib/hw:/sbin

log_msg() {
    echo "b2q-decrypt: $*" > /dev/kmsg 2>/dev/null || true
}

vendor_is_mounted() {
    grep -qsE '[[:space:]]/vendor[[:space:]]' /proc/mounts
}

ensure_vendor_mounted() {
    if vendor_is_mounted; then
        return 0
    fi

    mkdir -p /vendor

    # b2q is non-A/B and TWRP creates the bootdevice/by-name/vendor symlink
    # for the logical dm device. Keep mapper/by-name fallbacks for robustness.
    for block in \
        /dev/block/bootdevice/by-name/vendor \
        /dev/block/by-name/vendor \
        /dev/block/mapper/vendor; do
        [ -e "$block" ] || continue

        # Samsung vendor is EROFS on current firmware; older vendor images may
        # still be ext4. Mount read-only because recovery only needs HAL blobs.
        if mount -t erofs -o ro "$block" /vendor 2>/dev/null; then
            log_msg "mounted vendor (erofs) from $block"
            setprop b2q.decrypt.vendor_mounted erofs 2>/dev/null || true
            return 0
        fi
        if mount -t ext4 -o ro "$block" /vendor 2>/dev/null; then
            log_msg "mounted vendor (ext4) from $block"
            setprop b2q.decrypt.vendor_mounted ext4 2>/dev/null || true
            return 0
        fi
    done

    log_msg "unable to mount stock vendor partition"
    setprop b2q.decrypt.vendor_mount_failed 1 2>/dev/null || true
    return 1
}

pick_and_exec() {
    ensure_vendor_mounted || exit 70

    for candidate in "$@"; do
        if [ -x "$candidate" ]; then
            log_msg "$name -> $candidate"
            setprop "b2q.decrypt.${name}.path" "$candidate" 2>/dev/null || true
            exec "$candidate"
        fi
    done

    log_msg "$name: no compatible stock vendor binary found"
    setprop "b2q.decrypt.${name}.missing" 1 2>/dev/null || true
    exit 127
}

case "$name" in
    qseecomd)
        pick_and_exec \
            /vendor/bin/qseecomd
        ;;
    keymaster)
        pick_and_exec \
            /vendor/bin/hw/android.hardware.keymaster@4.0-service \
            /vendor/bin/hw/android.hardware.keymaster@4.0-service-qti
        ;;
    gatekeeper)
        pick_and_exec \
            /vendor/bin/hw/android.hardware.gatekeeper@1.0-service \
            /vendor/bin/hw/android.hardware.gatekeeper@1.0-service-qti
        ;;
    *)
        log_msg "unknown service '$name'"
        exit 64
        ;;
esac
