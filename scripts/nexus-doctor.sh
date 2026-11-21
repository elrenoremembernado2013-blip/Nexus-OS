#!/bin/sh
# NEXUS OS read-only project/environment diagnostic.
# Does not install packages, edit files, configure Buildroot, or compile.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd) || {
    echo "ERROR: cannot locate repository root" >&2
    exit 2
}

ok=0
warn=0
fail=0

pass() { printf '[ OK ] %s\n' "$1"; ok=$((ok + 1)); }
note() { printf '[INFO] %s\n' "$1"; }
warning() { printf '[WARN] %s\n' "$1"; warn=$((warn + 1)); }
failure() { printf '[FAIL] %s\n' "$1"; fail=$((fail + 1)); }

printf '%s\n' 'NEXUS OS diagnostic (read-only)' '================================='
printf 'Repository: %s\n\n' "$ROOT"

if [ -f "$ROOT/README.md" ]; then
    pass "README.md exists"
else
    failure "README.md is missing"
fi

if [ -d "$ROOT/buildroot" ]; then
    pass "buildroot/ source directory exists"
else
    warning "buildroot/ source directory not found; Buildroot has not been vendored here"
fi

if [ -f "$ROOT/.config" ]; then
    pass "root .config exists"
elif [ -f "$ROOT/buildroot/.config" ]; then
    pass "buildroot/.config exists"
else
    warning "No Buildroot .config found"
fi

if [ -f "$ROOT/configs/nexus_x86_64_defconfig" ]; then
    pass "NEXUS x86-64 defconfig exists"
else
    warning "NEXUS x86-64 defconfig not yet created"
fi

if [ -d "$ROOT/board" ] || [ -d "$ROOT/configs/rootfs_overlay" ]; then
    pass "Board/overlay configuration directory found"
else
    note "No board support or root filesystem overlay directory found yet"
fi

if command -v make >/dev/null 2>&1; then
    pass "make is available"
else
    warning "make is not installed or not on PATH"
fi

if command -v gcc >/dev/null 2>&1; then
    pass "gcc is available"
else
    warning "gcc is not installed or not on PATH"
fi

qemu_found=0
for qemu in qemu-system-x86_64 qemu-system-i386; do
    if command -v "$qemu" >/dev/null 2>&1; then
        pass "$qemu is available"
        qemu_found=1
    fi
done
if [ "$qemu_found" -eq 0 ]; then
    warning "No common x86 QEMU system emulator found"
fi

if [ -f "$ROOT/buildroot/Makefile" ]; then
    note "Buildroot Makefile detected; source version should be recorded and checked manually"
else
    note "Buildroot source tree is not ready for a build from this checkout"
fi

printf '\nSummary: %s OK, %s warning(s), %s failure(s)\n' "$ok" "$warn" "$fail"
printf '%s\n' 'This is an environment check, not a build or boot test.'
[ "$fail" -eq 0 ]
