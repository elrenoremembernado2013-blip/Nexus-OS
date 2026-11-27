#!/usr/bin/env bash
# Non-destructive automated installer qualification, failure-handling, recovery,
# and cross-edition consistency test suite.
# Never formats, repartitions, or modifies host disks.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
PREFLIGHT="$REPO_ROOT/linux/installer/nexus-install-preflight.sh"
DISK_INSTALL="$REPO_ROOT/linux/installer/nexus-disk-install.sh"
LAUNCHER="$REPO_ROOT/linux/installer/nexus-installer-launcher.sh"
LITE_INSTALL="$REPO_ROOT/linux/lite/nexus-lite-install.sh"
RECOVERY="$REPO_ROOT/linux/installer/nexus-recovery.sh"

expect_fail() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'FAIL [%s]: expected non-zero exit code\n' "$desc" >&2
    exit 1
  fi
  printf 'PASS [refusal] %s\n' "$desc"
}

echo "=== NEXUS Phase 13.1 Installer Safety, Failure & Recovery Tests ==="

# 1. Preflight structured warnings & edition-aware checks
for ed in cinnamon xfce lite lite-lxqt; do
  bash "$PREFLIGHT" --edition "$ed" --json | python3 -c '
import json, sys
ed = sys.argv[1]
d = json.load(sys.stdin)
got_ed = d["edition"]
assert got_ed == ed, f"edition mismatch: {got_ed} != {ed}"
assert "environment" in d and "is_virtual_machine" in d["environment"]
assert "ram_available_mib" in d["hardware"]
assert "required_tools" in d and "requirements_satisfied" in d
for w in d.get("structured_warnings", []):
    for key in ("id", "severity", "problem", "why_it_matters", "can_continue", "recommended_action"):
        assert key in w, f"missing structured warning key: {key}"
w_cnt = len(d.get("structured_warnings", []))
b_cnt = len(d.get("blockers", []))
print(f"PASS [preflight] edition={ed} warnings={w_cnt} blockers={b_cnt}")
' "$ed"
done

# 2. Failure & refusal paths in nexus-disk-install.sh (zero disk mutations)
expect_fail "missing --disk argument" bash "$DISK_INSTALL" --dry-run
expect_fail "invalid --edition value" bash "$DISK_INSTALL" --disk /dev/vda --edition invalid_ed --dry-run
expect_fail "refuse destructive erase without --yes-erase-disk" bash "$DISK_INSTALL" --disk /dev/vda
expect_fail "incomplete manual args (--efi-part only)" bash "$DISK_INSTALL" --disk /dev/vda --efi-part /dev/vda1 --dry-run
expect_fail "incomplete manual args (--root-part only)" bash "$DISK_INSTALL" --disk /dev/vda --root-part /dev/vda2 --dry-run
expect_fail "identical --efi-part and --root-part" bash "$DISK_INSTALL" --disk /dev/vda --efi-part /dev/vda1 --root-part /dev/vda1 --dry-run
expect_fail "--keep-efi without --efi-part/--root-part" bash "$DISK_INSTALL" --disk /dev/vda --keep-efi --dry-run
expect_fail "--luks combined with --efi-part" bash "$DISK_INSTALL" --disk /dev/vda --luks --efi-part /dev/vda1 --root-part /dev/vda2 --dry-run
expect_fail "invalid hostname rejected" bash "$DISK_INSTALL" --disk /dev/vda --hostname "bad host!" --dry-run
expect_fail "invalid username rejected" bash "$DISK_INSTALL" --disk /dev/vda --user "BadUser" --dry-run

# LUKS passphrase edge cases (safe temp file)
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT
printf '   \n' > "$tmp_dir/blank-pass"
expect_fail "--luks rejects missing passphrase file when confirmed" bash "$DISK_INSTALL" --disk /dev/nexus-nonexistent --luks --yes-erase-disk
expect_fail "--luks rejects whitespace-only passphrase file" bash "$DISK_INSTALL" --disk /dev/nexus-nonexistent --luks --luks-passphrase-file "$tmp_dir/blank-pass" --yes-erase-disk

# Locale, keymap, timezone & --validate-only checks (Phase 13.2)
expect_fail "invalid --locale rejected" bash "$DISK_INSTALL" --disk /dev/vda --locale "bad locale!" --validate-only
expect_fail "invalid --keymap rejected" bash "$DISK_INSTALL" --disk /dev/vda --keymap "bad keymap" --validate-only
expect_fail "invalid --timezone rejected" bash "$DISK_INSTALL" --disk /dev/vda --timezone "../etc/passwd" --validate-only
bash "$DISK_INSTALL" --disk /dev/vda --edition lite-lxqt --locale en_US.UTF-8 --keymap us --timezone Europe/Madrid --validate-only >/dev/null
echo "PASS [config-validation] locale, keymap, timezone, and --validate-only checks verified"

# QEMU minimum & recommended profile dry-run checks + Phase 13.2A interactive safety guards
q_min_out="$(bash "$REPO_ROOT/scripts/launch-qemu.sh" --profile minimum --edition lite-lxqt --dry-run)"
printf '%s\n' "$q_min_out" | grep -Fq 'Disk size: 30G'
q_rec_out="$(bash "$REPO_ROOT/scripts/launch-qemu.sh" --profile recommended --edition xfce --disk-only --dry-run)"
printf '%s\n' "$q_rec_out" | grep -Fq 'Disk size: 50G'
expect_fail "launch-qemu refuses --reset-disk without --yes-reset-disk" bash "$REPO_ROOT/scripts/launch-qemu.sh" --reset-disk --dry-run
expect_fail "launch-qemu refuses conflicting --installer-first and --disk-only" bash "$REPO_ROOT/scripts/launch-qemu.sh" --installer-first --disk-only --dry-run
q_int_out="$(bash "$REPO_ROOT/scripts/launch-qemu.sh" --installer-first --compat-video --vnc --dry-run)"
printf '%s\n' "$q_int_out" | grep -Fq 'usb-tablet'
printf '%s\n' "$q_int_out" | grep -Fq 'Video: std'
printf '%s\n' "$q_int_out" | grep -Fq 'Display: vnc=127.0.0.1:0'
printf '%s\n' "$q_int_out" | grep -Fq 'HMP monitor socket:'
echo "PASS [vm-profiles] minimum/recommended profiles & interactive usb-tablet/VNC/monitor/reset guards verified"

# QEMU disk path containment: valid disposable paths pass; outside paths and symlinks fail.
disk_guard="$REPO_ROOT/scripts/validate-qemu-disk-path.py"
guard_root="$tmp_dir/nexus-build"
mkdir -p "$guard_root/images"
python3 "$disk_guard" "$guard_root" "$guard_root/images/safe.qcow2" >/dev/null
expect_fail "QEMU disk path outside disposable build directory rejected" python3 "$disk_guard" "$guard_root" "$tmp_dir/outside.qcow2"
ln -s "$tmp_dir" "$guard_root/escape"
expect_fail "QEMU disk path through symlink rejected" python3 "$disk_guard" "$guard_root" "$guard_root/escape/unsafe.qcow2"
expect_fail "QEMU disk path with non-qcow2 extension rejected" python3 "$disk_guard" "$guard_root" "$guard_root/images/disk.raw"
echo "PASS [qemu-disk-path] build containment, symlink, and extension guards verified"

# Existing QEMU images must be standalone qcow2 files, never backing chains.
image_guard="$REPO_ROOT/scripts/validate-qemu-image.py"
printf '%s\n' '{"format":"qcow2","virtual-size":1073741824}' | python3 "$image_guard"
printf '%s\\n' '{"format":"raw"}' > "$tmp_dir/non-qcow2.json"
printf '%s\\n' '{"format":"qcow2","backing-filename":"../../host.img"}' > "$tmp_dir/backing-image.json"
printf '%s\\n' 'not-json' > "$tmp_dir/invalid-image.json"
expect_fail "QEMU image validator rejects non-qcow2 format" python3 "$image_guard" < "$tmp_dir/non-qcow2.json"
expect_fail "QEMU image validator rejects backing filename" python3 "$image_guard" < "$tmp_dir/backing-image.json"
expect_fail "QEMU image validator rejects invalid JSON" python3 "$image_guard" < "$tmp_dir/invalid-image.json"
echo "PASS [qemu-image-metadata] qcow2 format, standalone-image, and malformed-metadata checks verified"

# Dry-run coverage across all supported modes
bash "$DISK_INSTALL" --disk /dev/vda --edition cinnamon --dry-run >/dev/null
bash "$DISK_INSTALL" --disk /dev/vda --edition xfce --dry-run >/dev/null
bash "$DISK_INSTALL" --disk /dev/vda --edition lite --luks --dry-run >/dev/null
bash "$DISK_INSTALL" --disk /dev/vda --edition lite-lxqt --efi-part /dev/vda1 --root-part /dev/vda3 --keep-efi --dry-run >/dev/null
echo "PASS [installer-modes] dry-run guided, manual, dual-boot (--keep-efi), and LUKS2 across all 4 editions"

# 3. Launcher & Lite edition consistency checks
expect_fail "launcher refuses launch without --launch" bash "$LAUNCHER"
bash "$LAUNCHER" --check >/dev/null
bash "$LAUNCHER" --dry-run >/dev/null
lite_lxqt_out="$(bash "$LITE_INSTALL" --edition lite-lxqt --dry-run)"
printf '%s\n' "$lite_lxqt_out" | grep -Fq 'Edition: lite-lxqt'
echo "PASS [edition-consistency] nexus-lite-install preserves lite-lxqt edition"

# 4. Recovery tool read-only & confirmation safety checks
bash "$RECOVERY" --diagnose --json --redacted | python3 -c '
import json, re, sys
raw = sys.stdin.read()
assert not re.search(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b", raw), "UUID leaked in redacted output"
d = json.loads(raw)
assert d["read_only"] is True
assert "efi_paths" in d and "fstab_issues" in d
print("PASS [recovery] read-only diagnosis & UUID redaction verified")
'
for topic in all backup grub fsck luks packages dualboot; do
  bash "$RECOVERY" --guide "$topic" >/dev/null
done
expect_fail "recovery --fsck-dry-run refuses execution without --confirm" bash "$RECOVERY" --fsck-dry-run --partition /dev/vda2
fsck_out="$(bash "$RECOVERY" --fsck-dry-run --partition /dev/vda2 --dry-run)"
printf '%s\n' "$fsck_out" | grep -Fq 'fsck -n /dev/vda2'
echo "PASS [recovery] guides & --fsck-dry-run confirmation guard verified"

# 5. All 4 editions provisioner dry-runs include nexus-recovery + RECOVERY_AND_BOOT.md
for prov in \
  "$REPO_ROOT/linux/mint/provision-nexus-guest.sh" \
  "$REPO_ROOT/linux/lite/provision-nexus-lite.sh" \
  "$REPO_ROOT/linux/lite/scripts/provision-nexus-lite-lxqt.sh"; do
  p_out="$(bash "$prov" --dry-run)"
  printf '%s\n' "$p_out" | grep -Fq 'nexus-recovery'
  printf '%s\n' "$p_out" | grep -Fq 'RECOVERY_AND_BOOT.md'
done
echo "PASS [provisioners] nexus-recovery and RECOVERY_AND_BOOT.md staged across all edition provisioners"
