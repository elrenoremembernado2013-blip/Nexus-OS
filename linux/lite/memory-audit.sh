#!/usr/bin/env bash
# Audit live memory usage by process and list preserved essential services vs
# optional daemons excluded from NEXUS Lite (512 MB Experimental / 1 GB).
set -euo pipefail

FORMAT="text"
while (($#)); do
  case "$1" in
    --json) FORMAT="json"; shift ;;
    --help|-h)
      echo "Usage: bash linux/lite/memory-audit.sh [--json]"
      exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

python3 - "$FORMAT" <<'PY'
import json
from pathlib import Path
import subprocess
import sys

fmt = sys.argv[1]
mem = {}
for line in Path("/proc/meminfo").read_text(encoding="utf-8", errors="replace").splitlines():
    if ":" in line:
        k, rest = line.split(":", 1)
        tok = rest.strip().split()[0]
        if tok.isdigit():
            mem[k] = round(int(tok) / 1024)

procs = []
ps_res = subprocess.run(["ps", "-eo", "pid,comm,rss", "--sort=-rss"], capture_output=True, text=True)
for line in ps_res.stdout.splitlines()[1:11]:
    parts = line.split(None, 2)
    if len(parts) == 3 and parts[0].isdigit() and parts[2].isdigit():
        procs.append({"pid": int(parts[0]), "name": parts[1], "rss_mib": round(int(parts[2]) / 1024, 1)})

report = {
    "ram_total_mib": mem.get("MemTotal"),
    "ram_available_mib": mem.get("MemAvailable"),
    "ram_used_mib": (mem.get("MemTotal", 0) - mem.get("MemAvailable", 0)),
    "swap_total_mib": mem.get("SwapTotal", 0),
    "top_processes": procs,
    "preserved_essential_services": ["ufw", "unattended-upgrades", "polkit", "NetworkManager", "systemd-journald", "dbus"],
    "excluded_in_lite_512": ["cinnamon-session", "picom", "tracker-miner-fs", "evolution-data-server", "steam", "default-web-browser"],
}

if fmt == "json":
    print(json.dumps(report, indent=2))
else:
    print(f"NEXUS Lite Memory Audit: {report['ram_used_mib']} / {report['ram_total_mib']} MiB used ({report['ram_available_mib']} MiB avail)")
    for p in procs[:6]:
        print(f"  pid {p['pid']:<6} {p['name']:<20} {p['rss_mib']} MiB")
    print("Preserved essential security/network:", ", ".join(report["preserved_essential_services"]))
    print("Excluded in 512 MB Lite:", ", ".join(report["excluded_in_lite_512"]))
PY
