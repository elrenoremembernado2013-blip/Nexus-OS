#!/usr/bin/env bash
# Launch the Ubuntu installer or installed guest using QEMU with UEFI firmware.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
DOWNLOAD_DIR="${NEXUS_DOWNLOAD_DIR:-$BUILD_DIR/downloads}"
VM_STATE_DIR="$BUILD_DIR/qemu"
ISO_PATH="${NEXUS_ISO_PATH:-$DOWNLOAD_DIR/ubuntu-26.04.1-live-server-amd64.iso}"
DISK_PATH="${NEXUS_DISK_PATH:-$BUILD_DIR/images/nexus-ubuntu-26.04.1.qcow2}"
RAM_MB="${NEXUS_RAM_MB:-4096}"
CPUS="${NEXUS_CPUS:-4}"
DISK_SIZE="${NEXUS_DISK_SIZE:-40G}"
ACCEL="${NEXUS_QEMU_ACCEL:-tcg}"
QEMU="${QEMU_SYSTEM_X86_64:-qemu-system-x86_64}"

usage() {
  cat <<'USAGE'
Usage: bash scripts/launch-qemu.sh

Environment configuration:
  NEXUS_RAM_MB=4096          guest memory in MiB
  NEXUS_CPUS=4               virtual CPU count
  NEXUS_DISK_SIZE=40G        new qcow2 disk capacity (M, G, or T suffix)
  NEXUS_QEMU_ACCEL=tcg        QEMU accelerator (tcg or host-supported kvm)
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
[[ $# -eq 0 ]] || { usage >&2; exit 2; }
[[ "$RAM_MB" =~ ^[1-9][0-9]*$ ]] || { echo 'NEXUS_RAM_MB must be a positive integer.' >&2; exit 2; }
[[ "$CPUS" =~ ^[1-9][0-9]*$ ]] || { echo 'NEXUS_CPUS must be a positive integer.' >&2; exit 2; }
[[ "$DISK_SIZE" =~ ^[1-9][0-9]*[MGT]$ ]] || { echo 'NEXUS_DISK_SIZE must be a positive integer plus M, G, or T.' >&2; exit 2; }
[[ "$ACCEL" == tcg || "$ACCEL" == kvm ]] || { echo 'NEXUS_QEMU_ACCEL must be tcg or kvm.' >&2; exit 2; }
command -v "$QEMU" >/dev/null 2>&1 || { printf 'Missing QEMU executable: %s\n' "$QEMU" >&2; exit 1; }
command -v qemu-img >/dev/null 2>&1 || { echo 'Missing qemu-img (install qemu-utils).' >&2; exit 1; }

find_firmware_pair() {
  local code vars
  for code in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2/x64/OVMF_CODE.fd; do
    [[ -r "$code" ]] || continue
    case "$code" in
      *_4M.fd) vars="${code%CODE_4M.fd}VARS_4M.fd" ;;
      *.4m.fd) vars="${code%CODE.4m.fd}VARS.4m.fd" ;;
      *) vars="${code%CODE.fd}VARS.fd" ;;
    esac
    if [[ -r "$vars" ]]; then printf '%s\n%s\n' "$code" "$vars"; return 0; fi
  done
  return 1
}

if [[ -z "${OVMF_CODE:-}" || -z "${OVMF_VARS:-}" ]]; then
  mapfile -t FIRMWARE_PAIR < <(find_firmware_pair) || true
  if ((${#FIRMWARE_PAIR[@]} != 2)); then
    echo 'Could not find a matching OVMF code/variables pair. Install ovmf or set OVMF_CODE and OVMF_VARS.' >&2
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
if [[ ! -e "$VARS_PATH" ]]; then cp -- "$OVMF_VARS" "$VARS_PATH"; fi

ARGS=(-machine "q35,accel=$ACCEL" -cpu max -smp "$CPUS" -m "$RAM_MB"
  -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE"
  -drive "if=pflash,format=raw,unit=1,file=$VARS_PATH"
  -drive "file=$DISK_PATH,if=virtio,format=qcow2" -netdev user,id=n0 -device virtio-net-pci,netdev=n0
  -device virtio-vga -display gtk)
if [[ -f "$ISO_PATH" ]]; then
  ARGS+=(-cdrom "$ISO_PATH" -boot order=d)
else
  ARGS+=(-boot order=c)
fi
printf 'Starting QEMU (RAM=%s MiB, CPUs=%s, disk=%s, accel=%s)\n' "$RAM_MB" "$CPUS" "$DISK_SIZE" "$ACCEL"
exec "$QEMU" "${ARGS[@]}"
