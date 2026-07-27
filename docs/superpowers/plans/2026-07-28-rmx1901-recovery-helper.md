# RMX1901 Recovery Helper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Package an opt-in static AArch64 `RESTART2("recovery")` helper without persistent writes.

**Architecture:** A freestanding helper owns the fixed syscall ABI. The deterministic initrd derivation builds it in a private build directory and adds it as an allowlisted archive path. Existing panic code never invokes it automatically.

**Tech Stack:** POSIX sh, AArch64 GCC, freestanding C, ELF tools, cpio/gzip.

## Global Constraints

- Linux 4.9 only; do not add 4.14 code.
- No arguments, BCB/misc writes, userdata access, or automatic panic invocation.
- The only reboot target is literal `recovery` using syscall number 142.

### Task 1: Build and inspect the helper

**Files:** Create `tools/rmx1901-restart-recovery.c`, `tools/build-rmx1901-restart-recovery.sh`; create `tests/test-rmx1901-restart-recovery.sh`.

- [ ] Write a test that invokes the builder and asserts ELF64, AArch64, no program interpreter, fixed literal `recovery`, and no accepted arguments.
- [ ] Run `TMPDIR=/home/lknife/android/.tmp-rmx1901-m3 sh tests/test-rmx1901-restart-recovery.sh` and observe failure before the builder exists.
- [ ] Implement `_start` with registers x0=`0xfee1dead`, x1=`0x28121969`, x2=`0xa1b2c3d4`, x3=`"recovery"`, x8=`142`, then `svc #0`; compile using `aarch64-linux-gnu-gcc -nostdlib -static -Os -ffreestanding -fno-stack-protector -Wl,--build-id=none`.
- [ ] Re-run the test and commit with `git commit -m 'rmx1901: add recovery restart helper'`.

### Task 2: Package and audit it

**Files:** Modify `tools/derive-initrd.sh`, `tools/audit-initrd.sh`, and `tests/test-derive-initrd.sh`.

- [ ] Add a failing archive test for executable `sbin/rmx1901-restart-recovery` with ELF64/AArch64 and no interpreter.
- [ ] Build the helper under `$BUILD_ROOT`, install mode 0755 into the unpacked archive, normalize its timestamp, and add exactly `ADD sbin/rmx1901-restart-recovery` to the delta allowlist.
- [ ] Reject a missing, non-AArch64, dynamic, or altered helper in the archive auditor.
- [ ] Run derivation twice, compare outputs, run archive audit, and commit with `git commit -m 'rmx1901: package audited recovery helper'`.

### Task 3: Prove opt-in behavior

**Files:** Modify `tests/test-debug-rndis.sh`, `README.md`, and `docs/verification.md`.

- [ ] Add a test that `scripts/functions`, `scripts/panic/telnet`, and `scripts/halium` contain no helper invocation.
- [ ] Document that only an evidence-complete host controller may invoke it through the panic shell, and Recovery ADB identity must be verified afterward.
- [ ] Run the complete initrd test suite and commit with `git commit -m 'docs: gate RMX1901 automated recovery'`.
