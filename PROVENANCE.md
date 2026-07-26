# RMX1901 Safe Initrd Provenance

## Upstream source

- Repository: `https://github.com/Halium/initramfs-tools-halium.git`
- Local remote name: `upstream`
- Source commit/tag: `e6a91ad5dbd62521629ecd6f90d93c10884dc846` / `upstream-e6a91ad`
- Commit author date: `2022-07-19T03:15:16+07:00`
- Upstream source `scripts/halium` SHA-256: `02dd7445f272564ce2379ffa2fc9ef8bbdf8c414f39b9316d824f4bf2a507acd`
- Extracted official asset `scripts/halium` SHA-256: `02dd7445f272564ce2379ffa2fc9ef8bbdf8c414f39b9316d824f4bf2a507acd`
- Both scripts are 21,943 bytes; this byte match pins the boot script despite mutable `continuous` release metadata.

## Official base artifact

- GitHub release ID/tag: `9577925` / `continuous`
- arm64 asset ID: `92015679`
- Asset updated: `2023-01-17T13:46:48Z`
- Timestamp asset content: `Tue, 17 Jan 2023 13:46:06 +0000`
- Filename: `initrd.img-touch-arm64`
- Size: `4,106,247` bytes
- SHA-256: `0bbac4577f3567aec935c958216de5d30c7355452ca56248d6728f4f2634bdb6`
- Local pinned input: `/var/tmp/rmx1901-halium-initrd-cache/92015679-0bbac4577f3567aec935c958216de5d30c7355452ca56248d6728f4f2634bdb6-initrd.img-touch-arm64`

The mutable release `target_commitish` is not used as a trust anchor. The fixed asset hash and exact embedded-script/source match are used instead.

## Derived artifact

- Path: `out/reviewed/initrd.img-touch-arm64-rmx1901-safe`
- Size: `3,942,246` bytes
- SHA-256: `ac74c1124cc5cab7b9b42c9a06ca8ff5e14fc2d6e0d7237deb42da8a6788ceca`
- Fixed build epoch: `1673963166` (`2023-01-17T13:46:06Z`)
- SPDX document: `out/reviewed/initrd.spdx.json` and tracked copy `sbom/initrd.spdx.json`
- Before/after/delta manifests: `out/reviewed/initrd.{before,after,delta}.manifest`

The content/mode delta is exactly:

```text
ADD scripts/halium-userdata
DELETE sbin/dumpe2fs
DELETE sbin/e2fsck
DELETE sbin/resize2fs
REPLACE scripts/halium
```

All directory mtimes are normalized to the fixed build epoch. This metadata normalization is necessary because GNU cpio extraction otherwise updates directory mtimes while creating children; it does not alter non-allowlisted file content or modes.

## Builder environment

- OS/kernel: Linux x86_64, `7.1.3-2-cachyos`
- Git: `2.55.0`
- GNU cpio: `2.15`, `newc`, `--reproducible`, owner `0:0`
- gzip: `1.14-modified`, `-n -9`
- GNU coreutils/sha256sum: `9.11`
- GNU findutils: `4.11.0-modified`
- GNU awk: `5.4.1`
- Test shell: `/bin/sh` -> `/usr/bin/bash`; dash was unavailable

Two independent derivations from the fixed base produced the same SHA-256. Cross-toolchain byte identity still depends on the listed cpio/gzip implementations; a digest-pinned builder image remains desirable before publishing externally.

The production builder hard-codes the base SHA and release epoch; inherited environment variables cannot replace either trust anchor. The independent auditor verifies the base SHA before extracting or comparing caller-provided manifests. gzip, cpio, find, sort, stat, and hashing stages are separately checked so an intermediate failure cannot be hidden by the final process in a shell pipeline.

## Safety boundaries

- No phone was connected, inspected, staged, or flashed.
- No device, vendor, kernel, Halium build, or port repository was modified.
- The derived ramdisk has not been embedded into a boot image or staged for Task4.
- No repair, resize, or formatting executable is present in the derived archive.
- The existing RNDIS/telnet panic implementation is retained unchanged and remains device/kernel dependent.
