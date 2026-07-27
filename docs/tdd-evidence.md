# TDD Evidence

## Safe userdata policy

### RED

- Date: 2026-07-27 (Asia/Shanghai)
- Command: `/bin/sh tests/test-safe-userdata.sh`
- Exit: `1`
- Expected failure: `scripts/halium-userdata: No such file or directory`
- Interpretation: the behavioral fixture could not pass before the production policy existed.
- Environment note: `dash` is not installed; `/bin/sh` resolves to `/usr/bin/bash` on this builder.

### GREEN

- Command: `/bin/sh tests/test-safe-userdata.sh`
- Exit: `0`
- Result: 10/10 named behavior fixtures passed.

## System partition partlabel alias

### RED

- Date: 2026-07-27 (Asia/Shanghai)
- Command: `/bin/sh tests/test-safe-userdata.sh`
- Exit: `1`
- Expected failures: the new `/dev/disk/by-partlabel/system` positive fixture was rejected by the old allowlist, while the dedicated legacy-alias fixture showed that `/dev/block/by-name/system` was still accepted.
- Interpretation: the policy did not accept the alias actually created by the pinned initrd udev rules and retained an unusable legacy alias.

### GREEN

- Command: `/bin/sh tests/test-safe-userdata.sh`
- Exit: `0`
- Result: 24/24 named behavior fixtures passed, including partlabel acceptance, legacy-alias rejection, canonical `/dev/block/sda11` validation, pre-mount alias revalidation, and canonical-only mounting.

## Deterministic initrd derivation

### RED

- Date: 2026-07-27 (Asia/Shanghai)
- Command: `/bin/sh tests/test-derive-initrd.sh`
- Exit: `127`
- Expected failure: `tools/derive-initrd.sh: No such file or directory`
- Interpretation: deterministic derivation and archive auditing could not pass before builder/auditor production scripts existed.

### Regression RED: relative output path

- Command: `/bin/sh tests/test-derive-initrd.sh`
- Exit: `1`
- Expected failure: `relative-out/initrd.img-touch-arm64-rmx1901-safe: No such file or directory`
- Root cause: the packer changed to the unpacked tree before resolving a caller-relative output path.

### Regression RED: relative audit input path

- Command: `/bin/sh tests/test-derive-initrd.sh`
- Exit: `2`
- Expected failure: `out-one/initrd.img-touch-arm64-rmx1901-safe.gz: No such file or directory`
- Root cause: the auditor changed directories before resolving its artifact and manifest inputs.

### Regression RED: fixed release epoch

- Command: `/bin/sh tests/test-derive-initrd.sh`
- Exit: `1`
- Expected failure: `default epoch does not match pinned release timestamp`
- Root cause: the default epoch encoded 2023-01-19 rather than the pinned timestamp asset's 2023-01-17.

### GREEN

- Command: `/bin/sh tests/test-derive-initrd.sh`
- Exit: `0`
- Result: deterministic derivation, relative-path handling, allowlist delta, forbidden-tool deletion, packed-policy behavior, fixed epoch, SPDX output, and independent archive audit passed.

## Independent review regressions

### RED: immutable trust anchor

- Command: `/bin/sh tests/test-trust-anchor.sh`
- Exit: `1`
- Expected failure: `derive rejection was not the fixed-hash gate`
- Root cause: `EXPECTED_BASE_SHA` and `SOURCE_DATE_EPOCH` from the environment could replace production provenance constants, and the auditor did not independently verify the base hash.

### RED: checked archive stages

- Command: `/bin/sh tests/test-archive-errors.sh`
- Exit: `1`
- Expected failure: `checked pack_initrd function is missing`
- Root cause: gzip/cpio pipelines reported only the final process status under POSIX sh.

### RED: production command injection removed

- Command: `/bin/sh tests/test-safe-userdata.sh`
- Exit: `1`
- Expected failure: poisoned `HALIUM_*` environment commands prevented every policy fixture from reaching its fake command log.
- Root cause: test injection variables were also honored by the production initramfs path.

### GREEN

- `/bin/sh tests/test-archive-errors.sh`: corrupt gzip and unreadable cpio input fail closed.
- `/bin/sh tests/test-trust-anchor.sh`: base SHA and release epoch remain fixed despite poisoned environment values.
- `/bin/sh tests/test-safe-userdata.sh`: all ten policy fixtures pass through shell-only wrapper overrides; production no longer reads `HALIUM_*` command variables.

### RED: manifest stage errors

- Command: `/bin/sh tests/test-archive-errors.sh`
- Exit: `1`
- Expected failure: `manifest generation ignored an invalid root`
- Root cause: `manifest_tree` used an unchecked `find | sort | while` pipeline and could hash the caller's current directory after `cd` failed.

### GREEN: manifest stage errors

- `/bin/sh tests/test-archive-errors.sh`: nonexistent roots and unreadable files now make manifest generation fail; find, sort, stat, sha256sum, and output stages are checked separately.
