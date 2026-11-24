#!/usr/bin/env bash
# Launch the Linux Mint installer or installed guest using QEMU with UEFI firmware.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
DOWNLOAD_DIR="${NEXUS_DOWNLOAD_DIR:-$BUILD_DIR/downloads}"
VM_STATE_DIR="$BUILD_DIR/qemu"
ISO_PATH="${NEXUS_ISO_PATH:-$DOWNLOAD_DIR/linuxmint-22.3-xfce-64bit.iso}"
DISK_PATH="${NEXUS_DISK_PATH:-$BUILD_DIR/images/nexus-mint-22.3.qcow2}"
RAM_MB="${NEXUS_RAM_MB:-4096}"
CPUS="${NEXUS_CPUS:-2}"
DISK_SIZE="${NEXUS_DISK_SIZE:-40G}"
ACCEL="${NEXUS_QEMU_ACCEL:-tcg}"
VIDEO="${NEXUS_QEMU_VIDEO:-virtio}"
DEBUG_LOG="${NEXUS_QEMU_DEBUG_LOG:-}"
if [[ -n "${NEXUS_QEMU_DISPLAY:-}" ]]; then
  DISPLAY_BACKEND="$NEXUS_QEMU_DISPLAY"
elif [[ "$(uname -s)" == Darwin ]]; then
  DISPLAY_BACKEND=cocoa
else
  DISPLAY_BACKEND=gtk
fi
QEMU="${QEMU_SYSTEM_X86_64:-qemu-system-x86_64}"
DRY_RUN=false

usage() {
  cat <<'USAGE'
Usage: bash scripts/launch-qemu.sh
       bash scripts/launch-qemu.sh --dry-run

Environment configuration:
  NEXUS_RAM_MB=4096          guest memory in MiB
  NEXUS_CPUS=2               virtual CPU count
  NEXUS_DISK_SIZE=40G        new qcow2 disk capacity (M, G, or T suffix)
  NEXUS_QEMU_ACCEL=tcg        QEMU accelerator (tcg or host-supported kvm)
  NEXUS_QEMU_DISPLAY=BACKEND  display backend (defaults to cocoa on macOS, gtk elsewhere)
  NEXUS_QEMU_VIDEO=virtio|std  guest video device (defaults to virtio)
  NEXUS_QEMU_DEBUG_LOG=PATH    optional QEMU log path (overwritten; guest_errors,unimp)
  NEXUS_ISO_PATH=PATH         installer ISO; omit the file to boot the disk only
  NEXUS_DISK_PATH=PATH        guest qcow2 disk location
  OVMF_CODE=PATH              UEFI firmware code image
  OVMF_VARS=PATH              writable UEFI variable template
  QEMU_SYSTEM_X86_64=PATH     QEMU executable

Defaults to software emulation (TCG); it is portable but may be slow. The VM
state and disk are kept under ignored build/ and are not committed to Git.
USAGE
}

if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then usage; exit 0; fi
if [[ "${1:-}" == --dry-run ]]; then DRY_RUN=true; shift; fi
[[ $# -eq 0 ]] || { usage >&2; exit 2; }
[[ "$RAM_MB" =~ ^[1-9][0-9]*$ ]] || { echo 'NEXUS_RAM_MB must be a positive integer.' >&2; exit 2; }
[[ "$CPUS" =~ ^[1-9][0-9]*$ ]] || { echo 'NEXUS_CPUS must be a positive integer.' >&2; exit 2; }
[[ "$DISK_SIZE" =~ ^[1-9][0-9]*[MGT]$ ]] || { echo 'NEXUS_DISK_SIZE must be a positive integer plus M, G, or T.' >&2; exit 2; }
[[ "$ACCEL" == tcg || "$ACCEL" == kvm ]] || { echo 'NEXUS_QEMU_ACCEL must be tcg or kvm.' >&2; exit 2; }
[[ "$VIDEO" == virtio || "$VIDEO" == std ]] || { echo 'NEXUS_QEMU_VIDEO must be virtio or std.' >&2; exit 2; }
find_firmware_pair() {
  local code vars
  for code in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2/x64/OVMF_CODE.fd /opt/homebrew/share/qemu/edk2-x86_64-code.fd /usr/local/share/qemu/edk2-x86_64-code.fd; do
    [[ -r "$code" ]] || continue
    case "$code" in
      *_4M.fd) vars="${code%CODE_4M.fd}VARS_4M.fd" ;;
      *.4m.fd) vars="${code%CODE.4m.fd}VARS.4m.fd" ;;
      *edk2-x86_64-code.fd) vars="${code%edk2-x86_64-code.fd}edk2-i386-vars.fd" ;;
      *) vars="${code%CODE.fd}VARS.fd" ;;
    esac
    if [[ -r "$vars" ]]; then printf '%s\n%s\n' "$code" "$vars"; return 0; fi
  done
  return 1
}

if [[ "$DRY_RUN" == true ]]; then
  printf 'DRY RUN - NEXUS QEMU profile\n'
  printf 'QEMU: %s\nRAM: %s MiB\nCPUs: %s\nDisk size: %s\nDisk path: %s\nAccelerator: %s\nVideo: %s\n' \
    "$QEMU" "$RAM_MB" "$CPUS" "$DISK_SIZE" "$DISK_PATH" "$ACCEL" "$VIDEO"
  if [[ -n "$DEBUG_LOG" ]]; then printf 'Debug log: %s (overwritten)\n' "$DEBUG_LOG"; else printf 'Debug log: disabled\n'; fi
  if [[ -f "$ISO_PATH" ]]; then
    printf 'Boot media: present (%s)\n' "$ISO_PATH"
  else
    printf 'Boot media: not present; disk boot (%s)\n' "$ISO_PATH"
  fi
  if command -v "$QEMU" >/dev/null 2>&1; then printf 'Host QEMU: available\n'; else printf 'Host QEMU: missing (%s)\n' "$QEMU"; fi
  if command -v qemu-img >/dev/null 2>&1; then printf 'Host qemu-img: available\n'; else printf 'Host qemu-img: missing\n'; fi
  if find_firmware_pair >/dev/null 2>&1 || [[ -n "${OVMF_CODE:-}" && -n "${OVMF_VARS:-}" ]]; then
    printf 'Host OVMF firmware: available\n'
  else
    printf 'Host OVMF firmware: missing or custom paths not set\n'
  fi
  exit 0
fi
command -v "$QEMU" >/dev/null 2>&1 || { printf 'Missing QEMU executable: %s\n' "$QEMU" >&2; exit 1; }
command -v qemu-img >/dev/null 2>&1 || { echo 'Missing qemu-img (install qemu-utils).' >&2; exit 1; }

if [[ -z "${OVMF_CODE:-}" || -z "${OVMF_VARS:-}" ]]; then
  FIRMWARE_PAIR=()
  while IFS= read -r firmware_path; do FIRMWARE_PAIR+=("$firmware_path"); done < <(find_firmware_pair)
  if ((${#FIRMWARE_PAIR[@]} != 2)); then
    echo 'Could not find a matching OVMF code/variables pair. Install ovmf (Linux), use Homebrew QEMU (macOS), or set OVMF_CODE and OVMF_VARS.' >&2
    exit 1
  fi
  OVMF_CODE="${OVMF_CODE:-${FIRMWARE_PAIR[0]}}"
  OVMF_VARS="${OVMF_VARS:-${FIRMWARE_PAIR[1]}}"
fi
[[ -r "$OVMF_CODE" ]] || { printf 'Cannot read OVMF_CODE: %s\n' "$OVMF_CODE" >&2; exit 1; }
[[ -r "$OVMF_VARS" ]] || { printf 'Cannot read OVMF_VARS template: %s\n' "$OVMF_VARS" >&2; exit 1; }

mkdir -p -- "$(dirname -- "$DISK_PATH")" "$VM_STATE_DIR"
if [[ ! -e "$DISK_PATH" ]]; then
  echo "Creating qcow2 guest disk ($DISK_SIZE): $DISK_PATH"
  qemu-img create -f qcow2 "$DISK_PATH" "$DISK_SIZE"
fi
VARS_PATH="$VM_STATE_DIR/OVMF_VARS.fd"
TEMPLATE_BYTES="$(wc -c < "$OVMF_VARS")"
if [[ ! -e "$VARS_PATH" ]]; then
  cp -- "$OVMF_VARS" "$VARS_PATH"
elif [[ "$(wc -c < "$VARS_PATH")" -ne "$TEMPLATE_BYTES" ]]; then
  echo "Warning: cached $VARS_PATH size differs from $OVMF_VARS; refreshing writable UEFI vars." >&2
  cp -- "$OVMF_VARS" "$VARS_PATH"
fi

MACHINE_OPT="q35,accel=$ACCEL"
PFLASH_CODE_OPT="if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE"
PFLASH_VARS_OPT="if=pflash,format=raw,unit=1,file=$VARS_PATH"
DISK_DRIVE_OPT="file=$DISK_PATH,if=virtio,format=qcow2"
NETDEV_OPT="user,id=n0"
NET_DEVICE_OPT="virtio-net-pci,netdev=n0"
DEBUG_FLAGS="guest_errors,unimp"

ARGS=(-machine "$MACHINE_OPT" -cpu max -smp "$CPUS" -m "$RAM_MB"
  -drive "$PFLASH_CODE_OPT"
  -drive "$PFLASH_VARS_OPT"
  -drive "$DISK_DRIVE_OPT" -netdev "$NETDEV_OPT" -device "$NET_DEVICE_OPT"
  -display "$DISPLAY_BACKEND")
if [[ "$VIDEO" == std ]]; then ARGS+=(-vga std); else ARGS+=(-device virtio-vga); fi
if [[ -n "$DEBUG_LOG" ]]; then
  mkdir -p -- "$(dirname -- "$DEBUG_LOG")"
  ARGS+=(-D "$DEBUG_LOG" -d "$DEBUG_FLAGS")
fi
if [[ -f "$ISO_PATH" ]]; then
  ARGS+=(-cdrom "$ISO_PATH" -boot order=d)
else
  ARGS+=(-boot order=c)
fi
printf 'Starting QEMU (RAM=%s MiB, CPUs=%s, disk=%s, accel=%s)\n' "$RAM_MB" "$CPUS" "$DISK_SIZE" "$ACCEL"
exec "$QEMU" "${ARGS[@]}"
