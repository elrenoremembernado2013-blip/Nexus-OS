#!/usr/bin/env bash
# Collects structured guest memory, cache, swap, zram, CPU, OOM, and process RSS
# measurements across the six NEXUS Phase 12 acceptance stages inside a booted guest.
set -euo pipefail

STAGE="post_login"
OUT_FILE=""
DRY_RUN=false

usage() {
  cat <<'USAGE'
Usage: bash linux/test/guest-mem-probe.sh [OPTIONS]

Captures /proc/meminfo, free -h, ps RSS, /proc/swaps, /sys/block/zram*,
load/CPU, and /proc/vmstat oom_kill inside a booted guest.

Options:
  --stage NAME   post_login | idle_5min | file_manager | terminal | multi_apps | post_close
  --out PATH     Optional path to write JSON summary
  --dry-run      Print planned probe stages without collecting live metrics
  --help, -h     Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --stage) [[ $# -ge 2 ]] || { echo '--stage requires a value' >&2; exit 2; }; STAGE="$2"; shift 2 ;;
    --out) [[ $# -ge 2 ]] || { echo '--out requires a path' >&2; exit 2; }; OUT_FILE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$DRY_RUN" == true ]]; then
  echo "[dry-run] Probe guest memory stage=$STAGE (/proc/meminfo, free -h, ps, swapon, zram mm_stat, oom_kill)"
  exit 0
fi

python3 - "$STAGE" "$OUT_FILE" <<'PY'
import json
from pathlib import Path
import subprocess
import sys

stage, out_file = sys.argv[1], sys.argv[2]

mem = {}
for line in Path("/proc/meminfo").read_text(encoding="utf-8", errors="replace").splitlines():
    if ":" in line:
        k, rest = line.split(":", 1)
        tok = rest.strip().split()[0]
        if tok.isdigit():
            mem[k] = round(int(tok) / 1024, 1)

vmstat = {}
if Path("/proc/vmstat").is_file():
    for line in Path("/proc/vmstat").read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1].isdigit():
            vmstat[parts[0]] = int(parts[1])

zram = []
for dev in sorted(Path("/sys/block").glob("zram*")):
    item = {"device": dev.name}
    if (dev / "comp_algorithm").is_file():
        item["comp_algorithm"] = (dev / "comp_algorithm").read_text(encoding="utf-8", errors="replace").strip()
    if (dev / "mm_stat").is_file():
        cols = (dev / "mm_stat").read_text(encoding="utf-8", errors="replace").split()
        if len(cols) >= 3:
            item["orig_data_mib"] = round(int(cols[0]) / (1024 * 1024), 2)
            item["compr_data_mib"] = round(int(cols[1]) / (1024 * 1024), 2)
            item["mem_used_total_mib"] = round(int(cols[2]) / (1024 * 1024), 2)
    zram.append(item)

ps_out = subprocess.run(["ps", "-eo", "pid,comm,rss,vsz", "--sort=-rss"], capture_output=True, text=True).stdout
procs = []
rss_sum = 0.0
for idx, line in enumerate(ps_out.splitlines()[1:]):
    cols = line.split(None, 3)
    if len(cols) == 4 and cols[0].isdigit() and cols[2].isdigit():
        rss = int(cols[2]) / 1024
        rss_sum += rss
        if idx < 15:
            procs.append({"pid": int(cols[0]), "comm": cols[1], "rss_mib": round(rss, 1)})

free_h = subprocess.run(["free", "-h"], capture_output=True, text=True).stdout.strip()
total = mem.get("MemTotal", 0.0)
avail = mem.get("MemAvailable", 0.0)
swap_tot = mem.get("SwapTotal", 0.0)
swap_free = mem.get("SwapFree", 0.0)

payload = {
    "stage": stage,
    "ram_total_mib": round(total),
    "used_ram_mib": round(max(0.0, total - avail)),
    "available_ram_mib": round(avail),
    "cached_mib": round(mem.get("Cached", 0.0) + mem.get("SReclaimable", 0.0)),
    "buffers_mib": round(mem.get("Buffers", 0.0)),
    "process_rss_total_mib": round(rss_sum, 1),
    "swap_total_mib": round(swap_tot),
    "swap_used_mib": round(max(0.0, swap_tot - swap_free)),
    "zram": zram,
    "oom_kill_count": vmstat.get("oom_kill", 0),
    "loadavg": Path("/proc/loadavg").read_text(encoding="utf-8", errors="replace").split()[:3],
    "free_h": free_h,
    "top_processes": procs,
}
encoded = json.dumps(payload, indent=2) + "\n"
if out_file:
    Path(out_file).write_text(encoded, encoding="utf-8")
print(encoded, end="")
PY
