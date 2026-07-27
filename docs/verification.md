# Verification Record

The following gates apply to the committed source and ignored local artifact:

1. `/bin/sh tests/test-safe-userdata.sh` — 26 behavior fixtures, including the partlabel-only system partition contract.
2. `/bin/sh tests/test-debug-rndis.sh` — exact-token gating, known-good configfs layout, runtime mask, and public-key-only SSH policy.
3. `/bin/sh tests/test-derive-initrd.sh` — deterministic synthetic derivation, relative paths, fixed epoch, allowlist delta, packed-policy behavior, SBOM, and archive audit.
4. `/bin/sh tests/test-archive-errors.sh` — corrupt gzip and cpio read failures must propagate.
5. `/bin/sh tests/test-trust-anchor.sh` — environment cannot replace the fixed base SHA or epoch.
6. `tools/audit-initrd.sh` against the fixed official base and the selected derived artifact.
7. A second real derivation compared byte-for-byte with the selected artifact.
8. POSIX-shell syntax checks for every maintained shell script.
9. Static search for prohibited tools, invocations, and mount options.
10. `git diff --check` and repository-boundary inspection.

The final fresh outputs and commit IDs are recorded after the verification run rather than inferred from earlier runs.

## 2026-07-27 early-devnode derivation

- All four `tests/test-*.sh` scripts exited `0`; the policy suite reported 26/26 named fixtures passing.
- Both real derivations produced `b3582e99c21eab2dd2912fc2e1c8c128d9c03fab7147452569d0b2da6bf44e6a` (3,941,298 bytes) and compared byte-for-byte equal.
- The independent archive audit accepted only the documented five-path delta and found no forbidden tools, commands, or mount options.
- The tracked `sbom/initrd.spdx.json` compared byte-for-byte equal to the generated SPDX document.
