#!/usr/bin/env bash
# Reproducible QEMU multi-RAM & disposable-disk validation runner for NEXUS OS.
# Uses strictly disposable qcow2 disks under build/qemu-test/ (never touches host disks).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="${NEXUS_ISO_OUT_DIR:-$REPO_ROOT/build/iso/out}"
TEST_DIR="${NEXUS_QEMU_TEST_DIR:-$REPO_ROOT/build/qemu-test}"

EDITION="lite"
ISO_PATH=""
RAM_LIST="512 768 1024 2048 4096"
BOOT_SECONDS=90
DRY_RUN=false

usage() {
  cat <<'USAGE'
Usage: bash linux/test/run-qemu-validation.sh [OPTIONS]

Boots a built NEXUS ISO in headless UEFI/OVMF QEMU across multiple RAM budgets
using disposable qcow2 images under build/qemu-test/, capturing serial logs.

Options:
  --edition NAME      lite | cinnamon | xfce (default: lite)
  --iso PATH          Override ISO file path
  --ram-matrix LIST   Space-separated MiB list (default: "512 768 1024 2048 4096")
  --boot-seconds SEC  Headless boot observation window per VM (default: 90)
  --dry-run           Print QEMU test plan and host readiness without launching VMs
  --help, -h          Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --edition) [[ $# -ge 2 ]] || { echo '--edition requires a value' >&2; exit 2; }; EDITION="$2"; shift 2 ;;
    --iso) [[ $# -ge 2 ]] || { echo '--iso requires a path' >&2; exit 2; }; ISO_PATH="$2"; shift 2 ;;
    --ram-matrix) [[ $# -ge 2 ]] || { echo '--ram-matrix requires a list' >&2; exit 2; }; RAM_LIST="$2"; shift 2 ;;
    --boot-seconds) [[ $# -ge 2 ]] || { echo '--boot-seconds requires seconds' >&2; exit 2; }; BOOT_SECONDS="$2"; shift 2 ;;
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
  echo "  ISO: $ISO_PATH"
  echo "  RAM matrix (MiB): $RAM_LIST"
  echo "  Disposable work dir: $TEST_DIR"
  echo "  Host prereqs check:"
  for bin in qemu-system-x86_64 qemu-img xorriso; do
    if command -v "$bin" >/dev/null 2>&1; then
      echo "    [OK] $bin"
    else
      echo "    [MISSING] $bin (install: sudo apt install -y qemu-system-x86 qemu-utils ovmf xorriso)"
    fi
  done
  exit 0
fi

for bin in qemu-system-x86_64 qemu-img; do
  command -v "$bin" >/dev/null 2>&1 || {
    printf 'Missing %s. On Ubuntu/Debian install: sudo apt install -y qemu-system-x86 qemu-utils ovmf\n' "$bin" >&2
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
echo '{"edition":"'"$EDITION"'","iso":"'"$ISO_PATH"'","accel":"'"$ACCEL"'","runs":[]}' > "$SUMMARY"

for ram_mb in $RAM_LIST; do
  run_dir="$TEST_DIR/${EDITION}-${ram_mb}m"
  mkdir -p -- "$run_dir"
  disk="$run_dir/disposable.qcow2"
  vars_copy="$run_dir/OVMF_VARS.fd"
  serial_log="$run_dir/serial.log"
  qmp_sock="$run_dir/qmp.sock"
  screendump_ppm="$run_dir/screen.ppm"
  qemu-img create -f qcow2 "$disk" 20G >/dev/null
  cp -f -- "$OVMF_VARS" "$vars_copy"
  rm -f -- "$qmp_sock" "$screendump_ppm"

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

  vm_alive=false
  if kill -0 "$qemu_pid" 2>/dev/null; then
    vm_alive=true
    python3 - "$qmp_sock" "$screendump_ppm" <<'PY' 2>/dev/null || true
import json, socket, sys
sock_path, dump_path = sys.argv[1], sys.argv[2]
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
    s.settimeout(5)
    s.connect(sock_path)
    s.recv(4096)
    s.sendall(json.dumps({"execute": "qmp_capabilities"}).encode() + b"\n")
    s.recv(4096)
    s.sendall(json.dumps({"execute": "screendump", "arguments": {"filename": dump_path}}).encode() + b"\n")
    s.recv(4096)
    s.sendall(json.dumps({"execute": "quit"}).encode() + b"\n")
PY
    sleep 2
    kill "$qemu_pid" 2>/dev/null || true
  fi
  wait "$qemu_pid" 2>/dev/null || true

  boot_marker="boot_window_elapsed_no_serial"
  if grep -qiE 'lightdm|login:|ubuntu|linuxmint|nexus' "$serial_log" 2>/dev/null; then
    boot_marker="kernel_or_userspace_reached"
  elif [[ -s "$screendump_ppm" ]]; then
    boot_marker="framebuffer_captured_inspect_ppm"
  fi
  python3 - "$SUMMARY" "$ram_mb" "$boot_marker" "$vm_alive" "$serial_log" "$screendump_ppm" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
data = json.loads(p.read_text(encoding="utf-8"))
ppm = Path(sys.argv[6])
data["runs"].append({
    "ram_mib": int(sys.argv[2]),
    "boot_marker": sys.argv[3],
    "vm_alive_at_deadline": sys.argv[4] == "true",
    "serial_log": sys.argv[5],
    "screendump_ppm": sys.argv[6] if ppm.is_file() else None,
    "screendump_bytes": ppm.stat().st_size if ppm.is_file() else 0,
})
p.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
  printf 'QEMU %s %s MiB -> %s (alive=%s, ppm=%s)\n' "$EDITION" "$ram_mb" "$boot_marker" "$vm_alive" "$screendump_ppm"
done
