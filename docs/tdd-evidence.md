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
