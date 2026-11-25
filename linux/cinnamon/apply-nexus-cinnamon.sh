#!/usr/bin/env bash
# Generate and apply NEXUS OS Cinnamon themes, dock-style panel layout, workspace
# shortcuts, and performance profiles on Linux Mint Cinnamon.
# Runs strictly as the desktop user; never touches system files or requires root.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
THEMES_JSON="$SCRIPT_DIR/themes.json"
CINNAMON_TEMPLATE="$SCRIPT_DIR/cinnamon-base.css"
GTK3_TEMPLATE="$SCRIPT_DIR/gtk3-base.css"
DATA_THEME_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/themes"

THEME="midnight"
PROFILE="balanced"
DOCK_POSITION="bottom"
WORKSPACES=4
DRY_RUN=false
REVERT=false

usage() {
  cat <<'USAGE'
Usage: bash linux/cinnamon/apply-nexus-cinnamon.sh [OPTIONS]

Generates user-local NEXUS Cinnamon/GTK3 theme packages under
~/.local/share/themes/NEXUS-* and applies Cinnamon gsettings defaults for panel
layout, edge tiling, workspaces, notifications, and performance modes.

Options:
  --theme NAME           Theme preset: midnight | nebula | arctic | emerald | solar (default: midnight)
  --profile MODE         Performance mode: balanced | performance | lightweight (default: balanced)
  --dock-position POS    Primary Cinnamon panel edge: bottom | left | right (default: bottom)
  --workspaces COUNT     Number of virtual workspaces (1-8, default: 4)
  --revert               Remove user NEXUS-* themes and restore Mint-Y-Dark defaults
  --dry-run              Preview theme generation and gsettings commands without writing
  --help, -h             Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --theme)
      [[ $# -ge 2 ]] || { echo '--theme requires a preset name' >&2; exit 2; }
      THEME="$2"; shift 2 ;;
    --profile)
      [[ $# -ge 2 ]] || { echo '--profile requires a mode' >&2; exit 2; }
      PROFILE="$2"; shift 2 ;;
    --dock-position)
      [[ $# -ge 2 ]] || { echo '--dock-position requires bottom, left, or right' >&2; exit 2; }
      DOCK_POSITION="$2"; shift 2 ;;
    --workspaces)
      [[ $# -ge 2 ]] || { echo '--workspaces requires a count (1-8)' >&2; exit 2; }
      WORKSPACES="$2"; shift 2 ;;
    --revert) REVERT=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$DRY_RUN" == false && "$(id -u)" -eq 0 ]]; then
  echo 'Refusing to modify user Cinnamon configuration as root. Run as your regular Mint desktop user.' >&2
  exit 1
fi

case "$THEME" in
  midnight|nebula|arctic|emerald|solar) ;;
  *) printf 'Unknown --theme: %s (expected midnight, nebula, arctic, emerald, or solar)\n' "$THEME" >&2; exit 2 ;;
esac

case "$PROFILE" in
  balanced|performance|lightweight) ;;
  *) printf 'Unknown --profile: %s (expected balanced, performance, or lightweight)\n' "$PROFILE" >&2; exit 2 ;;
esac

case "$DOCK_POSITION" in
  bottom|left|right) ;;
  *) printf 'Unknown --dock-position: %s (expected bottom, left, or right)\n' "$DOCK_POSITION" >&2; exit 2 ;;
esac

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
  exit 0
fi

if [[ "$DRY_RUN" == true ]]; then
  printf '[dry-run] Generate NEXUS-* Cinnamon & GTK3 themes in %s\n' "$DATA_THEME_DIR"
else
  python3 - "$THEMES_JSON" "$CINNAMON_TEMPLATE" "$GTK3_TEMPLATE" "$DATA_THEME_DIR" <<'PY'
import json
from pathlib import Path
import sys

themes = json.load(open(sys.argv[1], encoding="utf-8"))
cinnamon_tpl = Path(sys.argv[2]).read_text(encoding="utf-8")
gtk3_tpl = Path(sys.argv[3]).read_text(encoding="utf-8")
out_root = Path(sys.argv[4])

for cfg in themes.values():
    name = cfg["displayName"]
    theme_dir = out_root / name
    (theme_dir / "cinnamon").mkdir(parents=True, exist_ok=True)
    (theme_dir / "gtk-3.0").mkdir(parents=True, exist_ok=True)

    replacements = {
        "__THEME_LABEL__": cfg["label"],
        "__BG__": cfg["bg"],
        "__PANEL__": cfg["panel"],
        "__SURFACE__": cfg["surface"],
        "__BORDER__": cfg["border"],
        "__TEXT__": cfg["text"],
        "__MUTED__": cfg["muted"],
        "__ACCENT__": cfg["accent"],
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
run_gsettings org.cinnamon panels-autohide "['1:false']"
run_gsettings org.cinnamon panels-enabled "['1:0:${DOCK_POSITION}']"

case "$PROFILE" in
  balanced)
    run_gsettings org.cinnamon.desktop.interface enable-animations "true"
    run_gsettings org.cinnamon desktop-effects "true"
    ;;
  performance)
    run_gsettings org.cinnamon.desktop.interface enable-animations "false"
    run_gsettings org.cinnamon desktop-effects "false"
    ;;
  lightweight)
    run_gsettings org.cinnamon.desktop.interface enable-animations "false"
    run_gsettings org.cinnamon desktop-effects "false"
    run_gsettings org.cinnamon.desktop.background picture-opacity "100"
    ;;
esac
