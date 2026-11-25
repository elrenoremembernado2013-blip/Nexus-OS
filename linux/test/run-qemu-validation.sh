#!/usr/bin/env bash
# Reproducible QEMU multi-RAM, UEFI boot, and graphical desktop validation runner.
# Uses strictly disposable qcow2 disks under build/qemu-test/ (never touches host disks).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="${NEXUS_ISO_OUT_DIR:-$REPO_ROOT/build/iso/out}"
TEST_DIR="${NEXUS_QEMU_TEST_DIR:-$REPO_ROOT/build/qemu-test}"

EDITION="lite"
ISO_PATH=""
RAM_LIST="512 768 1024 2048 4096"
BOOT_SECONDS=45
IDLE_SECONDS=30
PRIMARY_IDLE_SECONDS=300
GRAPHICAL=false
DRY_RUN=false

usage() {
  cat <<'USAGE'
Usage: bash linux/test/run-qemu-validation.sh [OPTIONS]

Runs UEFI/OVMF ISO boot checks and (with --graphical) full virtio-serial + QMP
graphical desktop validation, 6-stage guest RAM probes, ZRAM tests, and PNG captures.

Options:
  --edition NAME          lite | cinnamon | xfce (default: lite)
  --iso PATH              Override ISO file path
  --ram-matrix LIST       Space-separated MiB list (default: "512 768 1024 2048 4096")
  --boot-seconds SEC      UEFI boot check window in seconds (default: 45)
  --idle-seconds SEC      Secondary-tier guest idle probe window (default: 30)
  --primary-idle SEC      Primary-tier guest idle probe window (default: 300)
  --graphical             Enable virtio-serial + QMP graphical desktop & memory suite
  --dry-run               Print QEMU validation plan without launching VMs
  --help, -h              Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --edition) [[ $# -ge 2 ]] || { echo '--edition requires a value' >&2; exit 2; }; EDITION="$2"; shift 2 ;;
    --iso) [[ $# -ge 2 ]] || { echo '--iso requires a path' >&2; exit 2; }; ISO_PATH="$2"; shift 2 ;;
    --ram-matrix) [[ $# -ge 2 ]] || { echo '--ram-matrix requires a list' >&2; exit 2; }; RAM_LIST="$2"; shift 2 ;;
    --boot-seconds) [[ $# -ge 2 ]] || { echo '--boot-seconds requires seconds' >&2; exit 2; }; BOOT_SECONDS="$2"; shift 2 ;;
    --idle-seconds) [[ $# -ge 2 ]] || { echo '--idle-seconds requires seconds' >&2; exit 2; }; IDLE_SECONDS="$2"; shift 2 ;;
    --primary-idle) [[ $# -ge 2 ]] || { echo '--primary-idle requires seconds' >&2; exit 2; }; PRIMARY_IDLE_SECONDS="$2"; shift 2 ;;
    --graphical) GRAPHICAL=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$ISO_PATH" ]]; then
  case "$EDITION" in
    lite) ISO_PATH="$OUT_DIR/nexus-os-22.3-lite-amd64.iso" ;;
    cinnamon|standard) ISO_PATH="$OUT_DIR/nexus-os-22.3-cinnamon-amd64.iso" ;;
    xfce) ISO_PATH="$OUT_DIR/nexus-os-22.3-xfce-amd64.iso" ;;
    *) printf 'Unsupported --edition: %s\n' "$EDITION" >&2; exit 2 ;;
  esac
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "NEXUS QEMU Multi-RAM Validation Plan (dry-run)"
  echo "  Edition: $EDITION"
  echo "  Graphical mode: $GRAPHICAL"
  echo "  ISO: $ISO_PATH"
  echo "  RAM matrix (MiB): $RAM_LIST"
  echo "  Disposable work dir: $TEST_DIR"
  echo "  Host prereqs check:"
  for bin in qemu-system-x86_64 qemu-img xorriso cpio gzip; do
    if command -v "$bin" >/dev/null 2>&1; then
      echo "    [OK] $bin"
    else
      echo "    [MISSING] $bin (install: sudo apt install -y qemu-system-x86 qemu-utils ovmf xorriso)"
    fi
  done
  exit 0
fi

for bin in qemu-system-x86_64 qemu-img xorriso cpio gzip python3 unmkinitramfs; do
  command -v "$bin" >/dev/null 2>&1 || {
    printf 'Missing %s. On Ubuntu/Debian install: sudo apt install -y qemu-system-x86 qemu-utils ovmf xorriso initramfs-tools-core zstd xz-utils\n' "$bin" >&2
    exit 1
  }
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
[[ -n "$OVMF_CODE" ]] || { echo 'Missing OVMF firmware (install ovmf package).' >&2; exit 1; }

ACCEL="tcg"
[[ -w /dev/kvm ]] && ACCEL="kvm"

mkdir -p -- "$TEST_DIR"
SUMMARY="$TEST_DIR/qemu-results-${EDITION}.json"
echo '{"edition":"'"$EDITION"'","iso":"'"$ISO_PATH"'","accel":"'"$ACCEL"'","graphical":'"$GRAPHICAL"',"runs":[]}' > "$SUMMARY"

test_vmlinuz=""
test_initrd=""
overlay_dir=""
if [[ "$GRAPHICAL" == true ]]; then
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
  [[ -n "$initrd_name" ]] || { printf 'Could not locate /casper/initrd* inside %s (found: %s)\n' "$ISO_PATH" "$casper_list" >&2; exit 1; }
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
fi

for ram_mb in $RAM_LIST; do
  run_dir="$TEST_DIR/${EDITION}-${ram_mb}m"
  mkdir -p -- "$run_dir"
  disk="$run_dir/disposable.qcow2"
  vars_copy="$run_dir/OVMF_VARS.fd"
  serial_log="$run_dir/serial.log"
  qmp_sock="$run_dir/qmp.sock"
  screendump_ppm="$run_dir/uefi_boot.ppm"
  screendump_png="$run_dir/uefi_boot.png"
  qemu-img create -f qcow2 "$disk" 20G >/dev/null
  cp -f -- "$OVMF_VARS" "$vars_copy"
  rm -f -- "$qmp_sock" "$screendump_ppm" "$screendump_png"

  # Stage 1: UEFI/OVMF direct ISO boot check (proves unmodified ISO boots via GRUB/EFI)
  qemu-system-x86_64 \
    -machine "q35,accel=${ACCEL}" -cpu max -smp 2 -m "$ram_mb" \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=${OVMF_CODE}" \
    -drive "if=pflash,format=raw,unit=1,file=${vars_copy}" \
    -drive "file=${disk},if=virtio,format=qcow2" \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -vga std -display none -serial "file:${serial_log}" \
    -qmp "unix:${qmp_sock},server,nowait" \
    -cdrom "$ISO_PATH" -boot order=d >/dev/null 2>&1 &
  qemu_pid=$!
  sleep "$BOOT_SECONDS"

  uefi_alive=false
  if kill -0 "$qemu_pid" 2>/dev/null; then
    uefi_alive=true
    python3 - "$qmp_sock" "$screendump_ppm" <<'PY' 2>/dev/null || true
import json, socket, sys
sock_path, ppm = sys.argv[1], sys.argv[2]
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
    s.settimeout(5)
    s.connect(sock_path)
    s.recv(4096)
    s.sendall(b'{"execute":"qmp_capabilities"}\n'); s.recv(4096)
    s.sendall(json.dumps({"execute":"screendump","arguments":{"filename":ppm}}).encode()+b"\n"); s.recv(4096)
    s.sendall(b'{"execute":"quit"}\n')
PY
    sleep 2
    kill "$qemu_pid" 2>/dev/null || true
  fi
  wait "$qemu_pid" 2>/dev/null || true

  # Stage 2: Graphical desktop + GUI automation + 6-stage memory + ZRAM test via ephemeral initrd overlay
  graphical_json="$run_dir/graphical-result.json"
  if [[ "$GRAPHICAL" == true ]]; then
    idle_sec="$IDLE_SECONDS"
    if [[ "$EDITION" == "lite" && ( "$ram_mb" == "512" || "$ram_mb" == "1024" ) ]]; then
      idle_sec="$PRIMARY_IDLE_SECONDS"
    elif [[ "$EDITION" != "lite" && "$ram_mb" == "4096" ]]; then
      idle_sec="$PRIMARY_IDLE_SECONDS"
    fi
    timeout_sec=$(( idle_sec + 420 ))
    vserial_sock="$run_dir/vserial.sock"
    gqmp_sock="$run_dir/gqmp.sock"
    gserial_log="$run_dir/graphical-serial.log"
    rm -f -- "$vserial_sock" "$gqmp_sock" "$graphical_json"
    cmd_json="$(python3 - "$ACCEL" "$ram_mb" "$disk" "$ISO_PATH" "$test_vmlinuz" "$test_initrd" "$gserial_log" "$gqmp_sock" "$vserial_sock" <<'PY'
import json, sys
accel, ram, disk, iso, vml, initrd, slog, qmp, vs = sys.argv[1:]
print(json.dumps([
    "qemu-system-x86_64",
    "-machine", f"q35,accel={accel}",
    "-cpu", "max", "-smp", "2", "-m", ram,
    "-drive", f"file={disk},if=virtio,format=qcow2",
    "-netdev", "user,id=n0", "-device", "virtio-net-pci,netdev=n0",
    "-vga", "std", "-display", "none",
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
)"
    python3 "$SCRIPT_DIR/qemu-graphical-runner.py" \
      --qemu-cmd-json "$cmd_json" \
      --qmp-sock "$gqmp_sock" \
      --vserial-sock "$vserial_sock" \
      --out-dir "$run_dir" \
      --idle-seconds "$idle_sec" \
      --timeout-seconds "$timeout_sec" > "$graphical_json" || true
  fi

  python3 - "$SUMMARY" "$ram_mb" "$uefi_alive" "$serial_log" "$screendump_ppm" "$screendump_png" "$graphical_json" "$SCRIPT_DIR" <<'PY'
import importlib.util, json, sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("qgr", str(Path(sys.argv[8]) / "qemu-graphical-runner.py"))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

summary_path = Path(sys.argv[1])
ram_mb = int(sys.argv[2])
uefi_alive = sys.argv[3] == "true"
serial_log = Path(sys.argv[4])
uefi_ppm = Path(sys.argv[5])
uefi_png = Path(sys.argv[6])
graphical_json = Path(sys.argv[7])

uefi_shot = {"non_black_pct": 0.0, "png": None}
if uefi_ppm.is_file():
    uefi_shot = runner.ppm_to_png_and_stats(uefi_ppm, uefi_png)

gdata = {}
if graphical_json.is_file() and graphical_json.read_text(encoding="utf-8").strip():
    try:
        gdata = json.loads(graphical_json.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        gdata = {}

gr = gdata.get("guest_report") or {}
desk = gr.get("desktop") or {}
apps = gr.get("apps") or {}
stages = gr.get("stages") or {}
zram_p = gr.get("zram_pressure") or {}

entry = {
    "ram_mib": ram_mb,
    "uefi_boot_success": uefi_alive and (uefi_shot.get("non_black_pct", 0) > 0 or serial_log.stat().st_size > 0 if serial_log.is_file() else uefi_alive),
    "uefi_boot_screenshot": uefi_shot,
    "login_success": bool(desk.get("lightdm_active") and desk.get("user")),
    "graphical_session_success": bool(desk.get("wm") and desk.get("panel_running")),
    "application_test_success": bool(
        apps.get("file_manager", {}).get("window_verified")
        and apps.get("terminal", {}).get("window_verified")
    ),
    "memory_test_success": len(stages) >= 6,
    "zram_test_success": zram_p.get("status") == "PASS",
    "installation_preflight_success": bool(gr.get("lsblk_vda_present")),
    "desktop": desk,
    "apps": apps,
    "stages": stages,
    "network": gr.get("network"),
    "zram_status": gr.get("zram_status"),
    "zram_pressure": zram_p,
    "installer_preflight": gr.get("installer_preflight"),
    "ubiquity_present": gr.get("ubiquity_present"),
    "screenshots": gdata.get("screenshots", []),
    "desktop_failed": gdata.get("desktop_failed"),
}

data = json.loads(summary_path.read_text(encoding="utf-8"))
data["runs"].append(entry)
summary_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
  rm -f -- "$disk"
  printf 'QEMU %s %s MiB validation finished.\n' "$EDITION" "$ram_mb"
done

[[ -n "$overlay_dir" ]] && rm -rf -- "$overlay_dir"
