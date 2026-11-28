#!/usr/bin/env bash
# NEXUS OS Gaming, Steam/Proton, GPU/Vulkan, Controller, and Gaming Mode helper
# for Linux Mint 22.3. Never fabricates game libraries, FPS claims, or unsafe
# overclocking settings; Steam install/remove delegates via Polkit (pkexec).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
STORE_CLI="$SCRIPT_DIR/nexus-store-cli.sh"
[[ -x "$STORE_CLI" ]] || STORE_CLI="$(command -v nexus-store-cli || true)"
XFCE_APPLY="$SCRIPT_DIR/apply-nexus-xfce.sh"
[[ -x "$XFCE_APPLY" ]] || XFCE_APPLY="$(command -v nexus-apply-xfce || true)"
CINNAMON_APPLY="$REPO_ROOT/linux/cinnamon/apply-nexus-cinnamon.sh"
[[ -x "$CINNAMON_APPLY" ]] || CINNAMON_APPLY="$(command -v nexus-apply-cinnamon || true)"
LXQT_APPLY="$REPO_ROOT/linux/lite/scripts/apply-nexus-lite-lxqt.sh"
[[ -x "$LXQT_APPLY" ]] || LXQT_APPLY="$(command -v nexus-apply-lite-lxqt || true)"
LITE_APPLY="$REPO_ROOT/linux/lite/apply-nexus-lite.sh"
[[ -x "$LITE_APPLY" ]] || LITE_APPLY="$(command -v nexus-apply-lite || true)"
STATE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nexus-os"
GAMING_STATE_FILE="$STATE_DIR/gaming-mode.state"

DRY_RUN=false

usage() {
  cat <<'USAGE'
Usage: bash linux/mint/nexus-gaming-cli.sh [OPTIONS] <command> [args...]

Inspects real Linux Mint gaming readiness (Steam, Proton, installed Steam games,
GPU/Vulkan/OpenGL, controllers, GameMode) and manages non-destructive NEXUS
Gaming Mode and Steam installation via nexus-store-cli.sh.

Options:
  --dry-run       Print actions without executing mutations
  --help, -h      Show this help message

Commands:
  status                       Print real hardware, Steam, Proton, and controller JSON
  gaming-mode <enable|disable|status>
                               Toggle reversible performance/compositor Gaming Mode
  steam <install|remove|launch>
                               Install/remove Steam via APT (pkexec) or launch Steam
USAGE
}

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    --) shift; break ;;
    -*) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) break ;;
  esac
done

[[ $# -ge 1 ]] || { usage >&2; exit 2; }
CMD="$1"
shift

read_gaming_mode_state() {
  if [[ -r "$GAMING_STATE_FILE" ]] && grep -qx 'enabled=true' "$GAMING_STATE_FILE"; then
    printf 'enabled'
  else
    printf 'disabled'
  fi
}

case "$CMD" in
  status)
    gm_state="$(read_gaming_mode_state)"
    python3 - "$gm_state" <<'PY'
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

gm_state = sys.argv[1] if len(sys.argv) > 1 else "disabled"

def read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return None

# CPU / RAM / Storage
cpu_model = "unavailable"
cpu_raw = read_text(Path("/proc/cpuinfo"))
if cpu_raw:
    for line in cpu_raw.splitlines():
        if line.lower().startswith("model name"):
            cpu_model = line.split(":", 1)[1].strip()
            break

mem_total_mib = None
mem_avail_mib = None
mem_raw = read_text(Path("/proc/meminfo"))
if mem_raw:
    vals = {}
    for line in mem_raw.splitlines():
        if ":" in line:
            k, rest = line.split(":", 1)
            tok = rest.strip().split()[0]
            if tok.isdigit():
                vals[k] = int(tok)
    if "MemTotal" in vals:
        mem_total_mib = round(vals["MemTotal"] / 1024)
    if "MemAvailable" in vals:
        mem_avail_mib = round(vals["MemAvailable"] / 1024)

storage_avail_gib = None
try:
    st = os.statvfs("/")
    storage_avail_gib = round((st.f_bavail * st.f_frsize) / (1024 ** 3), 1)
except OSError:
    pass

# GPUs via sysfs + human-readable vendor/driver compatibility mapping
VENDOR_NAMES = {
    "0x1002": "AMD / ATI",
    "0x8086": "Intel",
    "0x10de": "NVIDIA",
    "0x1234": "QEMU / Bochs Virtual GPU",
    "0x1af4": "VirtIO GPU",
    "0x15ad": "VMware SVGA",
    "0x80ee": "VirtualBox GPU",
}
gpus = []
for dev in sorted(Path("/sys/bus/pci/devices").glob("*")):
    cls = read_text(dev / "class") or ""
    if not cls.startswith("0x03"):
        continue
    vendor = (read_text(dev / "vendor") or "unknown").lower()
    device = (read_text(dev / "device") or "unknown").lower()
    driver_link = dev / "driver"
    driver = driver_link.resolve().name if driver_link.is_symlink() else "none"
    vendor_name = VENDOR_NAMES.get(vendor, vendor)
    if vendor in ("0x1234", "0x1af4", "0x15ad", "0x80ee"):
        compat_note = "Virtual machine GPU (2D/basic 3D; native hardware GPU recommended for modern 3D games)."
    elif vendor == "0x10de" and driver == "nouveau":
        compat_note = "Open-source nouveau driver active; proprietary NVIDIA driver recommended for Vulkan & Proton."
    elif vendor == "0x10de" and driver == "nvidia":
        compat_note = "NVIDIA proprietary driver detected (Vulkan/DXVK compatible)."
    elif vendor == "0x1002" and driver == "amdgpu":
        compat_note = "AMDGPU + Mesa RADV driver stack detected (strong Vulkan/Proton support)."
    elif vendor == "0x8086" and driver in ("i915", "xe"):
        compat_note = "Intel Mesa Vulkan/ANV driver stack detected (lightweight/indie & compatible 3D titles)."
    else:
        compat_note = "Check Mesa/Vulkan ICD availability for this GPU."
    gpus.append({
        "slot": dev.name,
        "vendor": vendor,
        "vendor_name": vendor_name,
        "device": device,
        "driver": driver,
        "compatibility_note": compat_note,
    })

vulkan_summary = "unavailable"
vulkan_devices = []
if shutil.which("vulkaninfo"):
    try:
        res = subprocess.run(["vulkaninfo", "--summary"], capture_output=True, text=True, timeout=3)
        if res.returncode == 0 and res.stdout.strip():
            vulkan_summary = "available"
            for line in res.stdout.splitlines():
                if "deviceName" in line:
                    vulkan_devices.append(line.split("=", 1)[-1].strip())
        else:
            vulkan_summary = "unavailable"
    except Exception:
        vulkan_summary = "unavailable"

opengl_renderer = "unavailable"
if shutil.which("glxinfo"):
    try:
        res = subprocess.run(["glxinfo", "-B"], capture_output=True, text=True, timeout=3)
        for line in res.stdout.splitlines():
            if "OpenGL renderer string:" in line:
                opengl_renderer = line.split(":", 1)[1].strip()
                break
    except Exception:
        pass
software_rendering = "llvmpipe" in opengl_renderer.lower() or "softpipe" in opengl_renderer.lower()

# Steam & Proton (real local files only; never fabricated)
steam_bin = shutil.which("steam")
steam_roots = [
    Path.home() / ".local" / "share" / "Steam",
    Path.home() / ".steam" / "steam",
    Path.home() / ".var" / "app" / "com.valvesoftware.Steam" / ".local" / "share" / "Steam",
]
steam_dir = next((p for p in steam_roots if (p / "steamapps").is_dir()), None)

installed_games = []
proton_versions = []
if steam_dir:
    steamapps = steam_dir / "steamapps"
    for acf in sorted(steamapps.glob("appmanifest_*.acf")):
        raw = read_text(acf) or ""
        appid_m = re.search(r'"appid"\s+"(\d+)"', raw)
        name_m = re.search(r'"name"\s+"([^"]+)"', raw)
        if appid_m and name_m:
            name = name_m.group(1)
            if name.startswith("Proton ") or name.startswith("Steam Linux Runtime"):
                proton_versions.append(name)
            else:
                installed_games.append({"appid": appid_m.group(1), "name": name})
    common = steamapps / "common"
    if common.is_dir():
        for entry in sorted(common.glob("Proton*")):
            if entry.is_dir() and entry.name not in proton_versions:
                proton_versions.append(entry.name)
    compat_d = steam_dir / "compatibilitytools.d"
    if compat_d.is_dir():
        for entry in sorted(compat_d.iterdir()):
            if entry.is_dir() and entry.name not in proton_versions:
                proton_versions.append(entry.name)

# Controllers via /sys/class/input/js*
controllers = []
for js in sorted(Path("/sys/class/input").glob("js*")):
    name = read_text(js / "device" / "name") or js.name
    controllers.append({"device": js.name, "name": name})

def flatpak_app_installed(app_id: str) -> bool:
    return any(
        (root / app_id).is_dir()
        for root in (
            Path.home() / ".local" / "share" / "flatpak" / "app",
            Path("/var/lib/flatpak/app"),
        )
    )

lutris_bin = shutil.which("lutris")
lutris_flatpak = flatpak_app_installed("net.lutris.Lutris")
heroic_bin = shutil.which("heroic")
heroic_flatpak = flatpak_app_installed("com.heroicgameslauncher.hgl")
steam_flatpak = flatpak_app_installed("com.valvesoftware.Steam")
steam_installed = bool(steam_bin or steam_dir or steam_flatpak)
wine_installed = shutil.which("wine") is not None
gamemode_ok = shutil.which("gamemoded") is not None
mangohud_ok = shutil.which("mangohud") is not None
apt_ok = shutil.which("apt-get") is not None
flatpak_ok = shutil.which("flatpak") is not None
pkexec_ok = shutil.which("pkexec") is not None

power_profile = "unavailable"
if shutil.which("powerprofilesctl"):
    try:
        res = subprocess.run(["powerprofilesctl", "get"], capture_output=True, text=True, timeout=2)
        if res.returncode == 0 and res.stdout.strip():
            power_profile = res.stdout.strip()
    except Exception:
        pass

guidance = []
if software_rendering:
    guidance.append("Software OpenGL renderer (llvmpipe) detected: 3D gaming requires native hardware GPU drivers.")
if not steam_installed:
    guidance.append("Steam missing: install optional steam-installer via NEXUS Store (sudo apt install steam-installer) or Flatpak com.valvesoftware.Steam.")
if vulkan_summary != "available":
    guidance.append("Vulkan tools/drivers unavailable: install vulkan-tools and mesa-vulkan-drivers (or proprietary NVIDIA drivers via Driver Manager).")
if not gamemode_ok:
    guidance.append("GameMode missing: optional install via sudo apt install gamemode.")
if not mangohud_ok:
    guidance.append("MangoHud missing: optional HUD overlay via sudo apt install mangohud.")
if not (lutris_bin or lutris_flatpak):
    guidance.append("Lutris missing: optional install via flatpak install flathub net.lutris.Lutris.")
if not (heroic_bin or heroic_flatpak):
    guidance.append("Heroic missing: optional install via flatpak install flathub com.heroicgameslauncher.hgl.")

payload = {
    "steam": {
        "installed": steam_installed,
        "binary": steam_bin,
        "flatpak": steam_flatpak,
        "steamapps_found": steam_dir is not None,
        "installed_games": installed_games,
        "proton_versions": sorted(proton_versions),
        "wine_installed": wine_installed,
        "compatibility_caveat": "Proton/Wine compatibility varies by title (kernel anti-cheat and third-party DRM may block some Windows games); no guarantee is made that every Windows game works.",
    },
    "launchers": {
        "lutris": {
            "installed": bool(lutris_bin or lutris_flatpak),
            "binary": lutris_bin,
            "flatpak": lutris_flatpak,
            "install_hint": "flatpak install flathub net.lutris.Lutris (or apt install lutris)",
        },
        "heroic": {
            "installed": bool(heroic_bin or heroic_flatpak),
            "binary": heroic_bin,
            "flatpak": heroic_flatpak,
            "install_hint": "flatpak install flathub com.heroicgameslauncher.hgl",
        },
    },
    "graphics": {
        "gpus": gpus,
        "vulkan": vulkan_summary,
        "vulkan_devices": vulkan_devices,
        "opengl_renderer": opengl_renderer,
        "software_rendering": software_rendering,
    },
    "hardware": {
        "cpu": cpu_model,
        "ram_total_mib": mem_total_mib,
        "ram_available_mib": mem_avail_mib,
        "storage_available_gib": storage_avail_gib,
    },
    "controllers": controllers,
    "performance": {
        "gaming_mode": gm_state,
        "gamemode_installed": gamemode_ok,
        "mangohud_installed": mangohud_ok,
        "power_profile": power_profile,
    },
    "capabilities": {
        "apt_available": apt_ok,
        "flatpak_available": flatpak_ok,
        "pkexec_available": pkexec_ok,
    },
    "guidance": guidance,
}
print(json.dumps(payload, indent=2))
PY
    ;;

  gaming-mode)
    [[ $# -eq 1 ]] || { echo 'gaming-mode requires enable, disable, or status' >&2; exit 2; }
    action="$1"
    case "$action" in
      status)
        printf 'gaming_mode=%s\n' "$(read_gaming_mode_state)"
        ;;
      enable)
        if [[ "$DRY_RUN" == true ]]; then
          echo '[dry-run] Apply lightweight compositor mode (reduce animations/compositing overhead)'
          echo '[dry-run] powerprofilesctl set performance (if supported)'
          printf '[dry-run] Write %s (enabled=true)\n' "$GAMING_STATE_FILE"
        else
          if [[ "$(id -u)" -eq 0 ]]; then
            echo 'Run gaming-mode as your regular desktop user, not root.' >&2
            exit 1
          fi
          mkdir -p -- "$STATE_DIR"
          printf 'enabled=true\n' > "$GAMING_STATE_FILE"
          if command -v powerprofilesctl >/dev/null 2>&1; then
            powerprofilesctl set performance 2>/dev/null || true
          fi
          if [[ -x "$XFCE_APPLY" && "${XDG_CURRENT_DESKTOP:-}" == *XFCE* ]]; then
            bash "$XFCE_APPLY" --lightweight >/dev/null || true
          elif [[ -x "$CINNAMON_APPLY" && "${XDG_CURRENT_DESKTOP:-}" == *Cinnamon* ]]; then
            bash "$CINNAMON_APPLY" --profile performance >/dev/null || true
          elif [[ -x "$LXQT_APPLY" && "${XDG_CURRENT_DESKTOP:-}" == *LXQt* ]]; then
            bash "$LXQT_APPLY" --profile lite-1g >/dev/null || true
          elif [[ -x "$LITE_APPLY" && ( "${XDG_CURRENT_DESKTOP:-}" == *Openbox* || "${XDG_CURRENT_DESKTOP:-}" == *NEXUS-Lite* ) ]]; then
            bash "$LITE_APPLY" --profile lite-512 >/dev/null || true
          fi
          echo 'Gaming Mode enabled. Use "gamemoderun %command%" in Steam launch options when GameMode is installed.'
        fi
        ;;
      disable)
        if [[ "$DRY_RUN" == true ]]; then
          echo '[dry-run] Restore balanced compositor/power profile'
          echo '[dry-run] powerprofilesctl set balanced (if supported)'
          printf '[dry-run] Write %s (enabled=false)\n' "$GAMING_STATE_FILE"
        else
          if [[ "$(id -u)" -eq 0 ]]; then
            echo 'Run gaming-mode as your regular desktop user, not root.' >&2
            exit 1
          fi
          mkdir -p -- "$STATE_DIR"
          printf 'enabled=false\n' > "$GAMING_STATE_FILE"
          if command -v powerprofilesctl >/dev/null 2>&1; then
            powerprofilesctl set balanced 2>/dev/null || true
          fi
          if [[ -x "$XFCE_APPLY" && "${XDG_CURRENT_DESKTOP:-}" == *XFCE* ]]; then
            bash "$XFCE_APPLY" >/dev/null || true
          elif [[ -x "$CINNAMON_APPLY" && "${XDG_CURRENT_DESKTOP:-}" == *Cinnamon* ]]; then
            bash "$CINNAMON_APPLY" --profile balanced >/dev/null || true
          elif [[ -x "$LXQT_APPLY" && "${XDG_CURRENT_DESKTOP:-}" == *LXQt* ]]; then
            bash "$LXQT_APPLY" --profile lite-1g >/dev/null || true
          elif [[ -x "$LITE_APPLY" && ( "${XDG_CURRENT_DESKTOP:-}" == *Openbox* || "${XDG_CURRENT_DESKTOP:-}" == *NEXUS-Lite* ) ]]; then
            bash "$LITE_APPLY" --profile lite-1g >/dev/null || true
          fi
          echo 'Gaming Mode disabled; balanced desktop defaults restored.'
        fi
        ;;
      *)
        printf 'Invalid gaming-mode action: %s (expected enable, disable, or status)\n' "$action" >&2
        exit 2
        ;;
    esac
    ;;

  steam)
    [[ $# -eq 1 ]] || { echo 'steam requires install, remove, or launch' >&2; exit 2; }
    action="$1"
    case "$action" in
      install)
        [[ -n "$STORE_CLI" && -r "$STORE_CLI" ]] || { echo 'nexus-store-cli is unavailable; install steam-installer via APT manually.' >&2; exit 1; }
        if [[ "$DRY_RUN" == true ]]; then
          exec bash "$STORE_CLI" --dry-run install apt steam-installer
        else
          exec bash "$STORE_CLI" install apt steam-installer
        fi
        ;;
      remove)
        [[ -n "$STORE_CLI" && -r "$STORE_CLI" ]] || { echo 'nexus-store-cli is unavailable; remove steam-installer via APT manually.' >&2; exit 1; }
        if [[ "$DRY_RUN" == true ]]; then
          exec bash "$STORE_CLI" --dry-run remove apt steam-installer
        else
          exec bash "$STORE_CLI" remove apt steam-installer
        fi
        ;;
      launch)
        if [[ "$DRY_RUN" == true ]]; then
          echo '[dry-run] steam'
        elif command -v steam >/dev/null 2>&1; then
          nohup steam >/dev/null 2>&1 &
          echo 'Launched Steam.'
        else
          echo 'Steam is not installed on this host. Install steam-installer via NEXUS Store or nexus-gaming-cli.sh steam install.' >&2
          exit 1
        fi
        ;;
      *)
        printf 'Invalid steam action: %s (expected install, remove, or launch)\n' "$action" >&2
        exit 2
        ;;
    esac
    ;;

  *)
    printf 'Unknown command: %s\n' "$CMD" >&2
    usage >&2
    exit 2
    ;;
esac
