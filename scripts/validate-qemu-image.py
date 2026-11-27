#!/usr/bin/env python3
"""Validate qemu-img metadata before a disposable NEXUS disk is attached."""
import json
import sys


def main() -> int:
    try:
        info = json.load(sys.stdin)
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        print(f"QEMU disk safety abort: invalid qemu-img JSON: {exc}", file=sys.stderr)
        return 2

    if not isinstance(info, dict) or info.get("format") != "qcow2":
        print("QEMU disk safety abort: existing disk is not a qcow2 image", file=sys.stderr)
        return 2

    # A backing chain can cause QEMU to read files outside build/, even when
    # the top-level image itself is safely contained under the disposable root.
    if info.get("backing-filename") or info.get("full-backing-filename"):
        print("QEMU disk safety abort: qcow2 backing files are not permitted", file=sys.stderr)
        return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
