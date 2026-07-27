# RMX1901 diagnostic RNDIS bridge plan

## Goal

Provide a one-boot, command-line-gated diagnostic channel across the Halium
`run-init` handoff.  The production path must remain byte-for-byte equivalent
in behavior when `rmx1901.debug_rndis=1` is absent.

## Design

1. Add a separately testable `/scripts/halium-rmx1901-debug` helper and source
   it from `/scripts/halium`.
2. Accept exactly one literal `rmx1901.debug_rndis=1` command-line token.
3. At the end of a successful normal mountroot, runtime-mask only
   `usb-moded.service` under initramfs `/run` (which is moved into the new
   root), configure the same
   configfs RNDIS gadget already proven on this device, and assign
   `192.168.2.15`.
4. Start a helper already chrooted into the new root before `run-init`.  After a
   waits for the post-handoff `/dev` and `/proc`, generates an ephemeral host
   key under `/run`, and starts
   public-key-only sshd for `phablet`, using the immutable authorized key in the
   Halium overlay.  It must disable passwords, root login, forwarding, tunnels,
   and PAM.
5. Keep all state in initramfs/configfs or `/run`; never create a userdata
   marker or persistent key.
6. Derive and audit the initrd reproducibly from the pinned official base, then
   build a diagnostic boot image using the already verified kernel and an
   explicit debug command-line token.

## Verification

- Parser fixtures: absent, malformed, duplicate, glob, and metacharacter tokens
  do not enable the bridge; one exact token does.
- Stateful fixture: only the system usb-moded unit is masked, configfs values
  and links match the known-good panic gadget, the expected interface address
  is assigned, and the chrooted ssh helper is launched once.
- Source gate: no password/empty-password/root login, no userdata write path,
  no non-system block target, and no filesystem repair/format command.
- Existing safe-userdata and deterministic derive/audit suites continue to
  pass.
- Before flashing: verify boot size, component hashes, command line, absence of
  ReSukiSU/SukiSU, and exact `/dev/block/sde10` identity in Recovery.
