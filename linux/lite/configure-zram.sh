#!/usr/bin/env bash
# Transparent zram and conservative swap helper for NEXUS Lite.
# Never treats swap as physical RAM and never modifies disk partitions.
set -euo pipefail

DRY_RUN=false
ACTION="${1:-status}"
if [[ "$ACTION" == "--help" || "$ACTION" == "-h" ]]; then
  cat <<'USAGE'
Usage: bash linux/lite/configure-zram.sh [OPTIONS] <status|enable>

Inspects real physical RAM and swap/zram status, or configures compressed zram
swap (/etc/default/zramswap with zstd) without touching disk partitions.

Options:
  --dry-run   Preview zram configuration without writing system files
  --help, -h  Show this help message
USAGE
  exit 0
fi

args=()
while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) exec bash "$0" --help ;;
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
            mem[k] = round(int(tok) / 1024)

zram_devs = [p.name for p in sorted(Path("/sys/block").glob("zram*"))]
payload = {
    "ram_total_mib": mem.get("MemTotal"),
    "ram_available_mib": mem.get("MemAvailable"),
    "swap_total_mib": mem.get("SwapTotal", 0),
    "swap_free_mib": mem.get("SwapFree", 0),
    "zram_devices": zram_devs,
    "note": "Swap and zram reduce OOM crashes under transient spikes; they do not replace physical RAM.",
}
print(json.dumps(payload, indent=2))
PY
    ;;
  enable)
    if [[ "$DRY_RUN" == true ]]; then
      echo '[dry-run] Write /etc/default/zramswap (ALGO=zstd, PERCENT=50, PRIORITY=100)'
      echo '[dry-run] sysctl -w vm.swappiness=60'
      echo '[dry-run] systemctl restart zramswap.service'
      exit 0
    fi
    if [[ "$(id -u)" -ne 0 ]]; then
      echo 'Enabling zramswap requires root privileges (sudo) or --dry-run.' >&2
      exit 1
    fi
    cat > /etc/default/zramswap <<'CFG'
ALGO=zstd
PERCENT=50
PRIORITY=100
CFG
    sysctl -w vm.swappiness=60 >/dev/null
    if command -v systemctl >/dev/null 2>&1; then
      systemctl enable --now zramswap.service >/dev/null 2>&1 || true
    fi
    echo 'Configured zram swap (zstd, 50% cap, swappiness=60).'
    ;;
  *)
    printf 'Unknown action: %s (expected status or enable)\n' "$ACTION" >&2
    exit 2
    ;;
esac
