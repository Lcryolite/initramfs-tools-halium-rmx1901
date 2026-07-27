#!/usr/bin/env python3
import os
import stat
import sys


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


if len(sys.argv) != 3:
    fail("usage: snapshot-regular-file.py SOURCE PRIVATE_DESTINATION")

source, destination = sys.argv[1:]
source_fd = -1
destination_fd = -1
destination_created = False
try:
    source_flags = os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW
    try:
        source_fd = os.open(source, source_flags)
    except OSError as error:
        fail(f"refusing non-regular or linked snapshot source: {source}: {error.strerror}")

    before = os.fstat(source_fd)
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
        fail(f"refusing non-regular or linked snapshot source: {source}")

    destination_flags = (
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW
    )
    destination_fd = os.open(destination, destination_flags, 0o600)
    destination_created = True
    while True:
        chunk = os.read(source_fd, 1024 * 1024)
        if not chunk:
            break
        view = memoryview(chunk)
        while view:
            written = os.write(destination_fd, view)
            if written <= 0:
                fail("short write while creating private snapshot")
            view = view[written:]
    os.fsync(destination_fd)

    after = os.fstat(source_fd)
    stable_identity = (
        before.st_dev,
        before.st_ino,
        before.st_size,
        before.st_mtime_ns,
        before.st_ctime_ns,
    ) == (
        after.st_dev,
        after.st_ino,
        after.st_size,
        after.st_mtime_ns,
        after.st_ctime_ns,
    )
    if not stable_identity:
        fail(f"snapshot source changed while being copied: {source}")
finally:
    if destination_fd >= 0:
        os.close(destination_fd)
    if source_fd >= 0:
        os.close(source_fd)
    if destination_created and sys.exc_info()[0] is not None:
        try:
            os.unlink(destination)
        except FileNotFoundError:
            pass
