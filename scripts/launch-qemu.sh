#!/usr/bin/env bash
# Launch the NEXUS OS / Linux Mint installer or installed guest using QEMU with UEFI firmware.
# Uses disposable qcow2 virtual disks under ignored build/ (never host disks).
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
SYSTEM_CONF="$ROOT_DIR/linux/config/nexus-system.conf"
conf_value() {
  local key="$1" default="$2" val=""
  if [[ -r "$SYSTEM_CONF" ]]; then
    val="$(awk -F= -v k="$key" '$1 == k { print $2; exit }' "$SYSTEM_CONF")"
  fi
  printf '%s' "${val:-$default}"
}
DOWNLOAD_DIR="${NEXUS_DOWNLOAD_DIR:-$BUILD_DIR/downloads}"
ISO_OUT_DIR="${NEXUS_ISO_OUT_DIR:-$BUILD_DIR/iso/out}"
VM_STATE_DIR="$BUILD_DIR/qemu"

PROFILE="${NEXUS_QEMU_PROFILE:-}"
EDITION="${NEXUS_EDITION:-}"
BOOT_MODE="auto"
DISK_ONLY=false
INSTALLER_FIRST=false
COMPAT_VIDEO=false
VNC_DISPLAY=""
CUSTOM_ISO_PATH=""
CUSTOM_DISK_PATH=""
RESET_DISK=false
YES_RESET_DISK=false
DRY_RUN=false

usage() {
  cat <<'USAGE'
Usage: bash scripts/launch-qemu.sh [OPTIONS]

Boots a verified Linux Mint / NEXUS OS ISO or installed disposable qcow2 virtual
disk under QEMU/OVMF UEFI with absolute USB tablet pointer, HMP/QMP monitor
sockets, and serial log output.

Options:
  --profile NAME       VM hardware profile:
                         minimum     2 vCPUs, 4096 MiB RAM, 30G disposable disk
                         recommended 4 vCPUs, 8192 MiB RAM, 50G disposable disk
  --edition NAME       Select built NEXUS ISO: cinnamon | xfce | lite | lite-lxqt
                       (omit to use stock Linux Mint 22.3 Xfce ISO)
  --installer-first    Require ISO media and boot installer first (order=d)
  --disk-only          Detach ISO; boot directly from the installed virtual disk (order=c)
  --installed          Alias for --disk-only
  --iso-path PATH      Override ISO path
  --disk-path PATH     Override disposable qcow2 virtual disk path (under ignored build/)
  --compat-video       Use standard VGA (-vga std) for Mint compatibility graphics mode
  --vnc [ADDR:DISP]    Use VNC display (default: 127.0.0.1:0, TCP port 5900) instead of cocoa/gtk
  --reset-disk         Delete and recreate existing qcow2 disk (requires --yes-reset-disk)
  --yes-reset-disk     Explicit confirmation required with --reset-disk
  --dry-run            Print resolved QEMU profile, devices, and host tool availability
  --help, -h           Show this help message

Environment configuration:
  NEXUS_RAM_MB=4096            guest memory in MiB
  NEXUS_CPUS=2                 virtual CPU count
  NEXUS_DISK_SIZE=40G|30G|50G  new qcow2 disk capacity (M, G, or T suffix)
  NEXUS_QEMU_ACCEL=tcg         QEMU accelerator (tcg or host-supported kvm)
  NEXUS_QEMU_DISPLAY=BACKEND   display backend (defaults to cocoa on macOS, gtk elsewhere)
  NEXUS_QEMU_VIDEO=virtio|std  guest video device (defaults to virtio; --compat-video sets std)
  NEXUS_QEMU_DEBUG_LOG=PATH    optional QEMU log path (overwritten; guest_errors,unimp)
  NEXUS_QEMU_SERIAL_LOG=PATH   guest serial console log (default: build/qemu/serial.log)
  NEXUS_QEMU_MONITOR_SOCK=PATH HMP monitor Unix socket (default: build/qemu/monitor.sock)
  NEXUS_QEMU_QMP_SOCK=PATH     QMP monitor Unix socket (default: build/qemu/qmp.sock)
  NEXUS_ISO_PATH=PATH          installer ISO; omit or pass --disk-only to boot disk
  NEXUS_DISK_PATH=PATH         guest qcow2 disk location
  OVMF_CODE=PATH               UEFI firmware code image
  OVMF_VARS=PATH               writable UEFI variable template
  QEMU_SYSTEM_X86_64=PATH      QEMU executable

Safety:
  - Existing qcow2 disks are preserved across boots and never overwritten without
    explicit --reset-disk --yes-reset-disk.
  - OVMF_VARS state is preserved under build/qemu/OVMF_VARS.fd between installation
    and subsequent --disk-only boots.
  - All VM state and disposable disks remain under ignored build/ and are never committed.
USAGE
}

while (($#)); do
  case "$1" in
    --profile) [[ $# -ge 2 ]] || { echo '--profile requires a value (minimum | recommended)' >&2; exit 2; }; PROFILE="$2"; shift 2 ;;
    --edition) [[ $# -ge 2 ]] || { echo '--edition requires a value' >&2; exit 2; }; EDITION="$2"; shift 2 ;;
    --installer-first) INSTALLER_FIRST=true; BOOT_MODE="installer"; shift ;;
    --disk-only|--installed) DISK_ONLY=true; BOOT_MODE="installed"; shift ;;
    --iso-path) [[ $# -ge 2 ]] || { echo '--iso-path requires a path' >&2; exit 2; }; CUSTOM_ISO_PATH="$2"; shift 2 ;;
    --disk-path) [[ $# -ge 2 ]] || { echo '--disk-path requires a path' >&2; exit 2; }; CUSTOM_DISK_PATH="$2"; shift 2 ;;
    --compat-video) COMPAT_VIDEO=true; shift ;;
    --vnc)
      if [[ $# -ge 2 && "$2" != --* ]]; then
        VNC_DISPLAY="$2"
        shift 2
      else
        VNC_DISPLAY="127.0.0.1:0"
        shift
      fi
      ;;
    --reset-disk) RESET_DISK=true; shift ;;
    --yes-reset-disk) YES_RESET_DISK=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$INSTALLER_FIRST" == true && "$DISK_ONLY" == true ]]; then
  echo 'Cannot combine --installer-first with --disk-only / --installed.' >&2
  exit 2
fi

if [[ "$RESET_DISK" == true && "$YES_RESET_DISK" == false ]]; then
  echo 'SAFETY ABORT: --reset-disk refuses to overwrite an existing virtual disk without explicit --yes-reset-disk.' >&2
  exit 2
fi

DEFAULT_RAM_MB="$(conf_value NEXUS_TARGET_RAM_MB 4096)"
DEFAULT_CPUS=2
DEFAULT_DISK_SIZE="40G"
PROFILE_LABEL="default"

if [[ -n "$PROFILE" ]]; then
  case "$PROFILE" in
    min|minimum)
      DEFAULT_CPUS=2
      DEFAULT_RAM_MB=4096
      DEFAULT_DISK_SIZE="30G"
      PROFILE_LABEL="minimum"
      ;;
    rec|recommended)
      DEFAULT_CPUS=4
      DEFAULT_RAM_MB=8192
      DEFAULT_DISK_SIZE="50G"
      PROFILE_LABEL="recommended"
      ;;
    *)
      printf 'Unsupported --profile: %s (expected minimum or recommended)\n' "$PROFILE" >&2
      exit 2
      ;;
  esac
fi

if [[ -n "$EDITION" ]]; then
  case "$EDITION" in
    standard) EDITION="cinnamon" ;;
    cinnamon|xfce|lite|lite-lxqt) ;;
    *) printf 'Unsupported --edition: %s (expected cinnamon | xfce | lite | lite-lxqt)\n' "$EDITION" >&2; exit 2 ;;
  esac
  DEFAULT_ISO_PATH="$ISO_OUT_DIR/nexus-os-22.3-${EDITION}-amd64.iso"
  DEFAULT_DISK_PATH="$BUILD_DIR/images/nexus-${EDITION}-${PROFILE_LABEL}.qcow2"
else
  DEFAULT_ISO_PATH="$DOWNLOAD_DIR/linuxmint-22.3-xfce-64bit.iso"
  if [[ "$PROFILE_LABEL" == "default" ]]; then
    DEFAULT_DISK_PATH="$BUILD_DIR/images/nexus-mint-22.3.qcow2"
  else
    DEFAULT_DISK_PATH="$BUILD_DIR/images/nexus-${PROFILE_LABEL}.qcow2"
  fi
fi

ISO_PATH="${CUSTOM_ISO_PATH:-${NEXUS_ISO_PATH:-$DEFAULT_ISO_PATH}}"
DISK_PATH="${CUSTOM_DISK_PATH:-${NEXUS_DISK_PATH:-$DEFAULT_DISK_PATH}}"
RAM_MB="${NEXUS_RAM_MB:-$DEFAULT_RAM_MB}"
CPUS="${NEXUS_CPUS:-$DEFAULT_CPUS}"
DISK_SIZE="${NEXUS_DISK_SIZE:-$DEFAULT_DISK_SIZE}"
ACCEL="${NEXUS_QEMU_ACCEL:-tcg}"
if [[ "$COMPAT_VIDEO" == true ]]; then
  VIDEO="std"
else
  VIDEO="${NEXUS_QEMU_VIDEO:-virtio}"
fi
DEBUG_LOG="${NEXUS_QEMU_DEBUG_LOG:-}"
SERIAL_LOG="${NEXUS_QEMU_SERIAL_LOG:-$VM_STATE_DIR/serial.log}"
MONITOR_SOCK="${NEXUS_QEMU_MONITOR_SOCK:-$VM_STATE_DIR/monitor.sock}"
QMP_SOCK="${NEXUS_QEMU_QMP_SOCK:-$VM_STATE_DIR/qmp.sock}"

if [[ -n "$VNC_DISPLAY" ]]; then
  DISPLAY_BACKEND="vnc=$VNC_DISPLAY"
elif [[ -n "${NEXUS_QEMU_DISPLAY:-}" ]]; then
  DISPLAY_BACKEND="$NEXUS_QEMU_DISPLAY"
elif [[ "$(uname -s)" == Darwin ]]; then
  DISPLAY_BACKEND=cocoa
else
  DISPLAY_BACKEND=gtk
fi
QEMU="${QEMU_SYSTEM_X86_64:-qemu-system-x86_64}"

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
  printf 'DRY RUN - NEXUS QEMU profile (%s, boot_mode=%s)\n' "$PROFILE_LABEL" "$BOOT_MODE"
  printf 'QEMU: %s\nRAM: %s MiB\nCPUs: %s\nDisk size: %s\nDisk path: %s\nAccelerator: %s\nDisplay: %s\nVideo: %s\n' \
    "$QEMU" "$RAM_MB" "$CPUS" "$DISK_SIZE" "$DISK_PATH" "$ACCEL" "$DISPLAY_BACKEND" "$VIDEO"
  printf 'Input devices: qemu-xhci + usb-tablet (absolute pointer) + usb-kbd\n'
  printf 'HMP monitor socket: %s\nQMP monitor socket: %s\nSerial log: %s\n' \
    "$MONITOR_SOCK" "$QMP_SOCK" "$SERIAL_LOG"
  if [[ -n "$DEBUG_LOG" ]]; then printf 'Debug log: %s (overwritten)\n' "$DEBUG_LOG"; else printf 'Debug log: disabled\n'; fi
  if [[ "$DISK_ONLY" == true ]]; then
    printf 'Boot media: omitted (--disk-only); booting installed virtual disk\n'
  elif [[ -f "$ISO_PATH" ]]; then
    printf 'Boot media: present (%s)\n' "$ISO_PATH"
  elif [[ "$INSTALLER_FIRST" == true ]]; then
    printf 'Boot media: MISSING required installer ISO (%s)\n' "$ISO_PATH"
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

if [[ "$INSTALLER_FIRST" == true && ! -r "$ISO_PATH" ]]; then
  printf 'Installer ISO not found or unreadable: %s\n' "$ISO_PATH" >&2
  printf 'Run bash scripts/download-linux-mint.sh first or omit --installer-first.\n' >&2
  exit 1
fi

if [[ "$DISK_ONLY" == true && ! -e "$DISK_PATH" ]]; then
  printf 'Installed virtual disk not found: %s\n' "$DISK_PATH" >&2
  printf 'Boot with --installer-first first to install onto the disposable qcow2 disk.\n' >&2
  exit 1
fi

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

mkdir -p -- "$(dirname -- "$DISK_PATH")" "$VM_STATE_DIR" "$(dirname -- "$SERIAL_LOG")" "$(dirname -- "$MONITOR_SOCK")" "$(dirname -- "$QMP_SOCK")"
if [[ "$RESET_DISK" == true && -e "$DISK_PATH" ]]; then
  echo "Resetting disposable qcow2 guest disk (--yes-reset-disk confirmed): $DISK_PATH"
  rm -f -- "$DISK_PATH"
fi
if [[ ! -e "$DISK_PATH" ]]; then
  echo "Creating disposable qcow2 guest disk ($DISK_SIZE): $DISK_PATH"
  qemu-img create -f qcow2 "$DISK_PATH" "$DISK_SIZE"
else
  echo "Preserving existing disposable qcow2 guest disk: $DISK_PATH"
fi

VARS_PATH="$VM_STATE_DIR/OVMF_VARS.fd"
TEMPLATE_BYTES="$(wc -c < "$OVMF_VARS")"
if [[ ! -e "$VARS_PATH" || "$RESET_DISK" == true ]]; then
  cp -- "$OVMF_VARS" "$VARS_PATH"
elif [[ "$(wc -c < "$VARS_PATH")" -ne "$TEMPLATE_BYTES" ]]; then
  echo "Warning: cached $VARS_PATH size differs from $OVMF_VARS; refreshing writable UEFI vars." >&2
  cp -- "$OVMF_VARS" "$VARS_PATH"
fi

rm -f -- "$MONITOR_SOCK" "$QMP_SOCK"

MACHINE_OPT="q35,accel=$ACCEL"
PFLASH_CODE_OPT="if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE"
PFLASH_VARS_OPT="if=pflash,format=raw,unit=1,file=$VARS_PATH"
DISK_DRIVE_OPT="file=$DISK_PATH,if=virtio,format=qcow2"
NETDEV_OPT="user,id=n0"
NET_DEVICE_OPT="virtio-net-pci,netdev=n0"
DEBUG_FLAGS="guest_errors,unimp"

TABLET_DEV_OPT="usb-tablet,bus=xhci.0"
KBD_DEV_OPT="usb-kbd,bus=xhci.0"
XHCI_DEV_OPT="qemu-xhci,id=xhci"
MONITOR_OPT="unix:$MONITOR_SOCK,server,nowait"
QMP_OPT="unix:$QMP_SOCK,server,nowait"

ARGS=(
  -machine "$MACHINE_OPT"
  -cpu max
  -smp "$CPUS"
  -m "$RAM_MB"
  -drive "$PFLASH_CODE_OPT"
  -drive "$PFLASH_VARS_OPT"
  -drive "$DISK_DRIVE_OPT"
  -netdev "$NETDEV_OPT"
  -device "$NET_DEVICE_OPT"
  -device "$XHCI_DEV_OPT"
  -device "$TABLET_DEV_OPT"
  -device "$KBD_DEV_OPT"
  -serial "file:$SERIAL_LOG"
  -monitor "$MONITOR_OPT"
  -qmp "$QMP_OPT"
  -display "$DISPLAY_BACKEND"
)
if [[ "$VIDEO" == std ]]; then ARGS+=(-vga std); else ARGS+=(-device virtio-vga); fi
if [[ -n "$DEBUG_LOG" ]]; then
  mkdir -p -- "$(dirname -- "$DEBUG_LOG")"
  ARGS+=(-D "$DEBUG_LOG" -d "$DEBUG_FLAGS")
fi
if [[ "$DISK_ONLY" == false && -f "$ISO_PATH" ]]; then
  ARGS+=(-drive "file=$ISO_PATH,media=cdrom,readonly=on,index=0" -boot order=d)
  ACTUAL_BOOT_MODE="installer-first (ISO attached read-only)"
else
  ARGS+=(-boot order=c)
  ACTUAL_BOOT_MODE="installed-disk (ISO detached)"
fi

QEMU_VER="unknown"
if QEMU_VER_OUT="$("$QEMU" --version 2>/dev/null)"; then
  QEMU_VER="${QEMU_VER_OUT%%$'\n'*}"
fi
printf 'Starting QEMU (%s)\n' "$QEMU_VER"
printf '  Profile: %s | Boot mode: %s\n' "$PROFILE_LABEL" "$ACTUAL_BOOT_MODE"
printf '  RAM: %s MiB | CPUs: %s | Disk: %s (%s) | Video: %s | Display: %s\n' \
  "$RAM_MB" "$CPUS" "$DISK_PATH" "$DISK_SIZE" "$VIDEO" "$DISPLAY_BACKEND"
printf '  UEFI CODE: %s | VARS (persistent): %s\n' "$OVMF_CODE" "$VARS_PATH"
printf '  HMP monitor: socat - UNIX-CONNECT:%s (or nc -U %s)\n' "$MONITOR_SOCK" "$MONITOR_SOCK"
printf '  QMP monitor: %s | Serial log: %s\n' "$QMP_SOCK" "$SERIAL_LOG"
if [[ -n "$VNC_DISPLAY" ]]; then
  printf '  VNC viewer: connect to %s (e.g. vncviewer 127.0.0.1:5900 or macOS Screen Sharing)\n' "$VNC_DISPLAY"
fi
exec "$QEMU" "${ARGS[@]}"
