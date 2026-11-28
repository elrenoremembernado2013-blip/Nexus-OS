#!/usr/bin/env bash
# NEXUS OS Performance, Boot Analysis, Safe Cache Cleanup & Low-Resource Mode helper.
# Runs strictly as the regular user (delegating APT cache clean to pkexec only with --confirm).
# Never deletes personal documents, never disables security/firewall/network services,
# and never fabricates benchmark metrics.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
XFCE_APPLY="$SCRIPT_DIR/apply-nexus-xfce.sh"
[[ -x "$XFCE_APPLY" ]] || XFCE_APPLY="$(command -v nexus-apply-xfce || true)"
CINNAMON_APPLY="$REPO_ROOT/linux/cinnamon/apply-nexus-cinnamon.sh"
[[ -x "$CINNAMON_APPLY" ]] || CINNAMON_APPLY="$(command -v nexus-apply-cinnamon || true)"
LXQT_APPLY="$REPO_ROOT/linux/lite/scripts/apply-nexus-lite-lxqt.sh"
[[ -x "$LXQT_APPLY" ]] || LXQT_APPLY="$(command -v nexus-apply-lite-lxqt || true)"
LITE_APPLY="$REPO_ROOT/linux/lite/apply-nexus-lite.sh"
[[ -x "$LITE_APPLY" ]] || LITE_APPLY="$(command -v nexus-apply-lite || true)"

CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_DIR="$CFG_DIR/nexus-os"
LOW_RES_FILE="$STATE_DIR/low-resource.state"

DRY_RUN=false
CONFIRM=false
TARGET=""

usage() {
  cat <<'USAGE'
Usage: bash linux/mint/nexus-performance-cli.sh [OPTIONS] <command> [args...]

Safe, user-controlled performance diagnostics, boot timing, startup management,
low-resource mode, and cache cleanup helper for NEXUS OS.

Options:
  --dry-run        Preview actions without modifying files or system state
  --confirm        Required to execute cache cleanup (`cleanup`)
  --target NAME    Cache cleanup target: thumbnails | wallpapers | mesa | apt
  --help, -h       Show this help message

Commands:
  overview                      Print JSON memory, boot timing, startup apps, storage & cleanup preview
  low-resource <enable|disable|status>
                                Toggle reversible Low-Resource Mode (never disables security)
  startup <enable|disable> <id.desktop>
                                Reversible per-user autostart toggle in ~/.config/autostart
  cleanup --target NAME --confirm
                                Clean ONLY the confirmed cache directory (never user files)
USAGE
}

args=()
while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --confirm) CONFIRM=true; shift ;;
    --target) [[ $# -ge 2 ]] || { echo '--target requires a value' >&2; exit 2; }; TARGET="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) args+=("$1"); shift ;;
  esac
done

[[ ${#args[@]} -ge 1 ]] || { usage >&2; exit 2; }
CMD="${args[0]}"

read_low_res() {
  if [[ -r "$LOW_RES_FILE" ]] && grep -qx 'enabled=true' "$LOW_RES_FILE"; then
    printf 'enabled'
  else
    printf 'disabled'
  fi
}

lite_saved_args() {
  LITE_PRESERVE_ARGS=()
  local profile_file="$STATE_DIR/lite-profile"
  [[ -r "$profile_file" ]] || return 0
  local saved_theme saved_accent saved_appearance
  saved_theme="$(grep -E '^theme=' "$profile_file" | head -n1 | cut -d= -f2- || true)"
  saved_accent="$(grep -E '^accent=' "$profile_file" | head -n1 | cut -d= -f2- || true)"
  saved_appearance="$(grep -E '^appearance=' "$profile_file" | head -n1 | cut -d= -f2- || true)"
  case "$saved_theme" in
    midnight|nebula|arctic|emerald|solar) LITE_PRESERVE_ARGS+=(--theme "$saved_theme") ;;
  esac
  if [[ "$saved_accent" =~ ^#[0-9A-Fa-f]{6}$ ]]; then
    LITE_PRESERVE_ARGS+=(--accent "$saved_accent")
  fi
  if [[ "$saved_appearance" == "dark" || "$saved_appearance" == "light" ]]; then
    LITE_PRESERVE_ARGS+=(--appearance "$saved_appearance")
  fi
}

case "$CMD" in
  overview)
    lr_state="$(read_low_res)"
    python3 - "$lr_state" "$CFG_DIR" "$CACHE_DIR" "$DATA_DIR" <<'PY'
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

lr_state = sys.argv[1]
cfg_dir = Path(sys.argv[2])
cache_dir = Path(sys.argv[3])
data_dir = Path(sys.argv[4])

def read_text(p: Path):
    try:
        return p.read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return None

desktop = (os.environ.get("XDG_CURRENT_DESKTOP") or os.environ.get("DESKTOP_SESSION") or "").lower()
if "cinnamon" in desktop:
    edition = "cinnamon"
elif "xfce" in desktop:
    edition = "xfce"
elif "lxqt" in desktop:
    edition = "lite-lxqt"
elif "openbox" in desktop:
    edition = "lite"
elif Path("/etc/nexus-os-release").is_file():
    rel = read_text(Path("/etc/nexus-os-release")) or ""
    m = re.search(r'^NEXUS_EDITION="?([a-z0-9-]+)"?', rel, re.M)
    edition = m.group(1) if m else "xfce"
elif shutil.which("cinnamon-session"):
    edition = "cinnamon"
elif shutil.which("lxqt-session"):
    edition = "lite-lxqt"
elif shutil.which("xfce4-session"):
    edition = "xfce"
else:
    edition = "lite"

# Memory & Swap
mem = {}
raw_mem = read_text(Path("/proc/meminfo")) or ""
for line in raw_mem.splitlines():
    if ":" in line:
        k, rest = line.split(":", 1)
        tok = rest.strip().split()[0]
        if tok.isdigit():
            mem[k] = round(int(tok) / 1024, 1)

total_mib = round(mem.get("MemTotal", 0.0))
avail_mib = round(mem.get("MemAvailable", mem.get("MemFree", 0.0)))
used_mib = max(0, total_mib - avail_mib)
swap_total = round(mem.get("SwapTotal", 0.0))
swap_free = round(mem.get("SwapFree", 0.0))
swap_used = max(0, swap_total - swap_free)

zram_used = 0.0
for mm in sorted(Path("/sys/block").glob("zram*/mm_stat")):
    cols = (read_text(mm) or "").split()
    if len(cols) >= 3 and cols[2].isdigit():
        zram_used += int(cols[2]) / (1024 * 1024)

# Uptime
uptime_s = None
up_raw = read_text(Path("/proc/uptime"))
if up_raw:
    first = up_raw.split()[0]
    try:
        uptime_s = round(float(first))
    except ValueError:
        pass

# Boot duration & slow units via systemd-analyze (read-only)
boot = {
    "systemd_analyze_available": False,
    "summary": "Unavailable (systemd not active or running in container)",
    "firmware_s": None,
    "loader_s": None,
    "kernel_s": None,
    "userspace_s": None,
    "total_s": None,
    "top_slow_units": [],
}
if shutil.which("systemd-analyze") and Path("/run/systemd/system").is_dir():
    boot["systemd_analyze_available"] = True
    try:
        tres = subprocess.run(["systemd-analyze", "time"], capture_output=True, text=True, timeout=4)
        if tres.returncode == 0 and tres.stdout.strip():
            line = tres.stdout.strip().splitlines()[0]
            boot["summary"] = line
            for label, pat in (
                ("firmware_s", r"([\d.]+)(ms|s)\s+\(firmware\)"),
                ("loader_s", r"([\d.]+)(ms|s)\s+\(loader\)"),
                ("kernel_s", r"([\d.]+)(ms|s)\s+\(kernel\)"),
                ("userspace_s", r"([\d.]+)(ms|s)\s+\(userspace\)"),
                ("total_s", r"=\s*([\d.]+)(ms|s)"),
            ):
                m = re.search(pat, line)
                if m:
                    val = float(m.group(1))
                    if m.group(2) == "ms":
                        val = round(val / 1000.0, 3)
                    boot[label] = val
    except Exception:
        pass
    try:
        bres = subprocess.run(["systemd-analyze", "blame", "--no-pager"], capture_output=True, text=True, timeout=4)
        if bres.returncode == 0:
            units = []
            for ln in bres.stdout.splitlines()[:8]:
                parts = ln.strip().split(None, 1)
                if len(parts) == 2:
                    units.append({"time": parts[0], "unit": parts[1]})
            boot["top_slow_units"] = units
    except Exception:
        pass

# Startup applications (user + system XDG autostart, read-only)
essential_prefixes = ("polkit", "lxpolkit", "gnome-keyring", "nm-applet", "xdg-user-dirs", "at-spi")
startup_apps = []
seen = set()
user_autostart = cfg_dir / "autostart"
sys_autostart = Path("/etc/xdg/autostart")

def parse_desktop(path: Path):
    txt = read_text(path) or ""
    name = path.stem
    hidden = False
    exec_cmd = ""
    for ln in txt.splitlines():
        if ln.startswith("Name=") and name == path.stem:
            name = ln.split("=", 1)[1].strip()
        elif ln.startswith("Hidden="):
            hidden = ln.split("=", 1)[1].strip().lower() == "true"
        elif ln.startswith("Exec=") and not exec_cmd:
            exec_cmd = ln.split("=", 1)[1].strip()
    return name, hidden, exec_cmd

for base_dir, scope in ((user_autostart, "user"), (sys_autostart, "system")):
    if not base_dir.is_dir():
        continue
    for df in sorted(base_dir.glob("*.desktop")):
        if df.name in seen:
            continue
        seen.add(df.name)
        name, hidden, exec_cmd = parse_desktop(df)
        low_id = df.name.lower()
        essential = any(low_id.startswith(p) for p in essential_prefixes)
        startup_apps.append({
            "id": df.name,
            "name": name,
            "scope": scope,
            "enabled": not hidden,
            "essential": essential,
            "exec": exec_cmd[:80],
        })

# Storage type & safe cache preview
storage_devices = []
for blk in sorted(Path("/sys/block").iterdir()) if Path("/sys/block").is_dir() else []:
    if blk.name.startswith(("loop", "ram", "zram", "dm-")):
        continue
    rot = read_text(blk / "queue/rotational")
    dtype = "hdd" if rot == "1" else ("ssd_or_nvme" if rot == "0" else "unknown")
    storage_devices.append({"device": blk.name, "kind": dtype})

def dir_stats(path: Path, suffix_filter=None):
    total = 0
    count = 0
    if path.is_dir():
        for fp in path.rglob("*"):
            if fp.is_file() and (not suffix_filter or fp.name.endswith(suffix_filter)):
                try:
                    total += fp.stat().st_size
                    count += 1
                except OSError:
                    pass
    return {"path": str(path), "bytes": total, "mib": round(total / (1024 * 1024), 2), "files": count}

cleanup_preview = [
    {"target": "thumbnails", "label": "Image thumbnail cache", "requires_admin": False, **dir_stats(cache_dir / "thumbnails")},
    {"target": "wallpapers", "label": "Downloaded wallpaper cache", "requires_admin": False, **dir_stats(cache_dir / "nexus-os" / "wallpapers")},
    {"target": "mesa", "label": "Mesa GPU shader cache", "requires_admin": False, **dir_stats(cache_dir / "mesa_shader_cache")},
    {"target": "apt", "label": "APT downloaded .deb archives", "requires_admin": True, **dir_stats(Path("/var/cache/apt/archives"), ".deb")},
]

recs = {
    "cinnamon": [
        "Disable unneeded Cinnamon desklets/applets if idle RAM exceeds your target.",
        "Enable Low-Resource Mode or unredirect fullscreen windows for lower compositing overhead during games.",
    ],
    "xfce": [
        "Use `nexus-apply-xfce --lightweight` or Low-Resource Mode to turn off Xfwm4 compositor shadows/opacity on older GPUs.",
        "Keep ZRAM enabled on 1-2 GiB systems to absorb browser memory spikes.",
    ],
    "lite-lxqt": [
        "LXQt runs Openbox with zero panel animation delay; avoid heavy Electron apps on <=1 GiB RAM.",
        "Keep zramswap enabled (`configure-zram.sh enable`) for responsive multitasking.",
    ],
    "lite": [
        "Lite Openbox is already the minimal tier (no compositor, minimal tint2 panel, 2 workspaces in 512 MB profile).",
        "Use `lite-512` profile on <=768 MiB systems and avoid running simultaneous heavy web browsers.",
    ],
}

payload = {
    "edition": edition,
    "low_resource_mode": lr_state,
    "uptime_seconds": uptime_s,
    "memory": {
        "ram_total_mib": total_mib,
        "ram_used_mib": used_mib,
        "ram_available_mib": avail_mib,
        "cached_mib": round(mem.get("Cached", 0.0) + mem.get("SReclaimable", 0.0)),
        "swap_total_mib": swap_total,
        "swap_used_mib": swap_used,
        "zram_mem_used_mib": round(zram_used, 2),
    },
    "boot": boot,
    "startup_apps": startup_apps,
    "storage_devices": storage_devices,
    "cleanup_preview": cleanup_preview,
    "edition_recommendations": recs.get(edition, recs["xfce"]),
    "security_preserved": ["ufw", "polkit", "unattended-upgrades", "NetworkManager"],
}
print(json.dumps(payload, indent=2))
PY
    ;;

  low-resource)
    [[ ${#args[@]} -eq 2 ]] || { echo 'low-resource requires enable, disable, or status' >&2; exit 2; }
    sub="${args[1]}"
    case "$sub" in
      status)
        printf 'low_resource_mode=%s\n' "$(read_low_res)"
        ;;
      enable)
        if [[ "$DRY_RUN" == true ]]; then
          echo '[dry-run] Enable Low-Resource Mode (reduce animations/effects, slow background polling, keep UFW/Polkit/NetworkManager active)'
          printf '[dry-run] Write %s (enabled=true)\n' "$LOW_RES_FILE"
        else
          [[ "$(id -u)" -ne 0 ]] || { echo 'Run low-resource as your regular desktop user, not root.' >&2; exit 1; }
          mkdir -p -- "$STATE_DIR"
          printf 'enabled=true\n' > "$LOW_RES_FILE"
          if [[ -x "$XFCE_APPLY" && "${XDG_CURRENT_DESKTOP:-}" == *XFCE* ]]; then
            bash "$XFCE_APPLY" --lightweight >/dev/null || true
          elif [[ -x "$CINNAMON_APPLY" && "${XDG_CURRENT_DESKTOP:-}" == *Cinnamon* ]]; then
            bash "$CINNAMON_APPLY" --profile performance >/dev/null || true
          elif [[ -x "$LXQT_APPLY" && "${XDG_CURRENT_DESKTOP:-}" == *LXQt* ]]; then
            lite_saved_args
            bash "$LXQT_APPLY" --profile lite-512 "${LITE_PRESERVE_ARGS[@]}" >/dev/null || true
          elif [[ -x "$LITE_APPLY" && ( "${XDG_CURRENT_DESKTOP:-}" == *Openbox* || "${XDG_CURRENT_DESKTOP:-}" == *NEXUS-Lite* ) ]]; then
            lite_saved_args
            bash "$LITE_APPLY" --profile lite-512 "${LITE_PRESERVE_ARGS[@]}" >/dev/null || true
          fi
          echo 'Low-Resource Mode enabled (animations/effects lowered; security protections intact).'
        fi
        ;;
      disable)
        if [[ "$DRY_RUN" == true ]]; then
          echo '[dry-run] Disable Low-Resource Mode (restore balanced effects/polling)'
          printf '[dry-run] Write %s (enabled=false)\n' "$LOW_RES_FILE"
        else
          [[ "$(id -u)" -ne 0 ]] || { echo 'Run low-resource as your regular desktop user, not root.' >&2; exit 1; }
          mkdir -p -- "$STATE_DIR"
          printf 'enabled=false\n' > "$LOW_RES_FILE"
          if [[ -x "$XFCE_APPLY" && "${XDG_CURRENT_DESKTOP:-}" == *XFCE* ]]; then
            bash "$XFCE_APPLY" >/dev/null || true
          elif [[ -x "$CINNAMON_APPLY" && "${XDG_CURRENT_DESKTOP:-}" == *Cinnamon* ]]; then
            bash "$CINNAMON_APPLY" --profile balanced >/dev/null || true
          elif [[ -x "$LXQT_APPLY" && "${XDG_CURRENT_DESKTOP:-}" == *LXQt* ]]; then
            lite_saved_args
            bash "$LXQT_APPLY" --profile lite-1g "${LITE_PRESERVE_ARGS[@]}" >/dev/null || true
          elif [[ -x "$LITE_APPLY" && ( "${XDG_CURRENT_DESKTOP:-}" == *Openbox* || "${XDG_CURRENT_DESKTOP:-}" == *NEXUS-Lite* ) ]]; then
            lite_saved_args
            bash "$LITE_APPLY" --profile lite-1g "${LITE_PRESERVE_ARGS[@]}" >/dev/null || true
          fi
          echo 'Low-Resource Mode disabled; balanced desktop defaults restored.'
        fi
        ;;
      *)
        printf 'Invalid low-resource action: %s\n' "$sub" >&2
        exit 2
        ;;
    esac
    ;;

  startup)
    [[ ${#args[@]} -eq 3 ]] || { echo 'startup requires <enable|disable> <id.desktop>' >&2; exit 2; }
    sub="${args[1]}"
    desk_id="${args[2]}"
    [[ "$desk_id" =~ ^[A-Za-z0-9_.-]+\.desktop$ ]] || { printf 'Invalid desktop entry ID: %s\n' "$desk_id" >&2; exit 2; }
    case "$sub" in
      disable)
        case "${desk_id,,}" in
          polkit*|lxpolkit*|gnome-keyring*|nm-applet*|xdg-user-dirs*|at-spi*)
            printf 'Refusing to disable essential authentication/system startup item: %s\n' "$desk_id" >&2
            exit 1
            ;;
        esac
        if [[ "$DRY_RUN" == true ]]; then
          printf '[dry-run] Write Hidden=true override in %s/autostart/%s\n' "$CFG_DIR" "$desk_id"
          exit 0
        fi
        mkdir -p -- "$CFG_DIR/autostart"
        src_file="$CFG_DIR/autostart/$desk_id"
        [[ -r "$src_file" ]] || src_file="/etc/xdg/autostart/$desk_id"
        if [[ -r "$src_file" ]]; then
          grep -v '^Hidden=' "$src_file" > "$CFG_DIR/autostart/$desk_id.tmp" || true
          printf 'Hidden=true\n' >> "$CFG_DIR/autostart/$desk_id.tmp"
          mv -- "$CFG_DIR/autostart/$desk_id.tmp" "$CFG_DIR/autostart/$desk_id"
        else
          printf '[Desktop Entry]\nType=Application\nName=%s\nHidden=true\n' "$desk_id" > "$CFG_DIR/autostart/$desk_id"
        fi
        printf 'Disabled autostart entry for current user: %s\n' "$desk_id"
        ;;
      enable)
        if [[ "$DRY_RUN" == true ]]; then
          printf '[dry-run] Re-enable %s in %s/autostart/\n' "$desk_id" "$CFG_DIR"
          exit 0
        fi
        target_file="$CFG_DIR/autostart/$desk_id"
        if [[ -r "/etc/xdg/autostart/$desk_id" ]]; then
          rm -f -- "$target_file"
        elif [[ -r "$target_file" ]]; then
          grep -v '^Hidden=' "$target_file" > "$target_file.tmp" || true
          printf 'Hidden=false\n' >> "$target_file.tmp"
          mv -- "$target_file.tmp" "$target_file"
        fi
        printf 'Enabled autostart entry: %s\n' "$desk_id"
        ;;
      *)
        printf 'Invalid startup action: %s (expected enable or disable)\n' "$sub" >&2
        exit 2
        ;;
    esac
    ;;

  cleanup)
    [[ -n "$TARGET" ]] || { echo 'cleanup requires --target <thumbnails|wallpapers|mesa|apt>' >&2; exit 2; }
    case "$TARGET" in
      thumbnails|wallpapers|mesa|apt) ;;
      *) printf 'Unsupported cleanup target: %s\n' "$TARGET" >&2; exit 2 ;;
    esac
    if [[ "$DRY_RUN" == true ]]; then
      printf '[dry-run] Would safely clean cache target=%s (never touching user documents)\n' "$TARGET"
      exit 0
    fi
    if [[ "$CONFIRM" == false ]]; then
      echo 'Refusing cache cleanup without explicit --confirm.' >&2
      exit 2
    fi
    case "$TARGET" in
      thumbnails)
        if [[ -d "$CACHE_DIR/thumbnails" ]]; then
          find "$CACHE_DIR/thumbnails" -type f -delete
        fi
        echo 'Cleared user thumbnail cache (~/.cache/thumbnails).'
        ;;
      mesa)
        if [[ -d "$CACHE_DIR/mesa_shader_cache" ]]; then
          rm -rf -- "${CACHE_DIR:?}/mesa_shader_cache"
        fi
        echo 'Cleared Mesa GPU shader cache (~/.cache/mesa_shader_cache).'
        ;;
      wallpapers)
        active_wp=""
        if [[ -r "$STATE_DIR/wallpaper.conf" ]]; then
          active_wp="$(grep -E '^WALLPAPER_PATH=' "$STATE_DIR/wallpaper.conf" | head -n1 | cut -d= -f2- || true)"
        fi
        wp_cache="$CACHE_DIR/nexus-os/wallpapers"
        if [[ -d "$wp_cache" ]]; then
          while IFS= read -r -d '' f; do
            if [[ -n "$active_wp" && "$f" == "$active_wp" ]]; then
              continue
            fi
            rm -f -- "$f"
          done < <(find "$wp_cache" -type f -print0)
        fi
        echo 'Cleared unused downloaded wallpapers (active wallpaper and user files preserved).'
        ;;
      apt)
        if command -v pkexec >/dev/null 2>&1; then
          pkexec apt-get clean
          echo 'Cleared APT package archive cache (/var/cache/apt/archives).'
        else
          echo 'pkexec is unavailable; run "sudo apt-get clean" manually in Terminal.' >&2
          exit 1
        fi
        ;;
    esac
    ;;

  *)
    printf 'Unknown command: %s\n' "$CMD" >&2
    usage >&2
    exit 2
    ;;
esac
