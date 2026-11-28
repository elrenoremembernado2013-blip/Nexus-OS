#!/usr/bin/env bash
# Per-user NEXUS OS first-boot configuration and capability check for Linux Mint 22.3 Xfce.
# Runs strictly as the logged-in desktop user; never elevates privileges.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
APPLY_SCRIPT="$SCRIPT_DIR/apply-nexus-xfce.sh"
[[ -x "$APPLY_SCRIPT" ]] || APPLY_SCRIPT="$(command -v nexus-apply-xfce || true)"
CINNAMON_APPLY="$(cd -- "$SCRIPT_DIR/.." 2>/dev/null && pwd)/cinnamon/apply-nexus-cinnamon.sh"
[[ -x "$CINNAMON_APPLY" ]] || CINNAMON_APPLY="$(command -v nexus-apply-cinnamon || true)"
LITE_LXQT_APPLY="$(cd -- "$SCRIPT_DIR/.." 2>/dev/null && pwd)/lite/scripts/apply-nexus-lite-lxqt.sh"
[[ -x "$LITE_LXQT_APPLY" ]] || LITE_LXQT_APPLY="$(command -v nexus-apply-lite-lxqt || true)"
LITE_OPENBOX_APPLY="$(cd -- "$SCRIPT_DIR/.." 2>/dev/null && pwd)/lite/apply-nexus-lite.sh"
[[ -x "$LITE_OPENBOX_APPLY" ]] || LITE_OPENBOX_APPLY="$(command -v nexus-apply-lite || true)"
PANEL_SCRIPT="$SCRIPT_DIR/nexus-panel-status.sh"
[[ -x "$PANEL_SCRIPT" ]] || PANEL_SCRIPT="$(command -v nexus-panel-status || true)"
SECURITY_CLI="$SCRIPT_DIR/nexus-security-cli.sh"
[[ -x "$SECURITY_CLI" ]] || SECURITY_CLI="$(command -v nexus-security-cli || true)"
GAMING_CLI="$SCRIPT_DIR/nexus-gaming-cli.sh"
[[ -x "$GAMING_CLI" ]] || GAMING_CLI="$(command -v nexus-gaming-cli || true)"
MARKER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nexus-os"
MARKER_FILE="$MARKER_DIR/firstboot-done"

PROFILE="balanced"
THEME="dark"
THEME_PRESET="midnight"
DRY_RUN=false
CHECK_UPDATES=false
GAMING_STATUS=false
SECURITY_SUMMARY=false
SKIP_SETUP=false
MARK_DONE=false
NON_INTERACTIVE=false
AUTOSTART=false

usage() {
  cat <<'USAGE'
Usage: bash linux/mint/nexus-firstboot.sh [OPTIONS]

Per-user first-boot assistant for NEXUS OS on Linux Mint (Cinnamon / Xfce).
Configures theme preset, visual performance mode, security/update guidance,
and gaming readiness checks without elevating privileges.

Options:
  --profile MODE        Visual mode: balanced | performance | lightweight
  --theme MODE          Preferred base mode: dark | light
  --theme-preset NAME   NEXUS theme: midnight | nebula | arctic | emerald | solar
  --check-updates       Report APT / Mint update readiness (read-only)
  --gaming-status       Report Vulkan, GameMode, and Steam readiness (read-only)
  --security-summary    Report firewall, Secure Boot, LUKS, and update status
  --skip                Skip interactive setup and mark first-boot done
  --mark-done           Write ~/.config/nexus-os/firstboot-done marker
  --autostart           Run once per user (exit 0 immediately if already completed)
  --non-interactive     Apply flags without prompting
  --dry-run             Preview actions without modifying user configuration
  --help, -h            Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --profile)
      [[ $# -ge 2 ]] || { echo '--profile requires an argument' >&2; exit 2; }
      PROFILE="$2"; shift 2 ;;
    --theme)
      [[ $# -ge 2 ]] || { echo '--theme requires an argument' >&2; exit 2; }
      THEME="$2"; shift 2 ;;
    --theme-preset)
      [[ $# -ge 2 ]] || { echo '--theme-preset requires an argument' >&2; exit 2; }
      THEME_PRESET="$2"; shift 2 ;;
    --check-updates) CHECK_UPDATES=true; shift ;;
    --gaming-status) GAMING_STATUS=true; shift ;;
    --security-summary) SECURITY_SUMMARY=true; shift ;;
    --skip) SKIP_SETUP=true; MARK_DONE=true; NON_INTERACTIVE=true; shift ;;
    --mark-done) MARK_DONE=true; shift ;;
    --autostart) AUTOSTART=true; NON_INTERACTIVE=true; MARK_DONE=true; shift ;;
    --non-interactive) NON_INTERACTIVE=true; shift ;;
    --dry-run) DRY_RUN=true; NON_INTERACTIVE=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$AUTOSTART" == true && "$DRY_RUN" == false && -e "$MARKER_FILE" ]]; then
  exit 0
fi

if [[ "$DRY_RUN" == false && "$(id -u)" -eq 0 ]]; then
  echo 'Run nexus-firstboot.sh as your regular Mint desktop user, not root.' >&2
  exit 1
fi

case "$PROFILE" in
  balanced|performance|lightweight) ;;
  *) printf 'Invalid --profile: %s (expected balanced, performance, or lightweight)\n' "$PROFILE" >&2; exit 2 ;;
esac

case "$THEME" in
  dark|light) ;;
  *) printf 'Invalid --theme: %s (expected dark or light)\n' "$THEME" >&2; exit 2 ;;
esac

case "$THEME_PRESET" in
  midnight|nebula|arctic|emerald|solar) ;;
  *) printf 'Invalid --theme-preset: %s\n' "$THEME_PRESET" >&2; exit 2 ;;
esac

if [[ "$SKIP_SETUP" == true ]]; then
  echo 'NEXUS First-Boot: setup skipped by user (can be re-run anytime via nexus-firstboot).'
fi

if [[ "$NON_INTERACTIVE" == false && -t 0 ]]; then
  printf 'NEXUS OS First-Boot Setup (Linux Mint)\n'
  printf 'Choose theme preset [midnight|nebula|arctic|emerald|solar] (default midnight): '
  read -r tp_choice
  case "${tp_choice:-midnight}" in
    nebula|arctic|emerald|solar|midnight) THEME_PRESET="${tp_choice:-midnight}" ;;
    *) THEME_PRESET="midnight" ;;
  esac
  printf 'Choose performance profile [1=Balanced, 2=Performance, 3=Lightweight] (default 1): '
  read -r choice
  case "${choice:-1}" in
    2) PROFILE="performance" ;;
    3) PROFILE="lightweight" ;;
    *) PROFILE="balanced" ;;
  esac
  printf 'Choose theme [1=Dark, 2=Light] (default 1): '
  read -r theme_choice
  case "${theme_choice:-1}" in
    2) THEME="light" ;;
    *) THEME="dark" ;;
  esac
  MARK_DONE=true
fi

echo "NEXUS First-Boot: preset=$THEME_PRESET, profile=$PROFILE, theme=$THEME"

if [[ "$SKIP_SETUP" == false ]]; then
  if [[ -x "$CINNAMON_APPLY" && "${XDG_CURRENT_DESKTOP:-}" == *Cinnamon* ]]; then
    cin_args=(--theme "$THEME_PRESET" --profile "$PROFILE")
    [[ "$DRY_RUN" == true ]] && cin_args+=(--dry-run)
    bash "$CINNAMON_APPLY" "${cin_args[@]}"
  elif [[ -x "$LITE_LXQT_APPLY" && "${XDG_CURRENT_DESKTOP:-}" == *LXQt* ]]; then
    lite_prof="lite-1g"
    if [[ "$PROFILE" == "lightweight" ]]; then
      lite_prof="lite-512"
    fi
    lxqt_args=(--profile "$lite_prof" --theme "$THEME_PRESET" --appearance "$THEME")
    [[ "$DRY_RUN" == true ]] && lxqt_args+=(--dry-run)
    bash "$LITE_LXQT_APPLY" "${lxqt_args[@]}"
  elif [[ -x "$LITE_OPENBOX_APPLY" && "${XDG_CURRENT_DESKTOP:-}" == *Openbox* ]]; then
    lite_prof="lite-1g"
    if [[ "$PROFILE" == "lightweight" ]]; then
      lite_prof="lite-512"
    fi
    ob_args=(--profile "$lite_prof" --theme "$THEME_PRESET" --appearance "$THEME")
    [[ "$DRY_RUN" == true ]] && ob_args+=(--dry-run)
    bash "$LITE_OPENBOX_APPLY" "${ob_args[@]}"
  else
    apply_args=(--theme "$THEME_PRESET" --appearance "$THEME")
    [[ "$DRY_RUN" == true ]] && apply_args+=(--dry-run)
    [[ "$PROFILE" == "lightweight" || "$PROFILE" == "performance" ]] && apply_args+=(--lightweight)
    if [[ -x "$APPLY_SCRIPT" ]]; then
      bash "$APPLY_SCRIPT" "${apply_args[@]}"
    elif command -v nexus-apply-xfce >/dev/null 2>&1; then
      nexus-apply-xfce "${apply_args[@]}"
    else
      echo 'INFO desktop theme helper not found; skipped CSS application.'
    fi
  fi
fi

if [[ "$DRY_RUN" == true ]]; then
  printf '[dry-run] Prefer %s Mint GTK theme in xsettings /Net/ThemeName\n' "$THEME"
elif command -v xfconf-query >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
  if [[ "$THEME" == "light" ]]; then
    for candidate in Mint-Y-Sand Mint-Y-Orange Mint-Y; do
      if [[ -d "/usr/share/themes/$candidate" ]]; then
        xfconf-query -c xsettings -p /Net/ThemeName -n -t string -s "$candidate"
        break
      fi
    done
  fi
fi

if [[ "$CHECK_UPDATES" == true ]]; then
  echo '--- Security, Apps & Recovery Guidance ---'
  if command -v apt >/dev/null 2>&1; then
    echo 'Run "sudo apt update && sudo apt upgrade" or open Mint Update Manager (mintupdate) for signed security updates.'
    echo 'Recommended optional apps (via NEXUS Store / APT / Flatpak): gamemode, mangohud, libreoffice, net.lutris.Lutris.'
  else
    echo 'APT is unavailable on this host; run updates on an installed Linux Mint system.'
  fi
  echo 'Boot / system diagnostics: run "nexus-recovery --diagnose" anytime.'
fi

if [[ "$GAMING_STATUS" == true ]]; then
  echo '--- Gaming & Compatibility Readiness ---'
  if [[ -x "$GAMING_CLI" ]]; then
    bash "$GAMING_CLI" status
  else
    for tool in vulkaninfo gamemoded steam; do
      if command -v "$tool" >/dev/null 2>&1; then
        printf '  %s: installed\n' "$tool"
      else
        printf '  %s: not installed\n' "$tool"
      fi
    done
  fi
  echo 'Note: Linux-native games and Proton titles depend on GPU Vulkan/OpenGL support and per-title validation.'
fi

if [[ "$SECURITY_SUMMARY" == true && -x "$SECURITY_CLI" ]]; then
  echo '--- Security & Privacy Overview ---'
  bash "$SECURITY_CLI" status
fi

if [[ -x "$PANEL_SCRIPT" ]]; then
  bash "$PANEL_SCRIPT" --plain
fi

if [[ "$MARK_DONE" == true ]]; then
  if [[ "$DRY_RUN" == true ]]; then
    printf '[dry-run] Write first-boot marker: %s\n' "$MARKER_FILE"
  else
    mkdir -p -- "$MARKER_DIR"
    printf 'profile=%s\ntheme=%s\n' "$PROFILE" "$THEME" > "$MARKER_FILE"
    printf 'Recorded first-boot preference in %s\n' "$MARKER_FILE"
  fi
fi
