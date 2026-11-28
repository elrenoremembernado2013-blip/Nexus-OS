#!/usr/bin/env bash
set -euo pipefail

# NEXUS OS Phase 13.0 Qualification Runner (Disposable QEMU/OVMF VMs Only)
# Tests simulated dual-boot/NTFS/ESP preservation (--keep-efi),
# UEFI Secure Boot signed chain (OVMF secboot + MS-enrolled VARS if present),
# and Stage A/B hardware qualification + browser WebGL/video probes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

EDITION="lite-lxqt"
ISO_PATH=""
TEST_DIR=""
RUN_DUALBOOT=false
RUN_SECURE_BOOT=false
VGA_MODE="std"
STRICT=false
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: run-phase130-tests.sh [options]
  --edition <lite-lxqt|lite|cinnamon|xfce>
  --iso <path-to-iso>
  --test-dir <work-dir>
  --dualboot-test         Simulate ESP+NTFS dual-boot disk, verify preflight detection + --keep-efi preservation
  --secure-boot-test      Boot installed disk (and live ISO) under OVMF Secure Boot (if secboot OVMF firmware present)
  --vga <std|virtio>      QEMU VGA adapter (default: std)
  --strict                Exit non-zero if dualboot or Secure Boot test fails/is skipped
  --dry-run               Validate args and print execution plan
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --edition) EDITION="$2"; shift 2 ;;
    --iso) ISO_PATH="$2"; shift 2 ;;
    --test-dir) TEST_DIR="$2"; shift 2 ;;
    --dualboot-test) RUN_DUALBOOT=true; shift ;;
    --secure-boot-test) RUN_SECURE_BOOT=true; shift ;;
    --vga) VGA_MODE="$2"; shift 2 ;;
    --strict) STRICT=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[[ -n "$ISO_PATH" ]] || ISO_PATH="$REPO_ROOT/build/iso/out/nexus-os-22.3-${EDITION}-amd64.iso"
[[ -r "$ISO_PATH" ]] || [[ ! -r "$REPO_ROOT/build/iso/nexus-os-22.3-${EDITION}-amd64.iso" ]] || ISO_PATH="$REPO_ROOT/build/iso/nexus-os-22.3-${EDITION}-amd64.iso"
[[ -n "$TEST_DIR" ]] || TEST_DIR="$REPO_ROOT/build/phase130-test-${EDITION}"

if [[ "$DRY_RUN" == true ]]; then
  printf 'Phase 13.0 dry-run: edition=%s iso=%s dualboot=%s secure_boot=%s\n' \
    "$EDITION" "$ISO_PATH" "$RUN_DUALBOOT" "$RUN_SECURE_BOOT"
  exit 0
fi

for bin in qemu-system-x86_64 qemu-img xorriso cpio gzip python3 unmkinitramfs; do
  command -v "$bin" >/dev/null 2>&1 || { printf 'Missing required tool: %s\n' "$bin" >&2; exit 1; }
done
[[ -r "$ISO_PATH" ]] || { printf 'ISO not found: %s\n' "$ISO_PATH" >&2; exit 1; }

OVMF_CODE=""
OVMF_VARS=""
for code in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2/x64/OVMF_CODE.fd; do
  [[ -r "$code" ]] || continue
  vars="${code/CODE/VARS}"
  if [[ -r "$vars" ]]; then
    OVMF_CODE="$code"
    OVMF_VARS="$vars"
    break
  fi
done
[[ -n "$OVMF_CODE" ]] || { echo 'Missing OVMF firmware.' >&2; exit 1; }

SB_CODE=""
SB_VARS=""
for scode in /usr/share/OVMF/OVMF_CODE_4M.secboot.fd /usr/share/OVMF/OVMF_CODE.secboot.fd; do
  if [[ -r "$scode" && -r /usr/share/OVMF/OVMF_VARS_4M.ms.fd ]]; then
    SB_CODE="$scode"
    SB_VARS="/usr/share/OVMF/OVMF_VARS_4M.ms.fd"
    break
  fi
done

ACCEL="tcg"
[[ -w /dev/kvm ]] && ACCEL="kvm"
QEMU_SMP="$(nproc 2>/dev/null || echo 2)"
(( QEMU_SMP > 4 )) && QEMU_SMP=4
(( QEMU_SMP < 2 )) && QEMU_SMP=2

mkdir -p -- "$TEST_DIR"
TEST_DIR="$(cd -- "$TEST_DIR" && pwd)"
ISO_PATH="$(cd -- "$(dirname -- "$ISO_PATH")" && pwd)/$(basename -- "$ISO_PATH")"

# Build ephemeral QEMU test-initrd overlay (never persisted in ISO)
overlay_dir="$TEST_DIR/initrd-${EDITION}"
rm -rf -- "$overlay_dir"
mkdir -p -- "$overlay_dir/unpacked"
casper_list="$(xorriso -indev "$ISO_PATH" -find /casper -maxdepth 1 2>/dev/null || true)"
initrd_name=""
for cand in initrd.lz initrd.gz initrd.xz initrd; do
  if printf '%s\n' "$casper_list" | grep -qE "/${cand}('|$)"; then
    initrd_name="$cand"
    break
  fi
done
[[ -n "$initrd_name" ]] || { printf 'Could not locate /casper/initrd* inside %s\n' "$ISO_PATH" >&2; exit 1; }
xorriso -osirrox on -indev "$ISO_PATH" -extract /casper/vmlinuz "$overlay_dir/vmlinuz" >/dev/null 2>&1
xorriso -osirrox on -indev "$ISO_PATH" -extract "/casper/${initrd_name}" "$overlay_dir/orig-initrd" >/dev/null 2>&1
unmkinitramfs "$overlay_dir/orig-initrd" "$overlay_dir/unpacked"
main_dir="$overlay_dir/unpacked"
[[ -d "$overlay_dir/unpacked/main" ]] && main_dir="$overlay_dir/unpacked/main"

mkdir -p -- "$main_dir/scripts/casper-bottom" "$main_dir/nexus-test"
cp -f -- "$SCRIPT_DIR/casper-test-hook.sh" "$main_dir/scripts/casper-bottom/99nexus_test_harness"
cp -f -- "$SCRIPT_DIR/guest-mem-probe.sh" "$main_dir/nexus-test/guest-mem-probe.sh"
cp -f -- "$SCRIPT_DIR/test-zram-pressure.sh" "$main_dir/nexus-test/test-zram-pressure.sh"
cp -f -- "$SCRIPT_DIR/nexus-guest-test.py" "$main_dir/nexus-test/nexus-guest-test.py"
cp -f -- "$SCRIPT_DIR/nexus-browser-bench.py" "$main_dir/nexus-test/nexus-browser-bench.py"
chmod 0755 "$main_dir/scripts/casper-bottom/99nexus_test_harness" "$main_dir/nexus-test/"*
if [[ -f "$main_dir/scripts/casper-bottom/ORDER" ]]; then
  {
    printf '/scripts/casper-bottom/99nexus_test_harness "$@"\n'
    printf '[ -e /conf/param.conf ] && . /conf/param.conf\n'
  } >> "$main_dir/scripts/casper-bottom/ORDER"
fi

: > "$overlay_dir/test-initrd.img"
for early_dir in "$overlay_dir"/unpacked/early*; do
  [[ -d "$early_dir" ]] || continue
  (cd "$early_dir" && find . -print0 | cpio --null -o -H newc --quiet >> "$overlay_dir/test-initrd.img")
done
(cd "$main_dir" && find . -print0 | cpio --null -o -H newc --quiet | gzip -1 -c >> "$overlay_dir/test-initrd.img")
rm -rf -- "$overlay_dir/unpacked" "$overlay_dir/orig-initrd"
test_vmlinuz="$overlay_dir/vmlinuz"
test_initrd="$overlay_dir/test-initrd.img"

live_cmd_json() {
  python3 - "$ACCEL" "$QEMU_SMP" "$1" "$2" "$ISO_PATH" "$test_vmlinuz" "$test_initrd" "$3" "$4" "$5" "$VGA_MODE" <<'PY'
import json, sys
accel, smp, ram, disk, iso, vml, initrd, slog, qmp, vs, vga = sys.argv[1:]
print(json.dumps([
    "qemu-system-x86_64",
    "-machine", f"q35,accel={accel}",
    "-cpu", "max", "-smp", smp, "-m", ram,
    "-drive", f"file={disk},if=virtio,format=qcow2,cache=unsafe",
    "-netdev", "user,id=n0", "-device", "virtio-net-pci,netdev=n0",
    "-vga", vga, "-display", "none",
    "-serial", f"file:{slog}",
    "-qmp", f"unix:{qmp},server,nowait",
    "-device", "virtio-serial-pci",
    "-chardev", f"socket,path={vs},server=on,wait=off,id=nexus_ch",
    "-device", "virtserialport,chardev=nexus_ch,name=org.nexus.test.0",
    "-kernel", vml, "-initrd", initrd,
    "-append", "boot=casper cdrom-detect/try-usb=true noprompt console=ttyS0,115200 ---",
    "-cdrom", iso,
]))
PY
}

installed_cmd_json() {
  local smm="$7"
  python3 - "$ACCEL" "$QEMU_SMP" "$1" "$2" "$3" "$4" "$5" "$6" "$smm" "$VGA_MODE" <<'PY'
import json, sys
accel, smp, ram, disk, ovmf_code, ovmf_vars, slog, qmp_vs_prefix, smm, vga = sys.argv[1:]
machine = f"q35,smm=on,accel={accel}" if smm == "on" else f"q35,accel={accel}"
cmd = [
    "qemu-system-x86_64",
    "-machine", machine,
    "-cpu", "max", "-smp", smp, "-m", ram,
]
if smm == "on":
    cmd += ["-global", "driver=cfi.pflash01,property=secure,value=on"]
cmd += [
    "-drive", f"if=pflash,format=raw,unit=0,readonly=on,file={ovmf_code}",
    "-drive", f"if=pflash,format=raw,unit=1,file={ovmf_vars}",
    "-drive", f"file={disk},if=virtio,format=qcow2,cache=unsafe",
    "-netdev", "user,id=n0", "-device", "virtio-net-pci,netdev=n0",
    "-vga", vga, "-display", "none",
    "-serial", f"file:{slog}",
    "-qmp", f"unix:{qmp_vs_prefix}/qmp.sock,server,nowait",
    "-device", "virtio-serial-pci",
    "-chardev", f"socket,path={qmp_vs_prefix}/vs.sock,server=on,wait=off,id=nexus_ch",
    "-device", "virtserialport,chardev=nexus_ch,name=org.nexus.test.0",
    "-boot", "order=c",
]
print(json.dumps(cmd))
PY
}

if [[ "$RUN_DUALBOOT" == true ]]; then
  dbdir="$TEST_DIR/dualboot"
  disk="$dbdir/disk.qcow2"
  vars_copy="$dbdir/OVMF_VARS.fd"
  mkdir -p -- "$dbdir/live" "$dbdir/installed"
  qemu-img create -f qcow2 "$disk" 24G >/dev/null
  cp -f -- "$OVMF_VARS" "$vars_copy"

  c_live="$(live_cmd_json 2048 "$disk" "$dbdir/live/serial.log" "$dbdir/live/qmp.sock" "$dbdir/live/vs.sock")"
  python3 "$SCRIPT_DIR/qemu-graphical-runner.py" \
    --qemu-cmd-json "$c_live" \
    --qmp-sock "$dbdir/live/qmp.sock" \
    --vserial-sock "$dbdir/live/vs.sock" \
    --out-dir "$dbdir/live" \
    --idle-seconds 15 \
    --panel-wait-sec 90 \
    --do-install \
    --install-mode dualboot \
    --timeout-seconds 2700 > "$dbdir/live-install.json" || true

  c_inst="$(installed_cmd_json 2048 "$disk" "$OVMF_CODE" "$vars_copy" "$dbdir/installed/serial.log" "$dbdir/installed" "off")"
  python3 "$SCRIPT_DIR/qemu-graphical-runner.py" \
    --qemu-cmd-json "$c_inst" \
    --qmp-sock "$dbdir/installed/qmp.sock" \
    --vserial-sock "$dbdir/installed/vs.sock" \
    --out-dir "$dbdir/installed" \
    --idle-seconds 20 \
    --panel-wait-sec 90 \
    --expected-boots 1 \
    --final-action poweroff \
    --timeout-seconds 900 > "$dbdir/installed-boot.json" || true
  rm -f -- "$disk"
fi

if [[ "$RUN_SECURE_BOOT" == true ]]; then
  sbdir="$TEST_DIR/secure-boot"
  mkdir -p -- "$sbdir/live" "$sbdir/installed"
  if [[ -z "$SB_CODE" || -z "$SB_VARS" ]]; then
    cat > "$sbdir/secure-boot-status.json" <<'JSON'
{
  "tested": false,
  "status": "NOT TESTED",
  "reason": "secboot_ovmf_firmware_unavailable"
}
JSON
  else
    disk="$sbdir/disk.qcow2"
    vars_copy="$sbdir/OVMF_VARS_4M.ms.fd"
    qemu-img create -f qcow2 "$disk" 24G >/dev/null
    cp -f -- "$SB_VARS" "$vars_copy"

    # Install guided GPT+UEFI onto disposable disk
    c_live="$(live_cmd_json 2048 "$disk" "$sbdir/live/serial.log" "$sbdir/live/qmp.sock" "$sbdir/live/vs.sock")"
    python3 "$SCRIPT_DIR/qemu-graphical-runner.py" \
      --qemu-cmd-json "$c_live" \
      --qmp-sock "$sbdir/live/qmp.sock" \
      --vserial-sock "$sbdir/live/vs.sock" \
      --out-dir "$sbdir/live" \
      --idle-seconds 15 \
      --panel-wait-sec 90 \
      --do-install \
      --install-mode guided \
      --timeout-seconds 2700 > "$sbdir/live-install.json" || true

    # Boot installed disk under ENFORCED OVMF Secure Boot (smm=on, Microsoft UEFI CA VARS)
    c_sb="$(installed_cmd_json 2048 "$disk" "$SB_CODE" "$vars_copy" "$sbdir/installed/serial.log" "$sbdir/installed" "on")"
    python3 "$SCRIPT_DIR/qemu-graphical-runner.py" \
      --qemu-cmd-json "$c_sb" \
      --qmp-sock "$sbdir/installed/qmp.sock" \
      --vserial-sock "$sbdir/installed/vs.sock" \
      --out-dir "$sbdir/installed" \
      --idle-seconds 20 \
      --panel-wait-sec 90 \
      --expected-boots 1 \
      --final-action poweroff \
      --timeout-seconds 900 > "$sbdir/installed-sb-boot.json" || true
    rm -f -- "$disk"
  fi
fi

SUMMARY_JSON="$TEST_DIR/phase130-results-${EDITION}.json"
python3 - "$TEST_DIR" "$EDITION" "$ACCEL" "$SUMMARY_JSON" <<'PY'
import json, sys
from pathlib import Path

tdir = Path(sys.argv[1])
edition = sys.argv[2]
accel = sys.argv[3]
out_path = Path(sys.argv[4])

def load_json(p):
    try:
        return json.loads(Path(p).read_text(encoding="utf-8"))
    except Exception:
        return {}

summary = {
    "edition": edition,
    "accel": accel,
    "dualboot_test": {},
    "secure_boot_test": {},
}

dbdir = tdir / "dualboot"
if dbdir.is_dir():
    live = load_json(dbdir / "live-install.json")
    inst = load_json(dbdir / "installed-boot.json")
    ir = (live.get("guest_report") or {}).get("install_report") or {}
    ic = (inst.get("guest_report") or {}).get("installed_checks") or {}
    summary["dualboot_test"] = {
        "install_success": bool(ir.get("install_success")),
        "simulated_os_fs": ir.get("simulated_os_fs"),
        "dualboot_preflight_detected": ir.get("dualboot_preflight_detected"),
        "dualboot_efi_preserved_install": ir.get("dualboot_efi_preserved"),
        "dualboot_os_part_preserved_install": ir.get("dualboot_os_part_preserved"),
        "installed_boot_ok": bool(ic.get("booted_from_vda") and ic.get("live_iso_absent")),
        "dualboot_efi_preserved_after_boot": ic.get("dualboot_efi_preserved"),
        "dualboot_os_part_preserved_after_boot": ic.get("dualboot_os_part_preserved"),
        "failed_systemd_units": ic.get("failed_systemd_units"),
    }

sbdir = tdir / "secure-boot"
if sbdir.is_dir():
    st = load_json(sbdir / "secure-boot-status.json")
    if st:
        summary["secure_boot_test"] = st
    else:
        live = load_json(sbdir / "live-install.json")
        inst = load_json(sbdir / "installed-sb-boot.json")
        ir = (live.get("guest_report") or {}).get("install_report") or {}
        ic = (inst.get("guest_report") or {}).get("installed_checks") or {}
        hw = ic.get("hw_summary") or {}
        summary["secure_boot_test"] = {
            "tested": True,
            "install_success": bool(ir.get("install_success")),
            "installed_boot_ok": bool(ic.get("booted_from_vda") and ic.get("live_iso_absent")),
            "secure_boot_state": hw.get("secure_boot"),
            "secure_boot_chain": hw.get("secure_boot_chain") or {},
            "efi_boot_ok": ic.get("efi_boot_ok"),
            "failed_systemd_units": ic.get("failed_systemd_units"),
            "live_diag": {
                "desktop_failed": live.get("desktop_failed"),
                "install_reason": ir.get("reason"),
                "install_rc": ir.get("returncode"),
                "stderr_tail": (ir.get("stderr_tail") or [])[-5:],
            } if not ir.get("install_success") else None,
            "inst_diag": {
                "desktop_failed": inst.get("desktop_failed"),
                "vm_exited_cleanly": inst.get("vm_exited_cleanly"),
                "cycles": len(inst.get("boot_cycles") or []),
            } if not (ic.get("booted_from_vda") and ic.get("live_iso_absent")) else None,
        }

out_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
print(json.dumps(summary, indent=2))
PY

if [[ "$STRICT" == true ]]; then
  python3 - "$TEST_DIR/phase130-summary-${EDITION}.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
bad = []
db = d.get("dualboot_test") or {}
if db and not (db.get("install_success") and db.get("installed_boot_ok") and db.get("dualboot_efi_preserved_after_boot") and db.get("dualboot_os_part_preserved_after_boot")):
    bad.append("dualboot")
sb = d.get("secure_boot_test") or {}
if sb and (not sb.get("tested") or not sb.get("install_success") or not sb.get("installed_boot_ok") or sb.get("secure_boot_state") != "enabled"):
    bad.append(f"secure_boot:{sb.get('reason') or sb.get('secure_boot_state')}")
if bad:
    raise SystemExit(f"Phase 13.0 STRICT FAIL: {bad}")
PY
fi
