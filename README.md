# TWRP b2q v2

Experimental TWRP device tree for Samsung Galaxy Z Flip3 **SM-F711B / b2q**, based on AlexFurina's Android 12.1 tree and updated around failures reproduced from a real b2q recovery log.

## What v2 changes

- enables TWRP crypto, FBE and FBE metadata decryption
- enables TeamWin Qualcomm `qcom_decrypt` / `qcom_decrypt_fbe`
- adds the FBEv2 `metadata_encryption` mapping for `/data`
- launches b2q's stock `qseecomd`, Keymaster 4.0 and Gatekeeper 1.0 directly from the mounted `/vendor` partition, with generic / `-qti` filename fallback
- enables the new minadbd path for sideload testing
- replaces the old fixed `/dev/block/sdf1` USB-OTG path with dynamic removable-disk detection
- keeps `persist` read-only in TWRP
- validates all externally fetched upstream files by exact Git blob SHA

## Status

The tree validation workflow is passing. A full `recovery.img` build workflow is included as `.github/workflows/build-recovery.yml`.

**On-device decryption is not declared fixed until it is tested on an SM-F711B with encrypted `/data` and a real PIN/password. Do not Format Data just to test this recovery.**

## Prepare the tree

Binary kernel/DT files and the large unchanged recovery support files are fetched from the known upstream b2q tree instead of being duplicated in this repository:

```bash
bash scripts/prepare-tree.sh
bash scripts/validate-tree.sh
```

The preparation script verifies every downloaded file using its upstream Git blob SHA.

## Local build

Place this repository at `device/samsung/b2q` in a TWRP 12.1 source tree, then:

```bash
bash device/samsung/b2q/scripts/prepare-tree.sh
export ALLOW_MISSING_DEPENDENCIES=true
source build/envsetup.sh
lunch twrp_b2q-eng
mka recoveryimage
```

The expected output is:

```text
out/target/product/b2q/recovery.img
```

## First test

Test in this order:

1. boot recovery and check whether Internal Storage shows the correct size;
2. enter the existing Android PIN/password if TWRP prompts for it;
3. verify `/data/media` is readable without formatting `/data`;
4. test a USB-OTG drive;
5. test ADB sideload with a harmless/test ZIP before using it for a ROM update.

If any of those fail, connect ADB while still in recovery and run from the repository checkout:

```bash
bash scripts/collect-device-debug.sh
```

It creates a `b2q-twrp-debug-*.tar.gz` containing recovery log, crypto properties/processes, vendor service presence, mounts, block devices, OTG state and dmesg.

## Upstream / references

Base recovery tree: `AlexFurina/twrp_device_samsung_b2q` (`android-12.1`).

Qualcomm decryption flow: `TeamWin/android_device_qcom_twrp-common` (`android-12.1`).

The stock b2q service filenames were cross-checked against a public SM-F711B proprietary file list based on Samsung firmware (`opensourcefreak/android_device_samsung_b2q`).
