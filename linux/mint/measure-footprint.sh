#!/usr/bin/env bash
# Read-only footprint and hardware telemetry check for Linux Mint / Ubuntu guests.
# Measures actual host/VM RAM, swap, root filesystem space, and top processes.
set -euo pipefail

FORMAT="text"

usage() {
  cat <<'USAGE'
Usage: bash linux/mint/measure-footprint.sh [--markdown]

Reads /etc/os-release, /proc/meminfo, root filesystem usage, and top memory
processes without modifying system state. Intended for recording baseline
resource measurements inside a Linux Mint 22.3 Xfce QEMU guest or live session.
USAGE
}

while (($#)); do
  case "$1" in
    --markdown) FORMAT="markdown"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -r /proc/meminfo ]] || { echo '/proc/meminfo is required (run on Linux).' >&2; exit 1; }

OS_NAME="Unknown Linux"
if [[ -r /etc/os-release ]]; then
  OS_NAME="$(awk -F= '$1 == "PRETTY_NAME" { gsub(/^"|"$/, "", $2); print $2; exit }' /etc/os-release)"
fi
KERNEL="$(uname -r)"
ARCH="$(uname -m)"
TIMESTAMP_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

mem_kb() {
  awk -v key="$1:" '$1 == key { print $2; exit }' /proc/meminfo
}

MEM_TOTAL_KB="$(mem_kb MemTotal)"
MEM_AVAIL_KB="$(mem_kb MemAvailable)"
MEM_FREE_KB="$(mem_kb MemFree)"
SWAP_TOTAL_KB="$(mem_kb SwapTotal)"
SWAP_FREE_KB="$(mem_kb SwapFree)"
MEM_USED_EST_MIB=$(( (MEM_TOTAL_KB - MEM_AVAIL_KB) / 1024 ))
MEM_TOTAL_MIB=$(( MEM_TOTAL_KB / 1024 ))
MEM_AVAIL_MIB=$(( MEM_AVAIL_KB / 1024 ))
MEM_FREE_MIB=$(( MEM_FREE_KB / 1024 ))
SWAP_USED_MIB=$(( (SWAP_TOTAL_KB - SWAP_FREE_KB) / 1024 ))
SWAP_TOTAL_MIB=$(( SWAP_TOTAL_KB / 1024 ))

ROOT_DF="$(df -P -B1M / | awk 'NR==2 { printf "%s MiB total, %s MiB used, %s MiB avail (%s)", $2, $3, $4, $5 }')"

COMPOSITING="unavailable"
if command -v xfconf-query >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
  COMPOSITING="$(xfconf-query -c xfwm4 -p /general/use_compositing 2>/dev/null || echo 'unset')"
fi

TOP_PROCS="$(ps -eo pid,comm,rss --sort=-rss | awk 'NR>1 && NR<=9 { printf "  %-7s %-20s %6.1f MiB\n", $1, $2, $3/1024 }')"

if [[ "$FORMAT" == "markdown" ]]; then
  cat <<EOF
### NEXUS Linux Footprint Measurement ($TIMESTAMP_UTC)

| Metric | Measured value |
|---|---|
| OS | $OS_NAME |
| Kernel / Arch | \`$KERNEL\` ($ARCH) |
| RAM total | $MEM_TOTAL_MIB MiB |
| RAM available | $MEM_AVAIL_MIB MiB (free: $MEM_FREE_MIB MiB) |
| RAM used (Total - Available) | $MEM_USED_EST_MIB MiB |
| Swap used / total | $SWAP_USED_MIB MiB / $SWAP_TOTAL_MIB MiB |
| Root filesystem (/) | $ROOT_DF |
| Xfwm4 compositing | $COMPOSITING |

Top RSS processes:
\`\`\`text
$TOP_PROCS
\`\`\`
EOF
else
  cat <<EOF
NEXUS Linux Footprint Measurement ($TIMESTAMP_UTC)
============================================================
OS:           $OS_NAME
Kernel/Arch:  $KERNEL ($ARCH)
RAM Total:    $MEM_TOTAL_MIB MiB
RAM Avail:    $MEM_AVAIL_MIB MiB (MemFree: $MEM_FREE_MIB MiB)
RAM Used*:    $MEM_USED_EST_MIB MiB (MemTotal - MemAvailable)
Swap:         $SWAP_USED_MIB MiB / $SWAP_TOTAL_MIB MiB
Root (/):     $ROOT_DF
Compositing:  $COMPOSITING

Top RSS processes:
$TOP_PROCS
EOF
fi
