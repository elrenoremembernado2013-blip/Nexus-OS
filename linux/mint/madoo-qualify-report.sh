#!/usr/bin/env bash
# Read-only hardware & resource report for MADOO Chromebook / Linux Mint live-media qualification.
# Never modifies firmware, NVRAM, or storage, and never reads serial numbers or UUIDs.
set -euo pipefail

MODE="markdown"

usage() {
  cat <<'USAGE'
Usage: bash linux/mint/madoo-qualify-report.sh [OPTIONS]

Collects a read-only qualification snapshot aligned with
docs/MADOO_CHROMEBOOK_QUALIFICATION.md without touching firmware, internal
storage, or unique device identifiers (serials/UUIDs are never read).

Options:
  --markdown  Print a Markdown qualification summary (default)
  --plain     Print plain key=value summary lines
  --help, -h  Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --markdown) MODE="markdown"; shift ;;
    --plain) MODE="plain"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

read_sysfs() {
  local path="$1"
  if [[ -r "$path" ]]; then
    tr -d '\0\n' < "$path"
  else
    printf 'unavailable'
  fi
}

os_pretty="unknown"
if [[ -r /etc/os-release ]]; then
  os_pretty="$(awk -F= '/^PRETTY_NAME=/{gsub(/"/,"",$2); print $2; exit}' /etc/os-release || true)"
  [[ -n "$os_pretty" ]] || os_pretty="unknown"
fi

kernel_info="$(uname -rsm)"
sys_vendor="$(read_sysfs /sys/class/dmi/id/sys_vendor)"
product_name="$(read_sysfs /sys/class/dmi/id/product_name)"
board_name="$(read_sysfs /sys/class/dmi/id/board_name)"
bios_version="$(read_sysfs /sys/class/dmi/id/bios_version)"

cpu_model="unknown"
if [[ -r /proc/cpuinfo ]]; then
  cpu_model="$(awk -F: '/^model name[[:space:]]*:/{gsub(/^[[:space:]]+/,"",$2); print $2; exit}' /proc/cpuinfo || true)"
  [[ -n "$cpu_model" ]] || cpu_model="unknown"
fi
cpu_cores="$(nproc 2>/dev/null || printf 'unknown')"

mem_total_mib="0"
mem_avail_mib="0"
if [[ -r /proc/meminfo ]]; then
  while read -r key val _; do
    case "$key" in
      MemTotal:) mem_total_mib=$(( val / 1024 )) ;;
      MemAvailable:) mem_avail_mib=$(( val / 1024 )) ;;
    esac
  done < /proc/meminfo
fi

root_df="unavailable"
if command -v df >/dev/null 2>&1; then
  root_df="$(df -h / | awk 'NR==2 {printf "%s total, %s used, %s avail (%s)", $2, $3, $4, $5}')"
fi

block_summary="unavailable"
if command -v lsblk >/dev/null 2>&1; then
  block_summary="$(lsblk -dn -o NAME,SIZE,TYPE,TRAN 2>/dev/null | tr '\n' '; ' | sed 's/; $//' || printf 'unavailable')"
  [[ -n "$block_summary" ]] || block_summary="none"
fi

pci_devices="lspci unavailable"
if command -v lspci >/dev/null 2>&1; then
  pci_devices="$(lspci 2>/dev/null | grep -iE 'vga|display|network|wireless|audio|bluetooth|mmc' || printf 'no matching PCI entries')"
fi

backlight_list="none"
for bl in /sys/class/backlight/*; do
  [[ -e "$bl" ]] || continue
  backlight_list="${bl##*/}"
  break
done

power_list="none"
for ps in /sys/class/power_supply/*; do
  [[ -e "$ps" ]] || continue
  if [[ "$power_list" == "none" ]]; then
    power_list="${ps##*/}"
  else
    power_list="${power_list}, ${ps##*/}"
  fi
done

session_desc="${XDG_CURRENT_DESKTOP:-unknown} / ${XDG_SESSION_TYPE:-unknown}"

if [[ "$MODE" == "plain" ]]; then
  printf 'os=%s\n' "$os_pretty"
  printf 'kernel=%s\n' "$kernel_info"
  printf 'vendor=%s\n' "$sys_vendor"
  printf 'product=%s\n' "$product_name"
  printf 'board=%s\n' "$board_name"
  printf 'firmware=%s\n' "$bios_version"
  printf 'cpu=%s (%s cores)\n' "$cpu_model" "$cpu_cores"
  printf 'memory_mib=%s total / %s avail\n' "$mem_total_mib" "$mem_avail_mib"
  printf 'root_storage=%s\n' "$root_df"
  printf 'block_devices=%s\n' "$block_summary"
  printf 'backlight=%s\n' "$backlight_list"
  printf 'power_supply=%s\n' "$power_list"
  printf 'session=%s\n' "$session_desc"
  exit 0
fi

cat <<REPORT
# MADOO Live-Media Qualification Snapshot

- **OS:** $os_pretty
- **Kernel / Arch:** $kernel_info
- **Session:** $session_desc
- **Vendor / Product / Board:** $sys_vendor / $product_name / $board_name
- **Firmware version:** $bios_version
- **CPU:** $cpu_model ($cpu_cores logical CPUs)
- **Memory:** $mem_total_mib MiB total, $mem_avail_mib MiB available
- **Root storage (/):** $root_df
- **Block devices (read-only):** $block_summary
- **Backlight driver:** $backlight_list
- **Power supply nodes:** $power_list

## Relevant PCI Devices (Display / Network / Audio / MMC)

\`\`\`text
$pci_devices
\`\`\`
REPORT
