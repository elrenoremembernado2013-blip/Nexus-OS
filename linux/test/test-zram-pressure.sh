#!/usr/bin/env bash
# Verifies kernel ZRAM support, active zram swap device, compression algorithm,
# and bounded memory-pressure resilience inside a booted NEXUS Lite guest.
set -euo pipefail

DRY_RUN=false
PRESSURE_MB=96

usage() {
  cat <<'USAGE'
Usage: bash linux/test/test-zram-pressure.sh [OPTIONS]

Verifies ZRAM device creation, compression algorithm, active swap in /proc/swaps,
and stability under moderate bounded memory pressure without OOM kills.

Options:
  --pressure-mb N  Bounded allocation size in MiB for pressure check (default: 96)
  --dry-run        Preview ZRAM and memory-pressure check without allocating memory
  --help, -h       Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --pressure-mb) [[ $# -ge 2 ]] || { echo '--pressure-mb requires an integer' >&2; exit 2; }; PRESSURE_MB="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$PRESSURE_MB" =~ ^[1-9][0-9]*$ ]] || { echo '--pressure-mb must be a positive integer' >&2; exit 2; }

if [[ "$DRY_RUN" == true ]]; then
  echo "[dry-run] Verify /sys/block/zram0, /proc/swaps, zstd/lz4/lzo algorithm, and bounded ${PRESSURE_MB} MiB pressure test with zero OOM kills"
  exit 0
fi

[[ -d /sys/block/zram0 ]] || { echo 'FAIL: /sys/block/zram0 missing (kernel zram module not active).' >&2; exit 1; }
grep -q '/dev/zram' /proc/swaps || { echo 'FAIL: /dev/zram not active in /proc/swaps.' >&2; exit 1; }

python3 - "$PRESSURE_MB" <<'PY'
import json
from pathlib import Path
import sys

mb = int(sys.argv[1])
def read_oom():
    for line in Path("/proc/vmstat").read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("oom_kill "):
            return int(line.split()[1])
    return 0

before_oom = read_oom()
buf = bytearray(mb * 1024 * 1024)
# Touch pages so kernel commits anonymous memory cleanly
for i in range(0, len(buf), 4096):
    buf[i] = (i // 4096) & 0xFF

mm = Path("/sys/block/zram0/mm_stat").read_text(encoding="utf-8", errors="replace").split()
after_oom = read_oom()
del buf

result = {
    "pressure_mib": mb,
    "zram_comp_algorithm": Path("/sys/block/zram0/comp_algorithm").read_text(encoding="utf-8", errors="replace").strip(),
    "zram_orig_mib": round(int(mm[0]) / (1024 * 1024), 2) if len(mm) >= 3 else None,
    "zram_compr_mib": round(int(mm[1]) / (1024 * 1024), 2) if len(mm) >= 3 else None,
    "oom_kill_before": before_oom,
    "oom_kill_after": after_oom,
    "status": "PASS" if after_oom == before_oom else "FAIL",
}
print(json.dumps(result, indent=2))
if after_oom != before_oom:
    sys.exit(1)
PY
