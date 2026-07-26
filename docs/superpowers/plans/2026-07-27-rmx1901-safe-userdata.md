# RMX1901 Safe Userdata Initrd Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce an auditable RMX1901 Halium arm64 initrd that recognizes only ext4/f2fs userdata, probes it read-only, never repairs, formats, or resizes it, and panics into rescue on failure.

**Architecture:** Keep the byte-proven upstream `scripts/halium` as the boot integration point, but move userdata policy into a small POSIX shell library with injectable command paths. Derive the output from the pinned official initrd, replace only allowlisted files, remove prohibited filesystem tools, and emit deterministic manifests, hashes, provenance, and an SPDX SBOM.

**Tech Stack:** POSIX `sh`/dash, shell fixtures, initramfs `cpio newc`, `gzip -n`, Git, SHA-256, SPDX 2.3 JSON.

## Global Constraints

- Upstream source is exactly `Halium/initramfs-tools-halium@e6a91ad5dbd62521629ecd6f90d93c10884dc846`.
- Base arm64 asset SHA-256 is exactly `0bbac4577f3567aec935c958216de5d30c7355452ca56248d6728f4f2634bdb6`.
- Never call e2fsck, resize2fs, dumpe2fs, mkfs/mke2fs, or any f2fs repair utility during boot.
- Never connect to, inspect, stage to, or flash a phone.
- Do not modify any Halium build, device, vendor, kernel, or port repository.
- The derived archive may change only explicitly allowlisted initrd paths and delete prohibited tools.
- Tests must be observed RED before production behavior is implemented.

---

### Task 1: Injectable safety policy fixtures

**Files:**
- Create: `tests/test-safe-userdata.sh`
- Create: `tests/lib/fixture.sh`
- Test: `tests/test-safe-userdata.sh`

**Interfaces:**
- Consumes: `safe_mount_userdata DEVICE MOUNTPOINT` from `scripts/halium-userdata`.
- Produces: fake `blkid`, `mount`, `umount`, block-device predicate, payload predicate, logger, and panic commands with literal call logs.

- [ ] Write separate failing tests for ext4, f2fs, empty/unknown/multiline type, non-block device, read-only failure, unmount failure, writable failure with read-only rescue, and missing payload.
- [ ] Run `dash tests/test-safe-userdata.sh`; require failure because `scripts/halium-userdata` does not exist.
- [ ] Record the RED command, exit code, and expected failure in `docs/tdd-evidence.md`.

### Task 2: Minimal safe userdata policy

**Files:**
- Create: `scripts/halium-userdata`
- Modify: `scripts/halium`
- Modify: `hooks/halium`
- Test: `tests/test-safe-userdata.sh`

**Interfaces:**
- Consumes injected `HALIUM_BLKID`, `HALIUM_MOUNT`, `HALIUM_UMOUNT`, `HALIUM_IS_BLOCK`, `HALIUM_HAS_PAYLOAD`, `HALIUM_LOG`, and `HALIUM_PANIC` commands.
- Produces `safe_mount_userdata DEVICE MOUNTPOINT`, returning success only after `ro` probe, payload validation, clean unmount, and `rw` mount.

- [ ] Implement exact type allowlist: one-line `ext4` or `f2fs` only.
- [ ] For ext4 use `-t ext4 -o ro,noload`, then `-t ext4 -o rw,noatime`; for f2fs use `-t f2fs -o ro`, then `-t f2fs -o rw,noatime`.
- [ ] On writable failure, attempt one matching read-only rescue mount, log `userdata_mount=readonly-rescue`, then panic and return failure.
- [ ] Make `mountroot` call the policy and stop on failure before identifying the file layout.
- [ ] Remove the legacy repair/resize function and remove e2fsck, resize2fs, and dumpe2fs from the initramfs hook.
- [ ] Run `dash tests/test-safe-userdata.sh`; require every behavior test to pass.
- [ ] Record GREEN evidence in `docs/tdd-evidence.md`.

### Task 3: Reproducible pinned derivation and artifact audit

**Files:**
- Create: `tools/derive-initrd.sh`
- Create: `tools/audit-initrd.sh`
- Create: `tests/test-derive-initrd.sh`
- Create: `PROVENANCE.md`
- Create: `sbom/initrd.spdx.json` through the builder
- Create: `out/*.manifest`, `out/*.sha256`, and the derived initrd through the builder

**Interfaces:**
- Consumes a local file whose SHA-256 equals the fixed base hash.
- Produces deterministic `out/initrd.img-touch-arm64-rmx1901-safe`, before/after manifests, delta manifest, SPDX JSON, and SHA-256 records.

- [ ] Write a failing derivation fixture using a tiny synthetic base archive; assert deterministic repeated builds, allowlisted changes, forbidden-tool deletion, preserved unrelated file bytes, and artifact runtime policy tests.
- [ ] Run the fixture and record RED because builder/auditor scripts are absent.
- [ ] Implement a locale/timezone-fixed newc + `gzip -n` derivation with sorted input and normalized owner.
- [ ] Permit replacement only of `scripts/halium` and addition of `scripts/halium-userdata`; permit deletion only of `sbin/e2fsck`, `sbin/resize2fs`, and `sbin/dumpe2fs`.
- [ ] Reject forbidden executables and dangerous command invocations in the unpacked output.
- [ ] Build twice and compare output hashes; run the full audit and record GREEN.

### Task 4: Provenance, verification, and local commit

**Files:**
- Modify: `README.md`
- Create: `docs/verification.md`
- Modify: `PROVENANCE.md`

**Interfaces:**
- Consumes all test and build results.
- Produces a self-contained operator record without staging or flashing instructions.

- [ ] Record upstream remote, commit, release/asset IDs, timestamps, source-script byte match, base/output hashes, allowed delta, builder tool versions, and known residual risks.
- [ ] Run `dash -n`, all test scripts, derive twice, audit the final artifact, inspect `git diff --check`, and verify no other repository changed.
- [ ] Commit the independent local repository without pushing.
- [ ] Dispatch an independent read-only reviewer using the requirements and base/head SHAs; resolve every Critical or Important finding before reporting.
