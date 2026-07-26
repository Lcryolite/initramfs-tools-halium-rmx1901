# Verification Record

The following gates apply to the committed source and ignored local artifact:

1. `/bin/sh tests/test-safe-userdata.sh` — ten behavior fixtures.
2. `/bin/sh tests/test-derive-initrd.sh` — deterministic synthetic derivation, relative paths, fixed epoch, allowlist delta, packed-policy behavior, SBOM, and archive audit.
3. `/bin/sh tests/test-archive-errors.sh` — corrupt gzip and cpio read failures must propagate.
4. `/bin/sh tests/test-trust-anchor.sh` — environment cannot replace the fixed base SHA or epoch.
5. `tools/audit-initrd.sh` against the fixed official base and `out/reviewed` artifact.
6. A second real derivation compared byte-for-byte with `out/reviewed`.
7. POSIX-shell syntax checks for every maintained shell script.
8. Static search for prohibited tools, invocations, and mount options.
9. `git diff --check` and repository-boundary inspection.

The final fresh outputs and commit IDs are recorded after the verification run rather than inferred from earlier runs.
