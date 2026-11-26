#!/usr/bin/env python3
"""Compare NEXUS Lite Openbox vs. NEXUS Lite LXQt QEMU validation JSON outputs.
Produces machine-readable JSON and Markdown comparison tables from guest telemetry.
"""
import argparse
import json
from pathlib import Path
import sys


def load_runs(paths):
    by_ram = {}
    meta = {}
    for p in paths:
        if not p.is_file():
            continue
        data = json.loads(p.read_text(encoding="utf-8"))
        meta = {
            "edition": data.get("edition"),
            "accel": data.get("accel"),
            "graphical": data.get("graphical"),
            "install_test": data.get("install_test"),
        }
        for run in data.get("runs", []):
            ram = run.get("ram_mib")
            if ram is not None:
                by_ram[int(ram)] = run
    return meta, by_ram


def extract_metrics(run):
    if not run:
        return None
    reps = run.get("live_reps") or []
    r0 = reps[0] if reps else {}
    st = r0.get("stages") or {}
    desk = r0.get("desktop") or {}
    apps = r0.get("apps") or {}
    zp = r0.get("zram_pressure") or {}
    ir = r0.get("install_report") or {}

    def stage_val(name, field):
        return (st.get(name) or {}).get(field)

    def zram_ratio():
        for s in ("3_idle", "6_multi_apps", "7_post_close"):
            zlist = (st.get(s) or {}).get("zram") or []
            if zlist and zlist[0].get("compression_ratio"):
                return zlist[0].get("compression_ratio")
        return None

    boots = run.get("installed_boots") or []
    ib0 = boots[0] if boots else {}
    ib_st = ib0.get("stages") or {}

    return {
        "ram_mib": run.get("ram_mib"),
        "uefi_boot": run.get("uefi_boot_success"),
        "live_pass": f"{run.get('live_successes', 0)}/{run.get('live_attempts', 0)}",
        "install_pass": f"{run.get('install_successes', 0)}/{run.get('install_attempts', 0)}",
        "install_sec": ir.get("elapsed_sec"),
        "installed_boot_pass": f"{run.get('installed_boot_successes', 0)}/{run.get('installed_boot_attempts', 0)}",
        "persistence": run.get("persistence_verified"),
        "wm_ready_sec": desk.get("wm_ready_sec"),
        "panel_ready_sec": desk.get("panel_ready_sec"),
        "panel_rss_mib": desk.get("panel_rss_mib"),
        "apps_ok": r0.get("application_test_success"),
        "ram_total_mib": stage_val("1_post_login", "ram_total_mib"),
        "post_login_used_mib": stage_val("1_post_login", "used_ram_mib"),
        "post_login_avail_mib": stage_val("1_post_login", "available_ram_mib"),
        "idle_used_mib": stage_val("3_idle", "used_ram_mib"),
        "idle_avail_mib": stage_val("3_idle", "available_ram_mib"),
        "idle_cached_mib": stage_val("3_idle", "cached_mib"),
        "idle_swap_mib": stage_val("3_idle", "swap_used_mib"),
        "idle_cpu_pct": stage_val("3_idle", "cpu_usage_pct"),
        "file_manager_used_mib": stage_val("4_file_manager", "used_ram_mib"),
        "terminal_used_mib": stage_val("5_terminal", "used_ram_mib"),
        "multi_apps_used_mib": stage_val("6_multi_apps", "used_ram_mib"),
        "post_close_used_mib": stage_val("7_post_close", "used_ram_mib"),
        "post_close_swap_mib": stage_val("7_post_close", "swap_used_mib"),
        "zram_ratio": zram_ratio(),
        "zram_pressure": zp.get("status") if not zp.get("skipped") else "N/A",
        "oom_kills": max(
            ((v or {}).get("oom_kill_count") or 0) for v in st.values()
        ) if st else 0,
        "installed_idle_used_mib": (ib_st.get("3_idle") or {}).get("used_ram_mib"),
        "installed_multi_used_mib": (ib_st.get("6_multi_apps") or {}).get("used_ram_mib"),
        "installed_post_close_used_mib": (ib_st.get("7_post_close") or {}).get("used_ram_mib"),
        "installed_wm_ready_sec": ib0.get("wm_ready_sec"),
        "installed_panel_ready_sec": ib0.get("panel_ready_sec"),
        "installed_panel_rss_mib": (ib0.get("desktop") or {}).get("panel_rss_mib"),
        "live_shots": [(s.get("name"), s.get("non_black_pct")) for s in (r0.get("screenshots") or [])],
    }


def render_markdown(rows):
    lines = [
        "# NEXUS Lite Desktop Comparison: Openbox vs. LXQt",
        "",
        "| RAM Tier | Desktop | Live Boots | WM / Panel Startup (s) | Panel RSS (MiB) | `1_post_login` Used / Avail | `3_idle` Used / Avail / Cache / Swap | `4_fm` | `5_term` | `6_multi` | `7_close` | CPU Idle (%) | ZRAM Ratio / Pressure | OOM | Install | Installed 3-Boot |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for row in rows:
        ram = row["ram_mib"]
        for label, key in (("Openbox", "openbox"), ("LXQt", "lxqt")):
            m = row.get(key)
            if not m:
                lines.append(f"| {ram} MiB | {label} | — | — | — | — | — | — | — | — | — | — | — | — | — | — |")
                continue
            lines.append(
                f"| {ram} MiB | {label} | {m['live_pass']} | "
                f"{m['wm_ready_sec']} / {m['panel_ready_sec']} | {m['panel_rss_mib']} | "
                f"{m['post_login_used_mib']} / {m['post_login_avail_mib']} | "
                f"{m['idle_used_mib']} / {m['idle_avail_mib']} / {m['idle_cached_mib']} / {m['idle_swap_mib']} | "
                f"{m['file_manager_used_mib']} | {m['terminal_used_mib']} | {m['multi_apps_used_mib']} | "
                f"{m['post_close_used_mib']} | {m['idle_cpu_pct']} | "
                f"{m['zram_ratio']}x / {m['zram_pressure']} | {m['oom_kills']} | "
                f"{m['install_pass']} | {m['installed_boot_pass']} |"
            )
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser(description="Compare NEXUS Lite Openbox vs. LXQt QEMU results.")
    ap.add_argument("--openbox-json", nargs="+", type=Path, required=True)
    ap.add_argument("--lxqt-json", nargs="+", type=Path, required=True)
    ap.add_argument("--out-json", type=Path, required=True)
    ap.add_argument("--out-md", type=Path, required=True)
    args = ap.parse_args()

    ob_meta, ob_runs = load_runs(args.openbox_json)
    lx_meta, lx_runs = load_runs(args.lxqt_json)
    all_rams = sorted(set(ob_runs.keys()) | set(lx_runs.keys()))

    rows = []
    for ram in all_rams:
        ob_m = extract_metrics(ob_runs.get(ram))
        lx_m = extract_metrics(lx_runs.get(ram))
        delta_idle = None
        if ob_m and lx_m and ob_m["idle_used_mib"] is not None and lx_m["idle_used_mib"] is not None:
            delta_idle = round(lx_m["idle_used_mib"] - ob_m["idle_used_mib"], 1)
        rows.append({
            "ram_mib": ram,
            "openbox": ob_m,
            "lxqt": lx_m,
            "lxqt_minus_openbox_idle_mib": delta_idle,
        })

    out_obj = {
        "openbox_meta": ob_meta,
        "lxqt_meta": lx_meta,
        "comparison": rows,
    }
    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(out_obj, indent=2) + "\n", encoding="utf-8")
    args.out_md.parent.mkdir(parents=True, exist_ok=True)
    args.out_md.write_text(render_markdown(rows), encoding="utf-8")
    print(f"Wrote comparison JSON: {args.out_json}")
    print(f"Wrote comparison Markdown: {args.out_md}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
