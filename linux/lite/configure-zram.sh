#!/usr/bin/env bash
# Transparent zram and conservative swap helper for NEXUS Lite.
# Never treats swap as physical RAM and never modifies disk partitions.
set -euo pipefail

DRY_RUN=false

usage() {
  cat <<'USAGE'
Usage: bash linux/lite/configure-zram.sh [OPTIONS] <status|enable>

Inspects real physical RAM, cached memory, swap, and compressed zram status,
or configures compressed zram swap (/etc/default/zramswap with zstd or fallback
lz4/lzo) without touching disk partitions.

Options:
  --dry-run   Preview zram configuration without writing system files
  --help, -h  Show this help message
USAGE
}

args=()
while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) args+=("$1"); shift ;;
  esac
done
ACTION="${args[0]:-status}"

case "$ACTION" in
  status)
    python3 - <<'PY'
import json
from pathlib import Path

mem = {}
for line in Path("/proc/meminfo").read_text(encoding="utf-8", errors="replace").splitlines():
    if ":" in line:
        k, rest = line.split(":", 1)
        tok = rest.strip().split()[0]
        if tok.isdigit():
            mem[k] = round(int(tok) / 1024, 1)

swaps = []
swaps_path = Path("/proc/swaps")
if swaps_path.is_file():
    for line in swaps_path.read_text(encoding="utf-8", errors="replace").splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 5:
            swaps.append({
                "device": parts[0],
                "type": parts[1],
                "size_mib": round(int(parts[2]) / 1024, 1),
                "used_mib": round(int(parts[3]) / 1024, 1),
                "priority": int(parts[4]),
            })

zram_devs = []
for p in sorted(Path("/sys/block").glob("zram*")):
    info = {"name": p.name}
    algo_file = p / "comp_algorithm"
    if algo_file.is_file():
        info["comp_algorithm"] = algo_file.read_text(encoding="utf-8", errors="replace").strip()
    mm_file = p / "mm_stat"
    if mm_file.is_file():
        cols = mm_file.read_text(encoding="utf-8", errors="replace").split()
        if len(cols) >= 3:
            info["orig_data_mib"] = round(int(cols[0]) / (1024 * 1024), 2)
            info["compr_data_mib"] = round(int(cols[1]) / (1024 * 1024), 2)
            info["mem_used_total_mib"] = round(int(cols[2]) / (1024 * 1024), 2)
    zram_devs.append(info)

total = mem.get("MemTotal", 0.0)
avail = mem.get("MemAvailable", 0.0)
payload = {
    "ram_total_mib": round(total),
    "ram_used_mib": round(max(0.0, total - avail)),
    "ram_available_mib": round(avail),
    "ram_free_mib": round(mem.get("MemFree", 0.0)),
    "cached_mib": round(mem.get("Cached", 0.0) + mem.get("SReclaimable", 0.0)),
    "buffers_mib": round(mem.get("Buffers", 0.0)),
    "swap_total_mib": round(mem.get("SwapTotal", 0.0)),
    "swap_free_mib": round(mem.get("SwapFree", 0.0)),
    "swaps": swaps,
    "zram_devices": zram_devs,
    "note": "Swap and compressed zram absorb transient spikes; they do not replace physical RAM.",
}
print(json.dumps(payload, indent=2))
PY
    ;;
  enable)
    if [[ "$DRY_RUN" == true ]]; then
      echo '[dry-run] modprobe zram'
      echo '[dry-run] Select zstd (or lz4/lzo fallback) and write /etc/default/zramswap (PERCENT=50, PRIORITY=100)'
      echo '[dry-run] sysctl -w vm.swappiness=60'
      echo '[dry-run] systemctl enable --now zramswap.service && verify /proc/swaps'
      exit 0
    fi
    if [[ "$(id -u)" -ne 0 ]]; then
      echo 'Enabling zramswap requires root privileges (sudo) or --dry-run.' >&2
      exit 1
    fi
    modprobe zram 2>/dev/null || true
    algo="zstd"
    if [[ -r /sys/block/zram0/comp_algorithm ]]; then
      supported="$(cat /sys/block/zram0/comp_algorithm)"
      if [[ "$supported" != *zstd* ]]; then
        if [[ "$supported" == *lz4* ]]; then algo="lz4"; else algo="lzo"; fi
      fi
    fi
    cat > /etc/default/zramswap <<CFG
ALGO=${algo}
PERCENT=50
PRIORITY=100
CFG
    sysctl -w vm.swappiness=60 >/dev/null
    if command -v systemctl >/dev/null 2>&1; then
      systemctl enable --now zramswap.service
      systemctl restart zramswap.service
    elif command -v zramswap >/dev/null 2>&1; then
      zramswap start
    else
      echo 'zramswap tooling not installed (install zram-tools).' >&2
      exit 1
    fi
    if ! grep -q '/dev/zram' /proc/swaps 2>/dev/null; then
      echo 'ERROR: zramswap configured but no /dev/zram swap device is active in /proc/swaps.' >&2
      exit 1
    fi
    printf 'Configured and verified zram swap (%s, 50%% cap, swappiness=60).\n' "$algo"
    ;;
  *)
    printf 'Unknown action: %s (expected status or enable)\n' "$ACTION" >&2
    exit 2
    ;;
esac
