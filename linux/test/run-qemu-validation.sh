#!/usr/bin/env bash
# Reproducible QEMU multi-RAM, UEFI boot, graphical desktop, installation,
# and post-install multi-reboot validation runner.
# Strictly uses disposable qcow2 disks under build/qemu-test/ (never host disks).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="${NEXUS_ISO_OUT_DIR:-$REPO_ROOT/build/iso/out}"
TEST_DIR="${NEXUS_QEMU_TEST_DIR:-$REPO_ROOT/build/qemu-test}"

EDITION="lite"
ISO_PATH=""
RAM_LIST="512 768 1024 2048 4096"
INSTALL_RAM_LIST=""
BOOT_SECONDS=35
IDLE_SECONDS=30
PRIMARY_IDLE_SECONDS=120
GRAPHICAL=false
INSTALL_TEST=false
RELIABILITY=false
BIOS_CHECK="auto"
VGA_MODE="std"
DRY_RUN=false

usage() {
  cat <<'USAGE'
Usage: bash linux/test/run-qemu-validation.sh [OPTIONS]

Runs UEFI/OVMF and Legacy BIOS ISO boot checks, graphical live tests, disposable-disk installation,
and post-install multi-reboot validation without the live ISO.

Options:
  --edition NAME            lite | lite-lxqt | cinnamon | xfce (default: lite)
  --iso PATH                Override ISO file path
  --ram-matrix LIST         Space-separated MiB list (default: "512 768 1024 2048 4096")
  --install-ram-matrix LIST Optional subset of MiB tiers to install + 3-reboot test
  --boot-seconds SEC        Firmware ISO boot check window in seconds (default: 35)
  --idle-seconds SEC        Secondary-tier guest idle probe window (default: 30)
  --primary-idle SEC        Primary-tier guest idle probe window (default: 120)
  --graphical               Enable virtio-serial + QMP live graphical & memory suite
  --install-test            Install onto disposable qcow2 and run 3 installed-disk boots (no ISO)
  --reliability             Add repeated live boots (3x) and repeated installs (2x) on primary tier
  --bios-check              Force Legacy BIOS (SeaBIOS) ISO boot check on every RAM tier
  --no-bios-check           Skip Legacy BIOS ISO boot check
  --vga TYPE                QEMU VGA device: std | virtio (default: std)
  --dry-run                 Print QEMU validation plan without launching VMs
  --help, -h                Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --edition) [[ $# -ge 2 ]] || { echo '--edition requires a value' >&2; exit 2; }; EDITION="$2"; shift 2 ;;
    --iso) [[ $# -ge 2 ]] || { echo '--iso requires a path' >&2; exit 2; }; ISO_PATH="$2"; shift 2 ;;
    --ram-matrix) [[ $# -ge 2 ]] || { echo '--ram-matrix requires a list' >&2; exit 2; }; RAM_LIST="$2"; shift 2 ;;
    --install-ram-matrix) [[ $# -ge 2 ]] || { echo '--install-ram-matrix requires a list' >&2; exit 2; }; INSTALL_RAM_LIST="$2"; shift 2 ;;
    --boot-seconds) [[ $# -ge 2 ]] || { echo '--boot-seconds requires seconds' >&2; exit 2; }; BOOT_SECONDS="$2"; shift 2 ;;
    --idle-seconds) [[ $# -ge 2 ]] || { echo '--idle-seconds requires seconds' >&2; exit 2; }; IDLE_SECONDS="$2"; shift 2 ;;
    --primary-idle) [[ $# -ge 2 ]] || { echo '--primary-idle requires seconds' >&2; exit 2; }; PRIMARY_IDLE_SECONDS="$2"; shift 2 ;;
    --graphical) GRAPHICAL=true; shift ;;
    --install-test) INSTALL_TEST=true; GRAPHICAL=true; shift ;;
    --reliability) RELIABILITY=true; shift ;;
    --bios-check) BIOS_CHECK="always"; shift ;;
    --no-bios-check) BIOS_CHECK="never"; shift ;;
    --vga) [[ $# -ge 2 ]] || { echo '--vga requires std or virtio' >&2; exit 2; }; VGA_MODE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$ISO_PATH" ]]; then
  case "$EDITION" in
    lite) ISO_PATH="$OUT_DIR/nexus-os-22.3-lite-amd64.iso" ;;
    lite-lxqt) ISO_PATH="$OUT_DIR/nexus-os-22.3-lite-lxqt-amd64.iso" ;;
    cinnamon|standard) ISO_PATH="$OUT_DIR/nexus-os-22.3-cinnamon-amd64.iso" ;;
    xfce) ISO_PATH="$OUT_DIR/nexus-os-22.3-xfce-amd64.iso" ;;
    *) printf 'Unsupported --edition: %s\n' "$EDITION" >&2; exit 2 ;;
  esac
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "NEXUS QEMU Multi-RAM Validation Plan (dry-run)"
  echo "  Edition: $EDITION (vga=$VGA_MODE)"
  echo "  Firmware modes: UEFI (OVMF) + Legacy BIOS (SeaBIOS, policy=$BIOS_CHECK)"
  echo "  Graphical mode: $GRAPHICAL | Install+3-Reboot mode: $INSTALL_TEST | Reliability repeats: $RELIABILITY"
  echo "  ISO: $ISO_PATH"
  echo "  RAM matrix (MiB): $RAM_LIST"
  echo "  Disposable work dir: $TEST_DIR"
  for bin in qemu-system-x86_64 qemu-img xorriso cpio gzip unmkinitramfs; do
    if command -v "$bin" >/dev/null 2>&1; then
      echo "    [OK] $bin"
    else
      echo "    [MISSING] $bin"
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
QEMU_SMP="$(nproc 2>/dev/null || echo 2)"
(( QEMU_SMP > 4 )) && QEMU_SMP=4
(( QEMU_SMP < 2 )) && QEMU_SMP=2

mkdir -p -- "$TEST_DIR"
SUMMARY="$TEST_DIR/qemu-results-${EDITION}.json"
echo '{"edition":"'"$EDITION"'","iso":"'"$ISO_PATH"'","accel":"'"$ACCEL"'","graphical":'"$GRAPHICAL"',"install_test":'"$INSTALL_TEST"',"runs":[]}' > "$SUMMARY"

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
  [[ -f "$SCRIPT_DIR/nexus-browser-bench.py" ]] && cp -f -- "$SCRIPT_DIR/nexus-browser-bench.py" "$main_dir/nexus-test/nexus-browser-bench.py"
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

is_primary_tier() {
  local ed="$1" rm="$2"
  [[ ( "$ed" == "lite" || "$ed" == "lite-lxqt" ) && "$rm" == "1024" ]] && return 0
  [[ "$ed" == "cinnamon" && "$rm" == "4096" ]] && return 0
  [[ "$ed" == "xfce" && "$rm" == "4096" ]] && return 0
  return 1
}

should_install_ram() {
  local rm="$1"
  [[ "$INSTALL_TEST" == true ]] || return 1
  if [[ -z "$INSTALL_RAM_LIST" ]]; then
    return 0
  fi
  local inst_rams item
  read -r -a inst_rams <<< "$INSTALL_RAM_LIST"
  for item in "${inst_rams[@]}"; do
    [[ "$item" == "$rm" ]] && return 0
  done
  return 1
}

run_live_cmd_json() {
  python3 - "$ACCEL" "$QEMU_SMP" "$1" "$2" "$ISO_PATH" "$test_vmlinuz" "$test_initrd" "$3" "$4" "$5" "$6" <<'PY'
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

run_installed_cmd_json() {
  python3 - "$ACCEL" "$QEMU_SMP" "$1" "$2" "$OVMF_CODE" "$3" "$4" "$5" "$6" "$7" <<'PY'
import json, sys
accel, smp, ram, disk, ovmf_code, ovmf_vars, slog, qmp, vs, vga = sys.argv[1:]
print(json.dumps([
    "qemu-system-x86_64",
    "-machine", f"q35,accel={accel}",
    "-cpu", "max", "-smp", smp, "-m", ram,
    "-drive", f"if=pflash,format=raw,unit=0,readonly=on,file={ovmf_code}",
    "-drive", f"if=pflash,format=raw,unit=1,file={ovmf_vars}",
    "-drive", f"file={disk},if=virtio,format=qcow2,cache=unsafe",
    "-netdev", "user,id=n0", "-device", "virtio-net-pci,netdev=n0",
    "-vga", vga, "-display", "none",
    "-serial", f"file:{slog}",
    "-qmp", f"unix:{qmp},server,nowait",
    "-device", "virtio-serial-pci",
    "-chardev", f"socket,path={vs},server=on,wait=off,id=nexus_ch",
    "-device", "virtserialport,chardev=nexus_ch,name=org.nexus.test.0",
    "-boot", "order=c",
]))
PY
}

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

  # Stage 1: UEFI/OVMF direct ISO boot check
  qemu-system-x86_64 \
    -machine "q35,accel=${ACCEL}" -cpu max -smp 2 -m "$ram_mb" \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=${OVMF_CODE}" \
    -drive "if=pflash,format=raw,unit=1,file=${vars_copy}" \
    -drive "file=${disk},if=virtio,format=qcow2" \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -vga "$VGA_MODE" -display none -serial "file:${serial_log}" \
    -qmp "unix:${qmp_sock},server,nowait" \
    -cdrom "$ISO_PATH" -boot order=d >/dev/null 2>&1 &
  qemu_pid=$!
  sleep "$BOOT_SECONDS"

  uefi_alive=false
  if kill -0 "$qemu_pid" 2>/dev/null; then
    uefi_alive=true
    python3 - "$qmp_sock" "$screendump_ppm" <<'PY' 2>/dev/null || true
import json, socket, sys
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
    s.settimeout(5); s.connect(sys.argv[1]); s.recv(4096)
    s.sendall(b'{"execute":"qmp_capabilities"}\n'); s.recv(4096)
    s.sendall(json.dumps({"execute":"screendump","arguments":{"filename":sys.argv[2]}}).encode()+b"\n"); s.recv(4096)
    s.sendall(b'{"execute":"quit"}\n')
PY
    sleep 2
    kill "$qemu_pid" 2>/dev/null || true
  fi
  wait "$qemu_pid" 2>/dev/null || true

  # Stage 1b: Legacy BIOS (SeaBIOS) ISO boot check (ISOLINUX / El Torito boot verification)
  bios_tested=false
  bios_alive=false
  bios_serial_log="$run_dir/bios-serial.log"
  bios_qmp_sock="$run_dir/bios-qmp.sock"
  bios_ppm="$run_dir/bios_boot.ppm"
  bios_png="$run_dir/bios_boot.png"
  rm -f -- "$bios_qmp_sock" "$bios_ppm" "$bios_png"
  if [[ "$BIOS_CHECK" == "always" ]] || { [[ "$BIOS_CHECK" == "auto" ]] && is_primary_tier "$EDITION" "$ram_mb"; }; then
    bios_tested=true
    qemu-system-x86_64 \
      -machine "q35,accel=${ACCEL}" -cpu max -smp 2 -m "$ram_mb" \
      -drive "file=${disk},if=virtio,format=qcow2" \
      -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
      -vga "$VGA_MODE" -display none -serial "file:${bios_serial_log}" \
      -qmp "unix:${bios_qmp_sock},server,nowait" \
      -cdrom "$ISO_PATH" -boot order=d >/dev/null 2>&1 &
    bios_pid=$!
    sleep "$BOOT_SECONDS"
    if kill -0 "$bios_pid" 2>/dev/null; then
      bios_alive=true
      python3 - "$bios_qmp_sock" "$bios_ppm" <<'PY' 2>/dev/null || true
import json, socket, sys
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
    s.settimeout(5); s.connect(sys.argv[1]); s.recv(4096)
    s.sendall(b'{"execute":"qmp_capabilities"}\n'); s.recv(4096)
    s.sendall(json.dumps({"execute":"screendump","arguments":{"filename":sys.argv[2]}}).encode()+b"\n"); s.recv(4096)
    s.sendall(b'{"execute":"quit"}\n')
PY
      sleep 2
      kill "$bios_pid" 2>/dev/null || true
    fi
    wait "$bios_pid" 2>/dev/null || true
  fi

  # Determine idle & repeat counts
  idle_sec="$IDLE_SECONDS"
  if [[ ( "$EDITION" == "lite" || "$EDITION" == "lite-lxqt" ) && ( "$ram_mb" == "512" || "$ram_mb" == "1024" ) ]]; then
    idle_sec="$PRIMARY_IDLE_SECONDS"
  elif [[ "$EDITION" != "lite" && "$EDITION" != "lite-lxqt" && "$ram_mb" == "4096" ]]; then
    idle_sec="$PRIMARY_IDLE_SECONDS"
  fi
  live_repeats=1
  install_repeats=1
  if [[ "$RELIABILITY" == true ]] && is_primary_tier "$EDITION" "$ram_mb"; then
    live_repeats=3
    install_repeats=2
  elif [[ "$RELIABILITY" == true && ( "$EDITION" == "lite" || "$EDITION" == "lite-lxqt" ) && "$ram_mb" == "512" ]]; then
    live_repeats=3
    install_repeats=2
  fi
  if [[ ( "$EDITION" == "lite" || "$EDITION" == "lite-lxqt" ) && "$ram_mb" == "1024" ]]; then
    install_repeats=1
  fi
  do_install_tier=false
  if should_install_ram "$ram_mb"; then
    do_install_tier=true
  fi

  # Stage 2: Live graphical ISO runs + optional installation onto disposable qcow2
  live_runs_dir="$run_dir/live-runs"
  mkdir -p -- "$live_runs_dir"
  for rep in $(seq 1 "$live_repeats"); do
    rep_dir="$live_runs_dir/rep-${rep}"
    mkdir -p -- "$rep_dir"
    vserial_sock="$rep_dir/vserial.sock"
    gqmp_sock="$rep_dir/gqmp.sock"
    gserial_log="$rep_dir/live-serial.log"
    rep_json="$rep_dir/live-result.json"
    rm -f -- "$vserial_sock" "$gqmp_sock" "$rep_json"

    rep_idle="$idle_sec"
    if (( rep > 1 )); then
      rep_idle=20
    fi
    install_flag=()
    timeout_sec=$(( rep_idle + 720 ))
    rep_disk="$run_dir/rep-${rep}-disk.qcow2"
    qemu-img create -f qcow2 "$rep_disk" 20G >/dev/null
    if [[ "$do_install_tier" == true && "$rep" -le "$install_repeats" ]]; then
      install_flag=(--do-install)
      timeout_sec=$(( rep_idle + 2700 ))
    fi
    cmd_json="$(run_live_cmd_json "$ram_mb" "$rep_disk" "$gserial_log" "$gqmp_sock" "$vserial_sock" "$VGA_MODE")"
    python3 "$SCRIPT_DIR/qemu-graphical-runner.py" \
      --qemu-cmd-json "$cmd_json" \
      --qmp-sock "$gqmp_sock" \
      --vserial-sock "$vserial_sock" \
      --out-dir "$rep_dir" \
      --idle-seconds "$rep_idle" \
      --panel-wait-sec 120 \
      --timeout-seconds "$timeout_sec" \
      "${install_flag[@]}" > "$rep_json" || true
    if [[ "$do_install_tier" == true && "$rep" -le "$install_repeats" ]]; then
      rep_inst_ok="$(python3 -c 'import json,sys
try:
 d=json.load(open(sys.argv[1]))
 print("1" if ((d.get("guest_report") or {}).get("install_report") or {}).get("install_success") else "0")
except Exception: print("0")' "$rep_json")"
      if [[ "$rep_inst_ok" == "1" || ! -s "$disk" ]]; then
        mv -f -- "$rep_disk" "$disk"
      else
        rm -f -- "$rep_disk"
      fi
    else
      rm -f -- "$rep_disk"
    fi
  done

  # Stage 2b: Cinnamon 2048 MiB diagnostic comparison with virtio-gpu (when EDITION=cinnamon, ram=2048, vga=std)
  cinn_virtio_json="$run_dir/cinnamon-2g-virtio.json"
  if [[ "$EDITION" == "cinnamon" && "$ram_mb" == "2048" && "$VGA_MODE" == "std" ]]; then
    diag_dir="$run_dir/diag-virtio"
    mkdir -p -- "$diag_dir"
    diag_disk="$diag_dir/diag.qcow2"
    qemu-img create -f qcow2 "$diag_disk" 20G >/dev/null
    cmd_json="$(run_live_cmd_json "$ram_mb" "$diag_disk" "$diag_dir/serial.log" "$diag_dir/qmp.sock" "$diag_dir/vs.sock" "virtio")"
    python3 "$SCRIPT_DIR/qemu-graphical-runner.py" \
      --qemu-cmd-json "$cmd_json" \
      --qmp-sock "$diag_dir/qmp.sock" \
      --vserial-sock "$diag_dir/vs.sock" \
      --out-dir "$diag_dir" \
      --idle-seconds 90 \
      --panel-wait-sec 120 \
      --timeout-seconds 660 > "$cinn_virtio_json" || true
    rm -f -- "$diag_disk"
  fi

  # Stage 3: Installed-system multi-reboot validation WITHOUT live ISO (Boot 1 -> warm reboot -> Boot 2 -> poweroff -> Cold Boot 3)
  inst_warm_json="$run_dir/installed-warm.json"
  inst_cold_json="$run_dir/installed-cold.json"
  if [[ "$do_install_tier" == true ]]; then
    inst_dir="$run_dir/installed-boots"
    mkdir -p -- "$inst_dir/warm" "$inst_dir/cold"
    cp -f -- "$OVMF_VARS" "$inst_dir/warm/OVMF_VARS.fd"
    cp -f -- "$OVMF_VARS" "$inst_dir/cold/OVMF_VARS.fd"

    # Boots 1 & 2 (warm reboot cycle via OVMF + /dev/vda only)
    cmd_warm="$(run_installed_cmd_json "$ram_mb" "$disk" "$inst_dir/warm/OVMF_VARS.fd" "$inst_dir/warm/serial.log" "$inst_dir/warm/qmp.sock" "$inst_dir/warm/vs.sock" "$VGA_MODE")"
    python3 "$SCRIPT_DIR/qemu-graphical-runner.py" \
      --qemu-cmd-json "$cmd_warm" \
      --qmp-sock "$inst_dir/warm/qmp.sock" \
      --vserial-sock "$inst_dir/warm/vs.sock" \
      --out-dir "$inst_dir/warm" \
      --idle-seconds 30 \
      --panel-wait-sec 90 \
      --expected-boots 2 \
      --final-action poweroff \
      --timeout-seconds 1200 > "$inst_warm_json" || true

    # Boot 3 (cold power-on after clean shutdown, still NO ISO)
    cmd_cold="$(run_installed_cmd_json "$ram_mb" "$disk" "$inst_dir/cold/OVMF_VARS.fd" "$inst_dir/cold/serial.log" "$inst_dir/cold/qmp.sock" "$inst_dir/cold/vs.sock" "$VGA_MODE")"
    python3 "$SCRIPT_DIR/qemu-graphical-runner.py" \
      --qemu-cmd-json "$cmd_cold" \
      --qmp-sock "$inst_dir/cold/qmp.sock" \
      --vserial-sock "$inst_dir/cold/vs.sock" \
      --out-dir "$inst_dir/cold" \
      --idle-seconds "$idle_sec" \
      --panel-wait-sec 90 \
      --expected-boots 1 \
      --final-action poweroff \
      --timeout-seconds $(( idle_sec + 900 )) > "$inst_cold_json" || true
  fi

  python3 - "$SUMMARY" "$ram_mb" "$uefi_alive" "$serial_log" "$screendump_ppm" "$screendump_png" "$live_runs_dir" "$inst_warm_json" "$inst_cold_json" "$cinn_virtio_json" "$SCRIPT_DIR" "$bios_tested" "$bios_alive" "$bios_serial_log" "$bios_ppm" "$bios_png" <<'PY'
import importlib.util, json, sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("qgr", str(Path(sys.argv[11]) / "qemu-graphical-runner.py"))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

summary_path = Path(sys.argv[1])
ram_mb = int(sys.argv[2])
uefi_alive = sys.argv[3] == "true"
serial_log = Path(sys.argv[4])
uefi_ppm, uefi_png = Path(sys.argv[5]), Path(sys.argv[6])
live_runs_dir = Path(sys.argv[7])
inst_warm_json = Path(sys.argv[8])
inst_cold_json = Path(sys.argv[9])
cinn_virtio_json = Path(sys.argv[10])
bios_tested = sys.argv[12] == "true"
bios_alive = sys.argv[13] == "true"
bios_serial_log = Path(sys.argv[14])
bios_ppm, bios_png = Path(sys.argv[15]), Path(sys.argv[16])

def load_json(p):
    if p.is_file() and p.read_text(encoding="utf-8").strip():
        try:
            return json.loads(p.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            pass
    return {}

uefi_shot = {"non_black_pct": 0.0, "png": None}
if uefi_ppm.is_file():
    uefi_shot = runner.ppm_to_png_and_stats(uefi_ppm, uefi_png)
bios_shot = {"non_black_pct": 0.0, "png": None}
if bios_ppm.is_file():
    bios_shot = runner.ppm_to_png_and_stats(bios_ppm, bios_png)

live_reps = []
for rep_file in sorted(live_runs_dir.glob("rep-*/live-result.json")):
    ld = load_json(rep_file)
    gr = ld.get("guest_report") or {}
    desk = gr.get("desktop") or {}
    apps = gr.get("apps") or {}
    stages = gr.get("stages") or {}
    zp = gr.get("zram_pressure") or {}
    ir = gr.get("install_report") or {}
    live_reps.append({
        "rep": rep_file.parent.name,
        "login_success": bool(desk.get("lightdm_active") and desk.get("user")),
        "graphical_session_success": bool(desk.get("wm") and desk.get("panel_running")),
        "panel_win_mapped": desk.get("panel_win_mapped"),
        "wm_ready_sec": desk.get("wm_ready_sec"),
        "panel_ready_sec": desk.get("panel_ready_sec"),
        "application_test_success": bool(apps.get("file_manager", {}).get("window_verified") and apps.get("terminal", {}).get("window_verified")),
        "ubiquity_ui": gr.get("ubiquity_ui"),
        "memory_stages": len(stages),
        "zram_status": zp.get("status") if not zp.get("skipped") else "N/A",
        "install_executed": ir.get("executed", False),
        "install_success": ir.get("install_success"),
        "install_report": ir,
        "desktop": desk,
        "apps": apps,
        "stages": stages,
        "network": gr.get("network"),
        "zram_pressure": zp,
        "hw_summary": gr.get("hw_summary"),
        "sec_summary": gr.get("sec_summary"),
        "update_status": gr.get("update_status"),
        "recovery_diag": gr.get("recovery_diag"),
        "native_services": gr.get("native_services"),
        "screenshots": ld.get("screenshots", []),
        "desktop_failed": ld.get("desktop_failed"),
    })

installed_boots = []
for src_name, src_path in (("warm_cycle", inst_warm_json), ("cold_boot", inst_cold_json)):
    idata = load_json(src_path)
    for cyc in idata.get("boot_cycles") or []:
        gr = cyc.get("guest_report") or {}
        desk = gr.get("desktop") or {}
        apps = gr.get("apps") or {}
        ic = gr.get("installed_checks") or {}
        per = gr.get("persistence") or {}
        zp = gr.get("zram_pressure") or {}
        stages = gr.get("stages") or {}
        installed_boots.append({
            "source": src_name,
            "boot_num": gr.get("boot_num"),
            "vm_exited_cleanly": idata.get("vm_exited_cleanly"),
            "booted_from_vda": ic.get("booted_from_vda"),
            "live_iso_absent": ic.get("live_iso_absent"),
            "efi_boot_ok": ic.get("efi_boot_ok"),
            "login_success": bool(desk.get("lightdm_active") and desk.get("user")),
            "graphical_session_success": bool(desk.get("wm") and desk.get("panel_running")),
            "panel_win_mapped": desk.get("panel_win_mapped"),
            "wm_ready_sec": desk.get("wm_ready_sec"),
            "panel_ready_sec": desk.get("panel_ready_sec"),
            "application_test_success": bool(apps.get("file_manager", {}).get("window_verified") and apps.get("terminal", {}).get("window_verified")),
            "windows_closed_cleanup": apps.get("windows_closed_cleanup"),
            "persistence": per,
            "network": gr.get("network"),
            "memory_stages": len(stages),
            "stages": stages,
            "zram_pressure": zp,
            "installed_checks": ic,
            "update_status": gr.get("update_status"),
            "recovery_diag": gr.get("recovery_diag"),
            "native_services": gr.get("native_services"),
            "screenshots": cyc.get("screenshots", []),
        })

diag_virtio = load_json(cinn_virtio_json)
first_live = live_reps[0] if live_reps else {}
inst_ok_count = sum(1 for r in live_reps if r.get("install_executed") and r.get("install_success"))
inst_try_count = sum(1 for r in live_reps if r.get("install_executed"))
boot_ok_count = sum(1 for b in installed_boots if b.get("booted_from_vda") and b.get("live_iso_absent") and b.get("graphical_session_success"))

def diag_for(src_path):
    idata = load_json(src_path)
    slog = src_path.parent / "installed-boots" / ("warm" if "warm" in src_path.name else "cold") / "serial.log"
    stail = []
    if slog.is_file():
        stail = slog.read_text(encoding="utf-8", errors="replace").splitlines()[-20:]
    return {
        "vm_exited_cleanly": idata.get("vm_exited_cleanly"),
        "desktop_failed": idata.get("desktop_failed"),
        "screenshots": idata.get("screenshots", []),
        "cycles_count": len(idata.get("boot_cycles") or []),
        "serial_tail": stail,
    }

entry = {
    "ram_mib": ram_mb,
    "uefi_boot_success": uefi_alive and (uefi_shot.get("non_black_pct", 0) > 0 or (serial_log.stat().st_size > 0 if serial_log.is_file() else uefi_alive)),
    "uefi_boot_screenshot": uefi_shot,
    "bios_boot_tested": bios_tested,
    "bios_boot_success": (bios_alive and (bios_shot.get("non_black_pct", 0) > 0 or (bios_serial_log.stat().st_size > 0 if bios_serial_log.is_file() else bios_alive))) if bios_tested else None,
    "bios_boot_screenshot": bios_shot if bios_tested else None,
    "live_attempts": len(live_reps),
    "live_successes": sum(1 for r in live_reps if r.get("graphical_session_success") and r.get("application_test_success")),
    "install_attempts": inst_try_count,
    "install_successes": inst_ok_count,
    "installed_boot_attempts": 3 if inst_try_count > 0 else 0,
    "installed_boot_successes": boot_ok_count,
    "persistence_verified": any((b.get("persistence") or {}).get("persistence_verified") for b in installed_boots),
    "live_reps": live_reps,
    "installed_boots": installed_boots,
    "warm_diag": diag_for(inst_warm_json) if inst_warm_json.is_file() else None,
    "cold_diag": diag_for(inst_cold_json) if inst_cold_json.is_file() else None,
    "cinnamon_2g_virtio_diag": {
        "screenshots": diag_virtio.get("screenshots"),
        "glx_diag": ((diag_virtio.get("guest_report") or {}).get("desktop") or {}).get("glx_diag"),
        "panel_win_mapped": ((diag_virtio.get("guest_report") or {}).get("desktop") or {}).get("panel_win_mapped"),
        "wm_ready_sec": ((diag_virtio.get("guest_report") or {}).get("desktop") or {}).get("wm_ready_sec"),
        "panel_ready_sec": ((diag_virtio.get("guest_report") or {}).get("desktop") or {}).get("panel_ready_sec"),
    } if diag_virtio else None,
    "first_live_summary": {
        "login": first_live.get("login_success"),
        "desktop": first_live.get("graphical_session_success"),
        "apps_ok": first_live.get("application_test_success"),
        "hw_summary": first_live.get("hw_summary"),
        "sec_summary": first_live.get("sec_summary"),
        "native_services": first_live.get("native_services"),
    },
}

data = json.loads(summary_path.read_text(encoding="utf-8"))
data["runs"].append(entry)
summary_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
  rm -f -- "$disk"
  printf 'QEMU %s %s MiB Phase 12.3 validation finished.\n' "$EDITION" "$ram_mb"
done

[[ -n "$overlay_dir" ]] && rm -rf -- "$overlay_dir"
