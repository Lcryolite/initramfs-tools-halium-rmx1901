# RMX1901 Recovery restart helper

## Goal

Provide an initramfs-resident, auditable way for the host evidence controller
to request a Linux 4.9 reboot into Recovery after it has finished collecting a
panic attempt. It must not write Android `misc`, BCB, userdata, or any other
persistent partition.

## Design

`/sbin/rmx1901-restart-recovery` is a static AArch64 ELF with no arguments and
no runtime dependencies. Its only privileged action is the Linux AArch64
`reboot` syscall (`__NR_reboot=142`) with the two required reboot magic values,
`LINUX_REBOOT_CMD_RESTART2`, and the literal target `recovery`. If the syscall
returns, the helper exits non-zero.

The helper is packaged by the deterministic initrd derivation, with its source
and build script reviewed in-tree. The archive delta explicitly includes the
helper and is audited for an AArch64 static ELF without an interpreter.

The helper is deliberately not invoked by `panic()`, the panic telnet script,
or an unconditional kernel command-line option. A host-side, evidence-complete
controller may invoke it through the existing panic shell only after recording
the attempt; a later device test must prove the expected Recovery USB/ADB
identity before this is considered enabled for unattended operation.

## Acceptance

- Build output is ELF64/AArch64, static, and has no PT_INTERP segment.
- The executable accepts no arguments and contains exactly the literal target
  `recovery`.
- The derived archive contains it at the fixed path with mode 0755.
- Existing userdata, handoff, RNDIS, derivation, and archive-audit tests stay
  green.
- No boot image containing the helper is flashed until a separate candidate
  has passed offline verification and a single controlled device test is
  authorized.
