#!/system/bin/sh
# Initial idea by @Gabriel2392

job() {
    block_ro="sda sdb sdc sdd sde sdf mmcblk0"
    byname_rw="boot recovery super efs sec_efs vendor_boot odm omr dtbo userdata cache misc metadata init_boot prism optics dtb system product vendor vbmeta hidden bota"

    for i in $block_ro; do
        [ ! -b "/dev/block/$i" ] && continue
        blockdev --setro "/dev/block/$i" 2>/dev/null
    done

    for device in /dev/block/by-name/*; do
        [ ! -b "$device" ] && continue
        dev_name="${device##*/}"
        found=0
        for pattern in $byname_rw; do
            case "$dev_name" in
                $pattern*)
                    blockdev --setrw "$device" 2>/dev/null
                    found=1
                    break
                    ;;
            esac
        done
        [ "$found" -eq 0 ] && blockdev --setro "$device" 2>/dev/null
    done
}

job &
exit 0
