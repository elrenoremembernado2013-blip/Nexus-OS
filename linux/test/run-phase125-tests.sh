#!/usr/bin/env bash
set -euo pipefail

# NEXUS OS Phase 12.5 Qualification Runner (Disposable QEMU/OVMF VMs Only)
# Runs separated unencrypted installer qualification (manual, recovery),
# interactive LUKS2 cold-boot qualification, and Falkon vs Firefox browser benchmarks.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

EDITION="lite-lxqt"
ISO_PATH=""
TEST_DIR=""
RUN_MANUAL=false
RUN_RECOVERY=false
RUN_LUKS=false
RUN_BROWSER_BENCH=false
BENCH_TIERS="1024 2048 4096"
VGA_MODE="std"
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: run-phase125-tests.sh [options]
  --edition <lite-lxqt|lite|cinnamon|xfce>
  --iso <path-to-iso>
  --test-dir <work-dir>
  --manual-test           Test manual pre-partitioned GPT install + extra partition preservation
  --recovery-test         Test unconfirmed-guard refusal + stale mount recovery install
  --luks-test             Test interactive LUKS2 install + cold-boot wrong/valid unlock + persistence
  --browser-bench         Run Falkon vs Firefox benchmark on installed disposable disk
  --bench-ram-tiers "..." Space-separated RAM tiers in MiB (default: "1024 2048 4096")
  --vga <std|virtio>      QEMU VGA adapter (default: std)
  --dry-run               Validate args and print execution plan
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --edition) EDITION="$2"; shift 2 ;;
    --iso) ISO_PATH="$2"; shift 2 ;;
    --test-dir) TEST_DIR="$2"; shift 2 ;;
    --manual-test) RUN_MANUAL=true; shift ;;
    --recovery-test) RUN_RECOVERY=true; shift ;;
    --luks-test) RUN_LUKS=true; shift ;;
    --browser-bench) RUN_BROWSER_BENCH=true; shift ;;
    --bench-ram-tiers) BENCH_TIERS="$2"; shift 2 ;;
    --vga) VGA_MODE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[[ -n "$ISO_PATH" ]] || ISO_PATH="$REPO_ROOT/build/iso/out/nexus-os-22.3-${EDITION}-amd64.iso"
[[ -r "$ISO_PATH" ]] || [[ ! -r "$REPO_ROOT/build/iso/nexus-os-22.3-${EDITION}-amd64.iso" ]] || ISO_PATH="$REPO_ROOT/build/iso/nexus-os-22.3-${EDITION}-amd64.iso"
[[ -n "$TEST_DIR" ]] || TEST_DIR="$REPO_ROOT/build/phase125-test-${EDITION}"

if [[ "$DRY_RUN" == true ]]; then
  printf 'Phase 12.5 dry-run: edition=%s iso=%s manual=%s recovery=%s luks=%s browser_bench=%s tiers="%s"\n' \
    "$EDITION" "$ISO_PATH" "$RUN_MANUAL" "$RUN_RECOVERY" "$RUN_LUKS" "$RUN_BROWSER_BENCH" "$BENCH_TIERS"
  exit 0
fi

for bin in qemu-system-x86_64 qemu-img xorriso cpio gzip python3 unmkinitramfs openssl; do
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
  local serial_arg="$4"
  python3 - "$ACCEL" "$QEMU_SMP" "$1" "$2" "$OVMF_CODE" "$3" "$serial_arg" "$5" "$6" "$VGA_MODE" <<'PY'
import json, sys
accel, smp, ram, disk, ovmf_code, ovmf_vars, serial_arg, qmp, vs, vga = sys.argv[1:]
print(json.dumps([
    "qemu-system-x86_64",
    "-machine", f"q35,accel={accel}",
    "-cpu", "max", "-smp", smp, "-m", ram,
    "-drive", f"if=pflash,format=raw,unit=0,readonly=on,file={ovmf_code}",
    "-drive", f"if=pflash,format=raw,unit=1,file={ovmf_vars}",
    "-drive", f"file={disk},if=virtio,format=qcow2,cache=unsafe",
    "-netdev", "user,id=n0", "-device", "virtio-net-pci,netdev=n0",
    "-vga", vga, "-display", "none",
    "-serial", serial_arg,
    "-qmp", f"unix:{qmp},server,nowait",
    "-device", "virtio-serial-pci",
    "-chardev", f"socket,path={vs},server=on,wait=off,id=nexus_ch",
    "-device", "virtserialport,chardev=nexus_ch,name=org.nexus.test.0",
    "-boot", "order=c",
]))
PY
}

run_installer_variant() {
  local mode="$1"
  local vdir="$TEST_DIR/installer-${mode}"
  local disk="$vdir/disk.qcow2"
  local vars_copy="$vdir/OVMF_VARS.fd"
  mkdir -p -- "$vdir/live" "$vdir/installed"
  qemu-img create -f qcow2 "$disk" 24G >/dev/null
  cp -f -- "$OVMF_VARS" "$vars_copy"

  local pw_file=""
  local extra_runner=()
  if [[ "$mode" == "luks" ]]; then
    pw_file="$vdir/.ephemeral-luks-pw"
    openssl rand -base64 18 > "$pw_file"
    chmod 0600 "$pw_file"
    extra_runner=(--luks-passphrase-file "$pw_file")
  fi

  local c_live
  c_live="$(live_cmd_json 2048 "$disk" "$vdir/live/serial.log" "$vdir/live/qmp.sock" "$vdir/live/vs.sock")"
  python3 "$SCRIPT_DIR/qemu-graphical-runner.py" \
    --qemu-cmd-json "$c_live" \
    --qmp-sock "$vdir/live/qmp.sock" \
    --vserial-sock "$vdir/live/vs.sock" \
    --out-dir "$vdir/live" \
    --idle-seconds 15 \
    --panel-wait-sec 90 \
    --do-install \
    --install-mode "$mode" \
    "${extra_runner[@]}" \
    --timeout-seconds 2700 > "$vdir/live-install.json" || true

  if [[ "$mode" == "luks" ]]; then
    local c_luks
    c_luks="$(installed_cmd_json 2048 "$disk" "$vars_copy" "unix:$vdir/installed/serial.sock,server,nowait" "$vdir/installed/qmp.sock" "$vdir/installed/vs.sock")"
    python3 "$SCRIPT_DIR/qemu-graphical-runner.py" \
      --qemu-cmd-json "$c_luks" \
      --qmp-sock "$vdir/installed/qmp.sock" \
      --vserial-sock "$vdir/installed/vs.sock" \
      --serial-sock "$vdir/installed/serial.sock" \
      --luks-passphrase-file "$pw_file" \
      --luks-test-wrong-pass \
      --out-dir "$vdir/installed" \
      --idle-seconds 20 \
      --panel-wait-sec 90 \
      --expected-boots 2 \
      --final-action poweroff \
      --timeout-seconds 1500 > "$vdir/installed-boot.json" || true
    rm -f -- "$pw_file"
  else
    local c_inst
    c_inst="$(installed_cmd_json 2048 "$disk" "$vars_copy" "file:$vdir/installed/serial.log" "$vdir/installed/qmp.sock" "$vdir/installed/vs.sock")"
    python3 "$SCRIPT_DIR/qemu-graphical-runner.py" \
      --qemu-cmd-json "$c_inst" \
      --qmp-sock "$vdir/installed/qmp.sock" \
      --vserial-sock "$vdir/installed/vs.sock" \
      --out-dir "$vdir/installed" \
      --idle-seconds 20 \
      --panel-wait-sec 90 \
      --expected-boots 1 \
      --final-action poweroff \
      --timeout-seconds 900 > "$vdir/installed-boot.json" || true
  fi
  rm -f -- "$disk"
}

if [[ "$RUN_MANUAL" == true ]]; then
  run_installer_variant "manual"
fi

if [[ "$RUN_RECOVERY" == true ]]; then
  run_installer_variant "recovery"
fi

if [[ "$RUN_LUKS" == true ]]; then
  run_installer_variant "luks"
fi

if [[ "$RUN_BROWSER_BENCH" == true ]]; then
  bdir="$TEST_DIR/browser-bench"
  base_disk="$bdir/base-with-browsers.qcow2"
  mkdir -p -- "$bdir/install" "$bdir/prep"
  qemu-img create -f qcow2 "$base_disk" 24G >/dev/null
  cp -f -- "$OVMF_VARS" "$bdir/prep/OVMF_VARS.fd"

  c_live="$(live_cmd_json 2048 "$base_disk" "$bdir/install/serial.log" "$bdir/install/qmp.sock" "$bdir/install/vs.sock")"
  python3 "$SCRIPT_DIR/qemu-graphical-runner.py" \
    --qemu-cmd-json "$c_live" \
    --qmp-sock "$bdir/install/qmp.sock" \
    --vserial-sock "$bdir/install/vs.sock" \
    --out-dir "$bdir/install" \
    --idle-seconds 15 \
    --panel-wait-sec 90 \
    --do-install \
    --install-mode guided \
    --timeout-seconds 2700 > "$bdir/base-install.json" || true

  # Boot 1 on disposable disk: install falkon + firefox inside test VM only, then poweroff cleanly
  c_prep="$(installed_cmd_json 2048 "$base_disk" "$bdir/prep/OVMF_VARS.fd" "file:$bdir/prep/serial.log" "$bdir/prep/qmp.sock" "$bdir/prep/vs.sock")"
  python3 "$SCRIPT_DIR/qemu-graphical-runner.py" \
    --qemu-cmd-json "$c_prep" \
    --qmp-sock "$bdir/prep/qmp.sock" \
    --vserial-sock "$bdir/prep/vs.sock" \
    --out-dir "$bdir/prep" \
    --idle-seconds 15 \
    --panel-wait-sec 90 \
    --install-browsers \
    --expected-boots 1 \
    --final-action poweroff \
    --timeout-seconds 1200 > "$bdir/browser-prep.json" || true

  for ram_mb in $BENCH_TIERS; do
    tdir="$bdir/tier-${ram_mb}m"
    mkdir -p -- "$tdir"
    tier_disk="$tdir/tier.qcow2"
    cp -f -- "$base_disk" "$tier_disk"
    cp -f -- "$OVMF_VARS" "$tdir/OVMF_VARS.fd"
    c_bench="$(installed_cmd_json "$ram_mb" "$tier_disk" "$tdir/OVMF_VARS.fd" "file:$tdir/serial.log" "$tdir/qmp.sock" "$tdir/vs.sock")"
    python3 "$SCRIPT_DIR/qemu-graphical-runner.py" \
      --qemu-cmd-json "$c_bench" \
      --qmp-sock "$tdir/qmp.sock" \
      --vserial-sock "$tdir/vs.sock" \
      --out-dir "$tdir" \
      --idle-seconds 15 \
      --panel-wait-sec 90 \
      --browser-bench \
      --expected-boots 1 \
      --final-action poweroff \
      --timeout-seconds 1200 > "$tdir/bench-result.json" || true
    rm -f -- "$tier_disk"
  done
  rm -f -- "$base_disk"
fi

# Aggregate Phase 12.5 JSON summary cleanly separated into unencrypted vs luks_encrypted vs browser_bench
SUMMARY_JSON="$TEST_DIR/phase125-results-${EDITION}.json"
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
    "unencrypted_installer_tests": {},
    "luks_encrypted_installer_tests": {},
    "browser_benchmarks": {},
}

for mode in ("manual", "recovery"):
    mdir = tdir / f"installer-{mode}"
    if mdir.is_dir():
        live = load_json(mdir / "live-install.json")
        inst = load_json(mdir / "installed-boot.json")
        ir = (live.get("guest_report") or {}).get("install_report") or {}
        ic = (inst.get("guest_report") or {}).get("installed_checks") or {}
        per = (inst.get("guest_report") or {}).get("persistence") or {}
        summary["unencrypted_installer_tests"][mode] = {
            "install_success": bool(ir.get("install_success")),
            "elapsed_sec": ir.get("elapsed_sec"),
            "refused_without_confirm": ir.get("refused_without_confirm"),
            "dirty_mount_created": ir.get("dirty_mount_created"),
            "manual_extra_part_preserved": ir.get("manual_extra_part_preserved"),
            "installed_boot_ok": bool(ic.get("booted_from_vda") and ic.get("live_iso_absent")),
            "extra_partition_preserved_after_boot": ic.get("extra_partition_preserved"),
            "persistence_verified": per.get("persistence_verified"),
            "failed_systemd_units": ic.get("failed_systemd_units"),
        }

ldir = tdir / "installer-luks"
if ldir.is_dir():
    live = load_json(ldir / "live-install.json")
    inst = load_json(ldir / "installed-boot.json")
    ir = (live.get("guest_report") or {}).get("install_report") or {}
    cycles = inst.get("boot_cycles") or []
    c1 = (cycles[0].get("guest_report") or {}) if len(cycles) >= 1 else {}
    c2 = (cycles[1].get("guest_report") or {}) if len(cycles) >= 2 else {}
    ic1 = c1.get("installed_checks") or {}
    ic2 = c2.get("installed_checks") or {}
    per2 = c2.get("persistence") or {}
    summary["luks_encrypted_installer_tests"] = {
        "install_success": bool(ir.get("install_success")),
        "elapsed_sec": ir.get("elapsed_sec"),
        "crypto_luks_blkid": ir.get("crypto_luks_blkid"),
        "crypttab_ok": ir.get("crypttab_ok"),
        "luks_recovery_guide_ok": ir.get("luks_recovery_guide_ok"),
        "luks_unlock_diag": inst.get("luks_unlock_diag") or {},
        "boot1_from_luks": bool(ic1.get("booted_from_luks")),
        "boot1_recovery_guide_present": bool(ic1.get("luks_recovery_guide_present")),
        "boot2_from_luks": bool(ic2.get("booted_from_luks")),
        "boot2_persistence_verified": bool(per2.get("persistence_verified")),
        "boot_cycles_completed": len(cycles),
    }

bdir = tdir / "browser-bench"
if bdir.is_dir():
    prep = load_json(bdir / "browser-prep.json")
    pic = (prep.get("guest_report") or {}).get("installed_checks") or {}
    tiers = {}
    for t in sorted(bdir.glob("tier-*m")):
        res = load_json(t / "bench-result.json")
        bb = (res.get("guest_report") or {}).get("browser_bench") or {}
        tiers[t.name.replace("tier-", "")] = bb
    summary["browser_benchmarks"] = {
        "browsers_installed_rc": pic.get("browsers_installed_rc"),
        "falkon_bin": pic.get("falkon_bin"),
        "firefox_bin": pic.get("firefox_bin"),
        "tiers": tiers,
    }

out_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
print(json.dumps(summary, indent=2))
PY
