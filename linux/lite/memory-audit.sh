#!/usr/bin/env bash
# Audit live memory, cache, swap, zram, CPU, OOM counters, and per-process RSS.
# Distinguishes Used RAM, Available RAM, Cached memory, Process RSS, Swap, and ZRAM.
set -euo pipefail

FORMAT="text"
STAGE="manual"
while (($#)); do
  case "$1" in
    --json) FORMAT="json"; shift ;;
    --stage) [[ $# -ge 2 ]] || { echo '--stage requires a label' >&2; exit 2; }; STAGE="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: bash linux/lite/memory-audit.sh [--json] [--stage NAME]"
      exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

python3 - "$FORMAT" "$STAGE" <<'PY'
import json
from pathlib import Path
import subprocess
import sys

fmt = sys.argv[1]
stage = sys.argv[2]
mem = {}
for line in Path("/proc/meminfo").read_text(encoding="utf-8", errors="replace").splitlines():
    if ":" in line:
        k, rest = line.split(":", 1)
        tok = rest.strip().split()[0]
        if tok.isdigit():
            mem[k] = round(int(tok) / 1024, 1)

vmstat = {}
vm_path = Path("/proc/vmstat")
if vm_path.is_file():
    for line in vm_path.read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1].isdigit():
            vmstat[parts[0]] = int(parts[1])

zram_orig = zram_compr = zram_used = 0.0
for mm in sorted(Path("/sys/block").glob("zram*/mm_stat")):
    cols = mm.read_text(encoding="utf-8", errors="replace").split()
    if len(cols) >= 3:
        zram_orig += int(cols[0]) / (1024 * 1024)
        zram_compr += int(cols[1]) / (1024 * 1024)
        zram_used += int(cols[2]) / (1024 * 1024)

procs = []
ps_res = subprocess.run(["ps", "-eo", "pid,comm,rss,vsz", "--sort=-rss"], capture_output=True, text=True)
total_rss_mib = 0.0
for idx, line in enumerate(ps_res.stdout.splitlines()[1:]):
    parts = line.split(None, 3)
    if len(parts) == 4 and parts[0].isdigit() and parts[2].isdigit():
        rss = int(parts[2]) / 1024
        total_rss_mib += rss
        if idx < 15:
            procs.append({"pid": int(parts[0]), "name": parts[1], "rss_mib": round(rss, 1)})

loadavg = Path("/proc/loadavg").read_text(encoding="utf-8", errors="replace").split()[:3]
total = mem.get("MemTotal", 0.0)
avail = mem.get("MemAvailable", 0.0)
swap_total = mem.get("SwapTotal", 0.0)
swap_free = mem.get("SwapFree", 0.0)

report = {
    "stage": stage,
    "ram_total_mib": round(total),
    "ram_used_mib": round(max(0.0, total - avail)),
    "ram_available_mib": round(avail),
    "ram_free_mib": round(mem.get("MemFree", 0.0)),
    "cached_mib": round(mem.get("Cached", 0.0) + mem.get("SReclaimable", 0.0)),
    "buffers_mib": round(mem.get("Buffers", 0.0)),
    "process_rss_sum_mib": round(total_rss_mib, 1),
    "swap_total_mib": round(swap_total),
    "swap_used_mib": round(max(0.0, swap_total - swap_free)),
    "zram_orig_mib": round(zram_orig, 2),
    "zram_compr_mib": round(zram_compr, 2),
    "zram_mem_used_mib": round(zram_used, 2),
    "oom_kill_count": vmstat.get("oom_kill", 0),
    "load_average": loadavg,
    "top_processes": procs,
    "preserved_essential_services": ["ufw", "unattended-upgrades", "polkit", "NetworkManager", "systemd-journald", "dbus"],
    "excluded_in_lite_512": ["cinnamon-session", "picom", "tracker-miner-fs", "evolution-data-server", "steam", "default-web-browser"],
}

if fmt == "json":
    print(json.dumps(report, indent=2))
else:
    print(
        f"NEXUS Lite Memory Audit [{stage}]: "
        f"{report['ram_used_mib']}/{report['ram_total_mib']} MiB used, "
        f"{report['ram_available_mib']} MiB avail, {report['cached_mib']} MiB cached, "
        f"swap {report['swap_used_mib']}/{report['swap_total_mib']} MiB, "
        f"zram mem {report['zram_mem_used_mib']} MiB, oom_kill={report['oom_kill_count']}"
    )
    for p in procs[:8]:
        print(f"  pid {p['pid']:<6} {p['name']:<20} {p['rss_mib']} MiB")
    print("Preserved essential security/network:", ", ".join(report["preserved_essential_services"]))
    print("Excluded in 512 MB Lite:", ", ".join(report["excluded_in_lite_512"]))
PY
