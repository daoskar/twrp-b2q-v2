#!/system/bin/sh

echo "--- service states ---"
for s in vendor.spdaemon vendor.sec_nvm vendor.qseecomd vendor.keymaster-sb-4-0 vendor.keymaster-4-0; do
    printf "%s=" "$s"
    getprop "init.svc.$s"
done

echo "--- service pids ---"
for s in vendor.spdaemon vendor.sec_nvm vendor.qseecomd vendor.keymaster-sb-4-0 vendor.keymaster-4-0; do
    printf "%s pid=" "$s"
    getprop "init.svc_debug_pid.$s"
done

echo "--- relevant logcat ---"
logcat -b all -d -v brief 2>/dev/null     | grep -Ei 'init.*(spdaemon|sec_nvm|qseecomd|keymaster)|CANNOT LINK EXECUTABLE|linker|fatal|crash|segfault|keymaster|skeymaster|qsee|spdaemon|sec_nvm|spcom|spu|spss|nvm_ready|spu_ready|SKP|NvSegment|createSegment|sec_nvm_sp_nvm'     | tail -n 240 || true

echo "--- relevant dmesg ---"
dmesg 2>/dev/null     | grep -Ei 'avc:|denied|spdaemon|sec_nvm|qseecomd|keymaster|skeymaster|spcom|spu|spss|smcinvoke|segfault|nvm_ready|spu_ready|SKP|NvSegment'     | tail -n 220 || true

echo "--- SPU/QSEE nodes ---"
ls -la     /dev/qseecom /dev/smcinvoke /dev/qsee_ipc_irq_spss /dev/pft     /dev/spcom /dev/spss_utils /dev/sp_kernel /dev/sp_nvm /dev/sp_ssr     /dev/sp_keymaster /dev/sp_keymaster_ssr /dev/sec_nvm_*     /dev/cryptoapp /dev/spdaemon_ssr /dev/spu_hal_ssr     2>&1 | head -n 100

echo "--- persist ---"
grep -E ' /(persist|mnt/vendor/persist) ' /proc/mounts || true
ls -ld /persist /mnt/vendor/persist /mnt/vendor/persist/iar_db /mnt/vendor/persist/secnvm 2>&1 || true


echo "--- SP synchronization properties ---"
getprop | grep -Ei 'spcom|nvm_ready|spu_ready|spdaemon_init|sec_nvm_init|keymaster.strongbox' || true

echo "--- sec_nvm persisted segments ---"
find /mnt/vendor/persist/secnvm -maxdepth 2 -type f -printf '%p %s bytes\n' 2>/dev/null | head -n 120 || true
