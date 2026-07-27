# RMX1901 System Partition Partlabel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the RMX1901 initrd accept the system partition alias that its udev rules actually create while preserving fail-closed canonical-device validation.

**Architecture:** The kernel command line may contain exactly one `systempart=/dev/disk/by-partlabel/system`. The policy resolves that fixed alias to the early-udev node `/dev/sda11`, confirms it is a block device, saves both values, re-resolves the alias immediately before mount, and mounts only the saved canonical path.

**Tech Stack:** POSIX shell, shell fixture tests, deterministic cpio/gzip derivation.

## Global Constraints

- Reject `/dev/block/by-name/system` and every other command-line alias.
- Preserve the exact `/dev/sda11` early-udev allowlist, block-device check, and pre-mount TOCTOU revalidation.
- Modify only this initrd repository.
- Update README, provenance, TDD evidence, and verification records with exact artifact facts.

---

### Task 1: Partlabel systempart policy

**Files:**
- Modify: `tests/test-safe-userdata.sh`
- Modify: `scripts/halium-userdata`

**Interfaces:**
- Consumes: `validate_rmx1901_systempart_cmdline(cmdline)` and `safe_mount_rmx1901_systempart(mountpoint)`.
- Produces: validated `rmx1901_systempart=/dev/disk/by-partlabel/system` and `rmx1901_systempart_canonical=/dev/sda11`.

- [x] **Step 1: Write failing behavior tests**

  Change positive, canonical-mismatch, non-block, duplicate, glob, TOCTOU, and mount fixtures to use `/dev/disk/by-partlabel/system`; add a fixture proving `/dev/block/by-name/system` is rejected before path resolution.

- [x] **Step 2: Verify RED**

  Run: `/bin/sh tests/test-safe-userdata.sh`

  Expected: the new partlabel positive fixture fails with `Unsafe RMX1901 systempart command-line value`.

- [x] **Step 3: Implement the minimal policy change**

  Replace the accepted alias and all validated-state comparisons/logging in `scripts/halium-userdata` with `/dev/disk/by-partlabel/system`; bind the canonical target to the observed early-udev node `/dev/sda11`.

- [x] **Step 4: Verify GREEN**

  Run: `/bin/sh tests/test-safe-userdata.sh`

  Expected: all named fixtures pass, including rejection of the old alias.

### Task 2: Documentation, derivation, and audit

**Files:**
- Modify: `README.md`
- Modify: `PROVENANCE.md`
- Modify: `docs/tdd-evidence.md`
- Modify: `docs/verification.md`
- Generated ignored artifact: `out/systempart-devnode/initrd.img-touch-arm64-rmx1901-safe`

**Interfaces:**
- Consumes: fixed base asset and `tools/derive-initrd.sh`.
- Produces: deterministic reviewed initrd plus updated SHA-256, size, manifests, and verification record.

- [x] **Step 1: Update human-facing contract**

  Document the partlabel-only alias, old-alias rejection, unchanged canonical target, and the RED/GREEN evidence.

- [x] **Step 2: Run repository gates**

  Run every `tests/test-*.sh`, POSIX shell syntax checks, `git diff --check`, and the deterministic derivation/audit workflow.

- [x] **Step 3: Record exact derived facts**

  Replace the reviewed artifact size and SHA-256 in `PROVENANCE.md`; record the executed commands and outcomes in `docs/verification.md`.

- [x] **Step 4: Commit**

  Commit the policy, tests, plan, and documentation as one reviewed change and report both Git commit and initrd SHA-256.
