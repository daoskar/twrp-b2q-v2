#!/system/bin/sh
# Launch the crypto HAL/service binaries from the phone's mounted stock vendor.
# We intentionally do not redistribute Samsung/Qualcomm proprietary blobs in
# this device tree.  Different b2q vendor revisions may use the generic or
# -qti service filename, so probe a small known-safe candidate list.

name="$1"
export LD_LIBRARY_PATH=/vendor/lib64:/vendor/lib:/system/lib64:/system/lib:/sbin

log_msg() {
    echo "b2q-decrypt: $*" > /dev/kmsg 2>/dev/null || true
}

pick_and_exec() {
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
