#!/usr/bin/env bash
# Per-user NEXUS OS first-boot configuration and capability check for Linux Mint 22.3 Xfce.
# Runs strictly as the logged-in desktop user; never elevates privileges.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APPLY_SCRIPT="$SCRIPT_DIR/apply-nexus-xfce.sh"
PANEL_SCRIPT="$SCRIPT_DIR/nexus-panel-status.sh"
MARKER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nexus-os"
MARKER_FILE="$MARKER_DIR/firstboot-done"

PROFILE="balanced"
THEME="dark"
DRY_RUN=false
CHECK_UPDATES=false
GAMING_STATUS=false
MARK_DONE=false
NON_INTERACTIVE=false

usage() {
  cat <<'USAGE'
Usage: bash linux/mint/nexus-firstboot.sh [OPTIONS]

Per-user first-boot assistant for NEXUS OS on Linux Mint 22.3 Xfce.
Configures visual performance mode, theme preference, security/update guidance,
and optional gaming readiness checks without elevating privileges.

Options:
  --profile MODE      Visual performance mode: balanced | performance | lightweight
  --theme MODE        Preferred theme: dark | light
  --check-updates     Report APT / Mint update readiness (read-only)
  --gaming-status     Report Vulkan, GameMode, and Steam readiness (read-only)
  --mark-done         Write ~/.config/nexus-os/firstboot-done marker
  --non-interactive   Apply flags without prompting
  --dry-run           Preview actions without modifying user configuration
  --help, -h          Show this help message
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
    --check-updates) CHECK_UPDATES=true; shift ;;
    --gaming-status) GAMING_STATUS=true; shift ;;
    --mark-done) MARK_DONE=true; shift ;;
    --non-interactive) NON_INTERACTIVE=true; shift ;;
    --dry-run) DRY_RUN=true; NON_INTERACTIVE=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

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

if [[ "$NON_INTERACTIVE" == false && -t 0 ]]; then
  printf 'NEXUS OS First-Boot Setup (Linux Mint 22.3 Xfce)\n'
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

echo "NEXUS First-Boot: profile=$PROFILE, theme=$THEME"

apply_args=()
if [[ "$DRY_RUN" == true ]]; then
  apply_args+=(--dry-run)
fi
if [[ "$PROFILE" == "lightweight" || "$PROFILE" == "performance" ]]; then
  apply_args+=(--lightweight)
fi

if [[ -x "$APPLY_SCRIPT" ]]; then
  bash "$APPLY_SCRIPT" "${apply_args[@]}"
elif command -v nexus-apply-xfce >/dev/null 2>&1; then
  nexus-apply-xfce "${apply_args[@]}"
else
  echo 'INFO apply-nexus-xfce helper not found; skipped Xfce CSS application.'
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
  echo '--- Security & Update Guidance ---'
  if command -v apt >/dev/null 2>&1; then
    echo 'Run "sudo apt update && sudo apt upgrade" or open Mint Update Manager (mintupdate) for signed security updates.'
  else
    echo 'APT is unavailable on this host; run updates on an installed Linux Mint system.'
  fi
fi

if [[ "$GAMING_STATUS" == true ]]; then
  echo '--- Gaming & Compatibility Readiness ---'
  for tool in vulkaninfo gamemoded steam; do
    if command -v "$tool" >/dev/null 2>&1; then
      printf '  %s: installed\n' "$tool"
    else
      printf '  %s: not installed\n' "$tool"
    fi
  done
  echo 'Note: Linux-native games and Proton titles depend on GPU Vulkan/OpenGL support and per-title validation.'
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
