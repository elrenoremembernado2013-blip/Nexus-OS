#!/usr/bin/env bash
# Apply or revert NEXUS OS styling and low-resource Xfce defaults on Linux Mint 22.3 Xfce.
# Runs as the logged-in desktop user; never modifies system files or requires root.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
CSS_SOURCE="$REPO_ROOT/linux/xfce/nexus-dark.css"
GTK_CSS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0"
GTK_CSS_FILE="$GTK_CSS_DIR/gtk.css"
BEGIN_MARKER='/* BEGIN NEXUS OS XFCE THEME */'
END_MARKER='/* END NEXUS OS XFCE THEME */'

DRY_RUN=false
LIGHTWEIGHT=false
REVERT=false

usage() {
  cat <<'USAGE'
Usage: bash linux/mint/apply-nexus-xfce.sh [OPTIONS]

Applies NEXUS OS GTK3 panel/menu styling and low-resource Xfce defaults for
Linux Mint 22.3 Xfce (4 GB RAM / 32 GB eMMC target). Must run as a regular
desktop user, not root.

Options:
  --lightweight   Disable Xfwm4 shadows, opacity effects, and animations
  --revert        Remove the NEXUS GTK3 CSS block and restore default shadows
  --dry-run       Print actions without modifying ~/.config or xfconf
  --help, -h      Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --lightweight) LIGHTWEIGHT=true; shift ;;
    --revert) REVERT=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

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

if [[ "$DRY_RUN" == true ]]; then
  printf '[dry-run] Update %s with %s\n' "$GTK_CSS_FILE" "$CSS_SOURCE"
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

# Prefer dark Mint theme if available on the host
for candidate in Mint-Y-Dark-Sand Mint-Y-Dark-Orange Mint-Y-Dark; do
  if [[ -d "/usr/share/themes/$candidate" ]]; then
    run_xfconf xsettings /Net/ThemeName string "$candidate"
    break
  fi
done

if [[ "$DRY_RUN" == false ]]; then
  echo 'Applied NEXUS Xfce profile. Restart xfce4-panel (xfce4-panel -r) inside Xfce to reload CSS.'
fi
