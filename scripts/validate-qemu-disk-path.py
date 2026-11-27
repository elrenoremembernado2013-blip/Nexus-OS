#!/usr/bin/env python3
"""Validate that a QEMU guest disk stays inside NEXUS's disposable build tree."""
from __future__ import annotations

import os
import sys
from pathlib import Path


def fail(message: str) -> "None":
    print(f"QEMU disk safety abort: {message}", file=sys.stderr)
    raise SystemExit(2)


def main() -> int:
    if len(sys.argv) != 3:
        fail("usage: validate-qemu-disk-path.py BUILD_DIR DISK_PATH")

    build_arg = Path(sys.argv[1]).expanduser()
    disk_arg = Path(sys.argv[2]).expanduser()
    build = build_arg.resolve(strict=False)
    disk = disk_arg if disk_arg.is_absolute() else Path.cwd() / disk_arg

    # Refuse symlinks in the build root itself and every existing path component.
    cursor = build_arg.absolute()
    if cursor.is_symlink():
        fail("the build directory must not be a symlink")
    cursor = disk
    for component in (cursor, *cursor.parents):
        if component.exists() and component.is_symlink():
            fail(f"symlink paths are not permitted: {component}")

    resolved = disk.resolve(strict=False)
    try:
        relative = resolved.relative_to(build)
    except ValueError:
        fail(f"disk must be located inside the disposable build directory ({build})")

    if not relative.parts or resolved == build:
        fail("disk path must name a file below the build directory")
    if resolved.suffix.lower() != ".qcow2":
        fail("virtual disk path must end in .qcow2")
    if resolved.exists() and not resolved.is_file():
        fail("existing disk target is not a regular file")

    print(resolved)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
