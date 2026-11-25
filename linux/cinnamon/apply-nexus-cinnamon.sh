#!/usr/bin/env bash
# Generate and apply NEXUS OS Cinnamon themes, dock-style panel layout, workspace
# shortcuts, wallpaper fit/caching, and effect/performance profiles on Linux Mint.
# Runs strictly as the desktop user; never touches system files or requires root.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
THEMES_JSON="$SCRIPT_DIR/themes.json"
CINNAMON_TEMPLATE="$SCRIPT_DIR/cinnamon-base.css"
GTK3_TEMPLATE="$SCRIPT_DIR/gtk3-base.css"
DATA_THEME_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/themes"
WALLPAPER_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/nexus-os/wallpapers"

THEME="midnight"
PROFILE="balanced"
EFFECT_LEVEL=""
DOCK_POSITION="bottom"
PANEL_SIZE="medium"
PANEL_AUTOHIDE="false"
DESKTOP_ICONS="true"
WORKSPACES=4
WALLPAPER_FIT="zoom"
WALLPAPER_URL=""
CUSTOM_ACCENT=""
PRESET_PROFILE=""
DRY_RUN=false
REVERT=false

usage() {
  cat <<'USAGE'
Usage: bash linux/cinnamon/apply-nexus-cinnamon.sh [OPTIONS]

Generates user-local NEXUS Cinnamon/GTK3 theme packages under
~/.local/share/themes/NEXUS-* and applies Cinnamon gsettings defaults for panel
layout, dock position, icon sizing, wallpapers, workspaces, and visual effects.

Options:
  --theme NAME             midnight | nebula | arctic | emerald | solar (default: midnight)
  --accent HEX             Optional #RRGGBB accent override for generated user theme
  --profile MODE           balanced | performance | lightweight (default: balanced)
  --preset-profile NAME    default | minimal | gaming | productivity | cinematic | lightweight
  --effect-level LEVEL     off | subtle | balanced | enhanced
  --dock-position POS      bottom | left | right (default: bottom)
  --panel-size SIZE        small | medium | large (default: medium)
  --panel-autohide MODE    false | true | intel (default: false)
  --desktop-icons BOOL     true | false (default: true)
  --workspaces COUNT       1-8 (default: 4)
  --wallpaper-fit MODE     zoom | scaled | stretched | centered | wallpaper (default: zoom)
  --wallpaper-url URL      HTTPS URL (cached safely) or local image path to apply
  --revert                 Remove user NEXUS-* themes and restore Mint-Y-Dark defaults
  --dry-run                Preview theme generation and gsettings commands without writing
  --help, -h               Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --theme) [[ $# -ge 2 ]] || { echo '--theme requires a preset name' >&2; exit 2; }; THEME="$2"; shift 2 ;;
    --accent) [[ $# -ge 2 ]] || { echo '--accent requires #RRGGBB' >&2; exit 2; }; CUSTOM_ACCENT="$2"; shift 2 ;;
    --profile) [[ $# -ge 2 ]] || { echo '--profile requires a mode' >&2; exit 2; }; PROFILE="$2"; shift 2 ;;
    --preset-profile) [[ $# -ge 2 ]] || { echo '--preset-profile requires a name' >&2; exit 2; }; PRESET_PROFILE="$2"; shift 2 ;;
    --effect-level) [[ $# -ge 2 ]] || { echo '--effect-level requires off|subtle|balanced|enhanced' >&2; exit 2; }; EFFECT_LEVEL="$2"; shift 2 ;;
    --dock-position) [[ $# -ge 2 ]] || { echo '--dock-position requires bottom|left|right' >&2; exit 2; }; DOCK_POSITION="$2"; shift 2 ;;
    --panel-size) [[ $# -ge 2 ]] || { echo '--panel-size requires small|medium|large' >&2; exit 2; }; PANEL_SIZE="$2"; shift 2 ;;
    --panel-autohide) [[ $# -ge 2 ]] || { echo '--panel-autohide requires false|true|intel' >&2; exit 2; }; PANEL_AUTOHIDE="$2"; shift 2 ;;
    --desktop-icons) [[ $# -ge 2 ]] || { echo '--desktop-icons requires true|false' >&2; exit 2; }; DESKTOP_ICONS="$2"; shift 2 ;;
    --workspaces) [[ $# -ge 2 ]] || { echo '--workspaces requires 1-8' >&2; exit 2; }; WORKSPACES="$2"; shift 2 ;;
    --wallpaper-fit) [[ $# -ge 2 ]] || { echo '--wallpaper-fit requires zoom|scaled|stretched|centered|wallpaper' >&2; exit 2; }; WALLPAPER_FIT="$2"; shift 2 ;;
    --wallpaper-url) [[ $# -ge 2 ]] || { echo '--wallpaper-url requires URL or path' >&2; exit 2; }; WALLPAPER_URL="$2"; shift 2 ;;
    --revert) REVERT=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -n "$PRESET_PROFILE" ]]; then
  case "$PRESET_PROFILE" in
    default) THEME="midnight"; PROFILE="balanced"; EFFECT_LEVEL="${EFFECT_LEVEL:-balanced}"; DOCK_POSITION="bottom"; PANEL_AUTOHIDE="false"; WORKSPACES=4 ;;
    minimal) THEME="arctic"; PROFILE="balanced"; EFFECT_LEVEL="${EFFECT_LEVEL:-subtle}"; DOCK_POSITION="bottom"; PANEL_AUTOHIDE="intel"; WORKSPACES=2; DESKTOP_ICONS="false" ;;
    gaming) THEME="solar"; PROFILE="performance"; EFFECT_LEVEL="${EFFECT_LEVEL:-off}"; DOCK_POSITION="bottom"; PANEL_AUTOHIDE="true"; WORKSPACES=2 ;;
    productivity) THEME="midnight"; PROFILE="balanced"; EFFECT_LEVEL="${EFFECT_LEVEL:-subtle}"; DOCK_POSITION="left"; PANEL_AUTOHIDE="false"; WORKSPACES=6 ;;
    cinematic) THEME="nebula"; PROFILE="balanced"; EFFECT_LEVEL="${EFFECT_LEVEL:-enhanced}"; DOCK_POSITION="bottom"; PANEL_AUTOHIDE="intel"; WORKSPACES=4 ;;
    lightweight) THEME="midnight"; PROFILE="lightweight"; EFFECT_LEVEL="${EFFECT_LEVEL:-off}"; DOCK_POSITION="bottom"; PANEL_AUTOHIDE="false"; WORKSPACES=2 ;;
    *) printf 'Unknown --preset-profile: %s\n' "$PRESET_PROFILE" >&2; exit 2 ;;
  esac
fi

if [[ "$DRY_RUN" == false && "$(id -u)" -eq 0 ]]; then
  echo 'Refusing to modify user Cinnamon configuration as root. Run as your regular Mint desktop user.' >&2
  exit 1
fi

case "$THEME" in
  midnight|nebula|arctic|emerald|solar) ;;
  *) printf 'Unknown --theme: %s\n' "$THEME" >&2; exit 2 ;;
esac

case "$PROFILE" in
  balanced|performance|lightweight) ;;
  *) printf 'Unknown --profile: %s\n' "$PROFILE" >&2; exit 2 ;;
esac

if [[ -n "$EFFECT_LEVEL" ]]; then
  case "$EFFECT_LEVEL" in
    off|subtle|balanced|enhanced) ;;
    *) printf 'Unknown --effect-level: %s\n' "$EFFECT_LEVEL" >&2; exit 2 ;;
  esac
fi

case "$DOCK_POSITION" in
  bottom|left|right) ;;
  *) printf 'Unknown --dock-position: %s\n' "$DOCK_POSITION" >&2; exit 2 ;;
esac

case "$PANEL_SIZE" in
  small) PANEL_PX=36 ;;
  medium) PANEL_PX=44 ;;
  large) PANEL_PX=54 ;;
  *) printf 'Unknown --panel-size: %s\n' "$PANEL_SIZE" >&2; exit 2 ;;
esac

case "$PANEL_AUTOHIDE" in
  false|true|intel) ;;
  *) printf 'Unknown --panel-autohide: %s\n' "$PANEL_AUTOHIDE" >&2; exit 2 ;;
esac

case "$DESKTOP_ICONS" in
  true|false) ;;
  *) printf 'Unknown --desktop-icons: %s\n' "$DESKTOP_ICONS" >&2; exit 2 ;;
esac

case "$WALLPAPER_FIT" in
  zoom|scaled|stretched|centered|wallpaper) ;;
  *) printf 'Unknown --wallpaper-fit: %s\n' "$WALLPAPER_FIT" >&2; exit 2 ;;
esac

if [[ -n "$CUSTOM_ACCENT" ]] && ! [[ "$CUSTOM_ACCENT" =~ ^#[0-9A-Fa-f]{6}$ ]]; then
  printf 'Invalid --accent hex: %s\n' "$CUSTOM_ACCENT" >&2
  exit 2
fi

if ! [[ "$WORKSPACES" =~ ^[1-8]$ ]]; then
  printf 'Invalid --workspaces: %s (expected 1-8)\n' "$WORKSPACES" >&2
  exit 2
fi

[[ -r "$THEMES_JSON" && -r "$CINNAMON_TEMPLATE" && -r "$GTK3_TEMPLATE" ]] || {
  echo 'Missing Cinnamon theme templates or themes.json.' >&2
  exit 1
}

run_gsettings() {
  local schema="$1" key="$2" value="$3"
  if [[ "$DRY_RUN" == true ]]; then
    printf '[dry-run] gsettings set %s %s %s\n' "$schema" "$key" "$value"
    return 0
  fi
  if command -v gsettings >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    if gsettings writable "$schema" "$key" >/dev/null 2>&1; then
      gsettings set "$schema" "$key" "$value"
    else
      printf 'INFO skipped gsettings (%s %s); schema or key unavailable on this host.\n' "$schema" "$key"
    fi
  else
    printf 'INFO skipped gsettings (%s %s); run inside an active Cinnamon desktop session.\n' "$schema" "$key"
  fi
}

theme_display_name="$(python3 - "$THEMES_JSON" "$THEME" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
print(data[sys.argv[2]]["displayName"])
PY
)"

if [[ "$REVERT" == true ]]; then
  if [[ "$DRY_RUN" == true ]]; then
    printf '[dry-run] Remove user themes %s/NEXUS-*\n' "$DATA_THEME_DIR"
  else
    rm -rf -- "$DATA_THEME_DIR"/NEXUS-*
    printf 'Removed user NEXUS-* themes from %s\n' "$DATA_THEME_DIR"
  fi
  run_gsettings org.cinnamon.theme name "'Mint-Y-Dark'"
  run_gsettings org.cinnamon.desktop.interface gtk-theme "'Mint-Y-Dark'"
  run_gsettings org.cinnamon.desktop.interface enable-animations "true"
  run_gsettings org.cinnamon desktop-effects "true"
  run_gsettings org.cinnamon panels-autohide "['1:false']"
  run_gsettings org.cinnamon panels-enabled "['1:0:bottom']"
  run_gsettings org.cinnamon panels-height "['1:40']"
  run_gsettings org.nemo.desktop show-desktop-icons "true"
  exit 0
fi

if [[ "$DRY_RUN" == true ]]; then
  printf '[dry-run] Generate NEXUS-* Cinnamon & GTK3 themes in %s (active: %s, accent: %s)\n' "$DATA_THEME_DIR" "$theme_display_name" "${CUSTOM_ACCENT:-preset}"
else
  python3 - "$THEMES_JSON" "$CINNAMON_TEMPLATE" "$GTK3_TEMPLATE" "$DATA_THEME_DIR" "$THEME" "$CUSTOM_ACCENT" <<'PY'
import json
from pathlib import Path
import sys

themes = json.load(open(sys.argv[1], encoding="utf-8"))
cinnamon_tpl = Path(sys.argv[2]).read_text(encoding="utf-8")
gtk3_tpl = Path(sys.argv[3]).read_text(encoding="utf-8")
out_root = Path(sys.argv[4])
active_key = sys.argv[5]
custom_accent = sys.argv[6]

for key_name, cfg in themes.items():
    name = cfg["displayName"]
    theme_dir = out_root / name
    (theme_dir / "cinnamon").mkdir(parents=True, exist_ok=True)
    (theme_dir / "gtk-3.0").mkdir(parents=True, exist_ok=True)

    accent = custom_accent if (custom_accent and key_name == active_key) else cfg["accent"]
    replacements = {
        "__THEME_LABEL__": cfg["label"],
        "__BG__": cfg["bg"],
        "__PANEL__": cfg["panel"],
        "__SURFACE__": cfg["surface"],
        "__BORDER__": cfg["border"],
        "__TEXT__": cfg["text"],
        "__MUTED__": cfg["muted"],
        "__ACCENT__": accent,
    }

    cinnamon_css = cinnamon_tpl
    gtk3_css = gtk3_tpl
    for key, val in replacements.items():
        cinnamon_css = cinnamon_css.replace(key, val)
        gtk3_css = gtk3_css.replace(key, val)

    (theme_dir / "cinnamon" / "cinnamon.css").write_text(cinnamon_css, encoding="utf-8")
    (theme_dir / "gtk-3.0" / "gtk.css").write_text(gtk3_css, encoding="utf-8")
    (theme_dir / "index.theme").write_text(
        f"[Desktop Entry]\nType=X-GNOME-Metatheme\nName={name}\nComment={cfg['label']} theme for NEXUS OS\nEncoding=UTF-8\n\n"
        f"[X-GNOME-Metatheme]\nGtkTheme={name}\nMetacityTheme={cfg['baseGtk']}\nIconTheme=Mint-Y\n",
        encoding="utf-8",
    )
PY
  printf 'Generated NEXUS Cinnamon themes in %s (active: %s)\n' "$DATA_THEME_DIR" "$theme_display_name"
fi

run_gsettings org.cinnamon.theme name "'${theme_display_name}'"
run_gsettings org.cinnamon.desktop.interface gtk-theme "'${theme_display_name}'"
run_gsettings org.cinnamon.desktop.wm.preferences num-workspaces "$WORKSPACES"
run_gsettings org.cinnamon.muffin edge-tiling "true"
run_gsettings org.cinnamon.desktop.notifications display-notifications "true"
run_gsettings org.cinnamon panels-autohide "['1:${PANEL_AUTOHIDE}']"
run_gsettings org.cinnamon panels-enabled "['1:0:${DOCK_POSITION}']"
run_gsettings org.cinnamon panels-height "['1:${PANEL_PX}']"
run_gsettings org.nemo.desktop show-desktop-icons "$DESKTOP_ICONS"
run_gsettings org.cinnamon.desktop.background picture-options "'${WALLPAPER_FIT}'"

if [[ -n "$WALLPAPER_URL" ]]; then
  if [[ "$WALLPAPER_URL" =~ ^https:// ]]; then
    cache_name="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(sys.argv[1].encode()).hexdigest()[:16]+".jpg")' "$WALLPAPER_URL")"
    cache_path="$WALLPAPER_CACHE_DIR/$cache_name"
    if [[ "$DRY_RUN" == true ]]; then
      printf '[dry-run] Cache %s -> %s and set org.cinnamon.desktop.background picture-uri\n' "$WALLPAPER_URL" "$cache_path"
    else
      mkdir -p -- "$WALLPAPER_CACHE_DIR"
      if [[ ! -s "$cache_path" ]]; then
        curl -fsSL --proto '=https' --tlsv1.2 --max-time 25 -- "$WALLPAPER_URL" -o "${cache_path}.tmp"
        mv -f -- "${cache_path}.tmp" "$cache_path"
      fi
      run_gsettings org.cinnamon.desktop.background picture-uri "'file://${cache_path}'"
    fi
  elif [[ -f "$WALLPAPER_URL" ]]; then
    abs_wp="$(realpath "$WALLPAPER_URL")"
    run_gsettings org.cinnamon.desktop.background picture-uri "'file://${abs_wp}'"
  else
    printf 'Wallpaper source must be an https:// URL or readable local file: %s\n' "$WALLPAPER_URL" >&2
    exit 2
  fi
fi

effective_effects="$EFFECT_LEVEL"
if [[ -z "$effective_effects" ]]; then
  case "$PROFILE" in
    balanced) effective_effects="balanced" ;;
    performance|lightweight) effective_effects="off" ;;
  esac
fi

case "$effective_effects" in
  off)
    run_gsettings org.cinnamon.desktop.interface enable-animations "false"
    run_gsettings org.cinnamon desktop-effects "false"
    ;;
  subtle)
    run_gsettings org.cinnamon.desktop.interface enable-animations "true"
    run_gsettings org.cinnamon desktop-effects "false"
    ;;
  balanced|enhanced)
    run_gsettings org.cinnamon.desktop.interface enable-animations "true"
    run_gsettings org.cinnamon desktop-effects "true"
    ;;
esac
