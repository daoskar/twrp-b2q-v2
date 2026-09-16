#!/system/bin/sh
# Resolve USB mass-storage dynamically. b2q UFS already occupies sd* nodes,
# so a fixed /dev/block/sdX path is unreliable.

while true; do
    found=""
    for sysdev in /sys/block/sd*; do
        [ -e "$sysdev/removable" ] || continue
        [ "$(cat "$sysdev/removable" 2>/dev/null)" = "1" ] || continue
        dev="${sysdev##*/}"
        if [ -b "/dev/block/${dev}1" ]; then
            found="/dev/block/${dev}1"
            whole="/dev/block/${dev}"
            break
        elif [ -b "/dev/block/${dev}" ]; then
            found="/dev/block/${dev}"
            whole="$found"
            break
        fi
    done

    if [ -n "$found" ]; then
        ln -sf "$found" /dev/block/twrp-usb1
        ln -sf "$whole" /dev/block/twrp-usb
    else
        rm -f /dev/block/twrp-usb1 /dev/block/twrp-usb
    fi

    sleep 2
 done
