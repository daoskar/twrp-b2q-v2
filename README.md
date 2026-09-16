# twrp-b2q-v2

Experimental Samsung Galaxy Z Flip3 **SM-F711B / b2q** TWRP device tree based on AlexFurina/twrp_device_samsung_b2q (`android-12.1`).

## Main changes

- enable TWRP crypto + FBE + FBE metadata decryption
- enable Qualcomm FBE decryption helpers
- add FBEv2 `metadata_encryption` mapping for `/data`
- enable new minadbd for sideload testing
- replace fixed `/dev/block/sdf1` USB-OTG path with dynamic removable-disk detection
- keep `persist` read-only in TWRP

## Prebuilts

The GitHub connector cannot copy binary blobs between repositories directly, so fetch the exact upstream kernel/DTB/DTBO files before building:

```bash
bash scripts/fetch-prebuilts.sh
```

The script verifies each download using its upstream Git blob SHA before accepting it.

## Build target

Place this tree at:

```text
device/samsung/b2q
```

Then use the normal TWRP 12.1 environment and build `twrp_b2q-eng` / `recoveryimage`.

## Status

This branch is experimental and must be tested on-device. In particular, verify `/data` decryption, ADB sideload and USB-OTG before treating it as a release recovery.
