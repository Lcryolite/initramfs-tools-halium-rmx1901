# Verification Record

The following gates apply to the committed source and ignored local artifact:

1. `/bin/sh tests/test-safe-userdata.sh` — ten behavior fixtures.
2. `/bin/sh tests/test-derive-initrd.sh` — deterministic synthetic derivation, relative paths, fixed epoch, allowlist delta, packed-policy behavior, SBOM, and archive audit.
3. `tools/audit-initrd.sh` against the fixed official base and `out/final` artifact.
4. A second real derivation compared byte-for-byte with `out/final`.
5. POSIX-shell syntax checks for every maintained shell script.
6. Static search for prohibited tools, invocations, and mount options.
7. `git diff --check` and repository-boundary inspection.

The final fresh outputs and commit IDs are recorded after the verification run rather than inferred from earlier runs.
