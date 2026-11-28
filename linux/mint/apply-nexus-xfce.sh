#!/usr/bin/env bash
# Apply or revert NEXUS OS styling, theme/accent/appearance, wallpaper, and low-resource
# Xfce defaults on Linux Mint 22.3 Xfce. Runs as the desktop user; never requires root.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
CSS_SOURCE="$REPO_ROOT/linux/xfce/nexus-dark.css"
if [[ ! -r "$CSS_SOURCE" && -r "/usr/local/share/nexus-os/xfce/nexus-dark.css" ]]; then
  CSS_SOURCE="/usr/local/share/nexus-os/xfce/nexus-dark.css"
fi
WALLPAPER_CLI="${NEXUS_WALLPAPER_CLI:-$SCRIPT_DIR/nexus-wallpaper-cli.sh}"
if [[ ! -x "$WALLPAPER_CLI" && -x "/usr/local/bin/nexus-wallpaper" ]]; then
  WALLPAPER_CLI="/usr/local/bin/nexus-wallpaper"
fi
GTK_CSS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0"
GTK_CSS_FILE="$GTK_CSS_DIR/gtk.css"
BEGIN_MARKER='/* BEGIN NEXUS OS XFCE THEME */'
END_MARKER='/* END NEXUS OS XFCE THEME */'

DRY_RUN=false
LIGHTWEIGHT=false
REVERT=false
THEME="midnight"
APPEARANCE="dark"
CUSTOM_ACCENT=""
WALLPAPER_URL=""
WALLPAPER_FIT="zoom"
WORKSPACES=""
PANEL_AUTOHIDE=""

usage() {
  cat <<'USAGE'
Usage: bash linux/mint/apply-nexus-xfce.sh [OPTIONS]

Applies NEXUS OS GTK3 panel/menu styling, theme/accent/appearance, wallpaper,
and low-resource Xfce defaults for Linux Mint 22.3 Xfce.

Options:
  --theme NAME           midnight | nebula | arctic | emerald | solar (default: midnight)
  --accent HEX           Optional #RRGGBB accent override
  --appearance MODE      dark | light (default: dark; arctic forces light unless overridden)
  --wallpaper-url URL    HTTPS wallpaper URL or local file path to apply
  --wallpaper-fit MODE   zoom | scaled | stretched | centered | wallpaper (default: zoom)
  --workspaces COUNT     1-8 workspace count
  --panel-autohide MODE  false | true | intel
  --lightweight          Disable Xfwm4 shadows, opacity effects, and animations
  --revert               Remove the NEXUS GTK3 CSS block and restore default shadows
  --dry-run              Print actions without modifying ~/.config or xfconf
  --help, -h             Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --theme) [[ $# -ge 2 ]] || { echo '--theme requires a preset name' >&2; exit 2; }; THEME="$2"; shift 2 ;;
    --accent) [[ $# -ge 2 ]] || { echo '--accent requires #RRGGBB' >&2; exit 2; }; CUSTOM_ACCENT="$2"; shift 2 ;;
    --appearance) [[ $# -ge 2 ]] || { echo '--appearance requires dark|light' >&2; exit 2; }; APPEARANCE="$2"; shift 2 ;;
    --wallpaper-url) [[ $# -ge 2 ]] || { echo '--wallpaper-url requires URL or path' >&2; exit 2; }; WALLPAPER_URL="$2"; shift 2 ;;
    --wallpaper-fit) [[ $# -ge 2 ]] || { echo '--wallpaper-fit requires zoom|scaled|stretched|centered|wallpaper' >&2; exit 2; }; WALLPAPER_FIT="$2"; shift 2 ;;
    --workspaces) [[ $# -ge 2 ]] || { echo '--workspaces requires 1-8' >&2; exit 2; }; WORKSPACES="$2"; shift 2 ;;
    --panel-autohide) [[ $# -ge 2 ]] || { echo '--panel-autohide requires false|true|intel' >&2; exit 2; }; PANEL_AUTOHIDE="$2"; shift 2 ;;
    --lightweight) LIGHTWEIGHT=true; shift ;;
    --revert) REVERT=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$THEME" in
  midnight|nebula|arctic|emerald|solar) ;;
  *) printf 'Unknown --theme: %s\n' "$THEME" >&2; exit 2 ;;
esac
case "$APPEARANCE" in
  dark|light) ;;
  *) printf 'Unknown --appearance: %s\n' "$APPEARANCE" >&2; exit 2 ;;
esac
if [[ -n "$CUSTOM_ACCENT" ]] && ! [[ "$CUSTOM_ACCENT" =~ ^#[0-9A-Fa-f]{6}$ ]]; then
  printf 'Invalid --accent hex: %s\n' "$CUSTOM_ACCENT" >&2; exit 2
fi
if [[ -n "$WORKSPACES" ]] && ! [[ "$WORKSPACES" =~ ^[1-8]$ ]]; then
  printf 'Invalid --workspaces: %s\n' "$WORKSPACES" >&2; exit 2
fi
if [[ -n "$PANEL_AUTOHIDE" ]]; then
  case "$PANEL_AUTOHIDE" in
    false|true|intel) ;;
    *) printf 'Invalid --panel-autohide: %s\n' "$PANEL_AUTOHIDE" >&2; exit 2 ;;
  esac
fi

if [[ "$DRY_RUN" == false && "$(id -u)" -eq 0 ]]; then
  echo 'Refusing to modify user desktop configuration as root. Run as your regular Mint desktop user.' >&2
  exit 1
fi

[[ -r "$CSS_SOURCE" ]] || { printf 'Missing theme CSS file: %s\n' "$CSS_SOURCE" >&2; exit 1; }

run_xfconf() {
  local channel="$1" property="$2" type="$3" value="$4"
  if [[ "$DRY_RUN" == true ]]; then
    printf '[dry-run] xfconf-query -c %s -p %s -n -t %s -s %s\n' "$channel" "$property" "$type" "$value"
    return 0
  fi
  if command -v xfconf-query >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    xfconf-query -c "$channel" -p "$property" -n -t "$type" -s "$value"
  else
    printf 'INFO skipped xfconf-query (%s %s); run inside an active Xfce session.\n' "$channel" "$property"
  fi
}

strip_nexus_css_block() {
  local file="$1"
  python3 - "$file" "$BEGIN_MARKER" "$END_MARKER" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
begin = sys.argv[2]
end = sys.argv[3]
if not path.exists():
    raise SystemExit(0)
text = path.read_text(encoding="utf-8")
start_idx = text.find(begin)
end_idx = text.find(end)
if start_idx != -1 and end_idx != -1 and end_idx >= start_idx:
    after = end_idx + len(end)
    cleaned = (text[:start_idx].rstrip() + "\n" + text[after:].lstrip()).strip()
    if cleaned:
        path.write_text(cleaned + "\n", encoding="utf-8")
    else:
        path.unlink()
PY
}

if [[ "$REVERT" == true ]]; then
  if [[ "$DRY_RUN" == true ]]; then
    printf '[dry-run] Remove NEXUS CSS block from %s\n' "$GTK_CSS_FILE"
  else
    strip_nexus_css_block "$GTK_CSS_FILE"
    printf 'Removed NEXUS CSS block from %s (if present).\n' "$GTK_CSS_FILE"
  fi
  run_xfconf xfwm4 /general/use_compositing bool true
  run_xfconf xfwm4 /general/show_frame_shadow bool true
  run_xfconf xfwm4 /general/show_popup_shadow bool true
  run_xfconf xsettings /Gtk/EnableAnimations bool true
  exit 0
fi

# Resolve effective palette tokens
effective_accent="$CUSTOM_ACCENT"
effective_panel_bg="rgba(13, 20, 36, 0.94)"
effective_text="#eef4ff"
case "$THEME" in
  midnight) effective_accent="${effective_accent:-#66a3ff}"; effective_panel_bg="rgba(13, 20, 36, 0.94)" ;;
  nebula) effective_accent="${effective_accent:-#b185ff}"; effective_panel_bg="rgba(20, 16, 36, 0.94)" ;;
  arctic) effective_accent="${effective_accent:-#0284c7}"; effective_panel_bg="rgba(241, 247, 253, 0.94)"; effective_text="#0f172a"; APPEARANCE="light" ;;
  emerald) effective_accent="${effective_accent:-#34d399}"; effective_panel_bg="rgba(13, 25, 20, 0.94)" ;;
  solar) effective_accent="${effective_accent:-#ffad7a}"; effective_panel_bg="rgba(25, 26, 32, 0.94)" ;;
esac
if [[ "$APPEARANCE" == "light" && "$THEME" != "arctic" ]]; then
  effective_panel_bg="rgba(243, 246, 251, 0.95)"
  effective_text="#0f172a"
fi

if [[ "$DRY_RUN" == true ]]; then
  printf '[dry-run] Update %s with %s (theme=%s, accent=%s, appearance=%s)\n' "$GTK_CSS_FILE" "$CSS_SOURCE" "$THEME" "$effective_accent" "$APPEARANCE"
else
  mkdir -p -- "$GTK_CSS_DIR"
  if [[ -f "$GTK_CSS_FILE" && ! -f "$GTK_CSS_FILE.nexus-backup" ]]; then
    cp -- "$GTK_CSS_FILE" "$GTK_CSS_FILE.nexus-backup"
  fi
  strip_nexus_css_block "$GTK_CSS_FILE"
  {
    if [[ -s "$GTK_CSS_FILE" ]]; then
      cat "$GTK_CSS_FILE"
      printf '\n'
    fi
    printf '%s\n' "$BEGIN_MARKER"
    cat "$CSS_SOURCE"
    printf '\n@define-color nexus_accent %s;\n' "$effective_accent"
    printf '.xfce4-panel { background-color: %s; color: %s; border-top-color: %s; }\n' "$effective_panel_bg" "$effective_text" "$effective_accent"
    printf '%s\n' "$END_MARKER"
  } > "$GTK_CSS_FILE.part"
  mv -- "$GTK_CSS_FILE.part" "$GTK_CSS_FILE"
  printf 'Updated GTK3 theme overrides: %s\n' "$GTK_CSS_FILE"
fi

# Window management defaults aligned with NEXUS desktop behavior (snap & tile)
run_xfconf xfwm4 /general/snap_to_border bool true
run_xfconf xfwm4 /general/snap_to_windows bool true
run_xfconf xfwm4 /general/tile_on_move bool true
run_xfconf xfwm4 /general/cycle_preview bool true
if [[ "$APPEARANCE" == "light" ]]; then
  run_xfconf xfce4-panel /panels/dark-mode bool false
else
  run_xfconf xfce4-panel /panels/dark-mode bool true
fi
if [[ -n "$WORKSPACES" ]]; then
  run_xfconf xfwm4 /general/workspace_count int "$WORKSPACES"
fi
if [[ -n "$PANEL_AUTOHIDE" ]]; then
  ah=0
  [[ "$PANEL_AUTOHIDE" == "intel" ]] && ah=1
  [[ "$PANEL_AUTOHIDE" == "true" ]] && ah=2
  run_xfconf xfce4-panel /panels/panel-1/autohide-behavior int "$ah"
fi

if [[ "$LIGHTWEIGHT" == true ]]; then
  run_xfconf xfwm4 /general/use_compositing bool false
  run_xfconf xfwm4 /general/show_frame_shadow bool false
  run_xfconf xfwm4 /general/show_popup_shadow bool false
  run_xfconf xsettings /Gtk/EnableAnimations bool false
else
  run_xfconf xfwm4 /general/use_compositing bool true
  run_xfconf xfwm4 /general/show_frame_shadow bool false
  run_xfconf xfwm4 /general/show_popup_shadow bool false
  run_xfconf xfwm4 /general/frame_opacity int 100
  run_xfconf xfwm4 /general/inactive_opacity int 100
  run_xfconf xfwm4 /general/move_opacity int 100
  run_xfconf xfwm4 /general/resize_opacity int 100
fi

if [[ "$APPEARANCE" == "light" ]]; then
  for candidate in Mint-Y-Sand Mint-Y-Aqua Mint-Y; do
    if [[ -d "/usr/share/themes/$candidate" ]]; then
      run_xfconf xsettings /Net/ThemeName string "$candidate"
      break
    fi
  done
else
  for candidate in Mint-Y-Dark-Sand Mint-Y-Dark-Orange Mint-Y-Dark; do
    if [[ -d "/usr/share/themes/$candidate" ]]; then
      run_xfconf xsettings /Net/ThemeName string "$candidate"
      break
    fi
  done
fi

if [[ -n "$WALLPAPER_URL" && -x "$WALLPAPER_CLI" ]]; then
  wp_args=(apply --url "$WALLPAPER_URL" --fit "$WALLPAPER_FIT" --edition xfce)
  [[ "$DRY_RUN" == true ]] && wp_args+=(--dry-run)
  bash "$WALLPAPER_CLI" "${wp_args[@]}"
fi

if [[ "$DRY_RUN" == false ]]; then
  echo 'Applied NEXUS Xfce profile. Restart xfce4-panel (xfce4-panel -r) inside Xfce to reload CSS.'
fi
